# Gas Pipeline CPS Simulator — Complete Project Memory
**Last updated:** March 2026
**Session type:** Multi-session deep technical research + implementation

---

## 1. Core Context

### Main Project
A **Cyber-Physical System (CPS) Simulator** for a 20-node gas transmission pipeline, built for IDS and anomaly detection research. The simulator generates a labelled dual-layer dataset (physics layer + Modbus/TCP protocol layer) covering 10 MITRE ATT&CK attack scenarios.

### Research Context
- **Thesis deadline:** 10–15 days from last session (approximately early April 2026)
- **Two papers planned** with staggered submission:
  - Paper 1 (Month 3): Testbed architecture + dataset description → IEEE Access or Computers & Security
  - Paper 2 (Month 4): Novel physics-residual hybrid detection algorithm → IEEE Transactions on Industrial Informatics
- **Novel contribution identified:** Adaptation of GasLib-24 to Indian City Gas Distribution (CGD) parameters under BIS and PNGRB T4S regulations — no prior published work found on cyber-physical security of Indian CGD networks

### Key Objectives
1. Simulate a 20-node gas network using MATLAB physics (Weymouth/Darcy-Weisbach, Peng-Robinson EOS, Joule-Thomson, linepack)
2. Inject 10 labelled cyber-attack scenarios (A1–A10, MITRE ATT&CK ICS)
3. Use CODESYS SoftPLC as a real PLC producing authentic Modbus/TCP protocol artefacts
4. Export `master_dataset.csv` (physics + labels) and `pipeline_data_*.csv` (protocol layer)
5. Validate process-layer and protocol-layer authenticity with a standalone physical testbed

---

## 2. User Preferences

### Tools and Environments
| Layer | Tool | Notes |
|---|---|---|
| Physics engine | MATLAB | All physics, EKF, attack injection |
| PLC runtime | CODESYS V3.5 SP21 Patch 5 (64-bit), Control Win V3 x64 | Device-based ModbusTCP_Server_Device |
| PLC variables | All INT — zero REAL anywhere in CODESYS | MATLAB does float conversion |
| Gateway | Python 3, pymodbus 3.12+ + pyyaml only | |
| Physical testbed PLC | Siemens S7-1200 CPU 1214C | Standalone, separate from simulator |
| Physical testbed HMI | Separate laptop, Node-RED or WinCC | Air-gapped OT-LAN |

### Key Workflow Preferences
- Deliver complete phases in one pass, all files together
- CODESYS editor: two-panel (top = VAR declarations, bottom = code body — paste separately)
- All CODESYS variables stored as INT (scaled integers); float conversion handled entirely in MATLAB
- No Statistics and Machine Learning Toolbox dependency — use `-mu * log(rand())` instead of `exprnd(mu)`

---

## 3. Important Decisions

### Architecture (Final)
```
MATLAB (physics) ──UDP 5005──► Python gateway ──Modbus TCP 1502──► CODESYS SoftPLC
MATLAB (physics) ◄──UDP 6006── Python gateway ◄──Modbus TCP 1502── CODESYS SoftPLC
```

### Critical Architecture Constraints
- `runSimulation.m` is a **frozen 8-node-era orchestrator** — MUST NOT be modified
- 20-node physics files are used only at init time
- `updateFlow.m` was rewritten as a **compatibility wrapper** auto-detecting old vs new API call signatures
- Short-run handling: `duration_min < 30` → `initEmptySchedule(N)` instead of `initAttackSchedule`

### Physics Model Choices
- Weymouth steady-state flow + Darcy-Weisbach friction (Colebrook-White)
- Peng-Robinson EOS for gas density
- Isothermal Euler equations (same basis as GasLib)
- Joule-Thomson cooling coefficient: −0.45 K/bar
- EKF state dimension: 40 (20 pressures + 20 flows)
- Logging decimation: `log_every = 10` → 1 Hz dataset rows from 10 Hz physics

### Dataset Design
- ~340 valid baseline scenarios + ~90 attack runs
- Target: ~774,000 total rows
- ML split: **scenario-level** (not row-level) to prevent data leakage
- Include transient rows in training data

### Two-Paper Structure
- **Paper 1** (Month 3): Testbed architecture + dataset — system/data paper, ~5,000 words, IEEE Access target
- **Paper 2** (Month 4): Physics-residual hybrid detection — methods paper, ~4,500 words, IEEE TII target
- Both papers feed directly into thesis Chapters 3 and 4

