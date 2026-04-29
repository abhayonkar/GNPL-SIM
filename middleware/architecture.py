"""
architecture.py - Shared architecture manifest loader for middleware tools.
"""

from __future__ import annotations

import json
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def manifest_path() -> Path:
    return _repo_root() / "config" / "canonical_architecture.json"


def load_architecture() -> dict:
    with manifest_path().open("r", encoding="utf-8") as fh:
        return json.load(fh)


ARCHITECTURE = load_architecture()
RUNTIME_TOPOLOGY = ARCHITECTURE["runtime_topology"]
GATEWAY_PACKET = ARCHITECTURE["gateway_packet"]
PLC_SPLIT = ARCHITECTURE["plc_split"]

NODE_NAMES = RUNTIME_TOPOLOGY["node_names"]
EDGE_NAMES = [edge["name"] for edge in RUNTIME_TOPOLOGY["active_edges"]]
PLANNED_EDGE_NAMES = [edge["name"] for edge in RUNTIME_TOPOLOGY["planned_edges"]]
PRESSURE_TAGS = GATEWAY_PACKET["pressure_tags"]
FLOW_TAGS = GATEWAY_PACKET["flow_tags"]
TEMPERATURE_TAGS = GATEWAY_PACKET["temperature_tags"]

ACTUATOR_SPECS = GATEWAY_PACKET["actuators"]
COIL_SPECS = GATEWAY_PACKET["coils"]

ACTUATOR_NAMES = [spec["name"] for spec in ACTUATOR_SPECS]
ACTUATOR_SCALES = [spec["scale"] for spec in ACTUATOR_SPECS]
ACTUATOR_UNITS = [spec["unit"] for spec in ACTUATOR_SPECS]
ACTUATOR_DEFAULTS = {
    "cs1_ratio_cmd": 1250,
    "cs2_ratio_cmd": 1150,
    "valve_E8_cmd": 1000,
    "valve_E14_cmd": 1000,
    "valve_E15_cmd": 1000,
    "prs1_setpoint": 3000,
    "prs2_setpoint": 2500,
    "cs1_power_kW": 0,
    "cs2_power_kW": 0,
}

COIL_NAMES = [spec["name"] for spec in COIL_SPECS]
COIL_DEFAULTS = {name: False for name in COIL_NAMES}

SENSOR_MAP = [
    *[(f"p_{name}_bar", i, 100, "bar") for i, name in enumerate(NODE_NAMES)],
    *[(f"q_{name}_kgs", 20 + i, 100, "kg/s") for i, name in enumerate(EDGE_NAMES)],
    *[(f"T_{name}_K", 40 + i, 10, "K") for i, name in enumerate(NODE_NAMES)],
    ("demand_scalar", 60, 1000, ""),
]

ACTUATOR_MAP = [
    (spec["name"], spec["address"], spec["scale"], spec["unit"])
    for spec in ACTUATOR_SPECS
]

COIL_MAP = [(spec["name"], spec["address"]) for spec in COIL_SPECS]


def _plc_sensor_tags(plc_name: str) -> set[str]:
    split_cfg = PLC_SPLIT[plc_name]
    tags = {"demand_scalar"}
    tags.update({f"p_{name}" for name in split_cfg["owned_nodes"]})
    tags.update({f"T_{name}" for name in split_cfg["owned_nodes"]})
    tags.update({f"q_{name}" for name in split_cfg["owned_edges"]})
    return tags


PLC_NAMES = ("plc_a", "plc_b")
PLC_SENSOR_TAGS = {name: _plc_sensor_tags(name) for name in PLC_NAMES}
PLC_ACTUATOR_TAGS = {
    name: set(PLC_SPLIT[name]["owned_actuators"]) for name in PLC_NAMES
}
PLC_COIL_TAGS = {
    name: set(PLC_SPLIT[name]["owned_coils"]) for name in PLC_NAMES
}
PLC_SHARED_COILS = set(PLC_SPLIT.get("shared_coils", []))


def build_default_sensor_payload() -> dict[str, int]:
    payload = {f"p_{name}": 5000 for name in NODE_NAMES}
    payload.update({f"q_{name}": 0 for name in EDGE_NAMES})
    payload.update({f"T_{name}": 2850 for name in NODE_NAMES})
    payload["demand_scalar"] = 750
    return payload


def build_plc_sensor_payload(sensor_ints: dict, plc_name: str) -> dict[str, int]:
    payload = build_default_sensor_payload()
    owned = PLC_SENSOR_TAGS[plc_name]
    for key in owned:
        if key in sensor_ints:
            payload[key] = sensor_ints[key]
    return payload
