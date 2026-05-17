import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "middleware"))

import numpy as np

from adaptive_twin import AdaptiveDigitalTwin
from decision_engine import DecisionEngine


def test_adaptive_twin_updates_shadow_state():
    twin = AdaptiveDigitalTwin(forgetting_factor=0.9, q_floor=1e-3, q_cap=1e-1, divergence_threshold=0.5)
    snapshot = twin.update(
        measured_pressure=[10.0, 11.0, 12.0],
        measured_flow=[1.0, 2.0],
        predicted_pressure=[9.8, 10.4, 12.8],
        predicted_flow=[1.1, 1.9],
        metadata={"regime_id": 2},
    )

    assert snapshot.predicted_pressure.shape == (3,)
    assert snapshot.divergence_by_node.shape == (3,)
    assert isinstance(snapshot.physics_score, float)
    assert twin.q_diag is not None
    assert snapshot.anomaly_nodes == [1, 2]


def test_decision_engine_escalates_alerts():
    twin = AdaptiveDigitalTwin(divergence_threshold=0.2)
    snapshot = twin.update(
        measured_pressure=[10.0, 12.0],
        measured_flow=[1.0],
        predicted_pressure=[9.0, 10.0],
        predicted_flow=[0.8],
    )

    engine = DecisionEngine(alert_threshold=0.4, critical_threshold=0.8)
    decision = engine.evaluate(snapshot, ml_score=0.9, localisation=["J1", "J2"])

    assert decision.alert is True
    assert decision.severity == "critical"
    assert "Shadow-state divergence" in decision.explanation
