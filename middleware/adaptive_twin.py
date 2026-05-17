"""
adaptive_twin.py - Physics-constrained adaptive digital twin core.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import numpy as np


def _as_array(values: Any) -> np.ndarray:
    return np.asarray(values, dtype=np.float64).reshape(-1)


@dataclass
class TwinSnapshot:
    measured_pressure: np.ndarray
    predicted_pressure: np.ndarray
    measured_flow: np.ndarray
    predicted_flow: np.ndarray
    physics_score: float
    divergence_by_node: np.ndarray
    anomaly_nodes: list[int]
    metadata: dict[str, Any] = field(default_factory=dict)


class AdaptiveDigitalTwin:
    """
    Lightweight adaptive twin that tracks a shadow state and adapts its
    process uncertainty from recent residuals.
    """

    def __init__(
        self,
        forgetting_factor: float = 0.98,
        q_floor: float = 1e-3,
        q_cap: float = 2.5e-2,
        divergence_threshold: float = 0.75,
    ):
        self.forgetting_factor = float(forgetting_factor)
        self.q_floor = float(q_floor)
        self.q_cap = float(q_cap)
        self.divergence_threshold = float(divergence_threshold)
        self.q_diag: np.ndarray | None = None
        self.shadow_pressure: np.ndarray | None = None
        self.shadow_flow: np.ndarray | None = None

    def update(
        self,
        measured_pressure: Any,
        measured_flow: Any,
        predicted_pressure: Any,
        predicted_flow: Any,
        metadata: dict[str, Any] | None = None,
    ) -> TwinSnapshot:
        measured_pressure = _as_array(measured_pressure)
        measured_flow = _as_array(measured_flow)
        predicted_pressure = _as_array(predicted_pressure)
        predicted_flow = _as_array(predicted_flow)

        residual = np.concatenate(
            [measured_pressure - predicted_pressure, measured_flow - predicted_flow]
        )

        if self.q_diag is None:
            self.q_diag = np.full(residual.shape[0], self.q_floor, dtype=np.float64)
        else:
            self.q_diag = np.clip(
                self.forgetting_factor * self.q_diag
                + (1.0 - self.forgetting_factor) * residual**2,
                self.q_floor,
                self.q_cap,
            )

        self.shadow_pressure = predicted_pressure
        self.shadow_flow = predicted_flow

        divergence = np.abs(measured_pressure - predicted_pressure)
        anomaly_nodes = np.where(divergence >= self.divergence_threshold)[0].tolist()
        physics_score = float(np.linalg.norm(residual) / max(np.sqrt(residual.size), 1.0))

        return TwinSnapshot(
            measured_pressure=measured_pressure,
            predicted_pressure=predicted_pressure,
            measured_flow=measured_flow,
            predicted_flow=predicted_flow,
            physics_score=physics_score,
            divergence_by_node=divergence,
            anomaly_nodes=anomaly_nodes,
            metadata=metadata or {},
        )
