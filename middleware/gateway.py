"""
gateway.py - Gas pipeline gateway: MATLAB <-> CODESYS Modbus TCP.

Phase 2 adds explicit PLC_A / PLC_B ownership handling in the gateway path
while preserving the current single-PLC flow as the default mode.
"""

from __future__ import annotations

import argparse
import csv
import logging
import os
import socket
import struct
import time
from datetime import datetime

import yaml

from architecture import (
    ACTUATOR_DEFAULTS,
    ACTUATOR_NAMES,
    ACTUATOR_SCALES,
    ACTUATOR_UNITS,
    COIL_DEFAULTS,
    COIL_NAMES,
    EDGE_NAMES,
    NODE_NAMES,
    PLC_ACTUATOR_TAGS,
    PLC_COIL_TAGS,
    PLC_NAMES,
    PLC_SHARED_COILS,
    build_plc_sensor_payload,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)


def load_config(path="config.yaml") -> dict:
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def to_signed(val: int) -> int:
    return val - 65536 if val > 32767 else val


class ModbusGateway:

    def __init__(self, host, port, unit_id):
        self.host = host
        self.port = port
        self.unit_id = unit_id
        self._client = None

    def connect(self) -> bool:
        from pymodbus.client import ModbusTcpClient

        self._client = ModbusTcpClient(self.host, port=self.port, timeout=2)
        ok = self._client.connect()
        if ok:
            logger.info("Modbus connected %s:%s unit=%s", self.host, self.port, self.unit_id)
        return ok

    def disconnect(self):
        if self._client:
            try:
                self._client.close()
            except Exception:
                pass

    def is_connected(self) -> bool:
        return self._client is not None and self._client.is_socket_open()

    def write_sensors(self, sensor_ints: dict) -> bool:
        if not self.is_connected():
            return False
        try:
            regs = []
            for name in NODE_NAMES:
                regs.append(sensor_ints.get(f"p_{name}", 5000) & 0xFFFF)
            for name in EDGE_NAMES:
                regs.append(sensor_ints.get(f"q_{name}", 0) & 0xFFFF)
            for name in NODE_NAMES:
                regs.append(sensor_ints.get(f"T_{name}", 2850) & 0xFFFF)
            regs.append(sensor_ints.get("demand_scalar", 750) & 0xFFFF)
            response = self._client.write_registers(0, regs, device_id=self.unit_id)
            return not response.isError()
        except Exception as exc:
            logger.warning("write_sensors: %s", exc)
            return False

    def read_actuators(self) -> dict | None:
        if not self.is_connected():
            return None
        try:
            response = self._client.read_holding_registers(100, count=9, device_id=self.unit_id)
            if response.isError():
                return None
            return {name: to_signed(response.registers[i]) for i, name in enumerate(ACTUATOR_NAMES)}
        except Exception as exc:
            logger.warning("read_actuators: %s", exc)
            return None

    def read_coils(self) -> dict | None:
        if not self.is_connected():
            return None
        try:
            response = self._client.read_coils(0, count=7, device_id=self.unit_id)
            if response.isError():
                return None
            return {name: bool(response.bits[i]) for i, name in enumerate(COIL_NAMES)}
        except Exception as exc:
            logger.warning("read_coils: %s", exc)
            return None

    def reconnect(self):
        self.disconnect()
        time.sleep(1)
        return self.connect()


