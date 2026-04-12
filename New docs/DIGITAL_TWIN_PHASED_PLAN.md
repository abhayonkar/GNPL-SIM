# Digital Twin Integration — Phased Implementation Plan

**System:** 20-Node Indian CGD Gas Pipeline CPS Simulator
**Goal:** Run a shadow-mode digital twin in parallel with the physical/simulated plant, producing a dual-layer CPS dataset with device-level network identity

---

## Current State Assessment

### What Works
- 30/30 quick sweep scenarios complete with 0 failures
- Physics engine (Weymouth, PR-EOS, EKF-40, CUSUM, A1–A10 attacks)
- CODESYS gateway (Modbus TCP, 61 registers, 7 coils)
- ML pipeline (IsolationForest, RandomForest, XGBoost + SHAP)
- 48h continuous sweep script (from previous session)

### What's Broken or Missing
| Issue | Severity | Impact |
|---|---|---|
| Physics divergence (0.1/70 bar clamping) | **Critical** | Unrealistic data — ML learns clamp artefacts, not physics |
| No device identity in dataset | **Critical** | Cannot answer "who talked to whom" |
| Single PLC handles all nodes | **High** | No realistic network topology |
| No network-layer dataset | **High** | Missing entire cyber layer for IDS research |
| `runSimulation.m` marked frozen but needs CUSUM/EKF fixes propagated | **Medium** | Maintenance debt |
| `computeFDIVector.m` hardcodes nN=20, nE=20 | **Low** | Blocks future topology changes |

---

## Phase 0: Critical Fixes (Before Anything Else)

**Duration:** 1–2 days
**Prerequisite for:** Everything. No point building a digital twin on divergent physics.

### Fix 0.1 — Physics Divergence

**Root cause:** `updatePressure.m` coefficient `dt·c²/(V·1e5)` is too large at Indian CGD pressures (14–26 bar vs European 40–85 bar). The smaller pressure differentials amplify the gain ratio, causing sign oscillation across adjacent nodes.

**Two changes required:**

```matlab
% FILE: network/updatePressure.m
% CHANGE 1: Add under-relaxation factor
relax = 0.3;   % damping coefficient (0.3 = 30% of computed update applied)
p = p + relax * coeff .* (params.B * q);

% CHANGE 2: Add implicit pressure diffusion (smooths node-to-node oscillations)
% After the mass-balance update, apply one sweep of neighbour averaging:
alpha_diff = 0.05;   % diffusion coefficient
for e = 1:params.nEdges
    i_from = cfg.edges(e, 1);
    i_to   = cfg.edges(e, 2);
    dp_local = p(i_from) - p(i_to);
    p(i_from) = p(i_from) - alpha_diff * dp_local;
    p(i_to)   = p(i_to)   + alpha_diff * dp_local;
end
```

```matlab
% FILE: config/simConfig.m
% CHANGE: Increase nodal volume for damping
cfg.node_V = 500.0;   % was 100.0 — larger volume = more inertia = less oscillation
```

**Verification:**
```matlab
run_24h_sweep('mode', 'quick', 'gateway', false, 'dur_min', 30)
% Check: NO "[WARNING] Low/High pressure" messages
% Check: All pressures stay within 12–28 bar range
```

### Fix 0.2 — CUSUM Accepts Both Vector and Struct Input

`updateCUSUM.m` is called with `ekf.residual` (40×1 vector) from `runSimulation.m`, but `phase_a_verify.m` tests it with an `ekf_mock` struct containing `.residualP`. The function should handle both gracefully:

```matlab
% FILE: scada/updateCUSUM.m — at the top of the function, after argument parsing:
% Handle both vector input and struct input (for backward compatibility)
if isstruct(residual)
    if isfield(residual, 'residualP')
        residual = residual.residualP;
    elseif isfield(residual, 'residual')
        residual = residual.residual;
    end
end
```

### Fix 0.3 — `computeFlows.m` Guard Against Zero-Length Pipes

Some resilience edges (E21, E22) may have unusual parameters. Add a guard:

```matlab
% FILE: network/computeFlows.m — inside the conductance calculation:
L_vec = max(0.1, params.L(1:nE));   % prevent division by zero for stub edges
D_vec = max(0.01, params.D(1:nE));  % prevent zero diameter
```

---

## Phase 1: Device Registry + Network Identity

**Duration:** 2–3 days
**Depends on:** Phase 0 complete
**Deliverables:** `config/device_registry.m`, `config/register_map.m`, modified `gateway.py`

### 1.1 — Device Registry

Every physical component maps to a device with a unique ID, IP, and type. This mirrors real SCADA architecture where each PLC/RTU has its own network address.

