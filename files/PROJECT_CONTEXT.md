# Gas Pipeline CPS Simulator — Complete Project Context
**Last updated:** 2026-03-16  
**Session:** Third session — CODESYS Modbus, I/O mapping, Python gateway, MATLAB compatibility

---

## 1. Core Context

### Project
A **Cyber-Physical System (CPS) Simulator** for a 20-node gas transmission pipeline. Generates a **labelled dual-layer dataset** for IDS/anomaly detection research:
- **Process layer** — MATLAB physics simulation
- **Protocol layer** — real Modbus/TCP transactions from CODESYS SoftPLC

### Key Objectives
1. Simulate 20-node gas network (Peng-Robinson EOS, Darcy-Weisbach, Joule-Thomson, line pack, elevation)
2. Inject 10 labelled cyber-attack scenarios A1–A10 (MITRE ATT&CK)
3. CODESYS as real PLC — authentic protocol artefacts (FC codes, register quantisation, timing jitter)
4. Export: `master_dataset.csv` (physics + labels) + `pipeline_data_*.csv` (protocol layer)
5. One-line hardware swap: CODESYS → Siemens S7-1200 via `config.yaml`

---

## 2. User Preferences

| Category | Detail |
|---|---|
| **Physics engine** | MATLAB — all physics, EKF, attack injection |
| **PLC runtime** | CODESYS V3.5 SP21 Patch 5 (64-bit), Control Win V3 x64 |
| **PLC variables** | All **INT** — zero REAL anywhere in CODESYS. MATLAB does float conversion |
| **PLC communication** | Device-based `ModbusTCP_Server_Device` under Ethernet node |
| **Gateway** | Python 3, `pymodbus` + `pyyaml` only |
| **Delivery** | Complete phases in one pass, all files together |
| **CODESYS editor** | Two-panel: top = VAR declarations, bottom = code body — paste separately |
| **Scaling** | pressure ×100, flow ×100, temperature ×10, ratio ×1000, demand ×1000 |
| **Future hardware** | Siemens S7-1200 |

---

## 3. Important Decisions

### Architecture
```
MATLAB (physics) ──UDP 5005──► Python gateway ──Modbus TCP 1502──► CODESYS SoftPLC
MATLAB (physics) ◄──UDP 6006── Python gateway ◄──Modbus TCP 1502── CODESYS SoftPLC
```
- MATLAB = plant simulator (physics, EKF, attacks, logging)
- CODESYS = real PLC (PID, valve logic, safety interlocks)
- Python = protocol bridge + transaction logger

### Communication Protocol — Device-Based Modbus TCP
All alternatives rejected: Modbus FB (€50), OPC UA (paid), pyads (TwinCAT only), raw TCP socket.

### Critical Compatibility Architecture Decision
`runSimulation.m` is the **8-node era orchestrator** and MUST NOT be changed. The 20-node physics files are used only at **init time**. `updateFlow.m` was rewritten as a **compatibility wrapper** that auto-detects old call `(params, p_vec, scalar)` vs new `(params, state_struct, valve_vec)`.

### Short-Run Handling
`duration_min < 30` → `initEmptySchedule(N)` (all labels = "Normal") instead of `initAttackSchedule`. Avoids "can't place 8 attacks" error on test runs.

---

## 4. Files / Data / Resources