---

## 4. Files / Data / Resources

### Project Folder Structure
```
Sim/
├── config/simConfig.m               ✓ — 20-node, valve_open_default=1 added
├── network/
│   ├── initNetwork.m                ✓ — 20-node, elevation, linepack
│   ├── updateFlow.m                 ✓ — compatibility wrapper (old+new API)
│   ├── updatePressure.m             ✓
│   └── updateTemperature.m          ✓
├── equipment/
│   ├── initCompressor.m             ✓ — [comp1,comp2] = initCompressor(cfg)
│   ├── updateCompressor.m           ✓ — nargin<5 → comp_id=1 default
│   ├── initPRS.m / updatePRS.m      ✓
│   ├── updateStorage.m              ✓ — bidirectional, inventory tracking
│   ├── updateDensity.m              ✓ — Peng-Robinson EOS cubic Z solver
│   └── initValve.m                  ✓ — uses cfg.valveEdges (plural)
├── scada/
│   ├── initEKF.m / updateEKF.m      ~ EXISTS (8-node era, needs 40-state rewrite)
│   ├── initPLC.m                    ✓ — initPLC(cfg, state, comp) 3-arg
│   └── updatePLC.m                  ✓
├── control/updateControlLogic.m     ✓ — pid1_/pid2_ field names
├── attacks/
│   ├── initAttackSchedule.m         ✓
│   ├── applyAttackEffects.m         ✓ — cfg.comp_ratio → cfg.comp1_ratio fixed
│   ├── applySensorSpoof.m           ✓
│   └── detectIncidents.m            ✓
├── logging/
│   ├── initLogs.m / updateLogs.m    ✓
│   └── logEvent.m                   ✓ — persistent file handle
├── profiling/generateSourceProfile.m ✓ — diurnal AR(1) profiles
├── export/exportDataset.m           ✓
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

### Files That Must NOT Be Modified
`runSimulation.m`, `logging/initLogs.m`, `logging/updateLogs.m`, `scada/updatePLC.m`, `scada/updateEKF.m`, `attacks/applySensorSpoof.m`, `attacks/detectIncidents.m`, `export/exportDataset.m`

### External Resources
- **GasLib-24** — network topology and parameter baseline (gaslib.zib.de, CC BY 3.0)
- **MITRE ATT&CK for ICS** — attack scenario taxonomy
- **CIC Modbus 2023** — comparison dataset (UNB, Docker-based — lower fidelity than CODESYS)
- **UAH Gas Pipeline dataset** (Morris et al., 2014) — comparison benchmark
- **SWaT dataset** (iTrust, Singapore) — methodology precedent

### Generated Output Documents (this session)
- `gas_pipeline_research.docx` — comprehensive research design document
- `tabletop_physical_testbed.md` — standalone physical testbed construction guide
- Research justification article covering: dataset genuineness, GasLib validation, BIS/PNGRB Indian CGD standards, operational scenario matrix

---

## 5. Key Technical Details

### 20-Node Topology
```
Nodes: 1:S1  2:J1  3:CS1  4:J2  5:J3  6:J4  7:CS2  8:J5  9:J6  10:PRS1
       11:J7  12:STO  13:PRS2  14:S2  15:D1  16:D2  17:D3  18:D4  19:D5  20:D6

Valve edges: E8 (J2→J6), E14 (J7→STO), E15 (STO→J5)
Compressor nodes: CS1 (node 3), CS2 (node 7)
PRS nodes: PRS1 (node 10, 30 bar setpoint), PRS2 (node 13, 25 bar setpoint)
Storage node: STO (node 12)
Sources: S1 (node 1), S2 (node 14)
Demands: D1–D6 (nodes 15–20)
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

TOTALS: 70 holding registers + 7 coils
```

### CODESYS Connection
```
IP:       127.0.0.1 (localhost)
Port:     1502
Unit ID:  1
Status:   CONFIRMED LIVE (3269 requests served, all 5 diagnostic tests pass)
```

### UDP Protocol
```
MATLAB → Gateway (port 5005, 488 bytes): 61 × float64
  [20 pressures | 20 flows | 20 temps | 1 demand_scalar]
  Gateway scales: bar×100, kg/s×100, K×10, scalar×1000 → INT

