"""
models/gnn_ids.py — Graph Neural Network for CPS Anomaly Detection
====================================================================
Role in the IDS stack:
  GRAPH-AWARE — models the physical topology of the 20-node CGD network
  and the Modbus communication graph (who talks to whom).

  Detects attacks that change communication patterns or create
  topology-inconsistent pressure/flow readings:
    - MITM (new communication pair appears)
    - Command injection (SCADA_01 → wrong device)
    - Replay (abnormal inter_pkt_ms on specific edges)
    - Latency attack (PLCLatencyAttack, A7)

Architecture (simplified GDN — Graph Deviation Network):
  1. For each node, learn attention-weighted embedding from its neighbours
  2. Predict each node's feature vector from its neighbourhood embedding
  3. Anomaly score = deviation between predicted and actual node features

FIXES vs original version:
  FIX 1 — torch.load() called without weights_only= argument.
           PyTorch ≥2.0 raises FutureWarning. Fixed: weights_only=False
           (explicit, since checkpoint contains non-tensor int/str metadata).
"""

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset


# ─────────────────────────────────────────────────────────────────────────────
# Topology constants — must match cfg.edges and cfg.nodeNames exactly
# ─────────────────────────────────────────────────────────────────────────────

# Physical pipeline edges — 0-indexed, matching simConfig.m cfg.edges
PIPELINE_EDGES = [
    (0,  1),   # E1:  S1  → J1
    (1,  2),   # E2:  J1  → CS1
    (2,  3),   # E3:  CS1 → J2
    (3,  4),   # E4:  J2  → J3
    (4,  5),   # E5:  J3  → J4
    (5,  6),   # E6:  J4  → CS2
    (6,  7),   # E7:  CS2 → J5
    (7,  8),   # E8:  J5  → J6
    (8,  9),   # E9:  J6  → PRS1
    (9,  10),  # E10: PRS1→ J7
    (10, 11),  # E11: J7  → STO
    (11, 12),  # E12: STO → PRS2
    (12, 13),  # E13: PRS2→ S2
    (13, 14),  # E14: S2  → D1
    (14, 15),  # E15: D1  → D2
    (15, 16),  # E16: D2  → D3
    (16, 17),  # E17: D3  → D4
    (17, 18),  # E18: D4  → D5
    (18, 19),  # E19: D5  → D6
    (1,  10),  # E20: J1  → J7  (resilience edge)
]

NODE_NAMES = [
    "S1", "J1", "CS1", "J2", "J3", "J4", "CS2",
    "J5", "J6", "PRS1", "J7", "STO", "PRS2", "S2",
    "D1", "D2", "D3", "D4", "D5", "D6",
]


# ─────────────────────────────────────────────────────────────────────────────
# Adjacency matrix builders
# ─────────────────────────────────────────────────────────────────────────────

def build_pipeline_adj(n_nodes: int = 20,
                       bidirectional: bool = True) -> torch.Tensor:
    """
    Build row-normalised adjacency matrix for the 20-node pipeline topology.

    Parameters
    ----------
    n_nodes       : number of nodes (20 for the CGD network)
    bidirectional : if True, add reverse edges (undirected graph)

    Returns
    -------
    adj : (n_nodes, n_nodes) float tensor, row-normalised with self-loops
    """
    adj = torch.zeros(n_nodes, n_nodes)
    for i, j in PIPELINE_EDGES:
        if i < n_nodes and j < n_nodes:
            adj[i, j] = 1.0
            if bidirectional:
                adj[j, i] = 1.0
    # Self-loops (every node attends to itself)
    adj += torch.eye(n_nodes)
    # Row-normalise so attention weights sum to 1
    deg = adj.sum(dim=1, keepdim=True).clamp(min=1)
    return adj / deg


