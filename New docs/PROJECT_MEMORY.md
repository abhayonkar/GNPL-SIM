# Gas Pipeline CPS Simulator — Complete Project Memory
**Last updated:** April 2026
**Session type:** Multi-session deep technical research + implementation

---

## 1. Core Context

### Main Project
A **Cyber-Physical System (CPS) Simulator** for a 20-node gas transmission pipeline, built for IDS and anomaly detection research. The simulator generates a labelled dual-layer dataset (physics layer + Modbus/TCP protocol layer) covering 10 MITRE ATT&CK attack scenarios.

### Research Context
- **Thesis deadline:** Early April 2026
- **Two papers planned** with staggered submission:
  - Paper 1 (Month 3): Testbed architecture + dataset description → IEEE Access or Computers & Security
  - Paper 2 (Month 4): Novel physics-residual hybrid detection algorithm → IEEE Transactions on Industrial Informatics
- **Novel contribution identified:** Adaptation of GasLib-24 to Indian City Gas Distribution (CGD) parameters under BIS and PNGRB T4S regulations — no prior published work found on cyber-physical security of Indian CGD networks

### Key Objectives
1. Simulate a 20-node gas network using MATLAB physics (Weymouth/Darcy-Weisbach, Peng-Robinson EOS, Joule-Thomson, linepack)
2. Inject 10 labelled cyber-attack scenarios (A1–A10, MITRE ATT&CK ICS)
3. Use CODESYS SoftPLC as a real PLC producing authentic Modbus/TCP protocol artefacts
4. Export `ml_dataset_baseline.csv` (physics + labels, 1 Hz) assembled from per-scenario CSVs
5. Validate process-layer and protocol-layer authenticity with a standalone physical testbed

---

## 2. User Preferences

### Tools and Environments
| Layer | Tool | Notes |
|---|---|---|
| Physics engine | MATLAB | All physics, EKF, CUSUM, attack injection |
| PLC runtime | CODESYS V3.5 SP21 Patch 5 (64-bit), Control Win V3 x64 | Device-based ModbusTCP_Server_Device |
| PLC variables | All INT — zero REAL anywhere in CODESYS | MATLAB does float conversion |
| Gateway | Python 3, pymodbus 3.12+ + pyyaml only | |
| ML pipeline | Python 3: scikit-learn, xgboost, shap, joblib | New script: `ml_pipeline/cgd_ids_pipeline.py` |
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
- `runSimulation.m` is a **frozen orchestrator** — MUST NOT be modified
- `run_24h_sweep.m` drives scenario iteration; calls `execute_simulation()` which calls `runSimulation.m`
- Short-run handling: `make_empty_schedule(N)` used for baseline runs (no attacks)
- Gateway is optional: `run_24h_sweep('gateway', false)` runs fully offline at ~24× real-time

### Physics Model Choices
- Weymouth steady-state flow + Darcy-Weisbach friction (Colebrook-White)
- Peng-Robinson EOS for gas density
- Isothermal Euler equations (same basis as GasLib)
- Joule-Thomson cooling coefficient: −0.45 K/bar
- EKF state dimension: 40 (20 pressures + 20 flows), Phase 6 analytical Jacobian
- Logging decimation: `log_every = 10` → 1 Hz dataset rows from 10 Hz physics