Gateway → MATLAB (port 6006, 128 bytes): 16 × float64
  [cs1_ratio | cs2_ratio | v_E8 | v_E14 | v_E15 |
   prs1_sp | prs2_sp | cs1_pwr | cs2_pwr |
   e_shutdown | cs1_alarm | cs2_alarm | sto_inject |
   sto_withdraw | prs1_active | prs2_active]
```

### pymodbus 3.12+ API (breaking change — always use these)
```python
client.read_holding_registers(address, count=count, device_id=unit_id)
client.read_coils(address, count=count, device_id=unit_id)
client.write_registers(address, values, device_id=unit_id)
# WRONG (removed): slave=, unit=, positional unit_id
```

### simConfig.m Critical Fields
```matlab
cfg.dt = 0.1;              % physics time step (s) — do NOT change
cfg.T  = 100 * 60;         % total simulation time
cfg.log_every = 10;        % 1 Hz dataset rows from 10 Hz physics
cfg.n_attacks = 4;         % attacks to schedule
cfg.valveEdges = [8, 14, 15];   % NOT valveEdge (singular)
cfg.comp1_ratio = 1.25;    % NOT cfg.comp_ratio
cfg.pid1_Kp = 0.4;         % NOT cfg.pid_Kp
cfg.pid1_setpoint = 30.0;  % NOT cfg.pid_setpoint
cfg.pid_D1_node = 15;      % CS1 feedback node
cfg.pid_D3_node = 17;      % CS2 feedback node
cfg.valve_open_default = 1;
cfg.p0 = 50.0;             % bar initial pressure
cfg.sto_p_inject = 52.0;   % bar threshold for storage injection
cfg.sto_p_withdraw = 46.0; % bar threshold for storage withdrawal
```

### MATLAB Function Signatures (critical for compatibility)
```matlab
% Init:
[params, state]  = initNetwork(cfg)
[comp1, comp2]   = initCompressor(cfg)       % NOT single comp
[prs1, prs2]     = initPRS(cfg)
valve            = initValve(cfg)             % uses cfg.valveEdges
plc              = initPLC(cfg, state, comp1) % 3-arg
ekf              = initEKF(cfg, state)
logs             = initLogs(params, ekf, N, cfg)
schedule         = initAttackSchedule(N, cfg)

