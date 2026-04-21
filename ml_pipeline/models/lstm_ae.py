"""
models/lstm_ae.py — LSTM Autoencoder for Temporal Anomaly Detection
====================================================================
Role in the IDS stack:
  UNSUPERVISED — trained on normal-only sequences.
  Anomaly score = reconstruction error on test sequences.
  Detects attack types that unfold over time (FDI ramp, replay,
  compressor manipulation) better than point-in-time models.

Architecture:
  Encoder: LSTM(input_dim → hidden_dim)  → context vector h_T
  Decoder: LSTM(hidden_dim → input_dim)  ← reconstructs input sequence

  The bottleneck (h_T) forces the encoder to compress the normal
  operating pattern. Attacks produce high reconstruction error
  because they lie outside the normal manifold.

Usage:
  from models.lstm_ae import LSTMAEDetector, build_sequences, build_sequences_with_labels
  det = LSTMAEDetector(input_dim=174, hidden_dim=64, seq_len=30)
  det.fit(X_normal_sequences)           # X shape: (N, seq_len, input_dim)
  scores = det.anomaly_score(X_test)    # shape: (N,)  higher = more anomalous
  threshold = det.fit_threshold(X_val_normal, fpr=0.01)
  preds = (scores > threshold).astype(int)

FIXES vs original version:
  FIX 1 — build_sequences_with_labels used a separate range() loop for labels
           that did NOT account for max_sequences capping inside build_sequences.
           Result: len(windows) != len(labels) → crash in downstream np.stack.
           Fix: _compute_starts() helper shared by BOTH functions.

  FIX 2 — Misleading docstring in build_sequences claimed step=5 as default
           but function signature had step=1. Corrected to match actual default.

  FIX 3 — torch.load() called without weights_only= argument.
           PyTorch ≥2.0 raises FutureWarning. Fixed: weights_only=False
           (explicit, since checkpoint contains non-tensor metadata).
"""

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from pathlib import Path


# ─────────────────────────────────────────────────────────────────────────────
# Network definition
# ─────────────────────────────────────────────────────────────────────────────

class _LSTMEncoder(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int, num_layers: int = 1):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden_dim, num_layers,
                            batch_first=True, dropout=0.0)

    def forward(self, x):
        # x: (batch, seq_len, input_dim)
        out, (h_n, _) = self.lstm(x)
        return out, h_n[-1]   # full output + last hidden state


class _LSTMDecoder(nn.Module):
    def __init__(self, hidden_dim: int, output_dim: int, seq_len: int,
                 num_layers: int = 1):
        super().__init__()
        self.seq_len = seq_len
        self.lstm    = nn.LSTM(hidden_dim, hidden_dim, num_layers,
                               batch_first=True, dropout=0.0)
        self.fc      = nn.Linear(hidden_dim, output_dim)

    def forward(self, h):
        # h: (batch, hidden_dim) — repeat across seq_len
        h_rep = h.unsqueeze(1).repeat(1, self.seq_len, 1)
        out, _ = self.lstm(h_rep)
        return self.fc(out)   # (batch, seq_len, output_dim)


class LSTMAutoencoder(nn.Module):
    """LSTM sequence autoencoder."""

    def __init__(self, input_dim: int, hidden_dim: int = 64, seq_len: int = 30):
        super().__init__()
        self.encoder = _LSTMEncoder(input_dim, hidden_dim)
        self.decoder = _LSTMDecoder(hidden_dim, input_dim, seq_len)

    def forward(self, x):
        _, h = self.encoder(x)
        return self.decoder(h)

    def encode(self, x):
        _, h = self.encoder(x)
        return h


# ─────────────────────────────────────────────────────────────────────────────
# High-level detector wrapper
# ─────────────────────────────────────────────────────────────────────────────

