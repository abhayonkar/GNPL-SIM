# Gas Pipeline CPS Simulator — Dataset Design Reference

**Version:** Phase 6  
**Network:** 20-node, 20-edge, dual-source, dual-compressor, storage loop  
**Purpose:** Baseline + attack dataset generation for IDS/anomaly detection research

---

## Table of Contents

1. [CSV Schema — Master Dataset](#1-csv-schema--master-dataset)
2. [CSV Schema — Attack Dataset](#2-csv-schema--attack-dataset)
3. [CSV Schema — Historian (Irregular Timestep)](#3-csv-schema--historian-irregular-timestep)
4. [Baseline Scenario Matrix](#4-baseline-scenario-matrix)
5. [Baseline Generator Code](#5-baseline-generator-code)
6. [Attack Dataset Design](#6-attack-dataset-design)
7. [Attack Injection Code](#7-attack-injection-code)
8. [ML Dataset Assembly](#8-ml-dataset-assembly)
9. [Physical Validity Rules](#9-physical-validity-rules)
10. [Split Recommendations](#10-split-recommendations)

---

## 1. CSV Schema — Master Dataset

Each row = one physics timestep logged at 1 Hz (`log_every = 10` at 10 Hz physics).

### 1.1 Time and Scenario Identity

| Column | Type | Unit | Description |
|---|---|---|---|
| `Timestamp_s` | float64 | s | Simulation time from run start |
| `scenario_id` | int32 | — | Unique ID per scenario (see §4) |
| `source_config` | str | — | `S1_only`, `S2_only`, `both` |
| `demand_profile` | str | — | `low`, `medium`, `peak`, `uneven`, `spike` |
| `storage_init` | float32 | fraction | Initial STO inventory (0–1) |
| `valve_config` | str | — | `auto`, `E8_forced_open`, `E8_forced_closed` |
| `cs_mode` | str | — | `both_on`, `CS1_only`, `CS2_only`, `both_off` |

### 1.2 Node Pressures (20 columns)

| Column | Type | Unit | Description |
|---|---|---|---|
| `p_S1_bar` | float32 | bar | Source 1 pressure |
| `p_J1_bar` | float32 | bar | Junction 1 |
| `p_CS1_bar` | float32 | bar | Compressor outlet |
| `p_J2_bar` | float32 | bar | Branch junction |
| `p_J3_bar` | float32 | bar | Mid-network junction |
| `p_J4_bar` | float32 | bar | Pre-CS2 junction |
| `p_CS2_bar` | float32 | bar | CS2 outlet |
| `p_J5_bar` | float32 | bar | Eastern distribution |
| `p_J6_bar` | float32 | bar | Side branch junction |
| `p_PRS1_bar` | float32 | bar | PRS1 downstream |
| `p_J7_bar` | float32 | bar | Upper mid-network |
| `p_STO_bar` | float32 | bar | Storage cavern |
| `p_PRS2_bar` | float32 | bar | PRS2 downstream |
| `p_S2_bar` | float32 | bar | Source 2 pressure |
| `p_D1_bar` ... `p_D6_bar` | float32 | bar | Demand nodes 1–6 |

### 1.3 Edge Flows (20 columns)

| Column | Type | Unit | Description |
|---|---|---|---|
| `q_E1_kgs` ... `q_E20_kgs` | float32 | kg/s | Mass flow per edge |

> **Sign convention:** positive = flow in declared edge direction (from→to).  
> E14, E15 (storage valves) can be negative.

### 1.4 Equipment State (12 columns)

| Column | Type | Unit | Description |
|---|---|---|---|
| `CS1_ratio` | float32 | — | CS1 compression ratio |
| `CS1_power_kW` | float32 | kW | CS1 shaft power |
| `CS1_efficiency` | float32 | — | CS1 isentropic efficiency |
| `CS2_ratio` | float32 | — | CS2 compression ratio |
| `CS2_power_kW` | float32 | kW | CS2 shaft power |
| `CS2_efficiency` | float32 | — | CS2 isentropic efficiency |
| `PRS1_throttle` | float32 | 0–1 | PRS1 valve position |
| `PRS2_throttle` | float32 | 0–1 | PRS2 valve position |
| `valve_E8_cmd` | float32 | 0–1 | E8 command (1=open) |
| `valve_E14_cmd` | float32 | 0–1 | E14 storage inject |
| `valve_E15_cmd` | float32 | 0–1 | E15 storage withdraw |
| `STO_inventory` | float32 | 0–1 | Storage fill fraction |

### 1.5 EKF and PLC Bus (42 columns)

| Column | Type | Unit | Description |
|---|---|---|---|
| `ekf_p_S1` ... `ekf_p_D6` | float32 | bar | EKF pressure estimates (20) |
| `ekf_resid_S1` ... `ekf_resid_D6` | float32 | bar | EKF innovation residuals (20) |
| `chi2_stat` | float32 | — | Chi-squared bad-data statistic |
| `chi2_alarm` | bool | — | True when chi2 > 63.7 |

### 1.6 CUSUM Detector (4 columns)

| Column | Type | Unit | Description |
|---|---|---|---|
| `cusum_S_upper` | float32 | — | Upper arm statistic |
| `cusum_S_lower` | float32 | — | Lower arm statistic |
| `cusum_alarm` | bool | — | True when either arm > threshold |
| `cusum_z` | float32 | — | Normalised innovation RMS |

### 1.7 Fault and Attack Labels (5 columns)

| Column | Type | Values | Description |
|---|---|---|---|
| `FAULT_ID` | int8 | 0/1/2 | 0=none, 1=packet loss, 2=stuck sensor |
| `ATTACK_ID` | int8 | 0–10 | 0=Normal, 1–10=attack type |
| `ATTACK_NAME` | str | — | Human-readable attack name |
| `MITRE_ID` | str | — | MITRE ATT&CK ICS technique ID |
| `label` | int8 | 0/1 | Binary: 0=normal, 1=anomaly (attack OR fault) |

### 1.8 Demand and Source Inputs (3 columns)

| Column | Type | Unit | Description |
|---|---|---|---|
| `demand_scalar` | float32 | — | Normalised demand multiplier |
| `src_p1_bar` | float32 | bar | Actual S1 source pressure (post-attack) |
| `src_p2_bar` | float32 | bar | Actual S2 source pressure |

**Total master dataset columns: ~126**

---

## 2. CSV Schema — Attack Dataset

Extends the master schema with per-attack forensic columns.

### 2.1 Additional Attack Forensics

| Column | Type | Description |
|---|---|---|
| `attack_start_s` | float32 | Simulation time when attack started |
| `attack_dur_s` | float32 | Duration of active attack window |
| `attack_magnitude` | float32 | Normalised injection magnitude (0–1) |
| `attack_target_node` | int8 | Primary target node index |
| `attack_target_edge` | int8 | Primary target edge index (−1 if N/A) |
| `pre_attack_p_target` | float32 | Pressure at target node before attack |
| `post_attack_p_target` | float32 | Pressure at target node during attack |
| `sensor_p_spoofed` | float32[20] | Post-spoof sensor pressure vector |
| `sensor_q_spoofed` | float32[20] | Post-spoof sensor flow vector |
| `fdi_vector_norm` | float32 | L2 norm of FDI perturbation (A9 only) |
| `replay_buffer_age_s` | float32 | Age of replayed data in seconds (A10 only) |

### 2.2 Multi-Attack Coordination (for A10 coordinated attacks)

| Column | Type | Description |
|---|---|---|
| `concurrent_attacks` | str | Comma-separated active attack IDs |
| `attack_phase` | str | `ramp_up`, `steady`, `ramp_down` |

---

## 3. CSV Schema — Historian (Irregular Timestep)

One row per **change event** per tag. Suitable for event-based RNN / transformer training.

| Column | Type | Unit | Description |
|---|---|---|---|
| `Timestamp_s` | float64 | s | Exact time of change event |
| `Tag` | str | — | Node or edge name (e.g. `J5`, `E14`) |
| `VarType` | str | — | `pressure`, `flow`, `temperature` |
| `Value` | float32 | bar/kg·s⁻¹/K | Measured value at event |
| `Unit` | str | — | Engineering unit string |
| `ATTACK_ID` | int8 | — | Active attack at time of event |
| `FAULT_ID` | int8 | — | Active fault at time of event |
| `delta_t_s` | float32 | s | Time since previous event for this tag |
| `delta_value` | float32 | — | Change that triggered this event |

> **Deadband rules used:** pressure ±0.10 bar, flow ±0.50 kg/s, temperature ±0.20 K.  
> Heartbeat write forced every 60 s regardless of deadband.

---

## 4. Baseline Scenario Matrix

### 4.1 Dimensions

| Dimension | Values | Count |
|---|---|---|
| Source config | `S1_only`, `S2_only`, `both` | 3 |
| Demand profile | `low (30%)`, `medium (60%)`, `peak (100%)`, `uneven`, `spike` | 5 |
| Valve config | `auto`, `E8_forced_open`, `E8_forced_closed` | 3 |
| Storage init | `empty (0.1)`, `half (0.5)`, `full (0.9)` | 3 |
| Compressor mode | `both_on`, `CS1_only`, `CS2_only` | 3 |

**Total: 3 × 5 × 3 × 3 × 3 = 405 scenarios**

### 4.2 Validity Constraints (Prune Before Running)

The full 405 matrix contains physically invalid combinations. Apply these filters:

| Rule | Invalid Combination | Action |
|---|---|---|
| R1 | `S1_only` + `CS2_only` | Remove — CS2 is downstream of CS1; no S1 flow |
| R2 | `S2_only` + `CS1_only` | Remove — CS1 has no upstream supply without S1 |
| R3 | `E8_forced_closed` + `CS1_only` | Remove — PRS1 branch starved, no alternate path |
| R4 | `storage_empty` + `S1_only` + `peak` | Flag as stress — valid but high risk |
| R5 | `both_off` compressors + `peak` demand | Remove — insufficient pressure |

**After pruning: ~340 valid scenarios**

### 4.3 Scenario Duration

| Scenario Type | Duration | Steps (10 Hz) | Rows (1 Hz) |
|---|---|---|---|
| Startup transient only | 5 min | 3,000 | 300 |
| Steady state | 20 min | 12,000 | 1,200 |
| Full (transient + steady) | 30 min | 18,000 | 1,800 |
| Stress / extreme | 60 min | 36,000 | 3,600 |

**Recommended: 30 min per scenario = 340 × 1,800 = 612,000 baseline rows**

### 4.4 Dataset Balance Target

| Split | Rows | Fraction |
|---|---|---|
| Startup transient (first 5 min) | ~102,000 | 16.7% |
| Steady state (5–25 min) | ~408,000 | 66.7% |
| Stress / extreme | ~102,000 | 16.7% |

---

## 5. Baseline Generator Code

### 5.1 `run_baseline_sweep.m` — Main Sweep Script

```matlab
function run_baseline_sweep()
% run_baseline_sweep  Iterate all valid baseline scenarios and save CSVs.
%
%   Runs ~340 valid scenario combinations at 30 min each.
%   Output: automated_dataset/baseline/scenario_XXXX.csv
%
%   Estimated total time: 340 × ~3s wall = ~17 minutes

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling','processing');

    outDir = fullfile('automated_dataset', 'baseline');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    %% ── Scenario dimensions ──────────────────────────────────────────────
    source_configs   = {'both', 'S1_only', 'S2_only'};
    demand_profiles  = {'low', 'medium', 'peak', 'uneven', 'spike'};
    valve_configs    = {'auto', 'E8_forced_open', 'E8_forced_closed'};
    storage_inits    = [0.1, 0.5, 0.9];
    comp_modes       = {'both_on', 'CS1_only', 'CS2_only'};

    scenario_id = 0;
    skipped     = 0;
    run_log = fopen(fullfile(outDir, 'scenario_index.csv'), 'w');
    fprintf(run_log, 'scenario_id,source,demand,valve,storage_init,cs_mode,valid,rows\n');

    for si = 1:numel(source_configs)
      for di = 1:numel(demand_profiles)
        for vi = 1:numel(valve_configs)
          for sti = 1:numel(storage_inits)
            for ci = 1:numel(comp_modes)

              src  = source_configs{si};
              dem  = demand_profiles{di};
              valv = valve_configs{vi};
              sto  = storage_inits(sti);
              csm  = comp_modes{ci};

              scenario_id = scenario_id + 1;

              %% Validity check
              if ~is_valid_scenario(src, dem, valv, sto, csm)
                  skipped = skipped + 1;
                  fprintf(run_log, '%d,%s,%s,%s,%.1f,%s,0,0\n', ...
                          scenario_id,src,dem,valv,sto,csm);
                  continue;
              end

              fprintf('[sweep] Scenario %03d: %s | %s | %s | sto=%.1f | %s\n', ...
                      scenario_id, src, dem, valv, sto, csm);

              %% Build config for this scenario
              cfg = build_scenario_config(src, dem, valv, sto, csm);

              %% Run simulation (30 min, offline, no attacks)
              try
                  [logs, params, N, schedule] = run_scenario(cfg, 30);
                  fname = sprintf('scenario_%04d.csv', scenario_id);
                  fpath = fullfile(outDir, fname);
                  export_scenario_csv(logs, cfg, params, N, schedule, ...
                                      fpath, scenario_id, src, dem, valv, sto, csm);
                  rows = logs.N_log;
              catch e
                  fprintf('  [SKIP] Error: %s\n', e.message);
                  rows = 0;
              end

              fprintf(run_log, '%d,%s,%s,%s,%.1f,%s,1,%d\n', ...
                      scenario_id,src,dem,valv,sto,csm,rows);

            end
          end
        end
      end
    end

    fclose(run_log);
    fprintf('\n[sweep] Done. %d scenarios run, %d skipped.\n', ...
            scenario_id - skipped, skipped);
end
```

### 5.2 `is_valid_scenario.m` — Validity Filter

```matlab
function valid = is_valid_scenario(src, dem, valv, sto, csm)
% is_valid_scenario  Return false for physically impossible combinations.

    valid = true;

    % R1: S1_only cannot use CS2_only (CS2 is downstream of main trunk)
    if strcmp(src,'S1_only') && strcmp(csm,'CS2_only')
        valid = false; return;
    end

    % R2: S2_only cannot use CS1_only (CS1 needs S1 upstream supply)
    if strcmp(src,'S2_only') && strcmp(csm,'CS1_only')
        valid = false; return;
    end

    % R3: E8_forced_closed + CS1_only starves PRS1 branch
    if strcmp(valv,'E8_forced_closed') && strcmp(csm,'CS1_only')
        valid = false; return;
    end

    % R4: Cannot supply peak demand from storage alone with no compressors
    % (CS2_only requires upstream pressure — need at least S1 or STO > 0.3)
    if strcmp(dem,'peak') && strcmp(src,'S2_only') && sto < 0.2
        valid = false; return;
    end
end
```

### 5.3 `build_scenario_config.m` — Config Builder

```matlab
function cfg = build_scenario_config(src, dem, valv, sto, csm)
% build_scenario_config  Modify base simConfig for a specific scenario.

    cfg = simConfig();

    %% Source configuration
    switch src
        case 'S1_only'
            % S2 at minimum pressure (effectively off)
            cfg.src2_p_min = 10.0;
            cfg.src2_p_max = 12.0;
        case 'S2_only'
            % S1 at minimum pressure
            cfg.src_p_min = 10.0;
            cfg.src_p_max = 12.0;
        % 'both' uses defaults
    end

    %% Demand profile
    switch dem
        case 'low'
            cfg.dem_base = 0.25;
            cfg.dem_noise_std = 0.01;
        case 'medium'
            cfg.dem_base = 0.60;
            cfg.dem_noise_std = 0.02;
        case 'peak'
            cfg.dem_base = 1.10;
            cfg.dem_noise_std = 0.03;
        case 'uneven'
            cfg.dem_base = 0.60;
            cfg.dem_diurnal_amp = 0.50;  % high diurnal swing
            cfg.dem_noise_std = 0.05;
        case 'spike'
            % Use default — spike added dynamically in run_scenario
            cfg.dem_spike_enable = true;
    end

    %% Valve configuration
    cfg.valve_scenario = valv;   % consumed in run_scenario

    %% Storage initial condition
    cfg.sto_inventory_init = sto;

    %% Compressor mode
    cfg.cs_mode = csm;

    %% No attacks for baseline
    cfg.n_attacks = 0;
    cfg.fault_enable = false;   % optionally keep true for realistic baseline
end
```

### 5.4 `run_scenario.m` — Scenario Runner

```matlab
function [logs, params, N, schedule] = run_scenario(cfg, duration_min)
% run_scenario  Run one scenario offline, return logs.

    cfg.T = duration_min * 60;
    dt    = cfg.dt;
    N     = double(round(cfg.T / dt));

    [params, state] = initNetwork(cfg);
    src_p1 = generateSourceProfile(N, cfg);

    % S2 profile — use scaled version of S1
    cfg_s2        = cfg;
    cfg_s2.p0     = 48.0;
    cfg_s2.src_p_min = cfg.src2_p_min;
    cfg_s2.src_p_max = cfg.src2_p_max;
    src_p2 = generateSourceProfile(N, cfg_s2);

    %% Demand vector — add spike if enabled
    demand = ones(N, 1);
    if isfield(cfg, 'dem_spike_enable') && cfg.dem_spike_enable
        % Two demand spikes at random times
        for s = 1:2
            t_spike = randi([round(N*0.3), round(N*0.7)]);
            dur     = round(60 / dt);   % 60-second spike
            demand(t_spike:min(N, t_spike+dur)) = 2.5;
        end
    end

    [comp1, comp2] = initCompressor(cfg);
    [prs1, prs2]   = initPRS(cfg);
    initValve(cfg);

    %% Apply compressor mode
    switch cfg.cs_mode
        case 'CS1_only'
            comp2.online = false;
        case 'CS2_only'
            comp1.online = false;
    end

    plc   = initPLC(cfg, state, comp1);
    ekf   = initEKF(cfg, state);
    schedule = initEmptySchedule(N);
    logs  = initLogs(params, ekf, N, cfg);

    cfg.use_gateway = false;

    [~, ~, ~, ~, ~, ~, ~, ~, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule);
end

function schedule = initEmptySchedule(N)
    schedule.nAttacks   = 0;
    schedule.ids        = [];
    schedule.start_s    = [];
    schedule.end_s      = [];
    schedule.dur_s      = [];
    schedule.params     = {};
    schedule.label_id   = zeros(N, 1, 'int32');
    schedule.label_name = repmat("Normal", N, 1);
    schedule.label_mitre= repmat("None",   N, 1);
end
```

### 5.5 `export_scenario_csv.m` — Scenario Export

```matlab
function export_scenario_csv(logs, cfg, params, N, schedule, fpath, ...
                              scen_id, src, dem, valv, sto, csm)
% export_scenario_csv  Write one scenario to a labelled CSV.

    N_log  = logs.N_log;
    log_dt = cfg.dt * cfg.log_every;
    t_vec  = ((0:N_log-1)' * log_dt);

    %% Scenario identity columns (broadcast to all rows)
    scen_col  = repmat(scen_id,  N_log, 1);
    src_col   = repmat(string(src),  N_log, 1);
    dem_col   = repmat(string(dem),  N_log, 1);
    valv_col  = repmat(string(valv), N_log, 1);
    sto_col   = repmat(sto, N_log, 1);
    csm_col   = repmat(string(csm),  N_log, 1);

    fid = fopen(fpath, 'w');

    %% Header
    nn = params.nodeNames;
    en = params.edgeNames;

    hdr = 'Timestamp_s,scenario_id,source_config,demand_profile,';
    hdr = [hdr 'valve_config,storage_init,cs_mode,'];
    for i = 1:params.nNodes
        hdr = [hdr sprintf('p_%s_bar,', char(nn(i)))];
    end
    for i = 1:params.nEdges
        hdr = [hdr sprintf('q_%s_kgs,', char(en(i)))];
    end
    hdr = [hdr 'CS1_ratio,CS1_power_kW,CS2_ratio,CS2_power_kW,'];
    hdr = [hdr 'PRS1_throttle,PRS2_throttle,'];
    hdr = [hdr 'valve_E8,valve_E14,valve_E15,STO_inventory,'];
    hdr = [hdr 'cusum_S_upper,cusum_S_lower,cusum_alarm,'];
    hdr = [hdr 'chi2_stat,chi2_alarm,'];
    hdr = [hdr 'FAULT_ID,ATTACK_ID,label'];
    fprintf(fid, '%s\n', hdr);

    %% Data rows
    for k = 1:N_log
        fprintf(fid, '%.3f,%d,%s,%s,%s,%.1f,%s,', ...
            t_vec(k), scen_id, src, dem, valv, sto, csm);

        % Pressures
        for i = 1:params.nNodes
            fprintf(fid, '%.4f,', logs.logP(i,k));
        end
        % Flows
        for i = 1:params.nEdges
            fprintf(fid, '%.4f,', logs.logQ(i,k));
        end
        % Equipment
        fprintf(fid, '%.4f,%.2f,%.4f,%.2f,', ...
            logs.logCompRatio1(k), logs.logPow1(k), ...
            logs.logCompRatio2(k), logs.logPow2(k));
        fprintf(fid, '%.4f,%.4f,', ...
            logs.logPRS1Throttle(k), logs.logPRS2Throttle(k));

        if size(logs.logValveStates,1) >= 3
            fprintf(fid, '%.3f,%.3f,%.3f,', ...
                logs.logValveStates(1,k), logs.logValveStates(2,k), ...
                logs.logValveStates(3,k));
        else
            fprintf(fid, '1.000,1.000,1.000,');
        end
        fprintf(fid, '%.4f,', logs.logStoInventory(k));

        % CUSUM + chi2
        cusum_up  = 0; cusum_lo = 0; cusum_al = 0;
        chi2_s    = 0; chi2_al  = 0;
        if isfield(logs, 'logCUSUM_upper')
            cusum_up = logs.logCUSUM_upper(k);
            cusum_lo = logs.logCUSUM_lower(k);
            cusum_al = int32(logs.logCUSUM_alarm(k));
        end
        if isfield(logs, 'logChi2')
            chi2_s  = logs.logChi2(k);
            chi2_al = int32(logs.logChi2_alarm(k));
        end
        fprintf(fid, '%.4f,%.4f,%d,', cusum_up, cusum_lo, cusum_al);
        fprintf(fid, '%.4f,%d,', chi2_s, chi2_al);

        % Labels
        fault_id  = 0;
        attack_id = 0;
        if isfield(logs, 'logFaultId'),  fault_id  = logs.logFaultId(k);  end
        if isfield(logs, 'logAttackId'), attack_id = logs.logAttackId(k); end
        label = int32(fault_id > 0 || attack_id > 0);
        fprintf(fid, '%d,%d,%d\n', fault_id, attack_id, label);
    end

    fclose(fid);
end
```

---

## 6. Attack Dataset Design

### 6.1 Attack Catalogue (Complete)

| ID | Name | MITRE | Target | Type | Stealthy |
|---|---|---|---|---|---|
| A1 | SrcPressureManipulation | T0831 | S1 pressure | Process | No |
| A2 | CompressorRatioSpoofing | T0838 | CS1 PID setpoint | Actuator | Partial |
| A3 | ValveCommandTampering | T0855 | E8 valve | Actuator | No |
| A4 | DemandNodeManipulation | T0829 | Demand scalar | Process | No |
| A5 | PressureSensorSpoofing | T0831 | D1 sensor | Sensor | Partial |
| A6 | FlowMeterSpoofing | T0827 | E4/E5 flow meters | Sensor | Partial |
| A7 | PLCLatencyAttack | T0814 | Modbus timing | Protocol | Yes |
| A8 | PipelineLeak | T0829 | E12 edge | Physical | No |
| A9 | StealthyFDI | T0856 | Nodes J2/J3/J5 | Sensor | **Yes** |
| A10 | ReplayAttack | — | All sensors | Protocol | **Yes** |

### 6.2 Attack Injection Matrix

For IDS generalisability, **each attack is injected across multiple baseline conditions**:

| Attack | Required Baseline Configs |
|---|---|
| A1 | `both` sources, `medium` demand, `auto` valve |
| A1 | `S1_only`, `peak` demand (stress test) |
| A2 | `both_on` CS mode, `both` sources |
| A3 | `E8_forced_open` baseline, then tamper to closed |
| A4 | All demand profiles (D6 spike must be distinguishable from normal spike) |
| A5 | 3 baseline pressures: 45 bar, 50 bar, 55 bar at D1 |
| A6 | `medium` and `peak` demand (flow scaling must be detectable) |
| A7 | Gateway enabled runs only |
| A8 | `both` sources, `both_on` CS (leak is slow — needs long run) |
| A9 | All baselines — should NOT trigger CUSUM (by construction) |
| A10 | `both` sources, storage in withdrawal mode |

### 6.3 Attack Timing Protocol

To prevent the **Morris dataset flaw** (different pressure at attack vs normal time):

```
Per scenario:
  ┌─────────────────────────────────────────────────────────┐
  │  0–10 min  │  10–20 min  │  20–25 min  │  25–30 min    │
  │  Warmup    │  Steady     │  ATTACK     │  Recovery     │
  │  (discard) │  (normal)   │  (labelled) │  (labelled)   │
  └─────────────────────────────────────────────────────────┘
```

**Key rule:** pressure at attack start must be within ±5% of pressure at matched normal-operation rows.

### 6.4 Attack Severity Levels

Each attack should be run at 3 severity levels to create a graded dataset:

| Level | Description | Example (A1) |
|---|---|---|
| Low | 5–10% deviation, hard to detect | +10% S1 pressure, sinusoidal |
| Medium | 15–25% deviation, EKF detectable | +25% S1, 60s spike |
| High | >30% deviation, alarm triggers | +50% S1, sustained |

---

## 7. Attack Injection Code

### 7.1 `run_attack_sweep.m` — Attack Dataset Generator

```matlab
function run_attack_sweep()
% run_attack_sweep  Inject all 10 attacks across selected baseline configs.
%
%   Produces labelled CSV per (scenario × attack × severity).
%   Total: ~10 attacks × 3 baselines × 3 severities = 90 attack runs

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling','processing');

    outDir = fullfile('automated_dataset', 'attack');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    %% Attack configs: {attack_id, severity, source_config, demand_profile}
    attack_matrix = {
        1, 'medium', 'both',    'medium';
        1, 'high',   'S1_only', 'peak';
        2, 'medium', 'both',    'medium';
        2, 'high',   'both',    'peak';
        3, 'medium', 'both',    'medium';
        3, 'high',   'both',    'peak';
        4, 'low',    'both',    'uneven';
        4, 'medium', 'both',    'medium';
        4, 'high',   'both',    'peak';
        5, 'low',    'both',    'medium';
        5, 'medium', 'both',    'medium';
        5, 'high',   'both',    'peak';
        6, 'medium', 'both',    'medium';
        6, 'high',   'both',    'peak';
        8, 'low',    'both',    'medium';
        8, 'medium', 'both',    'medium';
        8, 'high',   'both',    'peak';
        9, 'medium', 'both',    'medium';
        9, 'high',   'both',    'peak';
       10, 'medium', 'both',    'medium';
    };

    for i = 1:size(attack_matrix, 1)
        atk_id   = attack_matrix{i,1};
        severity = attack_matrix{i,2};
        src      = attack_matrix{i,3};
        dem      = attack_matrix{i,4};

        fprintf('[attack_sweep] A%d | %s | %s | %s\n', atk_id, severity, src, dem);

        cfg = build_attack_config(atk_id, severity, src, dem);
        [logs, params, N, schedule] = run_scenario(cfg, 30);

        fname = sprintf('attack_A%02d_%s_%s_%s.csv', atk_id, severity, src, dem);
        export_scenario_csv(logs, cfg, params, N, schedule, ...
                            fullfile(outDir, fname), ...
                            i, src, dem, 'auto', 0.5, 'both_on');
    end

    fprintf('[attack_sweep] Done — %d attack runs completed.\n', size(attack_matrix,1));
end
```

### 7.2 `build_attack_config.m` — Attack Config Builder

```matlab
function cfg = build_attack_config(atk_id, severity, src, dem)
% build_attack_config  Create a config with one attack scheduled.

    cfg = build_scenario_config(src, dem, 'auto', 0.5, 'both_on');

    %% Severity modifiers
    switch severity
        case 'low'
            mag = 0.10;    % 10% deviation
            dur_s = 120;   % 2 min
        case 'medium'
            mag = 0.25;
            dur_s = 300;   % 5 min
        case 'high'
            mag = 0.50;
            dur_s = 480;   % 8 min
    end

    %% Enable fault injection for realism
    cfg.fault_enable = true;

    %% Schedule a single attack at t=12 min (after warmup+steady)
    cfg.n_attacks         = 1;
    cfg.atk_warmup_s      = 12 * 60;   % attack starts at 12 min
    cfg.atk_recovery_s    = 5  * 60;
    cfg.atk_min_gap_s     = 30 * 60;   % only one attack — gap irrelevant
    cfg.atk_dur_min_s     = dur_s;
    cfg.atk_dur_max_s     = dur_s;

    %% Per-attack magnitude overrides
    switch atk_id
        case 1   % Source manipulation
            cfg.atk1_spike_amp = 1 + mag;
        case 2   % Compressor spoofing
            cfg.atk2_target_ratio = cfg.comp1_ratio * (1 + mag);
        case 4   % Demand spike
            cfg.atk4_demand_scale = 1 + 3 * mag;
        case 5   % Pressure sensor bias
            cfg.atk5_bias_bar = -cfg.p0 * mag;
        case 6   % Flow meter scale
            cfg.atk6_scale = 1 - mag;
        case 8   % Pipeline leak
            cfg.atk8_leak_frac = mag;
        case 9   % FDI
            cfg.atk9_bias_scale = mag * 0.1;
    end

    %% Force attack ID (override random shuffle in initAttackSchedule)
    cfg.forced_attack_id = atk_id;
end
```

---

## 8. ML Dataset Assembly

### 8.1 `assemble_ml_dataset.m` — Merge All CSVs

```matlab
function assemble_ml_dataset(baseline_dir, attack_dir, out_path)
% assemble_ml_dataset  Concatenate all scenario CSVs into one ML-ready file.
%
%   assemble_ml_dataset('automated_dataset/baseline', ...
%                       'automated_dataset/attack', ...
%                       'automated_dataset/ml_dataset_final.csv')

    fprintf('[assemble] Reading baseline CSVs...\n');
    baseline_files = dir(fullfile(baseline_dir, 'scenario_*.csv'));
    attack_files   = dir(fullfile(attack_dir,   'attack_*.csv'));

    all_files = [baseline_files; attack_files];
    total     = numel(all_files);

    fout = fopen(out_path, 'w');
    header_written = false;

    for i = 1:total
        fpath = fullfile(all_files(i).folder, all_files(i).name);
        fid   = fopen(fpath, 'r');
        hdr   = fgetl(fid);   % read header line

        if ~header_written
            fprintf(fout, '%s\n', hdr);
            header_written = true;
        end

        % Copy all data rows
        while ~feof(fid)
            line = fgetl(fid);
            if ischar(line) && ~isempty(line)
                fprintf(fout, '%s\n', line);
            end
        end
        fclose(fid);

        if mod(i, 50) == 0
            fprintf('[assemble] %d / %d files merged\n', i, total);
        end
    end

    fclose(fout);
    fprintf('[assemble] Done → %s\n', out_path);
end
```

### 8.2 Feature Engineering Notes

Features derived from raw columns that improve IDS detection:

| Derived Feature | Formula | Detects |
|---|---|---|
| `dp_CS1` | `p_CS1_bar − p_J1_bar` | Compressor ratio anomaly |
| `dp_PRS1` | `p_J6_bar − p_PRS1_bar` | PRS setpoint attack |
| `q_balance_J3` | `q_E4_kgs − q_E5_kgs − q_E12_kgs` | Mass balance violation (leak) |
| `q_balance_J5` | `q_E7_kgs + q_E15_kgs − q_E16_kgs` | Storage loop anomaly |
| `ekf_resid_norm` | `‖ekf_resid‖₂` | EKF divergence |
| `jitter_ms` | Modbus inter-arrival jitter | Replay / MitM |
| `p_D1_error` | `p_D1_bar − CS1_pid_setpoint` | Control loop attack |
| `storage_rate` | `d(STO_inventory)/dt` | Storage manipulation |
| `valve_switch_count` | Count of E8 transitions in 60s window | Valve tampering |

---

## 9. Physical Validity Rules

Apply these post-simulation to reject corrupted runs before saving:

```matlab
function valid = check_run_validity(logs, params, cfg)
% check_run_validity  Return false if any physical constraint is violated.

    valid = true;
    N_log = logs.N_log;

    % R1: No negative absolute pressures
    if any(logs.logP(:) < 0)
        fprintf('[validity] FAIL: negative pressure detected\n');
        valid = false; return;
    end

    % R2: Source nodes must maintain minimum pressure
    src_idx = params.sourceNodes;
    if any(logs.logP(src_idx,:) < cfg.src_p_min - 5)
        fprintf('[validity] FAIL: source pressure below minimum\n');
        valid = false; return;
    end

    % R3: Demand nodes must receive supply (p > 5 bar for > 5% of time)
    dem_idx = params.demandNodes;
    for n = dem_idx(:)'
        low_frac = mean(logs.logP(n,:) < 5.0);
        if low_frac > 0.30
            fprintf('[validity] FAIL: demand node %d starved >30%% of time\n', n);
            valid = false; return;
        end
    end

    % R4: Simulation must not end at saturation clamp
    if mean(logs.logP(:, end-9:end) >= 69.9) > 0.1
        fprintf('[validity] FAIL: pressure stuck at ceiling in final 10 rows\n');
        valid = false; return;
    end

    % R5: EKF must not diverge permanently
    if all(abs(logs.logResP(:)) > cfg.alarm_ekf_resid)
        fprintf('[validity] FAIL: EKF permanently diverged\n');
        valid = false; return;
    end
end
```

---

## 10. Split Recommendations

### 10.1 Temporal Split (Recommended for IDS)

Do **not** use random row shuffle — use scenario-level splits to prevent data leakage:

```
Train:      scenarios 1–240   (70%)
Validation: scenarios 241–310 (18%)
Test:       scenarios 311–340 (12%)
```

Keep all rows from one scenario in the same split.

### 10.2 Class Balance

| Class | Target Fraction | Notes |
|---|---|---|
| Normal (no attack, no fault) | 65% | Must include all 5 demand profiles |
| Fault only (packet loss / stuck) | 10% | Fault is NOT an attack |
| Attack (any A1–A10) | 20% | Balanced across all 10 attack types |
| Attack + Fault concurrent | 5% | Hardest to detect — include in test set |

### 10.3 Transient vs Steady State

| Phase | Fraction | ML Role |
|---|---|---|
| Startup transient (0–5 min) | 15% | Train on transitions |
| Steady state (5–25 min) | 70% | Primary training data |
| Stress / post-attack recovery | 15% | Generalisation |

> **Rule:** IDS models trained only on steady-state data achieve ~95% accuracy in evaluation but fail in deployment. Include ≥15% transient rows.

### 10.4 Minimum Dataset Size for Publication

| Model Type | Minimum Rows | Recommended |
|---|---|---|
| Threshold / rule-based | 10,000 | 50,000 |
| ML (SVM, Random Forest) | 50,000 | 200,000 |
| Deep learning (LSTM, TCN) | 200,000 | 600,000+ |
| Anomaly detection (autoencoder) | 100,000 normal | 400,000 normal |

With 340 baseline scenarios × 1,800 rows + 90 attack runs × 1,800 rows:
**Total ≈ 774,000 rows** — sufficient for all model types.

---

*Document generated for Gas Pipeline CPS Simulator — Phase 6*  
*Topology: 20 nodes, 20 edges, GasLib-24 inspired, CODESYS Modbus TCP*
