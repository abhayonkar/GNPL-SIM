"""
models/hybrid_ids.py — Hybrid Temporal-Graph IDS
==================================================
Fuses three complementary anomaly signals into one detection decision:

  Signal 1 — TEMPORAL  (LSTM-AE reconstruction error)
    Best at: FDI ramp, replay attack, slow compressor manipulation.

  Signal 2 — GRAPH     (GNN node deviation from neighbourhood)
    Best at: MITM, command injection, topology-changing attacks.

  Signal 3 — PHYSICS   (EKF residual + Kirchhoff imbalance)
    No training needed — uses simulation output directly.
    Best at: pipe leak, rapid pressure spike, valve forcing.

Fusion modes:
  'equal'      — simple average of 3 normalised scores (unsupervised default)
  'supervised' — logistic regression fusion trained on labelled data

FIXES vs original version:
  FIX 1 — NODE_NAMES was imported inside localise_attack() method body,
           causing repeated module-level import on every call. Moved to
           module level alongside other imports.

  FIX 2 — fit_normalisation() includes assertion that all three inputs
           have equal row count, giving a clear error message instead of
           a confusing crash inside np.stack.

  FIX 3 — fuse_scores() raises a clear ValueError with diagnostic message
           if input lengths differ, explaining the exact fix needed.
"""

import numpy as np
import torch
import torch.nn as nn
from sklearn.linear_model import LogisticRegression

# MODULE-LEVEL IMPORTS — NODE_NAMES must be here, not inside method bodies
from .lstm_ae import LSTMAEDetector, build_sequences_with_labels
from .gnn_ids import GraphAnomalyDetector, NODE_NAMES


# ─────────────────────────────────────────────────────────────────────────────
# Physics residual scorer — no neural network needed
# ─────────────────────────────────────────────────────────────────────────────

def physics_anomaly_score(df) -> np.ndarray:
    """
    Compute a scalar physics anomaly score per row from the flat DataFrame.
    Uses EKF residuals and Kirchhoff imbalance — both in physics_dataset.csv
    without any additional computation.

    Returns
    -------
    scores : np.ndarray shape (N,), dtype float32
    """
    scores = np.zeros(len(df))

    ekf_cols = [c for c in df.columns if c.startswith('ekf_resid_')]
    if ekf_cols:
        ekf_vals  = df[ekf_cols].fillna(0).values
        scores   += np.linalg.norm(ekf_vals, axis=1)

    if 'kirchhoff_imbalance' in df.columns:
        scores += df['kirchhoff_imbalance'].fillna(0).abs().values

    if 'cusum_S_upper' in df.columns:
        scores += df['cusum_S_upper'].fillna(0).values * 0.1

    if 'chi2_stat' in df.columns:
        scores += df['chi2_stat'].fillna(0).values * 0.05

    return scores.astype(np.float32)


def normalise_scores(scores: np.ndarray,
                     ref_scores: np.ndarray = None) -> np.ndarray:
    """
    Normalise scores to [0, 1] using robust percentile scaling.
    Uses 1st-99th percentile of ref_scores (normal-only) as bounds.
    """
    ref = ref_scores if ref_scores is not None else scores
    lo  = np.percentile(ref, 1)
    hi  = np.percentile(ref, 99)
    if hi - lo < 1e-8:
        return np.zeros_like(scores)
    return np.clip((scores - lo) / (hi - lo), 0, 1)


# ─────────────────────────────────────────────────────────────────────────────
# Optional supervised fusion MLP
# ─────────────────────────────────────────────────────────────────────────────

class _FusionMLP(nn.Module):
    def __init__(self, hidden: int = 16):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(3, hidden), nn.ReLU(), nn.Dropout(0.2),
            nn.Linear(hidden, 1), nn.Sigmoid())

    def forward(self, x):
        return self.net(x).squeeze(-1)


# ─────────────────────────────────────────────────────────────────────────────
# Hybrid IDS
# ─────────────────────────────────────────────────────────────────────────────