class LSTMAEDetector:
    """
    Train-predict wrapper around LSTMAutoencoder.

    Parameters
    ----------
    input_dim  : number of features per timestep (174 for CGD pipeline dataset)
    hidden_dim : LSTM hidden size (64 recommended for ~174 features)
    seq_len    : window length in timesteps (30 = 30 s at 1 Hz)
    lr         : Adam learning rate
    batch_size : training batch size
    device     : 'cuda' or 'cpu' (auto-detected if None)
    """

    def __init__(self, input_dim: int, hidden_dim: int = 64, seq_len: int = 30,
                 lr: float = 1e-3, batch_size: int = 256, device=None):
        self.input_dim  = input_dim
        self.hidden_dim = hidden_dim
        self.seq_len    = seq_len
        self.lr         = lr
        self.batch_size = batch_size
        self.device     = device or ('cuda' if torch.cuda.is_available() else 'cpu')
        self.threshold_ = None

        self.model    = LSTMAutoencoder(input_dim, hidden_dim, seq_len).to(self.device)
        self._loss_fn = nn.MSELoss(reduction='none')

    # ── Training ──────────────────────────────────────────────────────────

    def fit(self, X_normal: np.ndarray, epochs: int = 20,
            val_split: float = 0.1, verbose: bool = True):
        """
        Train on normal-only sequences.

        Parameters
        ----------
        X_normal : np.ndarray shape (N, seq_len, input_dim)
                   Build from flat arrays using build_sequences().
        """
        X_t   = torch.tensor(X_normal, dtype=torch.float32)
        n_val = max(1, int(len(X_t) * val_split))
        idx   = torch.randperm(len(X_t))
        X_tr  = X_t[idx[n_val:]]
        X_val = X_t[idx[:n_val]]

        loader = DataLoader(TensorDataset(X_tr), batch_size=self.batch_size,
                            shuffle=True, drop_last=True)
        opt    = torch.optim.Adam(self.model.parameters(), lr=self.lr)
        sched  = torch.optim.lr_scheduler.StepLR(opt, step_size=10, gamma=0.5)

        best_val   = float('inf')
        best_state = None

        self.model.train()
        for epoch in range(epochs):
            train_loss = 0.0
            for (xb,) in loader:
                xb    = xb.to(self.device)
                recon = self.model(xb)
                loss  = self._loss_fn(recon, xb).mean()
                opt.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(self.model.parameters(), 1.0)
                opt.step()
                train_loss += loss.item()
            sched.step()

            val_loss = self._eval_loss(X_val.to(self.device))
            if val_loss < best_val:
                best_val   = val_loss
                best_state = {k: v.cpu().clone()
                              for k, v in self.model.state_dict().items()}

            if verbose:
                print(f"  [lstm_ae] epoch {epoch+1:3d}/{epochs}  "
                      f"train={train_loss/len(loader):.5f}  val={val_loss:.5f}")

        if best_state:
            self.model.load_state_dict(best_state)
        return self

    def _eval_loss(self, X_t: torch.Tensor) -> float:
        self.model.eval()
        with torch.no_grad():
            recon = self.model(X_t)
            loss  = self._loss_fn(recon, X_t).mean()
        self.model.train()
        return loss.item()

    # ── Scoring ───────────────────────────────────────────────────────────

    def anomaly_score(self, X: np.ndarray) -> np.ndarray:
        """
        Per-sequence reconstruction error. Shape: (N,).
        Higher score = more anomalous.
        """
        self.model.eval()
        scores = []
        loader = DataLoader(
            TensorDataset(torch.tensor(X, dtype=torch.float32)),
            batch_size=self.batch_size, shuffle=False)
        with torch.no_grad():
            for (xb,) in loader:
                xb    = xb.to(self.device)
                recon = self.model(xb)
                err   = self._loss_fn(recon, xb).mean(dim=(1, 2))
                scores.append(err.cpu().numpy())
        return np.concatenate(scores)

    def fit_threshold(self, X_val_normal: np.ndarray,
                      fpr: float = 0.01) -> float:
        """
        Set threshold at (1 - fpr) quantile of normal validation scores.
        fpr=0.01 → 1% of normal sequences flagged as anomalies.
        """
        scores = self.anomaly_score(X_val_normal)
        self.threshold_ = float(np.quantile(scores, 1.0 - fpr))
        print(f"[lstm_ae] Threshold={self.threshold_:.5f} "
              f"(FPR={fpr:.2f}, {len(scores)} val sequences)")
        return self.threshold_

    def predict(self, X: np.ndarray) -> np.ndarray:
        """Binary predictions — 1 for anomaly, 0 for normal."""
        if self.threshold_ is None:
            raise RuntimeError("Call fit_threshold() before predict().")
        return (self.anomaly_score(X) > self.threshold_).astype(int)

    # ── Persistence ───────────────────────────────────────────────────────

    def save(self, path: str):
        torch.save({
            'model_state': self.model.state_dict(),
            'threshold':   self.threshold_,
            'input_dim':   self.input_dim,
            'hidden_dim':  self.hidden_dim,
            'seq_len':     self.seq_len,
        }, path)
        print(f"[lstm_ae] Saved → {path}")

    @classmethod
    def load(cls, path: str, device=None):
        # FIX 3: weights_only=False because checkpoint contains int/str metadata
        ck  = torch.load(path, map_location='cpu', weights_only=False)
        det = cls(ck['input_dim'], ck['hidden_dim'], ck['seq_len'], device=device)
        det.model.load_state_dict(ck['model_state'])
        det.threshold_ = ck.get('threshold')
        return det


