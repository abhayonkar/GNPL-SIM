"""
network_logger.py — Phase 2: Modbus/TCP Network Traffic Logger
==============================================================
Generates a device-level network dataset from the gateway's Modbus
transactions, enriched with:
  - src/dst device IDs and IPs (who is communicating)
  - binary label (0=normal, 1=attack)
  - transition flags (attack_start, recovery_start)
  - inter-packet timing features (for ML)
  - communication pair identifier

This extends the basic stub into a production-grade Phase 2 logger.

Output: logs/pipeline_data_latest.csv
Schema (one row per Modbus transaction):
  timestamp_ms   — wall-clock milliseconds
  timestamp_s    — simulation time seconds (from caller)
  src_ip         — source device IP
  dst_ip         — destination device IP
  src_id         — source device ID (e.g. SCADA_01, PLC_001)
  dst_id         — destination device ID
  src_zone       — SCADA=0, sources/comp=1, transport=2, delivery=3
  dst_zone       — same scale
  fc             — Modbus function code (1=read coil, 3=read HR, 16=write HR)
  register       — Modbus register address
  variable       — engineering variable name (e.g. p_S1_bar)
  value          — engineering-scaled value
  unit           — physical unit string
  ATTACK_ID      — integer attack ID (0=Normal, 1-10 per MITRE map)
  label          — binary 0/1
  attack_start   — 1 on the FIRST step of an attack window, else 0
  recovery_start — 1 on the FIRST step after attack ends, else 0
  write_flag     — 1 if FC16 (write command), else 0
  inter_pkt_ms   — milliseconds since last packet from same src_id
  comm_pair      — 'src_id→dst_id' string (for graph-based ML)

Usage:
  from network_logger import NetworkLogger
  logger = NetworkLogger()
  logger.log_read(ts_ms, sim_s, 'SCADA_01', 'PLC_001', 3, 40001, 'p_S1_bar', 21.4, 'bar', attack_id)
  logger.log_write(ts_ms, sim_s, 'SCADA_01', 'RTU_015', 16, 1, 'valve_E8', 1, 'bool', attack_id)
  logger.close()
"""

import csv
import os
import time
from collections import defaultdict

# ── Device registry (mirrors device_registry.m) ──────────────────────────────
# Maps device_id → (ip, zone)
DEVICE_REGISTRY = {
    'SCADA_01': ('192.168.1.100', 0),
    'HIST_01':  ('192.168.1.101', 0),
    'ENG_01':   ('192.168.1.102', 0),
    # Zone 1
    'PLC_001':  ('192.168.1.10',  1),   # S1
    'PLC_002':  ('192.168.1.11',  1),   # S2
    'PLC_003':  ('192.168.1.12',  1),   # CS1
    'PLC_004':  ('192.168.1.13',  1),   # CS2
    # Zone 2
    'RTU_005':  ('192.168.1.20',  2),   # J1
    'RTU_006':  ('192.168.1.21',  2),   # J2
    'RTU_007':  ('192.168.1.22',  2),   # J3
    'RTU_008':  ('192.168.1.23',  2),   # J4
    'RTU_009':  ('192.168.1.24',  2),   # J5
    'RTU_010':  ('192.168.1.25',  2),   # J6
    'RTU_011':  ('192.168.1.26',  2),   # J7
    # Zone 3
    'PLC_012':  ('192.168.1.30',  3),   # PRS1
    'PLC_013':  ('192.168.1.31',  3),   # PRS2
    'PLC_014':  ('192.168.1.32',  3),   # STO
    'RTU_015':  ('192.168.1.33',  3),   # Valve E8
    'RTU_016':  ('192.168.1.34',  3),   # Valve E14
    'RTU_017':  ('192.168.1.35',  3),   # Valve E15
    'RTU_018':  ('192.168.1.40',  3),   # D1
    'RTU_019':  ('192.168.1.41',  3),   # D2
    'RTU_020':  ('192.168.1.42',  3),   # D3
    'RTU_021':  ('192.168.1.43',  3),   # D4
    'RTU_022':  ('192.168.1.44',  3),   # D5
    'RTU_023':  ('192.168.1.45',  3),   # D6
}

