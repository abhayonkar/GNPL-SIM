"""
ml_pipeline/models/__init__.py
================================
Package init — exposes all three IDS model tiers.
Required for relative imports in hybrid_ids.py to resolve correctly
when train_temporal_graph.py does:  from models.hybrid_ids import HybridIDS
"""

from .lstm_ae   import (LSTMAEDetector,
                         LSTMAutoencoder,
                         build_sequences,
                         build_sequences_with_labels)

from .gnn_ids   import (GraphAnomalyDetector,
                         GraphDeviationNetwork,
                         build_pipeline_adj,
                         build_comm_adj_from_df,
                         build_node_features,
                         DEFAULT_NODE_FEATURE_MAP,
                         NODE_NAMES,
                         PIPELINE_EDGES)

from .hybrid_ids import (HybridIDS,
                          physics_anomaly_score,
                          normalise_scores)

__all__ = [
    # LSTM-AE
    "LSTMAEDetector", "LSTMAutoencoder",
    "build_sequences", "build_sequences_with_labels",
    # GNN
    "GraphAnomalyDetector", "GraphDeviationNetwork",
    "build_pipeline_adj", "build_comm_adj_from_df",
    "build_node_features", "DEFAULT_NODE_FEATURE_MAP",
    "NODE_NAMES", "PIPELINE_EDGES",
    # Hybrid
    "HybridIDS", "physics_anomaly_score", "normalise_scores",
]
