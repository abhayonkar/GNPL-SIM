# Phase 7 Upgrade — Quick Start Guide
**Last updated:** April 2026 — reflects all bug fixes applied to get sweep to 0 failures

---

## What Was Changed and Why

### Phase A: Bug Fixes (April 2026) — Sweep Now Working

These fixes were required to get `run_24h_sweep('mode','quick')` from **0/30 completed** to **30/30 completed, 0 failures**.

| Fix | File | Root Cause | Change |
|---|---|---|---|
| CUSUM `n_steps` crash | `scada/initCUSUM.m` | Field never initialised | Added `cusum.n_steps = 0` |
| CUSUM field name mismatch | `scada/updateCUSUM.m` | `S_pos`/`S_neg` vs `S_upper`/`S_lower` | Renamed throughout; added `cusum.alarm = alarm` |
| Missing `pid1_setpoint` | `config/simConfig.m` | Field not defined | Added all PID setpoints/gains: `pid1_Ki/Kd/setpoint`, `pid2_Ki/Kd/setpoint`, `pid_D3_node` |
| Missing control thresholds | `config/simConfig.m` | Used by `updateControlLogic` | Added `emer_shutdown_p=28.0`, `valve_open_lo=14.0`, `valve_close_hi=24.0` |
| Missing historian fields | `config/simConfig.m` | Used by `updateHistorian` | Added `historian_enable/deadband_p/q/T/max_interval_s` |
| Missing fault fields | `config/simConfig.m` | Used by `applyFaultInjection` | Added `fault_enable/stuck_nodes/probs/dur` |
| Missing EKF aliases | `scada/updateEKF.m` | `detectIncidents` reads `ekf.residP/residQ` | Added alias lines after residual calc |
| Missing `jitter_enable` | `config/simConfig.m` | `addScanJitter` reads unconditionally | Added complete jitter section (all 6 fields) |

### Phase 7: Resilience Architecture (Previous)
Added 2 new edges + 1 isolation valve to the 20-node Indian CGD network:

| Addition | Type | Purpose | PNGRB T4S basis |
|---|---|---|---|
| **E21**: J4→J7 cross-tie (DN100, 8 km) | Resilience edge | Bypass CS2 during failure | T4S §6.3 N-1 |
| **E22**: J3→J5 emergency bypass (DN80, 12 km) | Resilience edge | Direct eastern feed | T4S §5.4 |
| **V_D1**: Isolation valve on E10 | PLC-controlled valve | Isolate D1 on overpressure | T4S Annexure III |

---

## Current Status (April 2026)

```
Quick sweep (30 scenarios):  30/30 completed, 0 failures, 18,030 rows, 17.2 MB
Full sweep (279 scenarios):  PENDING — run command below
Physics divergence:          KNOWN ISSUE — see Known Issues section
ML pipeline:                 NEW — ml_pipeline/cgd_ids_pipeline.py
```

---

## Run Order

### Step 1: Verify single scenario (sanity check)
```matlab
% From Sim/ directory in MATLAB:
run_24h_sweep('mode', 'quick', 'gateway', false, 'dur_min', 10)
% Expect: 30 scenarios, 0 failures, ~300 rows each
```

### Step 2: Run full baseline sweep (all 279 scenarios)
```matlab
% Offline — no CODESYS or gateway.py needed:
run_24h_sweep('gateway', false)

% Resume from scenario N if interrupted:
run_24h_sweep('gateway', false, 'resume', 45)

% Stress scenarios only (fastest subset):
run_24h_sweep('gateway', false, 'mode', 'stress')
```

### Step 3: Run with CODESYS gateway (optional — adds protocol artefacts)
```bash
# Terminal 1 — start gateway
cd middleware && python gateway.py

# MATLAB — gateway=true by default
run_24h_sweep()
```

### Step 4: Run ML pipeline
```bash
cd ml_pipeline
pip install -r requirements.txt

# Baseline only (unsupervised anomaly detection):
python cgd_ids_pipeline.py

# Quick test (5000 rows):
python cgd_ids_pipeline.py --nrows 5000

# With attacks dataset:
python cgd_ids_pipeline.py --attacks ../automated_dataset_attacks/ml_dataset_baseline.csv

# Skip rolling features (faster, less memory):
python cgd_ids_pipeline.py --no-rolling
```

---

## Dataset Schema (export_scenario_csv output)

One row per logged step at 1 Hz. ~126 columns total.

| Column Group | Columns | Notes |
|---|---|---|
| Metadata | Timestamp_s, scenario_id, source_config, demand_profile, valve_config, storage_init, cs_mode | 7 cols |
| Pressures | p_S1_bar … p_D6_bar | 20 cols, Indian CGD range 14–26 barg nominal |
| Flows | q_E1_kgs … q_E20_kgs | 20 cols, mass flow kg/s |
| Equipment | CS1_ratio, CS1_power_kW, CS2_ratio, CS2_power_kW, PRS1_throttle, PRS2_throttle, STO_inventory | 7 cols |
| Valves | valve_E8, valve_E14, valve_E15 | 3 cols |
| Detectors | cusum_S_upper, cusum_S_lower, cusum_alarm, chi2_stat, chi2_alarm | 5 cols — correctly populated after April 2026 fixes |
| EKF residuals | ekf_resid_S1 … ekf_resid_D6 | 20 cols |
| PLC measurements | plc_p_S1…plc_p_D6 (×20), plc_q_E1…plc_q_E20 (×20) | 40 cols |
| Labels | FAULT_ID, ATTACK_ID, MITRE_CODE, prop_origin_node, prop_hop_node, prop_delay_s, prop_cascade_step, label | 8 cols |

---