### Dataset Design
- ~279 valid baseline scenarios (after pruning from 405 combinations)
- Actual quick-mode test: 30 scenarios × 600 rows = 18,030 rows, 17.2 MB
- Full sweep estimate: 279 × 1800 rows ≈ 502,200 rows (~2h wall time offline)
- ML split: **scenario-level GroupKFold** (not row-level) to prevent data leakage
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
├── config/simConfig.m               ✔ Complete — all fields audited and added (April 2026)
├── network/
│   ├── initNetwork.m                ✔ 20-node, elevation, linepack
│   ├── updateFlow.m                 ✔ compatibility wrapper (old+new API)
│   ├── updatePressure.m             ✔
│   └── updateTemperature.m          ✔
├── equipment/
│   ├── initCompressor.m             ✔ [comp1,comp2] = initCompressor(cfg)
│   ├── updateCompressor.m           ✔ nargin<5 → comp_id=1 default
│   ├── initPRS.m / updatePRS.m      ✔
│   ├── updateStorage.m              ✔ bidirectional, inventory tracking
│   ├── updateDensity.m              ✔ Peng-Robinson EOS cubic Z solver
│   └── initValve.m                  ✔ uses cfg.valveEdges (plural)
├── scada/
│   ├── initEKF.m                    ✔ initialises residP, residQ (zero vectors)
│   ├── updateEKF.m                  ✔ Phase 6 — physics Jacobian, chi2_stat, residP/residQ aliases
│   ├── initCUSUM.m                  ✔ FIXED — S_upper, S_lower, n_steps = 0
│   ├── updateCUSUM.m                ✔ FIXED — S_upper/S_lower (was S_pos/S_neg), cusum.alarm stored
│   ├── initPLC.m                    ✔ initPLC(cfg, state, comp) 3-arg
│   └── updatePLC.m                  ✔
├── control/updateControlLogic.m     ✔ dual PID (pid1_/pid2_ fields)
├── attacks/
│   ├── initAttackSchedule.m         ✔
│   ├── applyAttackEffects.m         ✔
│   ├── applySensorSpoof.m           ✔ A5, A6, A9-FDI, A10-replay routing
│   ├── applyReplayAttack.m          ✔
│   ├── computeFDIVector.m           ✔
│   ├── initReplayBuffer.m           ✔
│   ├── initFaultState.m             ✔
│   ├── applyFaultInjection.m        ✔
│   └── detectIncidents.m            ✔
├── logging/
│   ├── initLogs.m / updateLogs.m    ✔
│   ├── logEvent.m                   ✔ persistent file handle
│   ├── initHistorian.m              ✔
│   ├── updateHistorian.m            ✔
│   └── exportHistorian.m            ✔
├── processing/
│   ├── addScanJitter.m              ✔ jitter_enable, platform, std/max_ms fields added
│   └── initJitterBuffer.m           ✔
├── profiling/generateSourceProfile.m ✔ diurnal AR(1) profiles
├── export/exportDataset.m           ✔
├── middleware/
│   ├── gateway.py                   ✔ LIVE — 61-reg send, 16-val recv
│   ├── data_logger.py               ✔ 150-col CSV, all 70 regs + 7 coils
│   ├── diagnostic.py                ✔ all 5 tests pass
│   ├── config.yaml                  ✔ host 127.0.0.1, port 1502
│   ├── sendToGateway.m              ✔ 61×float64 UDP TX
│   ├── receiveFromGateway.m         ✔ 16×float64 UDP RX, divides by scale
│   └── initGatewayState.m           ✔ safe defaults before first UDP packet
├── ml_pipeline/
│   ├── cgd_ids_pipeline.py          ✔ NEW — full ML pipeline (April 2026)
│   ├── requirements.txt             ✔ NEW
│   └── indian_cgd_ids_pipeline_fixed.ipynb  (older notebook, superseded)
├── runSimulation.m                  ✔ frozen orchestrator — DO NOT MODIFY
├── run_24h_sweep.m                  ✔ sweep working — 30/30 quick mode (0 failures)
└── main_simulation.m                ✔ thin wrapper, compatibility bridging
```

### Key Output Files (Generated)
```
automated_dataset/
├── baseline/
│   ├── scenario_0001.csv ... scenario_0030.csv   (quick mode, 600 rows each)
│   ├── scenario_index.csv
│   └── sweep_progress.log
├── ml_dataset_baseline.csv      (assembled master, 18,030 rows, 17.2 MB — quick mode)
└── execution_details.log
```

### ML Pipeline Outputs (after running cgd_ids_pipeline.py)
```
ml_pipeline/ml_outputs/
├── pressure_distributions.png
├── flow_distributions.png
├── dataset_composition.png
├── detector_timeseries.png
├── scenario_health.png / scenario_health.csv
├── cm_iforest.png, cm_rf.png, cm_xgb.png
├── importance_rf.png, importance_xgb.png, shap_xgb.png
├── cross_topology_cv.png / cross_topology_cv.csv
├── dataset_statistics.json
├── scaler.pkl, iforest.pkl, random_forest.pkl, xgboost.pkl
└── lstm_ae.pt  (if LSTM-AE is added)
```

---

## 5. Key Technical Details

### 20-Node Topology
```
Nodes: 1:S1  2:J1  3:CS1  4:J2  5:J3  6:J4  7:CS2  8:J5  9:J6  10:PRS1
       11:J7  12:STO  13:PRS2  14:S2  15:D1  16:D2  17:D3  18:D4  19:D5  20:D6