# Variable → (owning_device_id, modbus_register, fc, unit)
# Mirrors register_map.m
VARIABLE_DEVICE_MAP = {
    # Pressures — read by SCADA from each device's holding register
    'p_S1_bar':  ('PLC_001', 40001, 3, 'bar'),
    'p_J1_bar':  ('RTU_005', 40002, 3, 'bar'),
    'p_CS1_bar': ('PLC_003', 40003, 3, 'bar'),
    'p_J2_bar':  ('RTU_006', 40004, 3, 'bar'),
    'p_J3_bar':  ('RTU_007', 40005, 3, 'bar'),
    'p_J4_bar':  ('RTU_008', 40006, 3, 'bar'),
    'p_CS2_bar': ('PLC_004', 40007, 3, 'bar'),
    'p_J5_bar':  ('RTU_009', 40008, 3, 'bar'),
    'p_J6_bar':  ('RTU_010', 40009, 3, 'bar'),
    'p_PRS1_bar':('PLC_012', 40010, 3, 'bar'),
    'p_J7_bar':  ('RTU_011', 40011, 3, 'bar'),
    'p_STO_bar': ('PLC_014', 40012, 3, 'bar'),
    'p_PRS2_bar':('PLC_013', 40013, 3, 'bar'),
    'p_S2_bar':  ('PLC_002', 40014, 3, 'bar'),
    'p_D1_bar':  ('RTU_018', 40015, 3, 'bar'),
    'p_D2_bar':  ('RTU_019', 40016, 3, 'bar'),
    'p_D3_bar':  ('RTU_020', 40017, 3, 'bar'),
    'p_D4_bar':  ('RTU_021', 40018, 3, 'bar'),
    'p_D5_bar':  ('RTU_022', 40019, 3, 'bar'),
    'p_D6_bar':  ('RTU_023', 40020, 3, 'bar'),
    # Actuators — written by SCADA to PLC holding registers
    'cs1_ratio_cmd':  ('PLC_003', 40101, 16, 'ratio'),
    'cs2_ratio_cmd':  ('PLC_004', 40102, 16, 'ratio'),
    'valve_E8_cmd':   ('RTU_015', 40103, 16, '0-1'),
    'valve_E14_cmd':  ('RTU_016', 40104, 16, '0-1'),
    'valve_E15_cmd':  ('RTU_017', 40105, 16, '0-1'),
    'prs1_setpoint':  ('PLC_012', 40106, 16, 'bar'),
    'prs2_setpoint':  ('PLC_013', 40107, 16, 'bar'),
}

CSV_FIELDS = [
    'timestamp_ms', 'timestamp_s',
    'src_ip', 'dst_ip', 'src_id', 'dst_id', 'src_zone', 'dst_zone',
    'fc', 'register', 'variable', 'value', 'unit',
    'ATTACK_ID', 'label', 'attack_start', 'recovery_start',
    'write_flag', 'inter_pkt_ms', 'comm_pair',
]


def label_packet(attack_id: int) -> int:
    """Binary label: 1 if any attack active, else 0."""
    return 1 if attack_id > 0 else 0


