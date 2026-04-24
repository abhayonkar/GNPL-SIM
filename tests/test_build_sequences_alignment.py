"""
tests/test_build_sequences_alignment.py
=======================================
Unit tests for ml_pipeline/models/lstm_ae.py

Covers FIX 1: build_sequences_with_labels must produce len(windows) == len(labels)
even when max_sequences cap is applied (previously crashed with length mismatch).
"""

import sys
from pathlib import Path

import numpy as np
import pytest

# Allow running from repo root or from tests/
sys.path.insert(0, str(Path(__file__).parent.parent / "ml_pipeline"))

from models.lstm_ae import (
    _compute_starts,
    build_sequences,
    build_sequences_with_labels,
)


# ── _compute_starts ────────────────────────────────────────────────────────────

class TestComputeStarts:
    def test_basic_no_cap(self):
        starts = _compute_starts(N=100, seq_len=10, step=1, max_sequences=10_000)
        # raw starts: 0..90 (91 values with step=1)
        assert starts[0] == 0
        assert starts[-1] == 90
        assert len(starts) == 91

    def test_basic_with_step(self):
        starts = _compute_starts(N=100, seq_len=10, step=5, max_sequences=10_000)
        # 0, 5, 10, …, 90 → 19 values
        assert len(starts) == 19
        assert starts[0] == 0
        assert starts[-1] == 90

    def test_cap_applied(self):
        """When max_sequences < raw count, returns evenly-spaced subset."""
        starts = _compute_starts(N=1000, seq_len=10, step=1, max_sequences=50)
        assert len(starts) == 50
        assert starts[0] == 0
        assert starts[-1] == 990   # last valid start

    def test_no_overlap_step(self):
        starts = _compute_starts(N=90, seq_len=30, step=30, max_sequences=10_000)
        assert list(starts) == [0, 30, 60]


# ── build_sequences ────────────────────────────────────────────────────────────

class TestBuildSequences:
    def test_shape_no_cap(self):
        X = np.random.rand(200, 10).astype(np.float32)
        windows = build_sequences(X, seq_len=20, step=1, max_sequences=50_000)
        assert windows.shape == (181, 20, 10)

    def test_shape_with_cap(self):
        X = np.random.rand(500, 5).astype(np.float32)
        windows = build_sequences(X, seq_len=10, step=1, max_sequences=100)
        assert windows.shape == (100, 10, 5)

    def test_dtype_float32(self):
        X = np.random.rand(100, 4)          # float64 input
        windows = build_sequences(X, seq_len=10, step=5)
        assert windows.dtype == np.float32

    def test_window_content(self):
        X = np.arange(50, dtype=np.float32).reshape(50, 1)
        windows = build_sequences(X, seq_len=5, step=5, max_sequences=10_000)
        # First window should be rows 0-4
        np.testing.assert_array_equal(windows[0, :, 0], np.arange(5, dtype=np.float32))


# ── build_sequences_with_labels ───────────────────────────────────────────────

class TestBuildSequencesWithLabels:
    """FIX 1 coverage: windows and labels must ALWAYS have equal length."""

    def test_alignment_no_cap(self):
        X = np.random.rand(300, 8).astype(np.float32)
        y = np.zeros(300, dtype=int)
        y[100:150] = 1      # attack window
        windows, labels = build_sequences_with_labels(X, y, seq_len=30, step=1)
        assert len(windows) == len(labels), (
            f"Alignment broken: windows={len(windows)} labels={len(labels)}"
        )

    def test_alignment_with_cap(self):
        """Regression test for FIX 1 — cap must not break alignment."""
        X = np.random.rand(5000, 174).astype(np.float32)
        y = np.random.randint(0, 2, size=5000)
        windows, labels = build_sequences_with_labels(
            X, y, seq_len=30, step=1, max_sequences=200
        )
        assert len(windows) == len(labels) == 200

    def test_label_is_max_in_window(self):
        """A window is labelled 1 if ANY timestep inside is an attack."""
        N = 100
        X = np.random.rand(N, 4).astype(np.float32)
        y = np.zeros(N, dtype=int)
        y[50] = 1   # single attack row
        windows, labels = build_sequences_with_labels(X, y, seq_len=10, step=1)
        # Windows that contain row 50: start indices 41..50
        for start in range(41, 51):
            win_idx = start  # step=1, so window index == start index
            assert labels[win_idx] == 1, (
                f"Window starting at {start} should be labelled 1 (contains attack row 50)"
            )

    def test_all_normal_labels_zero(self):
        X = np.random.rand(100, 4).astype(np.float32)
        y = np.zeros(100, dtype=int)
        _, labels = build_sequences_with_labels(X, y, seq_len=10, step=1)
        assert labels.sum() == 0

    def test_shape_consistency(self):
        X  = np.random.rand(200, 6).astype(np.float32)
        y  = np.random.randint(0, 2, size=200)
        windows, labels = build_sequences_with_labels(X, y, seq_len=15, step=3)
        assert windows.ndim == 3
        assert windows.shape[1] == 15
        assert windows.shape[2] == 6
        assert labels.ndim == 1

    def test_various_caps_always_aligned(self):
        """Parameterised cap sizes — alignment must hold for all."""
        X = np.random.rand(2000, 10).astype(np.float32)
        y = np.random.randint(0, 2, size=2000)
        for cap in [10, 50, 200, 1000, 99_999]:
            windows, labels = build_sequences_with_labels(
                X, y, seq_len=30, step=1, max_sequences=cap
            )
            assert len(windows) == len(labels), (
                f"cap={cap}: windows={len(windows)} labels={len(labels)}"
            )
