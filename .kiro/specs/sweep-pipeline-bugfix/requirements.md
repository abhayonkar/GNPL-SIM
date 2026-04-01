# Bugfix Requirements Document

## Introduction

`run_24h_sweep()` is the orchestrator for generating the full 340-baseline + 90-attack Indian CGD
pipeline dataset. Six bugs currently prevent a clean sweep run:

1. `initAttackSchedule` ignores `cfg.forced_attack_id`, so attack scenarios always get 8 random
   attacks instead of the single forced one.
2. `initAttackSchedule` hardcodes `nA = 8` and ignores `cfg.n_attacks`, so sweep scenarios that
   set `cfg.n_attacks = 1` still schedule 8 attacks, causing timing/overlap errors in 30-min runs.
3. `validate_csv_quick` accesses `T.p_S1_bar` and `T.p_D1_bar`, but `exportDataset` writes those
   columns as `S1_bar` and `D1_bar` (no `p_` prefix), causing a struct-field error on every
   scenario validation.
4. `run_24h_sweep` `quick` mode hard-indexes `baseline_scenarios(1:10)` without guarding against
   a pruned baseline array shorter than 10 entries.
5. `main_simulation_scenario` reads `cfg.src2_p_min` / `cfg.src2_p_max` directly without a safety
   check; if those fields are absent the wrapper errors before the simulation starts.
6. `initLogger` accepts exactly three arguments `(dt, T, N)` — the wrapper calls it correctly —
   but this must be confirmed and locked so future callers cannot silently pass extra arguments.

All fixes must be confined to `run_24h_sweep.m` and `attacks/initAttackSchedule.m`.
`runSimulation.m` is frozen and must not be modified.

---

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN an attack scenario sets `cfg.forced_attack_id = atk_id` THEN the system ignores the
    field and calls `randperm(8)` to shuffle all 8 attack IDs, placing the wrong attack type in
    the schedule.

1.2 WHEN an attack scenario sets `cfg.n_attacks = 1` THEN the system uses the hardcoded value
    `nA = 8` and attempts to place 8 attacks inside a 30-minute window, producing a timing
    conflict or an `initAttackSchedule` error.

1.3 WHEN `validate_csv_quick` reads the exported CSV THEN the system throws a struct-field error
    because it accesses `T.p_S1_bar` and `T.p_D1_bar`, which do not exist; the actual column
    names written by `exportDataset` are `S1_bar` and `D1_bar`.

1.4 WHEN `run_24h_sweep` is called in `quick` mode and validity pruning has reduced the baseline
    array to fewer than 10 entries THEN the system throws an index-out-of-bounds error on
    `baseline_scenarios(1:10)`.

1.5 WHEN `build_scenario_config` builds a `S2_only` scenario (which sets `cfg.src_p_min = 0`
    but leaves `cfg.src2_p_min` / `cfg.src2_p_max` at their `simConfig` defaults) and
    `main_simulation_scenario` later reads `cfg.src2_p_min` / `cfg.src2_p_max` to construct
    `cfg2` THEN the system proceeds without error for `S2_only`, but for any scenario where
    those fields were never written the system may error; there is no defensive check.

1.6 WHEN any caller passes more than three arguments to `initLogger` THEN the system silently
    accepts extra arguments because MATLAB does not enforce arity on functions without an
    `inputParser`; a future caller adding `cfg.scenario_id` as a fourth argument would not
    receive an error, masking the mismatch.

### Expected Behavior (Correct)

2.1 WHEN an attack scenario sets `cfg.forced_attack_id = atk_id` THEN the system SHALL place
    exactly that one attack type in the schedule at the configured start time, ignoring
    `randperm`.

2.2 WHEN an attack scenario sets `cfg.n_attacks = 1` THEN the system SHALL read `cfg.n_attacks`
    and place exactly 1 attack in the schedule, fitting within the 30-minute window without
    timing conflicts.

2.3 WHEN `validate_csv_quick` reads the exported CSV THEN the system SHALL access the pressure
    columns using the correct names `S1_bar` and `D1_bar` (matching the `exportDataset` schema)
    and SHALL NOT throw a struct-field error.

2.4 WHEN `run_24h_sweep` is called in `quick` mode THEN the system SHALL select
    `min(10, numel(baseline_scenarios))` baseline entries and `min(10, numel(attack_scenarios))`
    attack entries, preventing any index-out-of-bounds error.

2.5 WHEN `main_simulation_scenario` constructs `cfg2` for the secondary source profile THEN the
    system SHALL verify that `cfg.src2_p_min` and `cfg.src2_p_max` are present fields before
    reading them, and SHALL fall back to `cfg.src_p_min` / `cfg.src_p_max` if they are absent.

