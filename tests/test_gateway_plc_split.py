"""
tests/test_gateway_plc_split.py
================================
Coverage for phase-2 PLC A / PLC B gateway routing and merge behavior.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "middleware"))

from architecture import (  # noqa: E402
    ACTUATOR_DEFAULTS,
    COIL_DEFAULTS,
    PLC_ACTUATOR_TAGS,
    PLC_COIL_TAGS,
    PLC_SHARED_COILS,
    build_plc_sensor_payload,
)
from gateway import GatewayPLCManager  # noqa: E402


class FakePLC:

    def __init__(self, host, port, unit_id):
        self.host = host
        self.port = port
        self.unit_id = unit_id
        self.connected = True
        self.last_write = None
        self._act = None
        self._coils = None

    def connect(self):
        return True

    def disconnect(self):
        self.connected = False

    def is_connected(self):
        return self.connected

    def write_sensors(self, payload):
        self.last_write = dict(payload)
        return True

    def read_actuators(self):
        return self._act

    def read_coils(self):
        return self._coils

    def reconnect(self):
        self.connected = True
        return True


def _split_config():
    return {
        "plc_mode": "split",
        "plcs": {
            "plc_a": {"host": "127.0.0.1", "port": 1502, "unit_id": 1},
            "plc_b": {"host": "127.0.0.1", "port": 1503, "unit_id": 1},
        },
        "matlab": {"recv_ip": "0.0.0.0", "recv_port": 5005, "send_ip": "127.0.0.1", "send_port": 6006},
    }


def _single_config():
    return {
        "plc_mode": "single",
        "plc": {"host": "127.0.0.1", "port": 1502, "unit_id": 1},
        "matlab": {"recv_ip": "0.0.0.0", "recv_port": 5005, "send_ip": "127.0.0.1", "send_port": 6006},
    }


def test_build_plc_sensor_payload_filters_by_owner():
    sensor_ints = {
        "p_S1": 1111,
        "p_CS2": 2222,
        "q_E1": 3333,
        "q_E20": 4444,
        "T_PRS1": 5555,
        "T_STO": 6666,
        "demand_scalar": 7777,
    }

    payload_a = build_plc_sensor_payload(sensor_ints, "plc_a")
    payload_b = build_plc_sensor_payload(sensor_ints, "plc_b")

    assert payload_a["p_S1"] == 1111
    assert payload_a["q_E1"] == 3333
    assert payload_a["T_PRS1"] == 5555
    assert payload_a["p_CS2"] == 5000
    assert payload_a["q_E20"] == 0
    assert payload_a["T_STO"] == 2850
    assert payload_a["demand_scalar"] == 7777

    assert payload_b["p_CS2"] == 2222
    assert payload_b["q_E20"] == 4444
    assert payload_b["T_STO"] == 6666
    assert payload_b["p_S1"] == 5000
    assert payload_b["q_E1"] == 0
    assert payload_b["T_PRS1"] == 2850
    assert payload_b["demand_scalar"] == 7777


def test_split_manager_writes_distinct_payloads():
    manager = GatewayPLCManager(_split_config(), client_factory=FakePLC)
    sensor_ints = {
        "p_S1": 1111,
        "p_CS2": 2222,
        "q_E1": 3333,
        "q_E20": 4444,
        "demand_scalar": 7777,
    }

    ok = manager.write_sensors(sensor_ints)

    assert ok is True
    session_a, session_b = manager.sessions
    assert session_a["client"].last_write["p_S1"] == 1111
    assert session_a["client"].last_write["p_CS2"] == 5000
    assert session_b["client"].last_write["p_CS2"] == 2222
    assert session_b["client"].last_write["q_E1"] == 0


def test_split_manager_merges_owned_outputs_only():
    manager = GatewayPLCManager(_split_config(), client_factory=FakePLC)
    session_a, session_b = manager.sessions

    session_a["client"]._act = {
        "cs1_ratio_cmd": 1300,
        "cs2_ratio_cmd": 9999,
        "valve_E8_cmd": 1000,
        "prs1_setpoint": 1800,
        "cs1_power_kW": 50,
    }
    session_a["client"]._coils = {
        "emergency_shutdown": False,
        "cs1_alarm": True,
        "prs1_active": True,
        "cs2_alarm": True,
    }

    session_b["client"]._act = {
        "cs2_ratio_cmd": 1250,
        "valve_E14_cmd": 1000,
        "valve_E15_cmd": 0,
        "prs2_setpoint": 1400,
        "cs2_power_kW": 60,
    }
    session_b["client"]._coils = {
        "emergency_shutdown": True,
        "cs2_alarm": True,
        "sto_inject_active": True,
        "sto_withdraw_active": False,
        "prs2_active": True,
    }

    act, coils = manager.merge_outputs(dict(ACTUATOR_DEFAULTS), dict(COIL_DEFAULTS))

    for tag in PLC_ACTUATOR_TAGS["plc_a"]:
        assert act[tag] == session_a["client"]._act[tag]
    for tag in PLC_ACTUATOR_TAGS["plc_b"]:
        assert act[tag] == session_b["client"]._act[tag]
    assert act["cs2_ratio_cmd"] != 9999

    for tag in PLC_COIL_TAGS["plc_a"]:
        assert coils[tag] == session_a["client"]._coils[tag]
    for tag in PLC_COIL_TAGS["plc_b"]:
        assert coils[tag] == session_b["client"]._coils[tag]
    for tag in PLC_SHARED_COILS:
        assert coils[tag] is True


def test_single_manager_keeps_legacy_behavior():
    manager = GatewayPLCManager(_single_config(), client_factory=FakePLC)
    session = manager.sessions[0]["client"]
    session._act = {"cs1_ratio_cmd": 1300, "cs2_ratio_cmd": 1200}
    session._coils = {"emergency_shutdown": True}

    sensor_ints = {"p_S1": 1111, "demand_scalar": 7777}
    assert manager.write_sensors(sensor_ints) is True
    assert session.last_write["p_S1"] == 1111
    assert session.last_write["demand_scalar"] == 7777

    act, coils = manager.merge_outputs(dict(ACTUATOR_DEFAULTS), dict(COIL_DEFAULTS))
    assert act["cs1_ratio_cmd"] == 1300
    assert act["cs2_ratio_cmd"] == 1200
    assert coils["emergency_shutdown"] is True