### Project Folder Structure
```
Sim/
├── config/simConfig.m               ✓ — 20-node, valve_open_default=1 added
├── network/
│   ├── initNetwork.m                ✓ — 20-node, elevation, line pack
│   ├── updateFlow.m                 ✓ — compatibility wrapper (old+new API)
│   ├── updatePressure.m             ✓
│   └── updateTemperature.m          ✓
├── equipment/
│   ├── initCompressor.m             ✓ — [comp1,comp2] = initCompressor(cfg)
│   ├── updateCompressor.m           ✓ — nargin<5 → comp_id=1 default
│   ├── initPRS.m / updatePRS.m      ✓
│   ├── updateStorage.m              ✓ — bidirectional, inventory tracking
│   ├── updateDensity.m              ✓ — Peng-Robinson EOS
│   └── initValve.m                  ✓ — uses cfg.valveEdges (plural)
├── scada/
│   ├── initEKF.m / updateEKF.m      ~ EXISTS (8-node era, needs 40-state rewrite)
│   ├── initPLC.m                    ✓ — initPLC(cfg, state, comp) 3-arg SCADA model
│   └── updatePLC.m                  ✓
├── control/updateControlLogic.m     ✓ — rewritten: pid1_/pid2_ field names
├── attacks/
│   ├── initAttackSchedule.m         ✓ EXISTS
│   ├── applyAttackEffects.m         ✓ — cfg.comp_ratio → cfg.comp1_ratio fixed
│   ├── applySensorSpoof.m           ✓ EXISTS
│   └── detectIncidents.m            ✓ EXISTS
├── logging/
│   ├── initLogs.m / updateLogs.m    ✓ EXISTS
│   └── logEvent.m                   ✓ EXISTS — persistent file handle
├── profiling/generateSourceProfile.m ✓ — uses cfg.src_slow_amp, cfg.src_med_amp etc.
├── export/exportDataset.m           ✓ EXISTS
├── middleware/
│   ├── gateway.py                   ✓ LIVE — 61-reg send, 16-val recv
│   ├── data_logger.py               ✓ — 150-col CSV, all 70 regs + 7 coils
│   ├── diagnostic.py                ✓ — all 5 tests pass
│   ├── config.yaml                  ✓ — host 127.0.0.1, port 1502
│   ├── sendToGateway.m              ✓ — 61×float64 UDP TX
│   ├── receiveFromGateway.m         ✓ — 16×float64 UDP RX, divides by scale
│   └── initGatewayState.m           ✓ — safe defaults before first UDP packet
├── runSimulation.m                  ✓ EXISTS — 8-node orchestrator, DO NOT MODIFY
└── main_simulation.m                ✓ — thin wrapper, compatibility bridging
```

### Files That Must NOT Be Modified (self-consistent 8-node runtime set)
`runSimulation.m`, `logging/initLogs.m`, `logging/updateLogs.m`, `scada/updatePLC.m`, `scada/updateEKF.m`, `attacks/applySensorSpoof.m`, `attacks/detectIncidents.m`, `export/exportDataset.m`

---

## 5. Key Technical Details

### 20-Node Topology
```
Nodes: 1:S1  2:J1  3:CS1  4:J2  5:J3  6:J4  7:CS2  8:J5  9:J6  10:PRS1
       11:J7  12:STO  13:PRS2  14:S2  15:D1  16:D2  17:D3  18:D4  19:D5  20:D6

Edges:
  E1:1→2  E2:2→3  E3:3→4  E4:4→5  E5:5→6  E6:6→7  E7:7→8
  E8:4→9* E9:9→10  E10:10→15  E11:10→16  E12:5→11  E13:14→11
  E14:11→12*  E15:12→8*  E16:8→13  E17:13→17  E18:13→18  E19:6→19  E20:11→20
  (* = valve edges: E8 upper branch, E14 inject to storage, E15 withdraw from storage)
```

### Modbus Register Map (0-based CODESYS addresses)
```
Holding Registers (FC3/FC16):
  0–19   : p_S1..p_D6      bar ×100    Python→PLC
  20–39  : q_E1..q_E20     kg/s ×100   Python→PLC
  40–59  : T_S1..T_D6      K ×10       Python→PLC
  60     : demand_scalar   ×1000        Python→PLC
  61–99  : RESERVED
  100    : cs1_ratio_cmd   ×1000        PLC→Python
  101    : cs2_ratio_cmd   ×1000        PLC→Python
  102    : valve_E8_cmd    ×1000        PLC→Python
  103    : valve_E14_cmd   ×1000        PLC→Python
  104    : valve_E15_cmd   ×1000        PLC→Python
  105    : prs1_setpoint   bar ×100     PLC→Python
  106    : prs2_setpoint   bar ×100     PLC→Python
  107    : cs1_power_kW    kW ×10       PLC→Python
  108    : cs2_power_kW    kW ×10       PLC→Python

Coils (FC1):
  0: emergency_shutdown    1: cs1_alarm    2: cs2_alarm
  3: sto_inject_active     4: sto_withdraw_active
  5: prs1_active           6: prs2_active

TOTALS: 70 holding registers + 7 coils, 0 input registers
```