Valve edges: E8 (J2→J6), E14 (J7→STO), E15 (STO→J5)
Compressor nodes: CS1 (node 3), CS2 (node 7)
PRS nodes: PRS1 (node 10, 18 barg setpoint), PRS2 (node 13, 14 barg setpoint)
Storage node: STO (node 12)
Sources: S1 (node 1), S2 (node 14)
Demands: D1–D6 (nodes 15–20)
```

### simConfig.m — Complete Field Inventory (as of April 2026)

All fields verified present after audit. Key groups:

| Section | Fields |
|---|---|
| Timing | `dt=0.1`, `log_every=10`, `sim_duration_min=1440` |
| PID | `pid1_Kp/Ki/Kd`, `pid1_setpoint=16.0`, `pid2_Kp/Ki/Kd`, `pid2_setpoint=15.0`, `pid_D1_node=15`, `pid_D3_node=17` |
| Control thresholds | `emer_shutdown_p=28.0`, `valve_open_lo=14.0`, `valve_close_hi=24.0` |
| EKF | `ekf_P0=1e-2`, `ekf_Qn=1e-4`, `ekf_Rk=1e-3` (aliased from `_diag` versions) |
| CUSUM | `cusum_slack=2.5`, `cusum_threshold=12.0`, `cusum_warmup_steps=300`, `cusum_reset_on_trip=true` |
| Storage | `sto_p_inject=24.5`, `sto_p_withdraw=16.5`, `sto_k_flow=0.2`, `sto_max_flow=200`, `sto_inventory_init=0.60` |
| Historian | `historian_enable=false`, `historian_deadband_p/q/T`, `historian_max_interval_s=300` |
| Fault | `fault_enable=false`, `fault_stuck_nodes=[15-18]`, `fault_stuck_prob=0.001`, `fault_stuck_dur_s=30`, `fault_loss_prob=0.002`, `fault_max_consec=3` |
| Jitter | `jitter_enable=false`, `jitter_platform='codesys'`, `jitter_codesys_std_ms=20`, `jitter_codesys_max_ms=150`, `jitter_s7_std_ms=1.5`, `jitter_s7_max_ms=10` |
| Attacks | `atk1_spike_amp`, `atk2_*`, `atk3_cmd`, `atk4_*`, `atk5_*`, `atk6_*`, `atk8_*`, `atk9_*`, `atk10_*` |
| Alarms | `alarm_P_high=26.0`, `alarm_P_low=14.0`, `alarm_ekf_resid=2.0`, `alarm_comp_hi=1.55` |

### CUSUM Fixes (Phase A — April 2026)

**initCUSUM.m:**
- Added `cusum.n_steps = 0` (was missing → crash on first `updateCUSUM` call)
- Fields named `S_upper`/`S_lower` (consistent with `updateCUSUM` and `runSimulation` log reads)

**updateCUSUM.m:**
- Renamed `S_pos` → `S_upper`, `S_neg` → `S_lower` throughout
- Added `cusum.alarm = alarm` so the alarm state is stored in-struct
- Early-return in warmup now sets `cusum.alarm = false` (not just local `alarm` var)
- `cusum.n_steps` incremented each call for warmup guard

### EKF Phase 6 Upgrade (April 2026)

**updateEKF.m:**
- Physics-derived Jacobian `F = buildJacobian(xhat, params, cfg, nN, nE)` replaces `F = eye(40)`
- Analytical linearised Jacobian: `F_pp = I + Γ·B·diag(w)·Bᵀ`, `F_qp = diag(w)·Bᵀ`, `F_qq = α·I`
- Added `ekf.residP = ekf.residualP` and `ekf.residQ = ekf.residualQ` aliases (required by `detectIncidents`)
- Added `ekf.chi2_stat = inn' * (S \ inn)` and `ekf.chi2_alarm` (threshold 63.7 for χ²(40))
- Divergence guard: resets to measurement if any state is non-finite or covariance diagonal goes negative

