# Phase 7 Upgrade — Quick Start Guide

## What Was Changed and Why

### Objective 1: Resilience Architecture
Added **2 new edges + 1 isolation valve** to the 20-node Indian CGD network
without touching `runSimulation.m` (frozen orchestrator):

| Addition | Type | Purpose | PNGRB T4S basis |
|---|---|---|---|
| **E21**: J4→J7 cross-tie (DN100, 8 km) | Resilience edge | Bypass CS2 during failure | T4S §6.3 N-1 |
| **E22**: J3→J5 emergency bypass (DN80, 12 km) | Resilience edge | Direct eastern feed | T4S §5.4 |
| **V_D1**: Isolation valve on E10 | PLC-controlled valve | Isolate D1 on overpressure | T4S Annexure III |

### Objective 2: Critical Attack Points (ranked)
Documented in `docs/RESILIENCE_AND_ATTACK_SURFACE.md`:
- **CS1 (rank 1, score 100)** — single point failure, entire S1 trunk
- **J7 (rank 2, score 75)** — stealthy FDI target, invisible to EKF
- **E12 (rank 1 edge, score 80)** — pipeline leak + flow spoof worst case

---

## File-by-File Changes

| File | Change | Why |
|---|---|---|
| `config/simConfig.m` | Full Indian CGD parameterisation (14–26 barg, SG 0.57, PNGRB T4S) | Replaces European GasLib values |
| `export/exportDataset.m` | New schema: `_bar`/`_scmd` suffixes, scenario columns, regulatory metadata JSON, 4 subset CSVs | ICS_Dataset_Design.md compliance |
| `run_24h_sweep.m` | 340 baseline + 90 attack scenarios, resume capability, validity checks | Unlimited CODESYS license |
| `ml_pipeline/indian_cgd_ids_pipeline.ipynb` | End-to-end ML: EDA → feature eng → XGBoost → LSTM-AE → SHAP → CV | Dataset analysis |
| `docs/RESILIENCE_AND_ATTACK_SURFACE.md` | Full criticality analysis, attack path scenarios, Modbus register extensions | Research documentation |

---

## Run Order

### Step 1: Update simConfig
```
Copy config/simConfig.m → Sim/config/simConfig.m
(replaces European parameters with PNGRB T4S)
```

### Step 2: Update exportDataset
```
Copy export/exportDataset.m → Sim/export/exportDataset.m
```

### Step 3: Verify single run (10 min test)
```matlab
>> main_simulation(10, false)   % offline, no gateway
% Check: automated_dataset/master_dataset.csv
% Verify: p_S1_bar values in 20–26 range (not 45–58)
```

### Step 4: Verify with CODESYS gateway (30 min test)
```bash
# Terminal 1
python gateway.py

# MATLAB
>> main_simulation(30, true)
```

### Step 5: Run 24-30 hour sweep
```matlab
% Option A: Full sweep (340 baseline + 90 attack)
>> run_24h_sweep()

% Option B: Baseline only first
>> run_24h_sweep('mode','baseline','dur_min',30)

% Option C: Quick test (10 scenarios)
>> run_24h_sweep('mode','quick','dur_min',5)

% Option D: Resume from scenario 45 (after interruption)
>> run_24h_sweep('resume',45)
```

### Step 6: Analyse dataset
```bash
cd ml_pipeline
jupyter notebook indian_cgd_ids_pipeline.ipynb
```

---

## Scenario Analysis Guide (Ignoring/Combining Scenarios)

After the sweep completes, run the notebook through **Section 8 (Cross-Topology CV)**.
Use these rules to prune the 340 scenarios:

| Pruning Criterion | Action |
|---|---|
| CV F1 < 0.4 for a topology group | Mark as "distribution-shift" — keep in test only |
| Scenarios where `p_D1_bar < 12 barg` > 40% of rows | "Degenerate" — exclude from training |
| `storage_init=0.1` + `source=S1_only` + `demand=peak` | Combine into single "extreme stress" class |
| All 3 `valve_config` variants for same source+demand+cs | Keep `auto` for training, use `forced_*` as attack-like scenarios |

The sweep logs `automated_dataset/sweep_progress.log` — check it for failed scenarios
before assembly.

---

## Modbus Register Map v7 (3 new registers)

| Address | Signal | Scaling | Description |
|---------|--------|---------|-------------|
| 109 | `v_d1_cmd` | 1000 | D1 isolation valve (1=open) |
| 110 | `crosstie_E21_cmd` | 1000 | E21 cross-tie valve |
| 111 | `bypass_E22_cmd` | 1000 | E22 emergency bypass |

**In CODESYS PLC_PRG:** Add three new `INT` variables at these addresses.
**In gateway.py:** Extend `ACTUATOR_MAP` and `ACTUATOR_SCALES` with 3 entries.
**In data_logger.py:** Extend `ACTUATOR_MAP` (same 3 entries).

---

## Dataset Schema Changes (vs Phase 6)

| Change | Old | New |
|---|---|---|
| Pressure column suffix | `p_S1_bar` (unchanged) | `p_S1_bar` (same, confirmed) |
| Flow column suffix | `q_E1_kgs` | `q_E1_scmd` (SCMD, Indian unit) |
| Scenario columns | None | `scenario_id`, `source_config`, etc. |
| Resilience columns | None | `crosstie_E21_active`, `bypass_E22_active` |
| Regulatory JSON | None | `scenario_metadata.json` per run |
| Subset CSVs | 3 (normal/attacks/spoof) | 4 (normal/attacks/faults/concurrent) |
| Flow unit | kg/s | SCMD (Standard Cubic Metres per Day) |
