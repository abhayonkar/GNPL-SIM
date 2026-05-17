"""
decision_engine.py - Alerting and explanation layer for twin outputs.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

try:
    from adaptive_twin import TwinSnapshot
except ImportError:
    from .adaptive_twin import TwinSnapshot


@dataclass
class AlertDecision:
    severity: str
    alert: bool
    score: float
    explanation: str
    anomaly_nodes: list[int]
    metadata: dict[str, Any]


class DecisionEngine:
    def __init__(self, alert_threshold: float = 0.65, critical_threshold: float = 0.85):
        self.alert_threshold = float(alert_threshold)
        self.critical_threshold = float(critical_threshold)

    def evaluate(
        self,
        twin_snapshot: TwinSnapshot,
        ml_score: float | None = None,
        localisation: list[str] | None = None,
    ) -> AlertDecision:
        physics_score = float(twin_snapshot.physics_score)
        fused_score = physics_score if ml_score is None else float((physics_score + ml_score) / 2.0)

        if fused_score >= self.critical_threshold:
            severity = "critical"
        elif fused_score >= self.alert_threshold:
            severity = "warning"
        else:
            severity = "normal"

        node_text = ", ".join(localisation or [str(i) for i in twin_snapshot.anomaly_nodes[:3]])
        if severity == "normal":
            explanation = "Twin and measured state remain within the learned operating envelope."
        else:
            max_div = float(np.max(twin_snapshot.divergence_by_node)) if twin_snapshot.divergence_by_node.size else 0.0
            explanation = (
                f"Shadow-state divergence exceeded threshold; top nodes: {node_text or 'n/a'} "
                f"(max pressure deviation {max_div:.3f} bar)."
            )

        return AlertDecision(
            severity=severity,
            alert=severity != "normal",
            score=fused_score,
            explanation=explanation,
            anomaly_nodes=twin_snapshot.anomaly_nodes,
            metadata=twin_snapshot.metadata,
        )