```matlab
% FILE: config/device_registry.m
function devices = device_registry()
% device_registry  Complete device-to-IP mapping for 20-node CGD network.
%
%   Topology follows real Indian CGD SCADA architecture:
%     Zone 1 (critical):   Sources + Compressors → PLCs, fast poll
%     Zone 2 (transport):  Junctions → RTUs, medium poll
%     Zone 3 (delivery):   PRS + Valves + Demand → RTUs/PLCs, slow poll
%     SCADA:               Central HMI/server

    devices = struct();

    % ── SCADA Layer ──────────────────────────────────────────────────
    devices.SCADA    = dev('SCADA_01', '192.168.1.100', 'SCADA',  0, 'Master station');
    devices.HIST     = dev('HIST_01',  '192.168.1.101', 'Server', 0, 'Historian');
    devices.ENG_WS   = dev('ENG_01',   '192.168.1.102', 'Workstation', 0, 'Engineering');

    % ── Zone 1: Sources + Compressors (PLC, 1s poll) ────────────────
    devices.S1       = dev('PLC_001', '192.168.1.10', 'PLC', 1, 'Source S1 — CGS outlet');
    devices.S2       = dev('PLC_002', '192.168.1.11', 'PLC', 1, 'Source S2 — CGS outlet');
    devices.CS1      = dev('PLC_003', '192.168.1.12', 'PLC', 1, 'Compressor CS1');
    devices.CS2      = dev('PLC_004', '192.168.1.13', 'PLC', 1, 'Compressor CS2');

    % ── Zone 2: Junctions (RTU, 1.5s poll) ──────────────────────────
    devices.J1       = dev('RTU_005', '192.168.1.20', 'RTU', 2, 'Junction J1');
    devices.J2       = dev('RTU_006', '192.168.1.21', 'RTU', 2, 'Junction J2 — branch');
    devices.J3       = dev('RTU_007', '192.168.1.22', 'RTU', 2, 'Junction J3');
    devices.J4       = dev('RTU_008', '192.168.1.23', 'RTU', 2, 'Junction J4');
    devices.J5       = dev('RTU_009', '192.168.1.24', 'RTU', 2, 'Junction J5');
    devices.J6       = dev('RTU_010', '192.168.1.25', 'RTU', 2, 'Junction J6');
    devices.J7       = dev('RTU_011', '192.168.1.26', 'RTU', 2, 'Junction J7');

    % ── Zone 3: PRS + Storage + Valves + Demand (mixed, 2s poll) ────
    devices.PRS1     = dev('PLC_012', '192.168.1.30', 'PLC', 3, 'PRS1 — 18 barg');
    devices.PRS2     = dev('PLC_013', '192.168.1.31', 'PLC', 3, 'PRS2 — 14 barg');
    devices.STO      = dev('PLC_014', '192.168.1.32', 'PLC', 3, 'Storage cavern');

    devices.VALVE_E8  = dev('RTU_015', '192.168.1.33', 'RTU', 3, 'Valve E8 — isolation');
    devices.VALVE_E14 = dev('RTU_016', '192.168.1.34', 'RTU', 3, 'Valve E14 — STO inject');
    devices.VALVE_E15 = dev('RTU_017', '192.168.1.35', 'RTU', 3, 'Valve E15 — STO withdraw');

    devices.D1       = dev('RTU_018', '192.168.1.40', 'RTU', 3, 'Demand D1');
    devices.D2       = dev('RTU_019', '192.168.1.41', 'RTU', 3, 'Demand D2');
    devices.D3       = dev('RTU_020', '192.168.1.42', 'RTU', 3, 'Demand D3');
    devices.D4       = dev('RTU_021', '192.168.1.43', 'RTU', 3, 'Demand D4');
    devices.D5       = dev('RTU_022', '192.168.1.44', 'RTU', 3, 'Demand D5');
    devices.D6       = dev('RTU_023', '192.168.1.45', 'RTU', 3, 'Demand D6');
end

function d = dev(id, ip, type, zone, desc)
    d.id   = id;
    d.ip   = ip;
    d.type = type;
    d.zone = zone;
    d.desc = desc;
end
```

### 1.2 — Register Map (Node → Modbus Address → Device)