def build_comm_adj_from_df(df, n_devices: int = 23) -> torch.Tensor:
    """
    Build a device communication adjacency matrix from network_logger CSV.
    Edge weight = normalised communication frequency between device pairs.

    Parameters
    ----------
    df        : pandas DataFrame with columns src_id, dst_id (device ID strings)
    n_devices : number of devices in device_registry.m (23 for full network)

    Returns
    -------
    adj : (n_devices, n_devices) float tensor, row-normalised
    """
    # Device ID string → integer index (matches device_registry.m zone order)
    DEVICE_IDX = {
        'SCADA_01': 0, 'HIST_01': 1,  'ENG_01': 2,
        'PLC_001':  3, 'PLC_002': 4,  'PLC_003': 5,  'PLC_004': 6,
        'RTU_005':  7, 'RTU_006': 8,  'RTU_007': 9,  'RTU_008': 10,
        'RTU_009': 11, 'RTU_010': 12, 'RTU_011': 13,
        'PLC_012': 14, 'PLC_013': 15, 'PLC_014': 16,
        'RTU_015': 17, 'RTU_016': 18, 'RTU_017': 19,
        'RTU_018': 20, 'RTU_019': 21, 'RTU_020': 22,
    }
    adj = torch.zeros(n_devices, n_devices)
    if 'src_id' not in df.columns or 'dst_id' not in df.columns:
        return adj + torch.eye(n_devices)

    for _, row in df.iterrows():
        i = DEVICE_IDX.get(row['src_id'], -1)
        j = DEVICE_IDX.get(row['dst_id'], -1)
        if i >= 0 and j >= 0:
            adj[i, j] += 1.0

    adj = adj / (adj.max() + 1e-8)    # normalise to [0, 1]
    adj += torch.eye(n_devices)        # self-loops
    deg = adj.sum(dim=1, keepdim=True).clamp(min=1)
    return adj / deg


# ─────────────────────────────────────────────────────────────────────────────
# GNN layers
# ─────────────────────────────────────────────────────────────────────────────

class GraphAttentionLayer(nn.Module):
    """
    Single graph attention layer.
    For each node i: h_i = σ( Σ_j  α_ij · W · x_j )
    where α_ij is a learned scalar attention weight between nodes i and j.
    """

    def __init__(self, in_dim: int, out_dim: int, n_nodes: int):
        super().__init__()
        self.W    = nn.Linear(in_dim, out_dim, bias=False)
        self.attn = nn.Parameter(torch.randn(n_nodes, n_nodes) * 0.01)

    def forward(self, x: torch.Tensor, adj: torch.Tensor) -> torch.Tensor:
        # x:   (batch, n_nodes, in_dim)
        # adj: (n_nodes, n_nodes)
        h     = self.W(x)                                          # (batch, n_nodes, out_dim)
        alpha = torch.softmax(self.attn * adj, dim=-1)             # (n_nodes, n_nodes)
        out   = torch.einsum('ij,bjk->bik', alpha, h)             # (batch, n_nodes, out_dim)
        return F.relu(out)


class GraphDeviationNetwork(nn.Module):
    """
    Simplified GDN: two graph attention layers + per-node prediction head.

    The network predicts each node's feature vector from its neighbourhood.
    Anomaly score at node i = |predicted_i − actual_i|.
    """

    def __init__(self, node_feat_dim: int, hidden_dim: int, n_nodes: int):
        super().__init__()
        self.gat1 = GraphAttentionLayer(node_feat_dim, hidden_dim, n_nodes)
        self.gat2 = GraphAttentionLayer(hidden_dim,    hidden_dim, n_nodes)
        self.pred = nn.Linear(hidden_dim, node_feat_dim)

    def forward(self, x: torch.Tensor, adj: torch.Tensor) -> torch.Tensor:
        h = self.gat1(x, adj)
        h = self.gat2(h, adj)
        return self.pred(h)   # (batch, n_nodes, node_feat_dim)


# ─────────────────────────────────────────────────────────────────────────────
# High-level detector wrapper
# ─────────────────────────────────────────────────────────────────────────────