class GatewayPLCManager:

    def __init__(self, config: dict, client_factory=ModbusGateway):
        self.mode = config.get("plc_mode", "single").lower()
        self.sessions = self._build_sessions(config, client_factory)

    def _build_sessions(self, config: dict, client_factory):
        if self.mode == "split":
            plc_cfgs = config.get("plcs", {})
            sessions = []
            for plc_name in PLC_NAMES:
                cfg = plc_cfgs.get(plc_name)
                if cfg is None:
                    raise ValueError(f"Missing split PLC config for '{plc_name}'")
                sessions.append({
                    "name": plc_name,
                    "client": client_factory(cfg["host"], cfg["port"], cfg["unit_id"]),
                })
            return sessions

        plc_cfg = config["plc"]
        return [{
            "name": "single",
            "client": client_factory(plc_cfg["host"], plc_cfg["port"], plc_cfg["unit_id"]),
        }]

    def connect_all(self):
        for session in self.sessions:
            while not session["client"].connect():
                logger.warning("PLC '%s' not ready - retrying in 3s...", session["name"])
                time.sleep(3)

    def disconnect_all(self):
        for session in self.sessions:
            session["client"].disconnect()

    def write_sensors(self, sensor_ints: dict) -> bool:
        results = []
        for session in self.sessions:
            payload = sensor_ints
            if self.mode == "split":
                payload = build_plc_sensor_payload(sensor_ints, session["name"])
            results.append(session["client"].write_sensors(payload))
        return all(results)

    def reconnect_disconnected(self) -> int:
        reconnects = 0
        for session in self.sessions:
            client = session["client"]
            if not client.is_connected():
                logger.warning("PLC '%s' disconnected - reconnecting...", session["name"])
                client.reconnect()
                reconnects += 1
        return reconnects

    def merge_outputs(self, last_act: dict, last_coils: dict) -> tuple[dict, dict]:
        merged_act = dict(last_act)
        merged_coils = dict(last_coils)

        for session in self.sessions:
            name = session["name"]
            client = session["client"]
            act = client.read_actuators()
            coils = client.read_coils()

            if self.mode == "single":
                if act is not None:
                    merged_act.update(act)
                if coils is not None:
                    merged_coils.update(coils)
                continue

            if act is not None:
                for tag in PLC_ACTUATOR_TAGS[name]:
                    if tag in act:
                        merged_act[tag] = act[tag]

            if coils is not None:
                for tag in PLC_COIL_TAGS[name]:
                    if tag in coils:
                        merged_coils[tag] = coils[tag]
                for tag in PLC_SHARED_COILS:
                    merged_coils[tag] = merged_coils.get(tag, False) or coils.get(tag, False)

        return merged_act, merged_coils


class MatlabUDP:

    SEND_BYTES = 61 * 8
    RECV_BYTES = 16 * 8

    def __init__(self, cfg):
        matlab_cfg = cfg["matlab"]
        self._rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._rx.bind((matlab_cfg["recv_ip"], matlab_cfg["recv_port"]))
        self._rx.settimeout(matlab_cfg.get("timeout_s", 0.5))
        self._tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._tx_ip = matlab_cfg["send_ip"]
        self._tx_port = matlab_cfg["send_port"]
        logger.info("UDP RX listening on %s:%s", matlab_cfg["recv_ip"], matlab_cfg["recv_port"])
        logger.info("UDP TX will reply to %s:%s", matlab_cfg["send_ip"], matlab_cfg["send_port"])

    def receive(self) -> dict | None:
        try:
            data, _ = self._rx.recvfrom(65535)
            if len(data) < self.SEND_BYTES:
                return None
            vals = struct.unpack("61d", data[:self.SEND_BYTES])
            ints = {}
            for i, name in enumerate(NODE_NAMES):
                ints[f"p_{name}"] = int(round(vals[i] * 100))
            for i, name in enumerate(EDGE_NAMES):
                ints[f"q_{name}"] = int(round(vals[20 + i] * 100))
            for i, name in enumerate(NODE_NAMES):
                ints[f"T_{name}"] = int(round(vals[40 + i] * 10))
            ints["demand_scalar"] = int(round(vals[60] * 1000))
            return ints
        except socket.timeout:
            return None
        except Exception as exc:
            logger.error("UDP receive error: %s", exc)
            return None

    def send(self, act_ints: dict, coils: dict):
        vals = [
            float(act_ints.get("cs1_ratio_cmd", 1250)),
            float(act_ints.get("cs2_ratio_cmd", 1150)),
            float(act_ints.get("valve_E8_cmd", 1000)),
            float(act_ints.get("valve_E14_cmd", 1000)),
            float(act_ints.get("valve_E15_cmd", 1000)),
            float(act_ints.get("prs1_setpoint", 3000)),
            float(act_ints.get("prs2_setpoint", 2500)),
            float(act_ints.get("cs1_power_kW", 0)),
            float(act_ints.get("cs2_power_kW", 0)),
            float(coils.get("emergency_shutdown", False)),
            float(coils.get("cs1_alarm", False)),
            float(coils.get("cs2_alarm", False)),
            float(coils.get("sto_inject_active", False)),
            float(coils.get("sto_withdraw_active", False)),
            float(coils.get("prs1_active", False)),
            float(coils.get("prs2_active", False)),
        ]
        self._tx.sendto(struct.pack(f"{len(vals)}d", *vals), (self._tx_ip, self._tx_port))

    def close(self):
        try:
            self._rx.close()
        except Exception:
            pass
        try:
            self._tx.close()
        except Exception:
            pass