```matlab
% FILE: config/register_map.m
function map = register_map()
% register_map  Maps every simulator variable to its Modbus address + owning device.
%
%   This is the bridge between physics and protocol layers.
%   When SCADA reads register 40003, it's talking to PLC_001 (S1) asking for pressure.
%   When SCADA writes coil 00001, it's commanding RTU_015 (Valve E8) to open/close.

    map = struct();

    % ── Holding Registers: Pressures (FC3 READ / FC16 WRITE) ────────
    % SCADA polls each device for its local pressure sensor
    % Address 40001–40020, one per node, scale ×100
    nodes = {'S1','J1','CS1','J2','J3','J4','CS2','J5','J6','PRS1', ...
             'J7','STO','PRS2','S2','D1','D2','D3','D4','D5','D6'};
    devs  = {'PLC_001','RTU_005','PLC_003','RTU_006','RTU_007','RTU_008', ...
             'PLC_004','RTU_009','RTU_010','PLC_012', ...
             'RTU_011','PLC_014','PLC_013','PLC_002', ...
             'RTU_018','RTU_019','RTU_020','RTU_021','RTU_022','RTU_023'};

    for i = 1:20
        r.address     = 40000 + i;
        r.variable    = sprintf('p_%s_bar', nodes{i});
        r.device_id   = devs{i};
        r.scale       = 100;
        r.unit        = 'bar';
        r.direction   = 'READ';
        r.fc          = 3;
        map.(sprintf('p_%s', nodes{i})) = r;
    end

    % ── Holding Registers: Flows (FC3 READ) ─────────────────────────
    % Flow meters are on edges, owned by the upstream node's device
    edges = {'E1','E2','E3','E4','E5','E6','E7','E8','E9','E10', ...
             'E11','E12','E13','E14','E15','E16','E17','E18','E19','E20'};
    edge_devs = {'PLC_001','RTU_005','PLC_003','RTU_006','RTU_007','RTU_008', ...
                 'PLC_004','RTU_009','RTU_010','PLC_012', ...
                 'RTU_011','PLC_014','PLC_013','PLC_002', ...
                 'RTU_018','RTU_019','RTU_020','RTU_021','RTU_022','RTU_023'};

    for i = 1:20
        r.address     = 40100 + i;
        r.variable    = sprintf('q_%s_kgs', edges{i});
        r.device_id   = edge_devs{i};
        r.scale       = 100;
        r.unit        = 'kg/s';
        r.direction   = 'READ';
        r.fc          = 3;
        map.(sprintf('q_%s', edges{i})) = r;
    end

    % ── Holding Registers: Equipment (FC3 READ + FC16 WRITE) ────────
    equip = {
        'CS1_ratio',   40201, 'PLC_003', 1000, '', 'READWRITE';
        'CS2_ratio',   40202, 'PLC_004', 1000, '', 'READWRITE';
        'CS1_power',   40203, 'PLC_003', 10,   'kW', 'READ';
        'CS2_power',   40204, 'PLC_004', 10,   'kW', 'READ';
        'PRS1_setpoint', 40205, 'PLC_012', 100, 'bar', 'READWRITE';
        'PRS2_setpoint', 40206, 'PLC_013', 100, 'bar', 'READWRITE';
        'STO_level',   40207, 'PLC_014', 1000, '', 'READ';
    };
    for i = 1:size(equip, 1)
        r.address   = equip{i, 2};
        r.variable  = equip{i, 1};
        r.device_id = equip{i, 3};
        r.scale     = equip{i, 4};
        r.unit      = equip{i, 5};
        r.direction = equip{i, 6};
        r.fc        = 3;
        map.(equip{i, 1}) = r;
    end

    % ── Coils (FC1 READ / FC5 WRITE) ────────────────────────────────
    coils = {
        'valve_E8',       1, 'RTU_015';
        'valve_E14',      2, 'RTU_016';
        'valve_E15',      3, 'RTU_017';
        'CS1_online',     4, 'PLC_003';
        'CS2_online',     5, 'PLC_004';
        'emer_shutdown',   6, 'SCADA_01';
        'STO_inject',     7, 'PLC_014';
    };
    for i = 1:size(coils, 1)
        r.address   = coils{i, 2};
        r.variable  = coils{i, 1};
        r.device_id = coils{i, 3};
        r.scale     = 1;
        r.unit      = 'BOOL';
        r.direction = 'READWRITE';
        r.fc        = 1;
        map.(sprintf('coil_%s', coils{i, 1})) = r;
    end
end
```

### 1.3 — Lookup Helpers

```matlab
% FILE: config/device_lookup.m
function [dev_id, dev_ip] = device_lookup(node_name, devices)
% device_lookup  Get device ID and IP for a given node name.
    if isfield(devices, node_name)
        d = devices.(node_name);
        dev_id = d.id;
        dev_ip = d.ip;
    else
        dev_id = 'UNKNOWN';
        dev_ip = '0.0.0.0';
    end
end
```

---

## Phase 2: Network Traffic Logger

