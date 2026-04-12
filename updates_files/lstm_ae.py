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
  from models.lstm_ae import LSTMAEDetector
  det = LSTMAEDetector(input_dim=174, hidden_dim=64, seq_len=30)
  det.fit(X_normal_sequences)           # X shape: (N, seq_len, input_dim)
  scores = det.anomaly_score(X_test)    # shape: (N,)  higher = more anomalous
  threshold = det.fit_threshold(X_val_normal, fpr=0.01)
  preds = (scores > threshold).astype(int)
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
        return out, h_n[-1]   # return full output + last hidden state


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
    input_dim  : number of features per timestep
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

        self.model = LSTMAutoencoder(input_dim, hidden_dim, seq_len).to(self.device)
        self._loss_fn = nn.MSELoss(reduction='none')

    # ── Training ──────────────────────────────────────────────────────────

    def fit(self, X_normal: np.ndarray, epochs: int = 20,
            val_split: float = 0.1, verbose: bool = True):
        """
        Train on normal-only sequences.

        Parameters
        ----------
        X_normal : np.ndarray of shape (N, seq_len, input_dim)
        """
        X_t = torch.tensor(X_normal, dtype=torch.float32)
        n_val = max(1, int(len(X_t) * val_split))
        idx   = torch.randperm(len(X_t))
        X_tr  = X_t[idx[n_val:]]
        X_val = X_t[idx[:n_val]]

        loader = DataLoader(TensorDataset(X_tr), batch_size=self.batch_size,
                            shuffle=True, drop_last=True)

        opt    = torch.optim.Adam(self.model.parameters(), lr=self.lr)
        sched  = torch.optim.lr_scheduler.StepLR(opt, step_size=10, gamma=0.5)

        best_val = float('inf')
        best_state = None

        self.model.train()
        for epoch in range(epochs):
            train_loss = 0.0
            for (xb,) in loader:
                xb = xb.to(self.device)
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

    def _eval_loss(self, X_t):
        self.model.eval()
        with torch.no_grad():
            recon = self.model(X_t)
            loss  = self._loss_fn(recon, X_t).mean()
        self.model.train()
        return loss.item()

    # ── Scoring ───────────────────────────────────────────────────────────

    def anomaly_score(self, X: np.ndarray) -> np.ndarray:
        """
        Per-sequence reconstruction error.  Shape: (N,).
        Higher score = more anomalous.
        """
        self.model.eval()
        scores = []
        loader = DataLoader(
            TensorDataset(torch.tensor(X, dtype=torch.float32)),
            batch_size=self.batch_size, shuffle=False
        )
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
        Set threshold at the (1-fpr) quantile of normal validation scores.
        fpr=0.01 means 1% of normal sequences are flagged as anomalies.
        """
        scores = self.anomaly_score(X_val_normal)
        self.threshold_ = float(np.quantile(scores, 1.0 - fpr))
        print(f"[lstm_ae] Threshold set at {self.threshold_:.5f} "
              f"(FPR={fpr:.2f}, {len(scores)} val sequences)")
        return self.threshold_

    def predict(self, X: np.ndarray) -> np.ndarray:
        """Binary predictions. Returns 1 for anomaly, 0 for normal."""
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
        ck  = torch.load(path, map_location='cpu')
        det = cls(ck['input_dim'], ck['hidden_dim'], ck['seq_len'], device=device)
        det.model.load_state_dict(ck['model_state'])
        det.threshold_ = ck.get('threshold')
        return det


# ─────────────────────────────────────────────────────────────────────────────
# Sequence builder — converts flat DataFrame to sliding windows
# ─────────────────────────────────────────────────────────────────────────────

def build_sequences(X: np.ndarray, seq_len: int = 30,
                    step: int = 1) -> np.ndarray:
    """
    Convert (N, features) array to (M, seq_len, features) sliding windows.

    Parameters
    ----------
    X       : scaled feature matrix, shape (N, F)
    seq_len : window length (timesteps)
    step    : stride between windows (1 = fully overlapping, seq_len = non-overlapping)

    Returns
    -------
    windows : shape (M, seq_len, F)
    """
    N, F = X.shape
    starts  = range(0, N - seq_len + 1, step)
    windows = np.stack([X[i:i+seq_len] for i in starts])
    return windows   # (M, seq_len, F)


def build_sequences_with_labels(X: np.ndarray, y: np.ndarray,
                                seq_len: int = 30,
                                step: int = 1):
    """
    Build sequences and assign label = max(y) over each window.
    A window is labelled as anomalous if ANY timestep inside is an attack.
    """
    windows = build_sequences(X, seq_len, step)
    labels  = np.array([
        int(y[i:i+seq_len].max())
        for i in range(0, len(X) - seq_len + 1, step)
    ])
    return windows, labels