class TransactionLogger:

    def __init__(self, log_dir="logs"):
        os.makedirs(log_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = os.path.join(log_dir, f"modbus_transactions_{ts}.csv")
        self._fh = open(path, "w", newline="", encoding="utf-8")
        self._w = csv.writer(self._fh)
        self._w.writerow(["timestamp_ms", "fc", "direction", "modbus_addr", "variable", "int16_raw", "eng_value", "unit"])
        logger.info("Transaction log: %s", path)

    def log_sensors(self, sensor_ints: dict):
        ts = int(time.time() * 1000)
        scales = ([100] * 20) + ([100] * 20) + ([10] * 20) + [1000]
        names = ([f"p_{n}" for n in NODE_NAMES] + [f"q_{e}" for e in EDGE_NAMES] + [f"T_{n}" for n in NODE_NAMES] + ["demand_scalar"])
        units = (["bar"] * 20) + (["kg/s"] * 20) + (["K"] * 20) + [""]
        for i, (name, scale, unit) in enumerate(zip(names, scales, units)):
            raw = sensor_ints.get(name, 0)
            eng = raw / scale
            self._w.writerow([ts, "FC16", "WRITE", 40001 + i, name, raw, f"{eng:.4f}", unit])

    def log_actuators(self, act_ints: dict):
        ts = int(time.time() * 1000)
        for i, (name, scale, unit) in enumerate(zip(ACTUATOR_NAMES, ACTUATOR_SCALES, ACTUATOR_UNITS)):
            raw = act_ints.get(name, 0)
            eng = raw / scale
            self._w.writerow([ts, "FC3", "READ", 40101 + i, name, raw, f"{eng:.4f}", unit])

    def log_coils(self, coils: dict):
        ts = int(time.time() * 1000)
        for i, name in enumerate(COIL_NAMES):
            val = coils.get(name, False)
            self._w.writerow([ts, "FC1", "READ", 1 + i, name, int(val), str(val), "BOOL"])

    def flush(self):
        self._fh.flush()

    def close(self):
        self._fh.close()


def run_gateway(config: dict):
    plc_manager = GatewayPLCManager(config)
    mat = MatlabUDP(config)
    txlog = TransactionLogger(config.get("log_dir", "logs"))
    plc_manager.connect_all()

    log_every = config.get("log_every_n_cycles", 10)
    stats = {"cycles": 0, "plc_errors": 0, "timeouts": 0, "reconnects": 0}
    last_act = dict(ACTUATOR_DEFAULTS)
    last_coils = dict(COIL_DEFAULTS)

    logger.info("Gateway ready - waiting for MATLAB UDP packets on port 5005")
    logger.info("Timing: REQUEST-RESPONSE (synchronised to MATLAB)")
    logger.info("PLC mode: %s", plc_manager.mode)
    logger.info("Press Ctrl+C to stop.")

    try:
        while True:
            sensor_ints = mat.receive()

            if sensor_ints is None:
                stats["timeouts"] += 1
                if stats["timeouts"] % 20 == 0:
                    elapsed = stats["timeouts"] * config["matlab"].get("timeout_s", 0.5)
                    logger.info("Waiting for MATLAB... (%.0fs elapsed, %s timeouts)", elapsed, stats["timeouts"])
                continue

            ok = plc_manager.write_sensors(sensor_ints)
            if not ok:
                stats["plc_errors"] += 1
                stats["reconnects"] += plc_manager.reconnect_disconnected()

            last_act, last_coils = plc_manager.merge_outputs(last_act, last_coils)
            mat.send(last_act, last_coils)

            stats["cycles"] += 1
            cycle = stats["cycles"]

            if cycle % log_every == 0:
                txlog.log_sensors(sensor_ints)
                txlog.log_actuators(last_act)
                txlog.log_coils(last_coils)
                txlog.flush()

            if cycle % 1000 == 0:
                p_s1 = sensor_ints.get("p_S1", 5000) / 100.0
                p_d1 = sensor_ints.get("p_D1", 0) / 100.0
                r_cs1 = last_act.get("cs1_ratio_cmd", 1250) / 1000.0
                logger.info("Step %6d  p_S1=%.1fbar  p_D1=%.1fbar  cs1_ratio=%.3f", cycle, p_s1, p_d1, r_cs1)

    except KeyboardInterrupt:
        logger.info("Keyboard interrupt - stopping gateway.")
    finally:
        txlog.close()
        mat.close()
        plc_manager.disconnect_all()
        logger.info(
            "Gateway stopped. Cycles=%s  PLCerrors=%s  Timeouts=%s",
            stats["cycles"],
            stats["plc_errors"],
            stats["timeouts"],
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Gas Pipeline Modbus Gateway")
    parser.add_argument("--config", default="config.yaml")
    args = parser.parse_args()
    run_gateway(load_config(args.config))