**Duration:** 3–4 days
**Depends on:** Phase 1 complete
**Deliverables:** `middleware/network_logger.py`, modified `gateway.py`, `network_dataset.csv`

### 2.1 — Network Packet Logger (Python)

This is the core addition. Every Modbus transaction gets logged with full source/destination identity.

```python
# FILE: middleware/network_logger.py
"""
network_logger.py — CPS Network Traffic Logger
================================================
Generates network_dataset.csv: one row per Modbus transaction.
Each row records WHO talked to WHOM, WHAT was sent, and WHEN.

This is the cyber layer that complements the physics dataset.
Together they form a complete CPS dataset.
"""

import csv
import os
import time
import json
from datetime import datetime

# Load device registry
DEVICE_REGISTRY = {
    'S1':  {'id': 'PLC_001', 'ip': '192.168.1.10',  'type': 'PLC'},
    'S2':  {'id': 'PLC_002', 'ip': '192.168.1.11',  'type': 'PLC'},
    'CS1': {'id': 'PLC_003', 'ip': '192.168.1.12',  'type': 'PLC'},
    'CS2': {'id': 'PLC_004', 'ip': '192.168.1.13',  'type': 'PLC'},
    'J1':  {'id': 'RTU_005', 'ip': '192.168.1.20',  'type': 'RTU'},
    'J2':  {'id': 'RTU_006', 'ip': '192.168.1.21',  'type': 'RTU'},
    'J3':  {'id': 'RTU_007', 'ip': '192.168.1.22',  'type': 'RTU'},
    'J4':  {'id': 'RTU_008', 'ip': '192.168.1.23',  'type': 'RTU'},
    'J5':  {'id': 'RTU_009', 'ip': '192.168.1.24',  'type': 'RTU'},
    'J6':  {'id': 'RTU_010', 'ip': '192.168.1.25',  'type': 'RTU'},
    'J7':  {'id': 'RTU_011', 'ip': '192.168.1.26',  'type': 'RTU'},
    'PRS1':{'id': 'PLC_012', 'ip': '192.168.1.30',  'type': 'PLC'},
    'PRS2':{'id': 'PLC_013', 'ip': '192.168.1.31',  'type': 'PLC'},
    'STO': {'id': 'PLC_014', 'ip': '192.168.1.32',  'type': 'PLC'},
    'VALVE_E8':  {'id': 'RTU_015', 'ip': '192.168.1.33', 'type': 'RTU'},
    'VALVE_E14': {'id': 'RTU_016', 'ip': '192.168.1.34', 'type': 'RTU'},
    'VALVE_E15': {'id': 'RTU_017', 'ip': '192.168.1.35', 'type': 'RTU'},
    'D1':  {'id': 'RTU_018', 'ip': '192.168.1.40',  'type': 'RTU'},
    'D2':  {'id': 'RTU_019', 'ip': '192.168.1.41',  'type': 'RTU'},
    'D3':  {'id': 'RTU_020', 'ip': '192.168.1.42',  'type': 'RTU'},
    'D4':  {'id': 'RTU_021', 'ip': '192.168.1.43',  'type': 'RTU'},
    'D5':  {'id': 'RTU_022', 'ip': '192.168.1.44',  'type': 'RTU'},
    'D6':  {'id': 'RTU_023', 'ip': '192.168.1.45',  'type': 'RTU'},
}

SCADA = {'id': 'SCADA_01', 'ip': '192.168.1.100', 'type': 'SCADA'}

# Register-to-node mapping (address → node name → device)
NODE_NAMES = ['S1','J1','CS1','J2','J3','J4','CS2','J5','J6','PRS1',
              'J7','STO','PRS2','S2','D1','D2','D3','D4','D5','D6']

REGISTER_TO_NODE = {}
for i, n in enumerate(NODE_NAMES):
    REGISTER_TO_NODE[i]      = n      # pressure: addr 0–19
    REGISTER_TO_NODE[20 + i] = n      # flow: addr 20–39
    REGISTER_TO_NODE[40 + i] = n      # temp: addr 40–59

HEADER = [
    'timestamp_s', 'timestamp_ms', 'datetime_utc',
    'src_ip', 'dst_ip', 'src_id', 'dst_id',
    'src_type', 'dst_type', 'src_zone', 'dst_zone',
    'protocol', 'fc', 'fc_name',
    'register_addr', 'register_name',
    'value_raw', 'value_eng', 'unit',
    'direction', 'payload_bytes', 'response_time_ms',
    'attack_id', 'is_anomalous'
]

FC_NAMES = {1: 'READ_COILS', 3: 'READ_HOLDING', 5: 'WRITE_COIL',
            6: 'WRITE_SINGLE', 16: 'WRITE_MULTIPLE'}


class NetworkLogger:
    """Logs every SCADA↔PLC/RTU transaction with full device identity."""

    def __init__(self, log_dir='logs', sim_time_offset=0.0):
        os.makedirs(log_dir, exist_ok=True)
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        self.path = os.path.join(log_dir, f'network_dataset_{ts}.csv')
        self._fh = open(self.path, 'w', newline='')
        self._w = csv.writer(self._fh)
        self._w.writerow(HEADER)
        self._sim_offset = sim_time_offset
        self._packet_count = 0

    def log_poll_cycle(self, sim_time_s, sensor_ints, act_ints, coil_vals,
                       attack_id=0):
        """Log a complete SCADA polling cycle (request + response for each device)."""

        base_ms = int(time.time() * 1000)

        # ── Pressure reads: SCADA → each node's PLC/RTU ──────────────
        for i, node in enumerate(NODE_NAMES):
            if node not in DEVICE_REGISTRY:
                continue
            dev = DEVICE_REGISTRY[node]

            raw = sensor_ints.get(f'p_{node}', 0)
            eng = raw / 100.0
            reg_addr = 40001 + i

            # Simulate realistic response time based on device type
            if dev['type'] == 'PLC':
                resp_ms = 2.0 + 1.5 * abs(hash(node) % 10) / 10.0
            else:
                resp_ms = 5.0 + 3.0 * abs(hash(node) % 10) / 10.0

            # REQUEST: SCADA → Device
            self._write_row(sim_time_s, base_ms,
                            SCADA, dev, 3, 'READ_HOLDING',
                            reg_addr, f'p_{node}_bar',
                            0, 0.0, '', 'REQUEST', 12, 0,
                            attack_id)

            # RESPONSE: Device → SCADA
            self._write_row(sim_time_s, base_ms + resp_ms,
                            dev, SCADA, 3, 'READ_HOLDING',
                            reg_addr, f'p_{node}_bar',
                            raw, eng, 'bar', 'RESPONSE', 9 + 2, resp_ms,
                            attack_id)

        # ── Flow reads ────────────────────────────────────────────────
        edges = ['E1','E2','E3','E4','E5','E6','E7','E8','E9','E10',
                 'E11','E12','E13','E14','E15','E16','E17','E18','E19','E20']
        for i, edge in enumerate(edges):
            node = NODE_NAMES[i]   # flow meter owned by same node
            if node not in DEVICE_REGISTRY:
                continue
            dev = DEVICE_REGISTRY[node]
            raw = sensor_ints.get(f'q_{edge}', 0)
            eng = raw / 100.0
            reg_addr = 40101 + i

            resp_ms = 3.0 + 2.0 * abs(hash(edge) % 10) / 10.0

            self._write_row(sim_time_s, base_ms + 50,
                            SCADA, dev, 3, 'READ_HOLDING',
                            reg_addr, f'q_{edge}_kgs',
                            0, 0.0, '', 'REQUEST', 12, 0,
                            attack_id)
            self._write_row(sim_time_s, base_ms + 50 + resp_ms,
                            dev, SCADA, 3, 'READ_HOLDING',
                            reg_addr, f'q_{edge}_kgs',
                            raw, eng, 'kg/s', 'RESPONSE', 11, resp_ms,
                            attack_id)

        # ── Actuator reads (CS1/CS2 ratio, valve cmds) ────────────────
        act_devs = [
            ('CS1_ratio', 40201, 'PLC_003', 'CS1', 1000, ''),
            ('CS2_ratio', 40202, 'PLC_004', 'CS2', 1000, ''),
        ]
        for name, addr, dev_id, node, scale, unit in act_devs:
            dev = DEVICE_REGISTRY[node]
            raw = act_ints.get(f'{name.lower()}_cmd', 0)
            eng = raw / scale

            self._write_row(sim_time_s, base_ms + 100,
                            SCADA, dev, 3, 'READ_HOLDING',
                            addr, name, raw, eng, unit,
                            'RESPONSE', 11, 4.0, attack_id)

        # ── Coil reads (valves, alarms) ───────────────────────────────
        coil_devs = [
            ('valve_E8',  1, 'VALVE_E8'),
            ('valve_E14', 2, 'VALVE_E14'),
            ('valve_E15', 3, 'VALVE_E15'),
        ]
        for name, addr, node in coil_devs:
            if node not in DEVICE_REGISTRY:
                continue
            dev = DEVICE_REGISTRY[node]
            val = int(coil_vals.get(name, False))

            self._write_row(sim_time_s, base_ms + 120,
                            SCADA, dev, 1, 'READ_COILS',
                            addr, name, val, float(val), 'BOOL',
                            'RESPONSE', 8, 6.0, attack_id)

        self._packet_count += 1
        if self._packet_count % 100 == 0:
            self._fh.flush()

    def _write_row(self, sim_s, wall_ms, src, dst, fc, fc_name,
                   reg, reg_name, raw, eng, unit, direction,
                   payload_bytes, resp_ms, attack_id):

        dt_str = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'

        src_zone = src.get('zone', 0) if isinstance(src, dict) else 0
        dst_zone = dst.get('zone', 0) if isinstance(dst, dict) else 0

        is_anomalous = 1 if attack_id > 0 else 0

        self._w.writerow([
            f'{sim_s:.3f}', wall_ms, dt_str,
            src['ip'], dst['ip'], src['id'], dst['id'],
            src['type'], dst['type'], src_zone, dst_zone,
            'Modbus/TCP', fc, fc_name,
            reg, reg_name,
            raw, f'{eng:.4f}', unit,
            direction, payload_bytes, f'{resp_ms:.2f}',
            attack_id, is_anomalous
        ])

    def close(self):
        self._fh.flush()
        self._fh.close()
        print(f'[network_logger] {self._packet_count} poll cycles → {self.path}')
```