### Modbus Register Map (0-based CODESYS addresses)
```
Holding Registers (FC3/FC16):
  0–19   : p_S1..p_D6      bar×100    Python→PLC
  20–39  : q_E1..q_E20     kg/s×100   Python→PLC
  40–59  : T_S1..T_D6      K×10       Python→PLC
  60     : demand_scalar   ×1000       Python→PLC
  61–99  : RESERVED
  100    : cs1_ratio_cmd   ×1000       PLC→Python
  101    : cs2_ratio_cmd   ×1000       PLC→Python
  102    : valve_E8_cmd    ×1000       PLC→Python
  103    : valve_E14_cmd   ×1000       PLC→Python
  104    : valve_E15_cmd   ×1000       PLC→Python
  105    : prs1_setpoint   bar×100     PLC→Python
  106    : prs2_setpoint   bar×100     PLC→Python
  107    : cs1_power_kW    kW×10       PLC→Python
  108    : cs2_power_kW    kW×10       PLC→Python
  109    : v_d1_cmd        ×1000       PLC→Python  (Phase 7 resilience)
  110    : crosstie_E21_cmd ×1000      PLC→Python  (Phase 7 resilience)
  111    : bypass_E22_cmd  ×1000       PLC→Python  (Phase 7 resilience)

Coils (FC1):
  0: emergency_shutdown    1: cs1_alarm    2: cs2_alarm
  3: sto_inject_active     4: sto_withdraw_active
  5: prs1_active           6: prs2_active
```

### MATLAB Function Signatures (critical for compatibility)
```matlab
% Init:
[params, state]  = initNetwork(cfg)
[comp1, comp2]   = initCompressor(cfg)
[prs1, prs2]     = initPRS(cfg)
valve            = initValve(cfg)               % uses cfg.valveEdges
plc              = initPLC(cfg, state, comp1)   % 3-arg
ekf              = initEKF(cfg, state)
logs             = initLogs(params, ekf, N, cfg)
schedule         = initAttackSchedule(N, cfg)   % or make_empty_schedule(N) for baseline

% Runtime (runSimulation.m calls these — MUST match):
[q, state]        = updateFlow(params, state, valve_states)
[p, p_acoustic]   = updatePressure(params, p, q, demand_vec, p_acoustic_prev, cfg)
[state, comp1]    = updateCompressor(state, comp1, k, cfg, 1)
[state, prs1]     = updatePRS(state, prs1, cfg)
[Tgas, T_turb]    = updateTemperature(params, Tgas, q, p_prev, p, T_turb, cfg)
[rho, rho_c]      = updateDensity(p, Tgas, rho_comp, cfg)
[sensor_p, sensor_q, fault, fault_label] = applyFaultInjection(sensor_p, sensor_q, fault, k, dt, cfg)
plc               = updatePLC(plc, sensor_p, sensor_q, k, cfg)
ekf               = updateEKF(ekf, plc.reg_p, plc.reg_q, state.p, state.q, params, cfg)
[cusum, alarm]    = updateCUSUM(cusum, ekf.residual, cfg, k)
[comp1,comp2,prs1,prs2,valve_states,plc] = updateControlLogic(...)
hist              = updateHistorian(hist, state, plc, aid, k, dt, cfg, params)
logs              = updateLogs(logs, state, ekf, plc, comp1, comp2, prs1, prs2, ...)
```