class HybridIDS:
    """
    Hybrid Temporal-Graph IDS for the 20-node CGD pipeline.

    IMPORTANT — input alignment rule:
        X_seq_test  : (N - seq_len + 1, seq_len, feat_dim)
        X_node_test : (N - seq_len + 1, n_nodes, node_feat)   ← use [seq_len-1:]
        df_test     : (N - seq_len + 1, cols)                 ← use .iloc[seq_len-1:]
        All three must have the SAME first dimension.
    """

    def __init__(self, lstm_det: LSTMAEDetector,
                 gnn_det: GraphAnomalyDetector,
                 mode: str = 'equal',
                 device=None):
        self.lstm_det    = lstm_det
        self.gnn_det     = gnn_det
        self.mode        = mode
        self.device      = device or ('cuda' if torch.cuda.is_available() else 'cpu')
        self.threshold_  = None
        self._lstm_ref   = None
        self._gnn_ref    = None
        self._phys_ref   = None
        self._lr_fusion  = None
        self._fusion_mlp = None

    def fit_normalisation(self, X_seq_normal: np.ndarray,
                          X_node_normal: np.ndarray,
                          df_normal):
        """
        Compute normalisation references from normal-only data.
        ALL THREE inputs must have the same number of rows (use n_val=min(n_val_seq,n_val_gnn)).
        """
        assert len(X_seq_normal) == len(X_node_normal) == len(df_normal), (
            f"fit_normalisation: all inputs must have same row count. "
            f"seq={len(X_seq_normal)}, node={len(X_node_normal)}, "
            f"df={len(df_normal)}. Use n_val = min(n_val_seq, n_val_gnn).")

        print("[hybrid] Computing normalisation references on normal data …")
        self._lstm_ref = self.lstm_det.anomaly_score(X_seq_normal)
        self._gnn_ref  = self.gnn_det.anomaly_score(X_node_normal)
        self._phys_ref = physics_anomaly_score(df_normal)
        print(f"  LSTM  range: [{self._lstm_ref.min():.4f}, {self._lstm_ref.max():.4f}]")
        print(f"  GNN   range: [{self._gnn_ref.min():.4f},  {self._gnn_ref.max():.4f}]")
        print(f"  Phys  range: [{self._phys_ref.min():.4f}, {self._phys_ref.max():.4f}]")

    def fit_weights(self, X_seq: np.ndarray, X_node: np.ndarray,
                    df, y: np.ndarray, epochs: int = 30, lr: float = 1e-3):
        """Fit LR fusion layer. Call fit_normalisation() first."""
        if self._lstm_ref is None:
            raise RuntimeError("Call fit_normalisation() before fit_weights().")

        s_lstm = normalise_scores(self.lstm_det.anomaly_score(X_seq),  self._lstm_ref)
        s_gnn  = normalise_scores(self.gnn_det.anomaly_score(X_node),  self._gnn_ref)
        s_phys = normalise_scores(physics_anomaly_score(df),           self._phys_ref)
        S      = np.stack([s_lstm, s_gnn, s_phys], axis=1)

        if len(np.unique(y)) < 2:
            print("[hybrid] Only one class — using equal weights.")
            self.mode = 'equal'
            return

        self.mode       = 'supervised'
        self._lr_fusion = LogisticRegression(class_weight='balanced', C=1.0)
        self._lr_fusion.fit(S, y)
        print(f"[hybrid] LR weights: LSTM={self._lr_fusion.coef_[0][0]:.3f}  "
              f"GNN={self._lr_fusion.coef_[0][1]:.3f}  "
              f"Phys={self._lr_fusion.coef_[0][2]:.3f}")

    def fuse_scores(self, X_seq: np.ndarray,
                    X_node: np.ndarray, df) -> np.ndarray:
        """Compute final fusion score. All inputs must have same first dimension."""
        s_lstm = normalise_scores(self.lstm_det.anomaly_score(X_seq),  self._lstm_ref)
        s_gnn  = normalise_scores(self.gnn_det.anomaly_score(X_node),  self._gnn_ref)
        s_phys = normalise_scores(physics_anomaly_score(df),           self._phys_ref)

        if not (len(s_lstm) == len(s_gnn) == len(s_phys)):
            raise ValueError(
                f"fuse_scores: all score arrays must have same length. "
                f"lstm={len(s_lstm)}, gnn={len(s_gnn)}, phys={len(s_phys)}. "
                f"Fix: X_node_test = X_node_full[seq_len-1:] and "
                f"df_test = df.iloc[seq_len-1:].reset_index(drop=True).")

        S = np.stack([s_lstm, s_gnn, s_phys], axis=1)
        if self.mode == 'supervised' and self._lr_fusion is not None:
            return self._lr_fusion.predict_proba(S)[:, 1]
        return S.mean(axis=1)

    def fit_threshold(self, X_seq_normal, X_node_normal, df_normal,
                      fpr: float = 0.01) -> float:
        scores = self.fuse_scores(X_seq_normal, X_node_normal, df_normal)
        self.threshold_ = float(np.quantile(scores, 1.0 - fpr))
        print(f"[hybrid] Threshold={self.threshold_:.4f}  (FPR={fpr:.2f})")
        return self.threshold_

    def predict(self, X_seq, X_node, df) -> np.ndarray:
        if self.threshold_ is None:
            raise RuntimeError("Call fit_threshold() before predict().")
        return (self.fuse_scores(X_seq, X_node, df) > self.threshold_).astype(int)

    def score_breakdown(self, X_seq, X_node, df) -> dict:
        """All component scores — for paper Table III."""
        raw_lstm  = self.lstm_det.anomaly_score(X_seq)
        raw_gnn   = self.gnn_det.anomaly_score(X_node)
        raw_phys  = physics_anomaly_score(df)
        return {
            'raw_lstm':    raw_lstm,
            'raw_gnn':     raw_gnn,
            'raw_physics': raw_phys,
            'norm_lstm':   normalise_scores(raw_lstm, self._lstm_ref),
            'norm_gnn':    normalise_scores(raw_gnn,  self._gnn_ref),
            'norm_physics':normalise_scores(raw_phys, self._phys_ref),
            'fused':       self.fuse_scores(X_seq, X_node, df),
        }

    def localise_attack(self, X_seq, X_node, df, top_k: int = 3) -> list:
        """Top-k anomalous node names per sample using GNN node-level scores."""
        node_scores = self.gnn_det.node_scores(X_node)   # (N, n_nodes)
        results = []
        for row_scores in node_scores:
            top_idx = np.argsort(row_scores)[::-1][:top_k]
            results.append([NODE_NAMES[i] for i in top_idx])
        return results