### 2.2 — Modify `gateway.py` to Call Network Logger

Add to the main loop in `gateway.py`, after the Modbus read/write completes:

```python
# In gateway.py, import at top:
from network_logger import NetworkLogger

# In run_gateway(), after client connects:
net_log = NetworkLogger(log_dir=config.get('log_dir', 'logs'))

# Inside the main loop, after mat.send():
net_log.log_poll_cycle(
    sim_time_s=stats['cycles'] * config.get('cycle_time_s', 0.1),
    sensor_ints=sensor_ints,
    act_ints=last_act,
    coil_vals=last_coils,
    attack_id=0   # populated from MATLAB via extended UDP packet
)

# In finally block:
net_log.close()
```

---

## Phase 3: Dataset Merger + ML Integration

**Duration:** 2–3 days
**Depends on:** Phase 2 complete
**Deliverables:** `ml_pipeline/merge_datasets.py`, updated `cgd_ids_pipeline.py`

### 3.1 — Dataset Merger Script

```python
# FILE: ml_pipeline/merge_datasets.py
"""
Merge physics_dataset.csv + network_dataset.csv into a unified CPS dataset.

Physics: 1 row per second (172,800 rows for 48h)
Network: ~100 rows per second (one per device poll)

Strategy: Aggregate network features per second, then left-join onto physics.
"""

import pandas as pd
import numpy as np
import argparse

def merge(physics_path, network_path, output_path):
    print(f'Loading physics: {physics_path}')
    phys = pd.read_csv(physics_path)

    print(f'Loading network: {network_path}')
    net = pd.read_csv(network_path)

    # Round network timestamps to nearest second for join
    net['ts_rounded'] = net['timestamp_s'].round(0)

    # ── Aggregate network features per second ──────────────────────
    agg = net.groupby('ts_rounded').agg(
        n_packets       = ('timestamp_s', 'count'),
        n_unique_src    = ('src_id', 'nunique'),
        n_unique_dst    = ('dst_id', 'nunique'),
        n_reads         = ('direction', lambda x: (x == 'REQUEST').sum()),
        n_responses     = ('direction', lambda x: (x == 'RESPONSE').sum()),
        n_writes        = ('fc', lambda x: (x.isin([5, 6, 16])).sum()),
        mean_resp_ms    = ('response_time_ms', 'mean'),
        max_resp_ms     = ('response_time_ms', 'max'),
        std_resp_ms     = ('response_time_ms', 'std'),
        n_fc1           = ('fc', lambda x: (x == 1).sum()),
        n_fc3           = ('fc', lambda x: (x == 3).sum()),
        n_fc16          = ('fc', lambda x: (x == 16).sum()),
        n_anomalous     = ('is_anomalous', 'sum'),
        unique_regs     = ('register_addr', 'nunique'),
    ).reset_index()
    agg.rename(columns={'ts_rounded': 'Timestamp_s'}, inplace=True)

    # Round physics timestamps for join
    phys['Timestamp_s'] = phys['Timestamp_s'].round(0)

    # Merge
    merged = phys.merge(agg, on='Timestamp_s', how='left')
    merged.fillna(0, inplace=True)

    print(f'Merged: {len(merged)} rows × {len(merged.columns)} cols')
    merged.to_csv(output_path, index=False)
    print(f'Saved: {output_path}')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--physics', default='../automated_dataset/continuous_48h/physics_dataset.csv')
    ap.add_argument('--network', default='../middleware/logs/network_dataset_latest.csv')
    ap.add_argument('--output',  default='../automated_dataset/continuous_48h/merged_cps_dataset.csv')
    args = ap.parse_args()
    merge(args.physics, args.network, args.output)
```