2.6 WHEN `initLogger` is called THEN the system SHALL accept exactly three arguments `(dt, T, N)`
    and the call site in `main_simulation_scenario` SHALL match that signature with no extra
    arguments.

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a baseline scenario runs with `cfg.n_attacks = 0` THEN the system SHALL CONTINUE TO
    call `initEmptySchedule` and produce a schedule with zero attacks and all-Normal labels.

3.2 WHEN a full-mode sweep runs all 340 baseline + 90 attack scenarios THEN the system SHALL
    CONTINUE TO iterate every scenario, write `scenario_XXXX.csv`, and assemble
    `ml_dataset_final.csv` without change to the output schema.

3.3 WHEN `exportDataset` writes `master_dataset.csv` THEN the system SHALL CONTINUE TO name
    node-pressure columns as `<nodeName>_bar` (e.g. `S1_bar`, `D1_bar`) with no `p_` prefix,
    matching the existing ICS_Dataset_Design.md §1.2 schema.

3.4 WHEN `initAttackSchedule` is called for a default multi-attack scenario (no
    `forced_attack_id`, `cfg.n_attacks > 1`) THEN the system SHALL CONTINUE TO place
    `cfg.n_attacks` randomly shuffled attacks with gap/warmup/recovery constraints respected.

3.5 WHEN `runSimulation.m` is invoked by `main_simulation_scenario` THEN the system SHALL
    CONTINUE TO receive the same frozen interface `(cfg, params, state, comp1, comp2, prs1,
    prs2, ekf, plc, logs, N, src_p1, src_p2, demand, schedule)` with no modifications.

3.6 WHEN `validate_csv_quick` finds a CSV with fewer than 50 rows or with negative / over-MAOP
    pressures THEN the system SHALL CONTINUE TO return `valid = false` with the appropriate
    reason string.

---

## Bug Condition Pseudocode

### Bug Condition Functions

```pascal
FUNCTION isBugCondition_1(cfg)
  // Triggers Bug 1: forced attack ID ignored
  INPUT: cfg of type SimConfig
  OUTPUT: boolean
  RETURN isfield(cfg, 'forced_attack_id') AND cfg.forced_attack_id > 0
END FUNCTION

FUNCTION isBugCondition_2(cfg)
  // Triggers Bug 2: n_attacks ignored
  INPUT: cfg of type SimConfig
  OUTPUT: boolean
  RETURN isfield(cfg, 'n_attacks') AND cfg.n_attacks ~= 8
END FUNCTION

FUNCTION isBugCondition_3(csv_path)
  // Triggers Bug 3: wrong column name in validate_csv_quick
  INPUT: csv_path of type string
  OUTPUT: boolean
  RETURN true  // fires on every scenario validation
END FUNCTION

FUNCTION isBugCondition_4(mode, baseline_scenarios)
  // Triggers Bug 4: quick-mode index overflow
  INPUT: mode string, baseline_scenarios array
  OUTPUT: boolean
  RETURN strcmp(mode, 'quick') AND numel(baseline_scenarios) < 10
END FUNCTION
```

### Fix-Checking Properties

```pascal
// Property: Fix Checking — Bug 1
FOR ALL cfg WHERE isBugCondition_1(cfg) DO
  schedule ← initAttackSchedule'(N, cfg)
  ASSERT schedule.nAttacks = 1
  ASSERT schedule.ids(1) = cfg.forced_attack_id
END FOR

// Property: Fix Checking — Bug 2
FOR ALL cfg WHERE isBugCondition_2(cfg) DO
  schedule ← initAttackSchedule'(N, cfg)
  ASSERT schedule.nAttacks = cfg.n_attacks
END FOR

// Property: Fix Checking — Bug 3
FOR ALL csv_path WHERE isBugCondition_3(csv_path) DO
  [valid, reason] ← validate_csv_quick'(csv_path, cfg)
  ASSERT reason ≠ "No such field 'p_S1_bar'"
  ASSERT reason ≠ "No such field 'p_D1_bar'"
END FOR

// Property: Fix Checking — Bug 4
FOR ALL (mode, baseline_scenarios) WHERE isBugCondition_4(mode, baseline_scenarios) DO
  scenarios ← select_scenarios'(mode, baseline_scenarios, attack_scenarios)
  ASSERT numel(scenarios) ≤ 20   // no index error thrown
END FOR
```

### Preservation Property

```pascal
// Property: Preservation Checking
FOR ALL cfg WHERE NOT isBugCondition_1(cfg)
                  AND NOT isBugCondition_2(cfg) DO
  schedule_before ← initAttackSchedule(N, cfg)
  schedule_after  ← initAttackSchedule'(N, cfg)
  ASSERT schedule_before.nAttacks = schedule_after.nAttacks
  // attack IDs, timing distribution, and label arrays are statistically equivalent
END FOR
```
