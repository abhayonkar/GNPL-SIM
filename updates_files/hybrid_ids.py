"""
models/hybrid_ids.py — Hybrid Temporal-Graph IDS (YOUR NOVEL CONTRIBUTION)
============================================================================
Fuses three complementary anomaly signals into one detection decision:

  Signal 1 — TEMPORAL  (LSTM-AE):
    Reconstruction error on 30-step sliding windows.
    Best at: FDI ramp, replay, slow compressor manipulation.

  Signal 2 — GRAPH     (GNN):
    Node deviation from predicted neighbourhood.
    Best at: MITM, command injection, communication anomalies.

  Signal 3 — PHYSICS   (EKF residual + Kirchhoff imbalance):
    Direct from simulation — no deep learning needed.
    Best at: pipe leak, rapid pressure spike, valve force.

Fusion strategy:
  Weighted sum of normalised scores → final anomaly score.
  Weights learned by a small supervised MLP if labelled data is available,
  or set to equal weights (1/3 each) in unsupervised mode.

Thesis contribution statement (write this verbatim):
  "A dual-layer CPS intrusion detection system for Indian CGD networks
   combining sequence-level LSTM reconstruction, graph-topology deviation,
   and physics-residual signals into a unified anomaly score — the first
   such system evaluated on an Indian PNGRB T4S-compliant dataset."

Usage:
  from models.hybrid_ids import HybridIDS
  ids = HybridIDS(lstm_det, gnn_det)
  ids.fit_weights(X_seq_tr, X_node_tr, X_flat_tr, y_tr)  # optional
  scores = ids.fuse_scores(X_seq_test, X_node_test, X_flat_test)
  preds  = ids.predict(X_seq_test, X_node_test, X_flat_test)
"""

import numpy as np
import torch
import torch.nn as nn
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

from .lstm_ae import LSTMAEDetector, build_sequences_with_labels
from .gnn_ids import GraphAnomalyDetector


# ─────────────────────────────────────────────────────────────────────────────
# Physics residual scorer — no neural network needed
# ─────────────────────────────────────────────────────────────────────────────

def physics_anomaly_score(df) -> np.ndarray:
    """
    Compute a scalar physics anomaly score per row from the flat DataFrame.
    Uses EKF residuals and Kirchhoff imbalance — both available in the
    physics_dataset.csv without any additional computation.

    Returns: np.ndarray shape (N,), normalised to [0, 1] approximately.
    """
    scores = np.zeros(len(df))

    # EKF residual norm (already computed by updateEKF in simulation)
    ekf_cols = [c for c in df.columns if c.startswith('ekf_resid_')]
    if ekf_cols:
        ekf_vals = df[ekf_cols].fillna(0).values
        scores  += np.linalg.norm(ekf_vals, axis=1)

    # Kirchhoff mass balance imbalance
    if 'kirchhoff_imbalance' in df.columns:
        scores += df['kirchhoff_imbalance'].fillna(0).abs().values

    # CUSUM upper accumulator (already a detector output)
    if 'cusum_S_upper' in df.columns:
        scores += df['cusum_S_upper'].fillna(0).values * 0.1

    # chi2 statistic
    if 'chi2_stat' in df.columns:
        scores += df['chi2_stat'].fillna(0).values * 0.05

    return scores.astype(np.float32)


def normalise_scores(scores: np.ndarray,
                     ref_scores: np.ndarray = None) -> np.ndarray:
    """
    Normalise scores to [0, 1] using robust percentile scaling.
    If ref_scores (normal-only) provided, use those for scale estimation.
    """
    ref = ref_scores if ref_scores is not None else scores
    lo  = np.percentile(ref, 1)
    hi  = np.percentile(ref, 99)
    if hi - lo < 1e-8:
        return np.zeros_like(scores)
    return np.clip((scores - lo) / (hi - lo), 0, 1)


# ─────────────────────────────────────────────────────────────────────────────
# Fusion MLP (learned weights when labels available)
# ─────────────────────────────────────────────────────────────────────────────