### 3.2 — New ML Feature Groups

Add to `cgd_ids_pipeline.py`:

```python
# Network-layer features (from merged dataset)
network_cols = [
    'n_packets', 'n_unique_src', 'n_unique_dst',
    'n_reads', 'n_responses', 'n_writes',
    'mean_resp_ms', 'max_resp_ms', 'std_resp_ms',
    'n_fc1', 'n_fc3', 'n_fc16',
    'unique_regs'
]
```

---

## Phase 4: Multi-PLC Architecture (Virtual + Real)

**Duration:** 3–5 days
**Depends on:** Phase 2 complete
**Deliverables:** `middleware/virtual_plc.py`, multi-instance CODESYS guide

### Architecture

```
             SCADA (Python master poller)
                 │
    ┌────────────┼────────────────┐
    ▼            ▼                ▼
 PLC_001      PLC_003          PLC_012
 (CODESYS     (CODESYS         (pymodbus
  real PLC)    real PLC)        virtual)
 port 1502    port 1503        port 1504
    │            │                │
    └────────────┼────────────────┘
                 ▼
          MATLAB Digital Twin
         (run_48h_continuous)
```

**Recommended minimum:** 2–3 real CODESYS PLCs + remaining as pymodbus virtual PLCs.

### 4.1 — Virtual PLC Emulator

