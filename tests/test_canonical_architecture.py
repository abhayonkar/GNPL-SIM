"""
tests/test_canonical_architecture.py
===================================
Regression coverage for the shared phase-1 architecture manifest.
"""

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "middleware"))

from architecture import (  # noqa: E402
    ACTUATOR_MAP,
    COIL_MAP,
    EDGE_NAMES,
    NODE_NAMES,
    PLC_ACTUATOR_TAGS,
    PLC_COIL_TAGS,
    PLC_SHARED_COILS,
    PLANNED_EDGE_NAMES,
    SENSOR_MAP,
)


def test_manifest_counts_match_runtime_gateway_contract():
    assert len(NODE_NAMES) == 20
    assert len(EDGE_NAMES) == 20
    assert len(PLANNED_EDGE_NAMES) == 2
    assert len(SENSOR_MAP) == 61
    assert len(ACTUATOR_MAP) == 9
    assert len(COIL_MAP) == 7


def test_manifest_edge_indices_are_contiguous():
    manifest = json.loads((REPO_ROOT / "config" / "canonical_architecture.json").read_text())
    active_indices = [edge["index"] for edge in manifest["runtime_topology"]["active_edges"]]
    planned_indices = [edge["index"] for edge in manifest["runtime_topology"]["planned_edges"]]

    assert active_indices == list(range(1, 21))
    assert planned_indices == [21, 22]


def test_sensor_map_addresses_cover_expected_ranges():
    pressure_addresses = [addr for name, addr, _, _ in SENSOR_MAP if name.startswith("p_")]
    flow_addresses = [addr for name, addr, _, _ in SENSOR_MAP if name.startswith("q_")]
    temp_addresses = [addr for name, addr, _, _ in SENSOR_MAP if name.startswith("T_")]

    assert pressure_addresses == list(range(0, 20))
    assert flow_addresses == list(range(20, 40))
    assert temp_addresses == list(range(40, 60))
    assert SENSOR_MAP[-1][0] == "demand_scalar"
    assert SENSOR_MAP[-1][1] == 60


def test_split_ownership_covers_outputs_cleanly():
    owned_actuators = PLC_ACTUATOR_TAGS["plc_a"] | PLC_ACTUATOR_TAGS["plc_b"]
    owned_coils = PLC_COIL_TAGS["plc_a"] | PLC_COIL_TAGS["plc_b"] | PLC_SHARED_COILS

    assert len(owned_actuators) == len(ACTUATOR_MAP)
    assert len(owned_coils) == len(COIL_MAP)