### Attack Scenarios (A1–A10)
| ID | Name | MITRE | Target |
|---|---|---|---|
| A1 | SrcPressureManipulation | T0831 | S1 inlet pressure altered |
| A2 | CompressorRatioSpoofing | T0838 | CS1/CS2 setpoint altered |
| A3 | ValveCommandTampering | T0855 | E8 valve command forced |
| A4 | DemandNodeManipulation | T0829 | demand withdrawal rate |
| A5 | PressureSensorSpoofing | T0831 | D1 pressure sensor bias |
| A6 | FlowMeterSpoofing | T0827 | CS2→J5 and J5→J6 flows |
| A7 | PLCLatencyAttack | T0814 | Modbus polling delayed |
| A8 | PipelineLeak | T0829 | E8 edge mass loss |
| A9 | StealthyFDI (Liu-Ning-Reiter) | — | Zero EKF residual by construction |
| A10 | ReplayAttack (Mo & Sinopoli) | — | 120 s frozen sensor buffer |

---

## 6. Current Progress (April 2026)

### Sweep Status
| Mode | Scenarios | Completed | Failed | Rows | Wall time |
|---|---|---|---|---|---|
| Quick (30) | 30 | **30** | **0** | 18,030 | 0.21h |
| Full (279) | 279 | Pending | — | ~502,200 est. | ~2h |

**Command for full run:**
```matlab
% Offline (no CODESYS/gateway needed):
run_24h_sweep('gateway', false)

% Resume from scenario N if interrupted:
run_24h_sweep('gateway', false, 'resume', N)

% With CODESYS + gateway.py running:
run_24h_sweep()
```

### Known Issues
| Issue | Status | Notes |
|---|---|---|
| **Physics divergence** | OPEN — separate task | Many nodes hit 0.1 bar floor / 70 bar ceiling. Detectable as ML signal but unrealistic physics. Root cause: network flow solver instability. Needs investigation in `updateFlow`/`updatePressure`. |
| CUSUM cold-start false alarms | RESOLVED | `cusum_warmup_steps=300`, `cusum_slack=2.5` |
| Storage loop divergence | RESOLVED | `sto_p_inject=24.5`, `sto_p_withdraw=16.5`, `sto_k_flow=0.2` |

### Module Completion Status
| Module | Status | Notes |
|---|---|---|
| config/simConfig.m | ✔ Complete | All fields audited April 2026 |
| network/ | ✔ Complete | All 4 files |
| equipment/ | ✔ Complete | All 7 files |
| scada/EKF | ✔ Complete | Phase 6 Jacobian, chi2, aliases |
| scada/CUSUM | ✔ Fixed | n_steps, S_upper/lower, alarm stored |
| scada/PLC | ✔ Complete | Zone-based polling |
| control/ | ✔ Complete | Dual PID, emergency shutdown |
| attacks/ | ✔ Complete | A1–A10, fault injection |
| logging/ | ✔ Complete | Historian, logs, events |
| processing/ | ✔ Complete | Jitter, Weymouth, propagation |
| middleware/ | ✔ Live | Gateway confirmed 3269+ requests |
| run_24h_sweep.m | ✔ Working | 30/30 quick mode, 0 failures |
| ML pipeline | ✔ New script | `cgd_ids_pipeline.py` |

---

## 7. ML Pipeline (April 2026)

### New Script: `ml_pipeline/cgd_ids_pipeline.py`