```python
# FILE: middleware/virtual_plc.py
"""
virtual_plc.py — Lightweight Modbus TCP server emulating a PLC/RTU.

Each instance binds to a unique port and holds its own register space.
The digital twin (MATLAB) writes sensor values; SCADA reads them.

Usage:
    python virtual_plc.py --device PLC_001 --port 1502
    python virtual_plc.py --device RTU_005 --port 1510
    python virtual_plc.py --all   # starts all 23 devices
"""

from pymodbus.server import StartTcpServer
from pymodbus.datastore import (ModbusSequentialDataBlock,
                                 ModbusSlaveContext,
                                 ModbusServerContext)
import threading
import argparse
import json
import time

def create_plc_context():
    """Create a Modbus datastore with realistic register layout."""
    store = ModbusSlaveContext(
        di=ModbusSequentialDataBlock(0, [0]*100),      # Discrete Inputs
        co=ModbusSequentialDataBlock(0, [0]*100),       # Coils
        hr=ModbusSequentialDataBlock(0, [0]*300),       # Holding Registers
        ir=ModbusSequentialDataBlock(0, [0]*100),       # Input Registers
    )
    return ModbusServerContext(slaves=store, single=True)

def start_virtual_plc(device_id, ip, port):
    """Start a single virtual PLC on the given port."""
    context = create_plc_context()
    print(f'[virtual_plc] Starting {device_id} on {ip}:{port}')
    StartTcpServer(context=context, address=(ip, port))

def start_all_virtual_plcs(registry_path='device_registry.json'):
    """Start all virtual PLCs from the device registry."""
    with open(registry_path) as f:
        registry = json.load(f)

    threads = []
    base_port = 1502
    for i, (name, dev) in enumerate(registry.items()):
        if dev['type'] in ('PLC', 'RTU'):
            port = base_port + i
            t = threading.Thread(
                target=start_virtual_plc,
                args=(dev['id'], '127.0.0.1', port),
                daemon=True
            )
            t.start()
            threads.append(t)
            time.sleep(0.1)

    print(f'[virtual_plc] {len(threads)} devices running')
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print('[virtual_plc] Shutting down')
```

---

## Phase 5: Shadow-Mode Digital Twin Connection

**Duration:** 3–5 days
**Depends on:** Phases 0–3 complete (Phase 4 optional but recommended)
**Deliverables:** `twin/shadow_twin.py`, `twin/comparator.py`

### Architecture

```
REAL PLANT (or simulator acting as plant)
    │
    │  Modbus/OPC-UA
    ▼
SHADOW TWIN (run_48h_continuous running in parallel)
    │
    │  Residual = Real - Twin
    ▼
COMPARATOR (drift detection, model calibration)
    │
    ▼
IDS / ML MODEL (trained on merged CPS dataset)
```

### 5.1 — Shadow Twin Runner