class GraphAnomalyDetector:
    """
    Train-predict wrapper around GraphDeviationNetwork.

    Parameters
    ----------
    node_feat_dim : features per node per timestep
                    Default: 3 — (p_*_bar, ekf_resid_*, plc_p_*)
    n_nodes       : number of nodes (20 for pipeline, 23 for comm graph)
    hidden_dim    : GNN hidden dimension (32 is sufficient)
    adj           : adjacency matrix (n_nodes, n_nodes) — use build_pipeline_adj()
    lr            : Adam learning rate
    batch_size    : training batch size
    device        : 'cuda' or 'cpu'

    Input shapes:
      fit()          : X_normal shape (N, n_nodes, node_feat_dim)
      anomaly_score(): X shape (N, n_nodes, node_feat_dim)
      node_scores()  : X shape (N, n_nodes, node_feat_dim) → (N, n_nodes)
    """

    def __init__(self, node_feat_dim: int, n_nodes: int = 20,
                 hidden_dim: int = 32, adj: torch.Tensor = None,
                 lr: float = 1e-3, batch_size: int = 128, device=None):
        self.node_feat_dim = node_feat_dim
        self.n_nodes       = n_nodes
        self.hidden_dim    = hidden_dim
        self.lr            = lr
        self.batch_size    = batch_size
        self.device        = device or ('cuda' if torch.cuda.is_available() else 'cpu')
        self.threshold_    = None

        self.model = GraphDeviationNetwork(
            node_feat_dim, hidden_dim, n_nodes).to(self.device)

        if adj is None:
            adj = build_pipeline_adj(n_nodes)
        self.adj = adj.to(self.device)

        self._loss_fn = nn.MSELoss(reduction='none')

    # ── Training ──────────────────────────────────────────────────────────

    def fit(self, X_normal: np.ndarray, epochs: int = 30,
            val_split: float = 0.1, verbose: bool = True):
        """
        Train on normal-only node feature snapshots.

        Parameters
        ----------
        X_normal : (N, n_nodes, node_feat_dim) — normal operation only
        """
        X_t   = torch.tensor(X_normal, dtype=torch.float32)
        n_val = max(1, int(len(X_t) * val_split))
        idx   = torch.randperm(len(X_t))
        X_tr  = X_t[idx[n_val:]]
        X_val = X_t[idx[:n_val]]

        loader = DataLoader(TensorDataset(X_tr), batch_size=self.batch_size,
                            shuffle=True, drop_last=True)
        opt    = torch.optim.Adam(self.model.parameters(), lr=self.lr,
                                  weight_decay=1e-5)

        best_val   = float('inf')
        best_state = None

        for epoch in range(epochs):
            self.model.train()
            train_loss = 0.0
            for (xb,) in loader:
                xb    = xb.to(self.device)
                pred  = self.model(xb, self.adj)
                loss  = self._loss_fn(pred, xb).mean()
                opt.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(self.model.parameters(), 1.0)
                opt.step()
                train_loss += loss.item()

            val_loss = self._eval_loss(X_val.to(self.device))
            if val_loss < best_val:
                best_val   = val_loss
                best_state = {k: v.cpu().clone()
                              for k, v in self.model.state_dict().items()}

            if verbose:
                print(f"  [gnn] epoch {epoch+1:3d}/{epochs}  "
                      f"train={train_loss/len(loader):.5f}  val={val_loss:.5f}")

        if best_state:
            self.model.load_state_dict(best_state)
        return self

    def _eval_loss(self, X_t: torch.Tensor) -> float:
        self.model.eval()
        with torch.no_grad():
            pred = self.model(X_t, self.adj)
            loss = self._loss_fn(pred, X_t).mean()
        return loss.item()

    # ── Scoring ───────────────────────────────────────────────────────────

    def anomaly_score(self, X: np.ndarray) -> np.ndarray:
        """
        Per-snapshot anomaly score = mean deviation across all nodes.

        Returns
        -------
        scores : (N,) float array — higher = more anomalous
        """
        self.model.eval()
        scores = []
        loader = DataLoader(
            TensorDataset(torch.tensor(X, dtype=torch.float32)),
            batch_size=self.batch_size, shuffle=False)
        with torch.no_grad():
            for (xb,) in loader:
                xb   = xb.to(self.device)
                pred = self.model(xb, self.adj)
                err  = self._loss_fn(pred, xb).mean(dim=(1, 2))   # (batch,)
                scores.append(err.cpu().numpy())
        return np.concatenate(scores)

    def node_scores(self, X: np.ndarray) -> np.ndarray:
        """
        Per-node anomaly scores — for attack localisation.

        Returns
        -------
        scores : (N, n_nodes) float array
                 Higher score at node i → that physical node is anomalous.
        """
        self.model.eval()
        all_scores = []
        loader = DataLoader(
            TensorDataset(torch.tensor(X, dtype=torch.float32)),
            batch_size=self.batch_size, shuffle=False)
        with torch.no_grad():
            for (xb,) in loader:
                xb   = xb.to(self.device)
                pred = self.model(xb, self.adj)
                err  = self._loss_fn(pred, xb).mean(dim=2)         # (batch, n_nodes)
                all_scores.append(err.cpu().numpy())
        return np.concatenate(all_scores, axis=0)

    def fit_threshold(self, X_val_normal: np.ndarray,
                      fpr: float = 0.01) -> float:
        """
        Set threshold at (1-fpr) quantile of normal validation scores.
        """
        scores = self.anomaly_score(X_val_normal)
        self.threshold_ = float(np.quantile(scores, 1.0 - fpr))
        print(f"[gnn] Threshold={self.threshold_:.5f}  (FPR={fpr:.2f})")
        return self.threshold_

    def predict(self, X: np.ndarray) -> np.ndarray:
        """Binary predictions — 1 for anomaly, 0 for normal."""
        if self.threshold_ is None:
            raise RuntimeError("Call fit_threshold() before predict().")
        return (self.anomaly_score(X) > self.threshold_).astype(int)

    # ── Persistence ───────────────────────────────────────────────────────

    def save(self, path: str):
        torch.save({
            'model_state':   self.model.state_dict(),
            'adj':           self.adj.cpu(),
            'threshold':     self.threshold_,
            'node_feat_dim': self.node_feat_dim,
            'n_nodes':       self.n_nodes,
            'hidden_dim':    self.hidden_dim,
        }, path)
        print(f"[gnn] Saved → {path}")

    @classmethod
    def load(cls, path: str, device=None):
        # FIX 1: weights_only=False because checkpoint contains non-tensor metadata
        ck  = torch.load(path, map_location='cpu', weights_only=False)
        det = cls(ck['node_feat_dim'], ck['n_nodes'], ck['hidden_dim'],
                  adj=ck['adj'], device=device)
        det.model.load_state_dict(ck['model_state'])
        det.threshold_ = ck.get('threshold')
        return det