### CODESYS Connection
```
IP:       127.0.0.1 (localhost — Python and CODESYS on same machine)
Port:     1502
Unit ID:  1
Machine:  DESKTOP-HP65TET
Status:   CONFIRMED LIVE (3269 requests served, all diagnostic tests pass)
```

### pymodbus 3.12+ API (breaking changes)
```python
# CORRECT for pymodbus 3.12:
client.read_holding_registers(address, count=count, device_id=unit_id)
client.read_coils(address, count=count, device_id=unit_id)
client.write_registers(address, values, device_id=unit_id)
# WRONG (removed in 3.12): slave=, unit=, positional unit_id
```

### UDP Protocol
```
MATLAB → Gateway (port 5005, 488 bytes): 61 × float64
  [20 pressures | 20 flows | 20 temps | 1 demand_scalar]
  Gateway scales to INT: bar×100, kg/s×100, K×10, scalar×1000

Gateway → MATLAB (port 6006, 128 bytes): 16 × float64
  [cs1_ratio | cs2_ratio | v_E8 | v_E14 | v_E15 |
   prs1_sp | prs2_sp | cs1_pwr | cs2_pwr |
   e_shutdown | cs1_alarm | cs2_alarm | sto_inject |
   sto_withdraw | prs1_active | prs2_active]
  MATLAB decodes: ratio÷1000, pressure÷100, kW÷10
```

### MATLAB Function Signatures (critical for compatibility)
```matlab
% INIT (main_simulation.m calls these):
[params, state]  = initNetwork(cfg)
[comp1, comp2]   = initCompressor(cfg)       % NOT single comp
valve            = initValve(cfg)             % uses cfg.valveEdges
plc              = initPLC(cfg, state, comp)  % 3-arg SCADA model
ekf              = initEKF(cfg, state)
logs             = initLogs(params, ekf, N)
schedule         = initAttackSchedule(N, cfg)

% RUNTIME (runSimulation.m calls these — MUST match):
state.q           = updateFlow(params, state.p, plc.act_valve_cmd)  % old signature
[state.p, p_ac]   = updatePressure(params, state.p, state.q, demand, p_ac, cfg)
[state, comp]     = updateCompressor(state, comp, k, cfg)           % 4 args, no comp_id
[Tgas, T_t]       = updateTemperature(params, Tgas, q, p_prev, p, T_turb, cfg)
[rho, rho_c]      = updateDensity(p, Tgas, rho_comp, cfg)
[comp,valve,plc]  = updateControlLogic(comp, valve, plc, xhatP, cfg, k, dt)
logs              = updateLogs(logs, state, ekf, plc, comp, valve, params, k, sp, sq)
exportDataset(logs, cfg, params, N, schedule)
```

### simConfig.m Fields (key additions this session)
```matlab
cfg.valve_open_default = 1      % ADDED — used by initPLC
cfg.valveEdges = [8, 14, 15]   % plural (not valveEdge)
cfg.comp1_ratio = 1.25          % (not cfg.comp_ratio)
cfg.pid1_Kp = 0.4               % (not cfg.pid_Kp)
cfg.pid1_setpoint = 30.0        % (not cfg.pid_setpoint)
cfg.pid_D1_node = 15            % CS1 feedback node index
cfg.pid_D3_node = 17            % CS2 feedback node index
```

### CODESYS PLC_PRG Pitfalls
| Wrong | Correct | Reason |
|---|---|---|
| `dt` as variable | `cycle_dt` | `dt` = IEC 61131-3 DATE_AND_TIME keyword |
| `DINT_TO_DINT(x)` | `INT_TO_DINT(x)` | Function does not exist |
| `ABS(q)*ratio` (two INTs) | `INT_TO_DINT(ABS(q)) * INT_TO_DINT(ratio)` | INT×INT overflows at real values |