Replaces older Jupyter notebook `indian_cgd_ids_pipeline_fixed.ipynb`.

**Key improvements over notebook:**

| Feature | Old Notebook | New Script |
|---|---|---|
| Column schema | Assumed European ~50 bar | Matches `export_scenario_csv` exactly |
| Feature set | Missing CUSUM/chi2 | Includes `cusum_S_upper/lower`, `chi2_stat`, `plc_p_*`, `plc_q_*` |
| Train/test split | Random row split (leakage) | GroupKFold by `scenario_id` |
| Scaler fit | All data | Normal-only training rows |
| Multi-class | Binary only | ATTACK_ID 0–10 with label remapping |
| Attacks dataset | Not supported | `--attacks path/to/attacks.csv` flag |
| Physics health check | None | `scenario_health_check()` flags clamp fraction |
| Feature engineering | None | Rolling mean/std, Δ ROC, Kirchhoff imbalance |
| Weymouth residuals | Referenced but missing | Removed (not generated by sim) |
| Hardcoded path | Absolute `C:\Users\...` | Relative to script |

**Usage:**
```bash
cd ml_pipeline
pip install -r requirements.txt
python cgd_ids_pipeline.py                           # baseline only
python cgd_ids_pipeline.py --nrows 5000              # quick test
python cgd_ids_pipeline.py --no-rolling              # skip rolling features (faster)
python cgd_ids_pipeline.py --attacks ../automated_dataset_attacks/ml_dataset_baseline.csv
```

**Models trained:** IsolationForest (unsupervised) → RandomForest (supervised) → XGBoost + SHAP (supervised + explainability) → GroupKFold CV

---

## 8. Pending Tasks / Next Steps

### Immediate Priorities
1. **Run full sweep** (279 scenarios):
   ```matlab
   run_24h_sweep('gateway', false)
   ```
2. **Investigate physics divergence** — pressures hitting 0.1 bar / 70 bar clamps in many nodes. Check `updateFlow.m` and `updatePressure.m` for solver stability at Indian CGD pressure ranges.
3. **Run attack sweep** — configure and run `automated_dataset_attacks/` equivalent sweep with A1–A10 injected.
4. **Run ML pipeline** on full dataset.

### Physics Divergence Investigation
Symptoms from quick sweep output:
```
Low pressure at node PRS2: 0.100 bar  (limit 14.0 bar)
Low pressure at node D1:   0.100 bar  (limit 14.0 bar)
High pressure at node D2:  70.000 bar (limit 26.0 bar)
```
Alternating floor/ceiling across adjacent demand nodes suggests the Darcy-Weisbach solver is oscillating. Likely fix: add relaxation / damping in `updateFlow.m` or increase node volumes in `cfg.node_V`.

### Dataset Generation Roadmap
1. Complete baseline sweep (279 scenarios × 30 min = ~502K rows)
2. Execute attack sweep (~90 runs × 10 attacks × 3 severities)
3. Assemble `ml_dataset_final.csv` (baseline + attacks combined)
4. Run `cgd_ids_pipeline.py` on final dataset
5. Export `dataset_statistics.json` for Paper 1 Table II

### Thesis Writing (Sprint)
| Day | Target |
|---|---|
| 1–2 | Chapter 1: Introduction, problem statement, objectives |
| 3–4 | Chapter 2: Literature review |
| 5 | Chapter 3: Methodology — network design, simulator architecture, attack taxonomy |
| 6 | Chapter 3 cont.: register map, data collection, pre-processing pipeline |
| 7–8 | Chapter 4: Results — baseline statistics, detection metrics, cross-topology tests |
| 9 | Chapter 5: Discussion, GasLib comparison, limitations |
| 10 | Abstract, references (IEEE format), proofread |

---

## 9. Key Technical Details — Bugs Fixed This Session