# ─────────────────────────────────────────────────────────────────────────────
# Sequence builder — converts flat (N, features) array to sliding windows
# ─────────────────────────────────────────────────────────────────────────────

def _compute_starts(N: int, seq_len: int, step: int,
                    max_sequences: int) -> np.ndarray:
    """
    Single source of truth for sliding-window start indices.
    Used by BOTH build_sequences() and build_sequences_with_labels()
    so len(windows) == len(labels) even when max_sequences cap is applied.

    Parameters
    ----------
    N             : total number of rows in X
    seq_len       : window length
    step          : stride between consecutive windows
    max_sequences : hard cap; evenly-spaced subset taken when exceeded

    Returns
    -------
    starts : 1-D int array of start row indices
    """
    raw_starts = np.arange(0, N - seq_len + 1, step)
    if len(raw_starts) > max_sequences:
        idx = np.linspace(0, len(raw_starts) - 1, max_sequences, dtype=int)
        return raw_starts[idx]
    return raw_starts


def build_sequences(X: np.ndarray,
                    seq_len: int = 30,
                    step: int = 1,
                    max_sequences: int = 50_000) -> np.ndarray:
    """
    Build sliding-window sequences from a flat (N, features) array.

    Memory guide for CGD pipeline dataset (174 features, float32):
      step=1,  max_sequences=50_000  → ~1.0 GB  (normal training set)
      step=5,  max_sequences=20_000  → ~0.2 GB  (test set, lighter)
      step=15, max_sequences=10_000  → ~0.1 GB  (quick eval)

    Parameters
    ----------
    X             : (N, n_features) array — cast to float32 internally
    seq_len       : window length in timesteps (30 = 30 s at 1 Hz)
    step          : stride between consecutive windows
                    (step=1 = maximum overlap; step=seq_len = no overlap)
    max_sequences : hard cap on number of windows (memory safety)

    Returns
    -------
    windows : (n_seq, seq_len, n_features) float32
    """
    X      = X.astype(np.float32)
    starts = _compute_starts(len(X), seq_len, step, max_sequences)
    return np.stack([X[i:i + seq_len] for i in starts])


def build_sequences_with_labels(X: np.ndarray,
                                y: np.ndarray,
                                seq_len: int = 30,
                                step: int = 1,
                                max_sequences: int = 50_000):
    """
    Build sequences and assign label = max(y) over each window.
    A window is labelled anomalous (1) if ANY timestep inside is an attack.

    CRITICAL FIX: uses _compute_starts() for BOTH windows and labels so
    len(windows) == len(labels) even when max_sequences cap is applied.
    Previous version used a separate range() for labels → length mismatch crash.

    Parameters
    ----------
    X             : (N, n_features) float array
    y             : (N,) integer label array
    seq_len       : window length
    step          : stride between consecutive windows
    max_sequences : hard cap on number of windows

    Returns
    -------
    windows : (n_seq, seq_len, n_features) float32
    labels  : (n_seq,) int  — 1 if any timestep in window is an attack
    """
    X = X.astype(np.float32)

    # Single shared starts array — guarantees alignment
    starts  = _compute_starts(len(X), seq_len, step, max_sequences)
    windows = np.stack([X[i:i + seq_len] for i in starts])
    labels  = np.array([int(y[i:i + seq_len].max()) for i in starts])

    assert len(windows) == len(labels), (
        f"BUG: windows={len(windows)} labels={len(labels)} — should never happen")

    return windows, labels