class _FusionMLP(nn.Module):
    """3-input → 1-output MLP for combining three anomaly scores."""

    def __init__(self, hidden: int = 16):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(3, hidden),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(hidden, 1),
            nn.Sigmoid()
        )

    def forward(self, x):
        return self.net(x).squeeze(-1)


# ─────────────────────────────────────────────────────────────────────────────
# Hybrid IDS
# ─────────────────────────────────────────────────────────────────────────────

class HybridIDS:
    """
    Hybrid Temporal-Graph IDS for the 20-node CGD pipeline.

    Parameters
    ----------
    lstm_det    : fitted LSTMAEDetector
    gnn_det     : fitted GraphAnomalyDetector
    mode        : 'equal'      — simple average of 3 normalised scores
                  'supervised' — MLP fusion trained on labelled data
    device      : torch device string
    """

    def __init__(self, lstm_det: LSTMAEDetector,
                 gnn_det: GraphAnomalyDetector,
                 mode: str = 'equal',
                 device=None):
        self.lstm_det  = lstm_det
        self.gnn_det   = gnn_det
        self.mode      = mode
        self.device    = device or ('cuda' if torch.cuda.is_available() else 'cpu')
        self.threshold_ = None

        # Normalisation reference (set during fit)
        self._lstm_ref  = None
        self._gnn_ref   = None
        self._phys_ref  = None

        # Supervised fusion components
        self._fusion_mlp = None
        self._lr_fusion  = None

    # ── Fitting ───────────────────────────────────────────────────────────

    def fit_normalisation(self, X_seq_normal: np.ndarray,
                          X_node_normal: np.ndarray,
                          df_normal):
        """
        Compute normalisation references from normal-only data.
        Must be called before fuse_scores().
        """
        print("[hybrid] Computing normalisation references on normal data …")
        self._lstm_ref = self.lstm_det.anomaly_score(X_seq_normal)
        self._gnn_ref  = self.gnn_det.anomaly_score(X_node_normal)
        self._phys_ref = physics_anomaly_score(df_normal)
        print(f"  LSTM score range: [{self._lstm_ref.min():.4f}, {self._lstm_ref.max():.4f}]")
        print(f"  GNN  score range: [{self._gnn_ref.min():.4f},  {self._gnn_ref.max():.4f}]")
        print(f"  Phys score range: [{self._phys_ref.min():.4f}, {self._phys_ref.max():.4f}]")

    def fit_weights(self, X_seq: np.ndarray, X_node: np.ndarray,
                    df, y: np.ndarray,
                    epochs: int = 30, lr: float = 1e-3):
        """
        Fit the supervised MLP fusion layer using labelled data.
        Call fit_normalisation() first.

        Parameters
        ----------
        X_seq  : (N, seq_len, feat_dim) — for LSTM
        X_node : (N, n_nodes, node_feat) — for GNN
        df     : DataFrame with physics features — for physics score
        y      : (N,) binary labels (0=normal, 1=attack)
        """
        if self._lstm_ref is None:
            raise RuntimeError("Call fit_normalisation() before fit_weights().")

        print("[hybrid] Computing anomaly scores for fusion training …")
        s_lstm = normalise_scores(self.lstm_det.anomaly_score(X_seq),  self._lstm_ref)
        s_gnn  = normalise_scores(self.gnn_det.anomaly_score(X_node),  self._gnn_ref)
        s_phys = normalise_scores(physics_anomaly_score(df),           self._phys_ref)

        S = np.stack([s_lstm, s_gnn, s_phys], axis=1)   # (N, 3)

        if len(np.unique(y)) < 2:
            print("[hybrid] Only one class — using equal weights (unsupervised mode).")
            self.mode = 'equal'
            return

        self.mode = 'supervised'

        # Option A — logistic regression (fast, interpretable)
        self._lr_fusion = LogisticRegression(class_weight='balanced', C=1.0)
        self._lr_fusion.fit(S, y)
        print(f"[hybrid] LR fusion weights: "
              f"LSTM={self._lr_fusion.coef_[0][0]:.3f}  "
              f"GNN={self._lr_fusion.coef_[0][1]:.3f}  "
              f"Phys={self._lr_fusion.coef_[0][2]:.3f}")

        # Option B — MLP (uncomment to use instead)
        # S_t = torch.tensor(S, dtype=torch.float32).to(self.device)
        # y_t = torch.tensor(y, dtype=torch.float32).to(self.device)
        # self._fusion_mlp = _FusionMLP().to(self.device)
        # opt = torch.optim.Adam(self._fusion_mlp.parameters(), lr=lr)
        # for ep in range(epochs):
        #     pred = self._fusion_mlp(S_t)
        #     loss = F.binary_cross_entropy(pred, y_t)
        #     opt.zero_grad(); loss.backward(); opt.step()

    # ── Inference ────────────────────────────────────────────────────────

    def fuse_scores(self, X_seq: np.ndarray,
                    X_node: np.ndarray,
                    df) -> np.ndarray:
        """
        Compute final fusion score for each sample.
        Shape: (N,), in [0, 1].
        """
        s_lstm = normalise_scores(self.lstm_det.anomaly_score(X_seq),  self._lstm_ref)
        s_gnn  = normalise_scores(self.gnn_det.anomaly_score(X_node),  self._gnn_ref)
        s_phys = normalise_scores(physics_anomaly_score(df),           self._phys_ref)

        S = np.stack([s_lstm, s_gnn, s_phys], axis=1)   # (N, 3)

        if self.mode == 'supervised' and self._lr_fusion is not None:
            return self._lr_fusion.predict_proba(S)[:, 1]
        else:
            # Equal weighted average
            return S.mean(axis=1)

    def fit_threshold(self, X_seq_normal, X_node_normal, df_normal,
                      fpr: float = 0.01) -> float:
        scores = self.fuse_scores(X_seq_normal, X_node_normal, df_normal)
        self.threshold_ = float(np.quantile(scores, 1.0 - fpr))
        print(f"[hybrid] Threshold={self.threshold_:.4f} (FPR={fpr:.2f})")
        return self.threshold_

    def predict(self, X_seq, X_node, df) -> np.ndarray:
        if self.threshold_ is None:
            raise RuntimeError("Call fit_threshold() before predict().")
        return (self.fuse_scores(X_seq, X_node, df) > self.threshold_).astype(int)

    # ── Per-component breakdown (for paper Table) ─────────────────────────

    def score_breakdown(self, X_seq, X_node, df) -> dict:
        """
        Returns raw and normalised scores per component.
        Useful for generating Table III in your paper.
        """
        raw_lstm  = self.lstm_det.anomaly_score(X_seq)
        raw_gnn   = self.gnn_det.anomaly_score(X_node)
        raw_phys  = physics_anomaly_score(df)
        norm_lstm = normalise_scores(raw_lstm, self._lstm_ref)
        norm_gnn  = normalise_scores(raw_gnn,  self._gnn_ref)
        norm_phys = normalise_scores(raw_phys, self._phys_ref)
        fused     = self.fuse_scores(X_seq, X_node, df)

        return {
            'raw_lstm':   raw_lstm,
            'raw_gnn':    raw_gnn,
            'raw_physics':raw_phys,
            'norm_lstm':  norm_lstm,
            'norm_gnn':   norm_gnn,
            'norm_physics':norm_phys,
            'fused':      fused,
        }

    # ── Attack localisation (bonus: tells you WHERE the attack is) ────────

    def localise_attack(self, X_seq, X_node, df,
                        top_k: int = 3) -> list:
        """
        Returns the top-k most anomalous node names for each sample.
        Uses GNN node-level scores for spatial localisation.
        """
        node_scores = self.gnn_det.node_scores(X_node)   # (N, n_nodes)
        from .gnn_ids import NODE_NAMES
        results = []
        for row_scores in node_scores:
            top_idx = np.argsort(row_scores)[::-1][:top_k]
            results.append([NODE_NAMES[i] for i in top_idx])
        return results