### Bug 1: `Unrecognized field name "n_steps"` (all scenarios, sweep run 1)
**Root cause:** `initCUSUM.m` never initialised `n_steps`; also field names `S_pos`/`S_neg` in `updateCUSUM` did not match `S_upper`/`S_lower` from `initCUSUM`.
**Fix:** Added `cusum.n_steps = 0` in `initCUSUM`; renamed `S_pos→S_upper`, `S_neg→S_lower` in `updateCUSUM`; added `cusum.alarm = alarm`.

### Bug 2: `Unrecognized field name "pid1_setpoint"` (sweep run 2)
**Root cause:** `simConfig.m` missing 15+ fields used by subsystem functions.
**Fix:** Comprehensive audit of all function files. Added: PID setpoints/gains, control thresholds (`emer_shutdown_p`, `valve_open_lo/hi`), historian parameters, fault injection parameters, storage limits, alarm thresholds.

### Bug 3: `Unrecognized field name "jitter_enable"` (sweep run 3)
**Root cause:** `addScanJitter.m` line 50 reads `cfg.jitter_enable` unconditionally; field never defined in `simConfig.m`.
**Fix:** Added complete jitter section to `simConfig.m`: `jitter_enable=false`, `jitter_platform='codesys'`, 4 platform-specific std/max fields. Setting `jitter_enable=false` short-circuits the function at line 51 (fast path).

---

## 10. Research Justification Points (for thesis)

### Why CODESYS beats Docker for dataset genuineness
- Real IEC 61131-3 runtime with authentic scan cycles (~10 ms)
- Genuine 16-bit register quantisation (INT-only storage)
- Real Modbus/TCP timing: FC03 response times 7.694–8.234 ms measured
- Inter-request interval jitter ~0.5 ms (vs Docker's OS-level randomness)

### Why GasLib-24 is a valid reference
- 138+ citations in top venues (INFORMS, Applied Energy, Nature Scientific Reports)
- Based on real German network operator data (Open Grid Europe)
- Uses identical physics: isothermal Euler + Darcy-Weisbach + Colebrook-White

### Indian CGD parameter adaptation (novel contribution)
- GasLib operates at 40–85 bar (German transmission)
- Indian CGD steel grid: **14–26 bar** (PNGRB T4S Regulation GSR 612(E))
- Compressor PID targets adapted: CS1→D1 at 16 barg, CS2→D3 at 14 barg
- No published work on cyber-physical security of Indian CGD — genuine gap

### Statistical validation battery for dataset realism
1. ADF test — stationarity of steady-state variables
2. ACF/PACF — AR(1) structure confirms physical inertia
3. KS two-sample test — compare simulated vs reference distributions
4. PSD analysis — scan-cycle frequency peaks in Modbus timing
5. Shapiro-Wilk — Gaussian residuals in steady-state sensor noise

---

## 11. Important Terminology

- **Dual-layer dataset**: simultaneous physics-layer (pressure, flow, temperature) + protocol-layer (Modbus FC codes, register INTs, timestamps)
- **Spatiotemporal propagation labels**: per-row columns recording `attack_origin`, `t_origin`, `propagation_hop`, `t_hop`, `propagation_delay_s` — computed from Weymouth residual crossing 3σ at downstream nodes
- **Physics residual**: `|P_measured − P_Weymouth_predicted|` per pipe per cycle — the signal that detects slow-ramp FDI invisible to protocol-only detectors
- **Scenario-level ML split**: GroupKFold by `scenario_id` — avoids data leakage across topological regimes
- **Morris dataset flaw**: attacks performed at one pressure, normal operation at another — classifiers learn operational state, not attack signature. Avoided by injecting attacks across all operational scenarios
- **Physics divergence**: pressure floor/ceiling clamping (0.1/70 bar) due to flow solver instability — observed in current quick-mode runs; under investigation
- **log_every=10**: physics runs at 10 Hz (dt=0.1s), 1 in 10 steps written to CSV → 1 Hz dataset rows