class NetworkLogger:
    """
    Phase 2 network traffic logger.

    Tracks:
      - per-packet device identity and direction
      - attack state transitions (start/recovery)
      - inter-packet timing per source device
      - communication pair frequency

    The logger is designed to be called from gateway.py on every
    Modbus transaction, both reads (FC3) and writes (FC16).
    """

    def __init__(self, log_dir: str = 'logs', flush_every: int = 100):
        os.makedirs(log_dir, exist_ok=True)
        ts_str   = time.strftime('%Y%m%d_%H%M%S')
        log_path = os.path.join(log_dir, 'pipeline_data_latest.csv')
        archive  = os.path.join(log_dir, f'pipeline_data_{ts_str}.csv')

        # Always write to pipeline_data_latest.csv (overwrite on new run)
        self._fh   = open(log_path, 'w', newline='')
        self._arch = open(archive,  'w', newline='')
        self._w1   = csv.DictWriter(self._fh,   fieldnames=CSV_FIELDS)
        self._w2   = csv.DictWriter(self._arch,  fieldnames=CSV_FIELDS)
        self._w1.writeheader()
        self._w2.writeheader()

        self._flush_every = flush_every
        self._row_count   = 0

        # State tracking for transition detection
        self._prev_attack_id  = 0
        self._last_pkt_ms     = defaultdict(lambda: None)  # src_id → last ts_ms

        print(f'[network_logger] Writing to {log_path}')
        print(f'[network_logger] Archiving to {archive}')

    # ── Public API ────────────────────────────────────────────────────────

    def log_read(self, ts_ms: int, sim_s: float,
                 src_id: str, dst_id: str,
                 fc: int, register: int,
                 variable: str, value: float, unit: str,
                 attack_id: int):
        """Log a Modbus READ (FC3 or FC1) transaction."""
        self._log(ts_ms, sim_s, src_id, dst_id, fc, register,
                  variable, value, unit, attack_id, is_write=False)

    def log_write(self, ts_ms: int, sim_s: float,
                  src_id: str, dst_id: str,
                  fc: int, register: int,
                  variable: str, value: float, unit: str,
                  attack_id: int):
        """Log a Modbus WRITE (FC16 or FC5) transaction."""
        self._log(ts_ms, sim_s, src_id, dst_id, fc, register,
                  variable, value, unit, attack_id, is_write=True)

    def log_sensor_poll(self, ts_ms: int, sim_s: float,
                        sensor_values: dict, attack_id: int):
        """
        Bulk-log a full SCADA polling cycle.
        sensor_values: dict of variable_name → engineering_value
        This generates one row per variable, simulating individual FC3 polls.
        """
        for var, val in sensor_values.items():
            if var in VARIABLE_DEVICE_MAP:
                dev_id, reg, fc, unit = VARIABLE_DEVICE_MAP[var]
                # SCADA reads from device
                self.log_read(ts_ms, sim_s,
                              'SCADA_01', dev_id,
                              fc, reg, var, val, unit, attack_id)

    def log_actuator_write(self, ts_ms: int, sim_s: float,
                           actuator_values: dict, attack_id: int):
        """
        Log actuator commands written by SCADA to PLCs (FC16).
        """
        for var, val in actuator_values.items():
            if var in VARIABLE_DEVICE_MAP:
                dev_id, reg, fc, unit = VARIABLE_DEVICE_MAP[var]
                self.log_write(ts_ms, sim_s,
                               'SCADA_01', dev_id,
                               16, reg, var, val, unit, attack_id)

    def flush(self):
        self._fh.flush()
        self._arch.flush()

    def close(self):
        self._fh.close()
        self._arch.close()
        print(f'[network_logger] Closed. Total rows: {self._row_count:,}')

    # ── Internal ──────────────────────────────────────────────────────────

    def _log(self, ts_ms, sim_s, src_id, dst_id, fc, register,
             variable, value, unit, attack_id, is_write):

        src_ip, src_zone = DEVICE_REGISTRY.get(src_id, ('0.0.0.0', -1))
        dst_ip, dst_zone = DEVICE_REGISTRY.get(dst_id, ('0.0.0.0', -1))

        # Transition detection
        attack_start   = int(attack_id > 0 and self._prev_attack_id == 0)
        recovery_start = int(attack_id == 0 and self._prev_attack_id > 0)

        # Inter-packet timing per source device
        prev_ms = self._last_pkt_ms[src_id]
        inter_pkt_ms = (ts_ms - prev_ms) if prev_ms is not None else 0
        self._last_pkt_ms[src_id] = ts_ms

        row = {
            'timestamp_ms':   ts_ms,
            'timestamp_s':    f'{sim_s:.3f}',
            'src_ip':         src_ip,
            'dst_ip':         dst_ip,
            'src_id':         src_id,
            'dst_id':         dst_id,
            'src_zone':       src_zone,
            'dst_zone':       dst_zone,
            'fc':             fc,
            'register':       register,
            'variable':       variable,
            'value':          f'{value:.4f}',
            'unit':           unit,
            'ATTACK_ID':      attack_id,
            'label':          label_packet(attack_id),
            'attack_start':   attack_start,
            'recovery_start': recovery_start,
            'write_flag':     int(is_write),
            'inter_pkt_ms':   inter_pkt_ms,
            'comm_pair':      f'{src_id}→{dst_id}',
        }

        self._w1.writerow(row)
        self._w2.writerow(row)
        self._row_count += 1
        self._prev_attack_id = attack_id

        if self._row_count % self._flush_every == 0:
            self.flush()