## ML Pipeline: cgd_ids_pipeline.py

Replaces the older `indian_cgd_ids_pipeline_fixed.ipynb` notebook.

### Feature Groups Used
```
pressure_cols      p_*_bar (20)
flow_cols          q_*_kgs (20)
equipment_cols     CS1/CS2 ratio/power, PRS throttle, STO_inventory, valves (10)
detector_cols      cusum_S_upper, cusum_S_lower, chi2_stat (3)
ekf_cols           ekf_resid_* (20)
plc_p_cols         plc_p_* (20)
plc_q_cols         plc_q_* (20)
rolling_features   rmean/rstd of first 5 pressure+flow cols (20)
roc_features       Δ rate-of-change for all pressure+flow cols (40)
kirchhoff          mass balance imbalance proxy (1)
Total: ~174 features
```

### Key Design Decisions vs Old Notebook
| Feature | Old Notebook | New Script |
|---|---|---|
| Column schema | European ~50 bar assumed | Matches `export_scenario_csv` exactly |
| Feature set | Missing CUSUM/chi2/PLC cols | All detector, EKF, PLC cols included |
| Train/test split | Random row split (data leakage) | GroupKFold by `scenario_id` |
| Scaler | Fit on all data | Fit on normal-only training rows |
| Multi-class | Binary only | ATTACK_ID 0–10 with remapping |
| Attacks dataset | Not supported | `--attacks` flag |
| Health check | None | Flags scenarios with >10% clamped pressure |
| Hardcoded path | `C:\Users\Abhay\...` absolute | Relative to script location |

### Models Trained
1. **IsolationForest** — unsupervised, trained on normal rows only
2. **RandomForest** — supervised, balanced class weights
3. **XGBoost + SHAP** — supervised + feature importance
4. **GroupKFold CV** — 5-fold cross-validation by scenario_id

---

## Known Issues

### Physics Divergence (OPEN)
**Symptom:** Many nodes hit pressure clamps:
```
[WARNING] Low pressure at PRS2: 0.100 bar  (limit 14.0 bar)
[WARNING] High pressure at D2:  70.000 bar (limit 26.0 bar)
```
**Pattern:** Alternating floor/ceiling across adjacent demand nodes (D1=low, D2=high, D3=low) — indicates sign oscillation in the pressure solver.

**Impact:** Simulation runs without crashing; dataset is produced. Clamp values are detectable anomaly signals but do not represent realistic Indian CGD physics.

**Likely fix:** Increase `cfg.node_V` (nodal volume) to add solver damping, or add relaxation coefficient in `updatePressure.m`.

**Workaround:** `scenario_health_check()` in the ML pipeline identifies diverged scenarios (`pct_floor > 10%`). Filter from training if needed.

---

## simConfig.m Field Reference (all required fields, April 2026)

```matlab
% Timing
cfg.dt = 0.1; cfg.log_every = 10; cfg.sim_duration_min = 1440;

% PID (updateControlLogic.m)
cfg.pid1_Kp=0.10; cfg.pid1_Ki=0.01; cfg.pid1_Kd=0.001; cfg.pid1_setpoint=16.0;
cfg.pid2_Kp=0.10; cfg.pid2_Ki=0.01; cfg.pid2_Kd=0.001; cfg.pid2_setpoint=15.0;
cfg.pid_D1_node=15; cfg.pid_D3_node=17;

% Control thresholds (updateControlLogic.m)
cfg.emer_shutdown_p=28.0; cfg.valve_open_lo=14.0; cfg.valve_close_hi=24.0;

% EKF (initEKF.m, updateEKF.m)
cfg.ekf_P0=1e-2; cfg.ekf_Qn=1e-4; cfg.ekf_Rk=1e-3;

% CUSUM (initCUSUM.m, updateCUSUM.m)
cfg.cusum_slack=2.5; cfg.cusum_threshold=12.0;
cfg.cusum_warmup_steps=300; cfg.cusum_reset_on_trip=true;

% Historian (updateHistorian.m)
cfg.historian_enable=false; cfg.historian_deadband_p=0.1;
cfg.historian_deadband_q=10.0; cfg.historian_deadband_T=0.5;
cfg.historian_max_interval_s=300.0;

% Fault injection (applyFaultInjection.m)
cfg.fault_enable=false; cfg.fault_stuck_nodes=[15,16,17,18];
cfg.fault_stuck_prob=0.001; cfg.fault_stuck_dur_s=30.0;
cfg.fault_loss_prob=0.002; cfg.fault_max_consec=3;

% Jitter (addScanJitter.m) — ALL 6 fields required even if jitter_enable=false
cfg.jitter_enable=false; cfg.jitter_platform='codesys';
cfg.jitter_codesys_std_ms=20.0; cfg.jitter_codesys_max_ms=150.0;
cfg.jitter_s7_std_ms=1.5; cfg.jitter_s7_max_ms=10.0;

% Storage
cfg.sto_p_inject=24.5; cfg.sto_p_withdraw=16.5; cfg.sto_k_flow=0.2;
cfg.sto_max_flow=200.0; cfg.sto_inventory_init=0.60;

% Attacks (A1–A10)
cfg.atk5_target_node=15; cfg.atk5_bias_bar=2.0;
cfg.atk6_edges=[7,8]; cfg.atk6_scale=0.0;
cfg.atk8_edge=8; cfg.atk8_leak_frac=0.3; cfg.atk8_ramp_time=60.0;
cfg.atk9_ramp_s=60.0; cfg.atk9_target_nodes=[15,16,17]; cfg.atk9_bias_scale=0.05;
cfg.atk10_buffer_s=120.0; cfg.atk10_inject_mode='straight';
```