# ─────────────────────────────────────────────────────────────────────────────
# Data preparation helpers
# ─────────────────────────────────────────────────────────────────────────────

def build_node_features(df, node_feature_map: dict) -> np.ndarray:
    """
    Build a (N_timesteps, n_nodes, feat_dim) array from a flat DataFrame.

    Parameters
    ----------
    df               : physics or merged CPS DataFrame (N rows)
    node_feature_map : dict mapping node_name → list of column names
                       e.g. {'S1': ['p_S1_bar', 'ekf_resid_S1', 'plc_p_S1']}
                       Columns not found in df are filled with 0.

    Returns
    -------
    X_nodes : (N, n_nodes, feat_dim) float32
    """
    n_nodes  = len(node_feature_map)
    feat_dim = max(len(v) for v in node_feature_map.values())
    N        = len(df)

    X = np.zeros((N, n_nodes, feat_dim), dtype=np.float32)
    for node_idx, (node_name, cols) in enumerate(node_feature_map.items()):
        for feat_idx, col in enumerate(cols):
            if col in df.columns:
                X[:, node_idx, feat_idx] = (df[col]
                                             .fillna(0)
                                             .values
                                             .astype(np.float32))
    return X


# Default node feature map for the 20-node CGD network
# Each node gets 3 features: physics pressure, EKF residual, PLC reading
# Column names match export_scenario_csv schema exactly
DEFAULT_NODE_FEATURE_MAP = {
    name: [f'p_{name}_bar', f'ekf_resid_{name}', f'plc_p_{name}']
    for name in NODE_NAMES
}
