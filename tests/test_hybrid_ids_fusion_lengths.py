"""
tests/test_hybrid_ids_fusion_lengths.py
=======================================
Unit tests for ml_pipeline/models/hybrid_ids.py

Covers:
  FIX 2: fit_normalisation() assertion that all three inputs have equal row count.
  FIX 3: fuse_scores() raises ValueError with diagnostic message if lengths differ.
  Sanity: fuse_scores() returns equal-length output when inputs are aligned.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "ml_pipeline"))

from models.hybrid_ids import (
    HybridIDS,
    normalise_scores,
    physics_anomaly_score,
)


# ── Helpers ────────────────────────────────────────────────────────────────────

def _make_mock_lstm_det(n_samples: int, score_val: float = 0.1):
    """Return a mock LSTMAEDetector whose anomaly_score returns constant array."""
    det = MagicMock()
    det.anomaly_score.return_value = np.full(n_samples, score_val, dtype=np.float32)
    return det


def _make_mock_gnn_det(n_samples: int, score_val: float = 0.2):
    det = MagicMock()
    det.anomaly_score.return_value = np.full(n_samples, score_val, dtype=np.float32)
    det.node_scores.return_value   = np.zeros((n_samples, 20), dtype=np.float32)
    return det


def _make_df(n_rows: int) -> "pd.DataFrame":
    import pandas as pd
    # Minimal DataFrame with columns physics_anomaly_score inspects
    df = pd.DataFrame({
        "ekf_resid_S1": np.random.rand(n_rows).astype(np.float32),
        "ekf_resid_J1": np.random.rand(n_rows).astype(np.float32),
    })
    return df


def _make_hybrid(n_normal: int):
    """Build a HybridIDS with mocked detectors and fitted normalisation."""
    lstm_det = _make_mock_lstm_det(n_normal)
    gnn_det  = _make_mock_gnn_det(n_normal)
    ids = HybridIDS(lstm_det=lstm_det, gnn_det=gnn_det, mode="equal")

    X_seq  = np.random.rand(n_normal, 30, 10).astype(np.float32)
    X_node = np.random.rand(n_normal, 20, 5).astype(np.float32)
    df     = _make_df(n_normal)

    ids.fit_normalisation(X_seq, X_node, df)
    return ids


# ── normalise_scores ───────────────────────────────────────────────────────────

class TestNormaliseScores:
    def test_output_in_01(self):
        ref = np.random.rand(1000).astype(np.float32)
        out = normalise_scores(ref)
        assert out.min() >= 0.0
        assert out.max() <= 1.0

    def test_flat_input_returns_zeros(self):
        scores = np.ones(100, dtype=np.float32)
        out = normalise_scores(scores)
        np.testing.assert_array_equal(out, np.zeros(100))

    def test_ref_scores_used(self):
        ref    = np.linspace(0, 1, 1000).astype(np.float32)
        scores = np.array([0.0, 0.5, 1.0], dtype=np.float32)
        out    = normalise_scores(scores, ref_scores=ref)
        assert out.min() >= 0.0
        assert out.max() <= 1.0


# ── physics_anomaly_score ──────────────────────────────────────────────────────

class TestPhysicsAnomalyScore:
    def test_shape(self):
        import pandas as pd
        df = pd.DataFrame({
            "ekf_resid_S1": [0.1, 0.2, 0.3],
            "ekf_resid_J1": [0.0, 0.1, 0.0],
            "cusum_S_upper": [1.0, 2.0, 0.5],
            "chi2_stat":    [0.0, 5.0, 0.0],
        })
        scores = physics_anomaly_score(df)
        assert scores.shape == (3,)
        assert scores.dtype == np.float32

    def test_nonzero_for_nonzero_input(self):
        import pandas as pd
        df = pd.DataFrame({"ekf_resid_S1": [1.0]})
        scores = physics_anomaly_score(df)
        assert scores[0] > 0.0

    def test_empty_df_returns_zeros(self):
        import pandas as pd
        df = pd.DataFrame({"unrelated_col": [1.0, 2.0]})
        scores = physics_anomaly_score(df)
        np.testing.assert_array_equal(scores, np.zeros(2, dtype=np.float32))


# ── HybridIDS.fit_normalisation ────────────────────────────────────────────────

class TestFitNormalisation:
    def test_passes_with_equal_lengths(self):
        """FIX 2: must not raise when all inputs have the same row count."""
        ids = _make_hybrid(200)   # no exception → pass

    def test_raises_on_mismatched_seq_node(self):
        """FIX 2: assertion fires if seq and node lengths differ."""
        n = 100
        lstm_det = _make_mock_lstm_det(n)
        gnn_det  = _make_mock_gnn_det(n)
        ids = HybridIDS(lstm_det=lstm_det, gnn_det=gnn_det, mode="equal")

        X_seq  = np.random.rand(n,   30, 10).astype(np.float32)
        X_node = np.random.rand(n+5, 20, 5).astype(np.float32)  # mismatched
        df     = _make_df(n)

        with pytest.raises(AssertionError, match="fit_normalisation"):
            ids.fit_normalisation(X_seq, X_node, df)

    def test_raises_on_mismatched_seq_df(self):
        n = 80
        lstm_det = _make_mock_lstm_det(n)
        gnn_det  = _make_mock_gnn_det(n)
        ids = HybridIDS(lstm_det=lstm_det, gnn_det=gnn_det, mode="equal")

        X_seq  = np.random.rand(n,    30, 10).astype(np.float32)
        X_node = np.random.rand(n,    20, 5).astype(np.float32)
        df     = _make_df(n + 10)   # mismatched

        with pytest.raises(AssertionError, match="fit_normalisation"):
            ids.fit_normalisation(X_seq, X_node, df)


# ── HybridIDS.fuse_scores — length equality ────────────────────────────────────

class TestFuseScoresLengths:
    def test_output_length_equals_input_length(self):
        """FIX 3: fused output length == input length when all are aligned."""
        n = 150
        ids = _make_hybrid(n)

        X_seq  = np.random.rand(n, 30, 10).astype(np.float32)
        X_node = np.random.rand(n, 20, 5).astype(np.float32)
        df     = _make_df(n)

        # update mocks to return n-length scores
        ids.lstm_det.anomaly_score.return_value = np.full(n, 0.1)
        ids.gnn_det.anomaly_score.return_value  = np.full(n, 0.2)

        fused = ids.fuse_scores(X_seq, X_node, df)
        assert len(fused) == n

    def test_raises_on_mismatched_score_lengths(self):
        """FIX 3: fuse_scores raises ValueError with diagnostic message."""
        n = 100
        ids = _make_hybrid(n)

        X_seq  = np.random.rand(n, 30, 10).astype(np.float32)
        X_node = np.random.rand(n, 20, 5).astype(np.float32)
        df     = _make_df(n)

        # Force LSTM mock to return wrong length
        ids.lstm_det.anomaly_score.return_value = np.full(n + 10, 0.1)
        ids.gnn_det.anomaly_score.return_value  = np.full(n,      0.2)

        with pytest.raises(ValueError, match="fuse_scores"):
            ids.fuse_scores(X_seq, X_node, df)

    def test_output_range_0_to_1(self):
        """Equal fusion of normalised scores must be in [0, 1]."""
        n = 200
        ids = _make_hybrid(n)

        ids.lstm_det.anomaly_score.return_value = np.random.rand(n).astype(np.float32)
        ids.gnn_det.anomaly_score.return_value  = np.random.rand(n).astype(np.float32)

        X_seq  = np.random.rand(n, 30, 10).astype(np.float32)
        X_node = np.random.rand(n, 20, 5).astype(np.float32)
        df     = _make_df(n)

        fused = ids.fuse_scores(X_seq, X_node, df)
        assert fused.min() >= 0.0
        assert fused.max() <= 1.0

    def test_fit_threshold_uses_fuse_scores(self):
        """fit_threshold() must set threshold_ and return a float."""
        n = 100
        ids = _make_hybrid(n)

        ids.lstm_det.anomaly_score.return_value = np.random.rand(n).astype(np.float32)
        ids.gnn_det.anomaly_score.return_value  = np.random.rand(n).astype(np.float32)

        X_seq  = np.random.rand(n, 30, 10).astype(np.float32)
        X_node = np.random.rand(n, 20, 5).astype(np.float32)
        df     = _make_df(n)

        thr = ids.fit_threshold(X_seq, X_node, df, fpr=0.05)
        assert isinstance(thr, float)
        assert ids.threshold_ == thr