### Attack Scenarios
| ID | Name | MITRE | Target |
|---|---|---|---|
| A1 | SrcPressureManipulation | T0831 | src_p_out |
| A2 | CompressorRatioSpoofing | T0838 | comp.ratio |
| A3 | ValveCommandTampering | T0855 | valve cmd |
| A4 | DemandNodeManipulation | T0829 | demand |
| A5 | PressureSensorSpoofing | T0831 | sensor_p(node 4) |
| A6 | FlowMeterSpoofing | T0827 | sensor_q(E4,E5) |
| A7 | PLCLatencyAttack | T0814 | latency buffer |
| A8 | PipelineLeak | T0829 | q_E12 |
| A9 | FDI Attack | — | nodes 4,5,8 |
| A10 | Replay Attack | — | 60s buffer |

---

## 6. Current Progress

### Phase 1 — Pure MATLAB Enhancements (0%)
- Measurement quantisation (12-bit ADC) — pending
- Packet loss / stuck sensor — pending
- A9 FDI attack (`computeFDIVector.m`) — pending
- A10 Replay attack (`applyReplayAttack.m`) — pending

### Phase 2 — 20-Node Physics (100% ✓)
All 14 physics files complete.

### Phase 3 — Historian + EKF (10%)
- `initEKF.m` / `updateEKF.m` — exist but are 8-node era, need 40-state rewrite
- `updateHistorian.m` — not written

### Phase 4 — External Stack (85%)
| Item | Status |
|---|---|
| CODESYS Modbus device + I/O mapping | ✓ Done |
| PLC_PRG all-INT, 0 build errors | ✓ Done |
| Python gateway live | ✓ CONFIRMED — 3269 requests |
| data_logger.py | ✓ 998 cycles, 0 errors |
| diagnostic.py | ✓ All 5 tests pass |
| main_simulation.m + UDP functions | ✓ Done |
| **End-to-end MATLAB→CODESYS** | ○ PENDING — fix applied, not yet tested |

### Last Known State
`main_simulation(10)` was crashing at `runSimulation` line 46 because `updateFlow` received a pressure vector where it expected a state struct. **Fix applied** (compatibility wrapper) but **not yet run**.

---

## 7. Pending Tasks / Next Steps

### Immediate — Run the fixed simulation
```matlab
main_simulation(10)    % 10 min, clean baseline, offline mode
% If that passes, try with gateway:
main_simulation(10, true)  % requires: python gateway.py running first
% Full run:
main_simulation(300)   % 300 min with attacks (A1–A10)
```

### CODESYS Startup Sequence
```
1. System tray CODESYS icon → Start PLC (green)
2. CODESYS IDE: F11 (Build) → F4 (Login) → Yes to download → F5 (Start)
3. Terminal: python gateway.py
4. MATLAB: main_simulation(300)
```

### After Simulation Runs — Phase 1 Files
1. `attacks/applyReplayAttack.m` — 60s rolling buffer playback (A10)
2. `attacks/computeFDIVector.m` — triangle FDI nodes 4,5,8 (A9)
3. `runSimulation.m` additions — ADC quantisation + packet loss
4. `scada/initEKF.m` + `updateEKF.m` — 40-state [20p, 20q] rewrite

### Future Hardware (S7-1200)
Change `config.yaml`: `plc.type: "s7"`, `host: "192.168.x.x"`  
TIA Portal: enable PUT/GET, DB1 (122 bytes, non-optimised) = sensors, DB2 (18 bytes) = actuators, rack=0 slot=1

---

## 8. Useful Commands

```bash
# Standalone protocol logger (no MATLAB needed)
python data_logger.py --host 127.0.0.1 --port 1502 --duration 3600

# Full connection diagnostic
python diagnostic.py

# Print all 150 CSV column names
python data_logger.py --print-header

# Gateway (must run before MATLAB when use_gateway=true)
python gateway.py
```