```python
# FILE: twin/shadow_twin.py
"""
shadow_twin.py — Runs the digital twin in shadow mode.

Reads real plant data via Modbus (or from a live CSV feed),
feeds it to the MATLAB twin, compares outputs, logs residuals.

The twin does NOT control the real plant — it only observes and predicts.
"""

import time
import csv
import numpy as np
from pymodbus.client import ModbusTcpClient

class ShadowTwin:
    def __init__(self, real_plc_host='192.168.1.10', real_plc_port=1502,
                 twin_host='127.0.0.1', twin_port=5005):
        self.real_client = ModbusTcpClient(real_plc_host, port=real_plc_port)
        self.twin_host = twin_host
        self.twin_port = twin_port
        self.residual_log = []

    def run(self, duration_s=3600, poll_interval=1.0):
        """Run shadow mode for the specified duration."""
        self.real_client.connect()

        t0 = time.time()
        cycle = 0

        while (time.time() - t0) < duration_s:
            # 1. Read real plant state
            real_pressures = self._read_real_pressures()
            real_flows     = self._read_real_flows()

            # 2. Get twin prediction (from MATLAB via UDP or shared memory)
            twin_pressures = self._get_twin_prediction()

            # 3. Compute residuals
            residual = np.array(real_pressures) - np.array(twin_pressures)

            # 4. Log
            self.residual_log.append({
                'cycle': cycle,
                'time_s': time.time() - t0,
                'max_residual': float(np.max(np.abs(residual))),
                'mean_residual': float(np.mean(np.abs(residual))),
                'residuals': residual.tolist(),
            })

            # 5. Alert if drift exceeds threshold
            if np.max(np.abs(residual)) > 2.0:  # bar
                print(f'[ALERT] Twin drift: max residual = {np.max(np.abs(residual)):.2f} bar')

            cycle += 1
            time.sleep(poll_interval)

        self.real_client.close()

    def _read_real_pressures(self):
        r = self.real_client.read_holding_registers(0, count=20, device_id=1)
        if r.isError():
            return [0.0] * 20
        return [v / 100.0 for v in r.registers]

    def _read_real_flows(self):
        r = self.real_client.read_holding_registers(20, count=20, device_id=1)
        if r.isError():
            return [0.0] * 20
        return [v / 100.0 for v in r.registers]

    def _get_twin_prediction(self):
        # In production: read from MATLAB UDP or shared memory
        # For now: placeholder
        return [0.0] * 20

    def export_residuals(self, path='twin_residuals.csv'):
        with open(path, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=['cycle', 'time_s',
                               'max_residual', 'mean_residual'])
            w.writeheader()
            for r in self.residual_log:
                w.writerow({k: r[k] for k in ['cycle', 'time_s',
                            'max_residual', 'mean_residual']})
```

---

## Phase Summary

| Phase | What | Duration | Depends On | Key Output |
|---|---|---|---|---|
| **0** | Fix physics divergence + small bugs | 1–2 days | Nothing | Stable pressures 12–28 bar |
| **1** | Device registry + register map | 2–3 days | Phase 0 | `device_registry.m`, `register_map.m` |
| **2** | Network traffic logger | 3–4 days | Phase 1 | `network_dataset.csv` with src/dst IPs |
| **3** | Dataset merger + ML integration | 2–3 days | Phase 2 | `merged_cps_dataset.csv` (~300 cols) |
| **4** | Multi-PLC virtual architecture | 3–5 days | Phase 2 | 23 virtual PLCs with unique IPs |
| **5** | Shadow twin connection | 3–5 days | Phase 0–3 | Live residual monitoring |

**Total:** 14–22 days for full implementation.

**Minimum viable path (Phases 0+1+2+3):** 8–12 days → gives you a complete CPS dataset with device-level network identity, suitable for thesis and papers.

---

## File Manifest (New + Modified)

### New Files
```
config/
  device_registry.m          ← Phase 1
  register_map.m             ← Phase 1
  device_lookup.m            ← Phase 1

middleware/
  network_logger.py          ← Phase 2
  virtual_plc.py             ← Phase 4

ml_pipeline/
  merge_datasets.py          ← Phase 3

twin/
  shadow_twin.py             ← Phase 5
  comparator.py              ← Phase 5
```

### Modified Files
```
network/updatePressure.m     ← Phase 0 (relaxation + diffusion)
config/simConfig.m           ← Phase 0 (node_V = 500)
scada/updateCUSUM.m          ← Phase 0 (struct input guard)
network/computeFlows.m       ← Phase 0 (zero-length pipe guard)
middleware/gateway.py        ← Phase 2 (network logger integration)
ml_pipeline/cgd_ids_pipeline.py ← Phase 3 (network feature columns)
```