% Runtime (runSimulation.m calls these — MUST match):
[q, state]        = updateFlow(params, state, valve_states)
[p, p_acoustic]   = updatePressure(params, p, q, demand_vec, p_acoustic_prev, cfg)
[state, comp1]    = updateCompressor(state, comp1, k, cfg, 1)
[state, prs1]     = updatePRS(state, prs1, cfg)
[Tgas, T_turb]    = updateTemperature(params, Tgas, q, p_prev, p, T_turb, cfg)
[rho, rho_c]      = updateDensity(p, Tgas, rho_comp, cfg)
[comp1,comp2,prs1,prs2,valve_states,plc] = updateControlLogic(...)
logs              = updateLogs(logs, state, ekf, plc, comp1, comp2, prs1, prs2, ...)
exportDataset(logs, cfg, params, N, schedule)
```

### Attack Scenarios (A1–A10)
| ID | Name | MITRE | Target |
|---|---|---|---|
| A1 | SrcPressureManipulation | T0831 | src_p_out |
| A2 | CompressorRatioSpoofing | T0838 | comp.ratio |
| A3 | ValveCommandTampering | T0855 | valve cmd |
| A4 | DemandNodeManipulation | T0829 | demand scalar |
| A5 | PressureSensorSpoofing | T0831 | sensor_p node 4 |
| A6 | FlowMeterSpoofing | T0827 | sensor_q E4,E5 |
| A7 | PLCLatencyAttack | T0814 | latency buffer |
| A8 | PipelineLeak | T0829 | q_E12 |
| A9 | FDI Attack | — | nodes 4,5,8 |
| A10 | Replay Attack | — | 60s buffer |

### CODESYS PLC_PRG Pitfalls (hard-won fixes)
| Wrong | Correct | Reason |
|---|---|---|
| `dt` as variable | `cycle_dt` | `dt` = IEC 61131-3 DATE_AND_TIME keyword |
| `DINT_TO_DINT(x)` | `INT_TO_DINT(x)` | Function does not exist |
| `ABS(q)*ratio` (two INTs) | `INT_TO_DINT(ABS(q)) * INT_TO_DINT(ratio)` | INT×INT overflows at real values |

### Known Physics Issues (fixes provided but not yet tested)
1. **Storage loop divergence** (nodes J7/J5 hitting pressure ceilings/floors): adjust `sto_p_inject`, `sto_p_withdraw`, `sto_k_flow`
2. **CUSUM cold-start false alarms**: increase slack and threshold parameters

---

## 6. Current Progress

### Phase 1 — Pure MATLAB Enhancements (0%)
- A9 FDI attack (`computeFDIVector.m`) — pending
- A10 Replay attack (`applyReplayAttack.m`) — pending
- ADC quantisation (12-bit) — pending
- Packet loss / stuck sensor simulation — pending

### Phase 2 — 20-Node Physics (100% ✓)
All 14 physics files complete and verified.

### Phase 3 — Historian + EKF (10%)
- `initEKF.m` / `updateEKF.m` — exist but are 8-node era; need 40-state [20p, 20q] rewrite
- `updateHistorian.m` — not written

### Phase 4 — External Stack (85%)
| Item | Status |
|---|---|
| CODESYS Modbus device + I/O mapping | Done |
| PLC_PRG all-INT, 0 build errors | Done |
| Python gateway live | CONFIRMED — 3269 requests served |
| data_logger.py | 998 cycles, 0 errors |
| diagnostic.py | All 5 tests pass |
| main_simulation.m + UDP functions | Done |
| **End-to-end MATLAB→CODESYS** | PENDING — fix applied (updateFlow compatibility wrapper), not yet tested |

### Last Known Crash Point
`main_simulation(10)` crashed at `runSimulation` line 46 because `updateFlow` received a pressure vector where it expected a state struct. **Compatibility wrapper fix was applied** to `updateFlow.m` but the fix had not yet been tested when the session ended.

### Physical Testbed
- Design complete (Bill of Materials, wiring diagrams, Purdue architecture, TIA Portal config)
- Build not started
- Estimated build time: 20–22 hours active work
- Estimated cost: INR 1.5–2.5 lakh

### Research Documents Generated
- Comprehensive research design document (Word .docx) — network properties, topology variations, objectives, 3-month roadmap, baseline strategy, GasLib validation, BIS/PNGRB conversion, research papers, dataset pre-processing protocol
- Physical testbed construction guide (Markdown) — standalone, Purdue-compliant
- Four novel research objectives document with literature citations
- Two-paper strategy document with section-by-section breakdown

---

## 7. Pending Tasks / Next Steps

### Immediate (Simulator)
1. **Run the fixed simulation** to confirm compatibility wrapper works:
   ```matlab
   main_simulation(10)           % 10 min, offline, no gateway
   main_simulation(10, true)     % 10 min with gateway (run python gateway.py first)
   main_simulation(300)          % full 300-min run with attacks
   ```
2. CODESYS startup sequence before gateway run:
   ```
   1. System tray CODESYS icon → Start PLC (green)
   2. CODESYS IDE: F11 (Build) → F4 (Login) → Yes to download → F5 (Start)
   3. Terminal: python gateway.py
   4. MATLAB: main_simulation(300)
   ```
3. Confirm storage divergence fix resolves (J7/J5 pressure ceiling/floor hits)
4. Confirm CUSUM cold-start false alarm fix resolves

### Phase 1 Remaining Files
1. `attacks/applyReplayAttack.m` — 60s rolling buffer playback (A10)
2. `attacks/computeFDIVector.m` — triangle FDI nodes 4,5,8 (A9)
3. ADC quantisation + packet loss additions to `runSimulation.m`
4. `scada/initEKF.m` + `updateEKF.m` — 40-state [20p, 20q] rewrite

### Dataset Generation
1. Execute baseline scenario sweep (~340 runs across 9 topology scenarios)
2. Execute attack sweep (~90 runs — 10 attacks × 9 scenarios)
3. Feature engineering on derived columns
4. ML train/val/test splits at scenario level (not row level)

### Thesis Writing (10–15 day sprint)
| Day | Target |
|---|---|
| 1–2 | Chapter 1: Introduction, problem statement, objectives |
| 3–4 | Chapter 2: Literature review |
| 5 | Chapter 3: Methodology — network design, simulator architecture, attack taxonomy |
| 6 | Chapter 3 cont.: register map, data collection, pre-processing pipeline |
| 7–8 | Chapter 4: Results — baseline statistics, detection metrics, cross-topology tests |
| 9 | Chapter 5: Discussion, GasLib comparison, limitations |
| 10 | Abstract, references (IEEE format), proofread |

### Paper 1 (Month 3 Submission)
- Write now: Sections 1 (Introduction), 2 (Related work), 3 (Testbed architecture) — ~2,600 words possible before implementation is complete
- Write after data: Sections 4 (Dataset), 5 (Validation)

### Paper 2 (Month 4 Submission)
- Novel algorithm: CUSUM on Weymouth residuals + LSTM on FC-layer features → fused score
- Claim: physics residuals detect slow-ramp FDI ~4× earlier than Modbus-only LSTM

### Physical Testbed (Optional, Low Priority)
- Procure components (1–2 weeks lead time)
- Build after thesis submission if time permits

### Future Hardware (S7-1200 swap for full simulator)
- Change `config.yaml`: `plc.type: "s7"`, `host: "192.168.x.x"`
- TIA Portal: enable PUT/GET, DB1 (122 bytes, non-optimised) = sensors, DB2 (18 bytes) = actuators

---

## 8. Key Research Justification Points (for thesis)

### Why CODESYS beats Docker for dataset genuineness
- Real IEC 61131-3 runtime with authentic scan cycles (~10 ms)
- Genuine 16-bit register quantisation (INT-only storage)
- Real Modbus/TCP timing: FC03 response times 7.694–8.234 ms measured
- Inter-request interval jitter ~0.5 ms (vs Docker's OS-level randomness)

### Why GasLib-24 is a valid reference
- 138+ citations in top venues (INFORMS, Applied Energy, Nature Scientific Reports)
- Based on real German network operator data (Open Grid Europe)
- Uses identical physics: isothermal Euler + Darcy-Weisbach + Colebrook-White
- 20-node network sits between GasLib-24 (24 nodes) and GasLib-11 (11 nodes)

### Indian CGD parameter adaptation (novel contribution)
- GasLib operates at 40–85 bar (German transmission)
- Indian CGD steel grid: **14–26 bar** (PNGRB T4S Regulation GSR 612(E))
- Replace compressors with DRS/PRS units (regulating from 60–99 bar to 26 bar at CGS)
- Pipe: DN 100–300 steel (IS 3589) or MDPE PE 80/100 (max 7 bar, IS 14885)
- No published work on cyber-physical security of Indian CGD → genuine gap

### Statistical validation battery for dataset realism
1. ADF test — stationarity of steady-state variables
2. ACF/PACF — AR(1) structure confirms physical inertia
3. KS two-sample test — compare simulated vs reference distributions
4. PSD analysis — scan-cycle frequency peaks in Modbus timing
5. Shapiro-Wilk — Gaussian residuals in steady-state sensor noise

---

## 9. Important Terminology and Context

- **Dual-layer dataset**: simultaneous physics-layer (pressure, flow, temperature) + protocol-layer (Modbus FC codes, register INTs, timestamps)
- **Spatiotemporal propagation labels**: per-row columns recording `attack_origin`, `t_origin`, `propagation_hop`, `t_hop`, `propagation_delay_s` — computed from Weymouth residual crossing 3σ at downstream nodes
- **Physics residual**: `|P_measured − P_Weymouth_predicted|` per pipe per cycle — the signal that detects slow-ramp FDI invisible to protocol-only detectors
- **Scenario-level ML split**: train on SC-01 to SC-06, validate on SC-07, test on SC-08 and SC-09 (avoids data leakage across topological regimes)
- **Morris dataset flaw**: attacks performed at one pressure, normal operation at another → classifiers learn operational state, not attack signature. Avoided here by injecting attacks across all 9 operational scenarios
- **CODESYS "bus not running" banner**: can be cosmetic — confirm server liveness by checking request count (was 3269 and growing when last confirmed live)
- **log_every=10**: physics runs at 10 Hz (dt=0.1s), but only 1 in 10 steps written to CSV → 1 Hz dataset rows, prevents enormous file sizes
