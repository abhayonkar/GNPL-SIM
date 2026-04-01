# Implementation Plan

- [x] 1. Write bug condition exploration tests
  - **Property 1: Bug Condition** - Forced Attack ID Ignored / n_attacks Ignored / Wrong Column Names / Quick-Mode Index Overflow
  - **CRITICAL**: These tests MUST FAIL on unfixed code — failure confirms the bugs exist
  - **DO NOT attempt to fix the tests or the code when they fail**
  - **NOTE**: These tests encode the expected behavior — they will validate the fixes when they pass after implementation
  - **GOAL**: Surface counterexamples that demonstrate each bug exists
  - **Scoped PBT Approach**: Scope each property to the concrete failing case(s) for reproducibility

  - Bug 1 — forced_attack_id ignored:
    - Build a cfg with `cfg.forced_attack_id = 3`, `cfg.n_attacks = 1`, valid atk timing fields
    - Call `initAttackSchedule(N, cfg)` on UNFIXED code
    - Assert `schedule.nAttacks == 1` AND `schedule.ids(1) == 3`
    - **EXPECTED OUTCOME**: FAILS — schedule has 8 random attacks, not the forced one
    - Document counterexample (e.g. `schedule.nAttacks = 8`, `schedule.ids(1) ≠ 3`)
    - _Requirements: 1.1_

  - Bug 2 — n_attacks hardcoded to 8:
    - Build a cfg with `cfg.n_attacks = 1`, no `forced_attack_id`, valid 30-min timing fields
    - Call `initAttackSchedule(N, cfg)` on UNFIXED code
    - Assert `schedule.nAttacks == 1`
    - **EXPECTED OUTCOME**: FAILS — `nA = 8` is hardcoded; timing conflict error or 8-attack schedule
    - Document counterexample (e.g. error message or `schedule.nAttacks = 8`)
    - _Requirements: 1.2_

  - Bug 3 — wrong column names in validate_csv_quick:
    - Create a minimal CSV with columns `S1_bar` and `D1_bar` (no `p_` prefix, matching exportDataset)
    - Call `validate_csv_quick(csv_path, cfg)` on UNFIXED code
    - Assert no struct-field error is thrown (i.e. `valid` is returned without exception)
    - **EXPECTED OUTCOME**: FAILS — throws `No such field 'p_S1_bar'`
    - Document counterexample (exact error message)
    - _Requirements: 1.3_

  - Bug 4 — quick-mode index overflow:
    - Build a `baseline_scenarios` array of length 5 (fewer than 10)
    - Invoke the quick-mode scenario selection logic: `[baseline_scenarios(1:10); ...]`
    - Assert no index-out-of-bounds error is thrown
    - **EXPECTED OUTCOME**: FAILS — MATLAB throws index error
    - Document counterexample (e.g. `index (10) exceeds array bounds (5)`)
    - _Requirements: 1.4_

  - Mark task complete when all four exploration tests are written, run, and failures are documented

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Multi-Attack Random Schedule and Baseline Zero-Attack Behavior
  - **IMPORTANT**: Follow observation-first methodology — run UNFIXED code with non-buggy inputs first
  - **Scoped to non-bug-condition inputs**: cfg where `forced_attack_id` is absent AND `cfg.n_attacks == 8`

  - Preservation test A — default multi-attack schedule (no forced_attack_id, n_attacks = 8):
    - Build a cfg with `cfg.n_attacks = 8` (or absent), no `forced_attack_id`, valid timing fields
    - Call `initAttackSchedule(N, cfg)` on UNFIXED code; observe `schedule.nAttacks == 8`
    - Write property-based test: for all such cfg, `schedule.nAttacks == 8` and all label arrays have length N
    - Verify test PASSES on UNFIXED code
    - _Requirements: 3.4_

  - Preservation test B — baseline zero-attack path:
    - Build a cfg with `cfg.n_attacks = 0`
    - Confirm `initEmptySchedule` is called (not `initAttackSchedule`)
    - Observe `schedule.nAttacks == 0` and all labels are "Normal"
    - Write property-based test: for all cfg with n_attacks = 0, schedule has zero attacks and all-Normal labels
    - Verify test PASSES on UNFIXED code
    - _Requirements: 3.1_

  - Preservation test C — validate_csv_quick non-pressure-error paths:
    - Create CSVs: one with < 50 rows, one with negative pressure, one with pressure > 30
    - Call `validate_csv_quick` on UNFIXED code; observe `valid = false` with correct reason strings
    - Write property-based test: these three cases always return `valid = false` with the expected reason
    - Verify test PASSES on UNFIXED code
    - _Requirements: 3.6_

  - Mark task complete when all preservation tests are written, run, and confirmed passing on unfixed code

- [~] 3. Fix all six bugs in run_24h_sweep.m and attacks/initAttackSchedule.m

  - [ ] 3.1 Fix Bug 1 & 2 — honour cfg.forced_attack_id and cfg.n_attacks in initAttackSchedule
    - Read `nA` from `cfg.n_attacks` instead of hardcoding `nA = 8`
    - Before the random-placement loop, check `isfield(cfg, 'forced_attack_id') && cfg.forced_attack_id > 0`
    - If true: set `nA = 1`, `attack_ids = cfg.forced_attack_id`, skip `randperm`
    - Otherwise: `attack_ids = randperm(nA)` as before
    - Update the error message to use the dynamic `nA`
    - _Bug_Condition: isBugCondition_1(cfg) — isfield(cfg,'forced_attack_id') AND cfg.forced_attack_id > 0_
    - _Bug_Condition: isBugCondition_2(cfg) — isfield(cfg,'n_attacks') AND cfg.n_attacks ~= 8_
    - _Expected_Behavior: schedule.nAttacks = cfg.n_attacks; schedule.ids(1) = cfg.forced_attack_id when forced_
    - _Preservation: default multi-attack path (no forced_attack_id, n_attacks=8) unchanged_
    - _Requirements: 2.1, 2.2, 3.4_

  - [~] 3.2 Fix Bug 3 — correct column names in validate_csv_quick
    - Replace `T.p_S1_bar` with `T.S1_bar` and `T.p_D1_bar` with `T.D1_bar`
    - _Bug_Condition: isBugCondition_3 — fires on every scenario validation_
    - _Expected_Behavior: no struct-field error; pressure bounds checked against correct columns_
    - _Preservation: valid=false paths for <50 rows, negative pressure, >30 bar remain unchanged_
    - _Requirements: 2.3, 3.3, 3.6_

  - [~] 3.3 Fix Bug 4 — guard quick-mode index in run_24h_sweep
    - Replace `baseline_scenarios(1:10)` with `baseline_scenarios(1:min(10, numel(baseline_scenarios)))`
    - Replace `attack_scenarios(1:10)` with `attack_scenarios(1:min(10, numel(attack_scenarios)))`
    - _Bug_Condition: isBugCondition_4 — quick mode AND numel(baseline_scenarios) < 10_
    - _Expected_Behavior: no index error; at most 10 entries selected from each array_
    - _Requirements: 2.4_

  - [~] 3.4 Fix Bug 5 — defensive fallback for cfg.src2_p_min / cfg.src2_p_max in main_simulation_scenario
    - Before constructing `cfg2`, check `isfield(cfg, 'src2_p_min')` and `isfield(cfg, 'src2_p_max')`
    - If absent, fall back to `cfg.src_p_min` / `cfg.src_p_max`
    - _Bug_Condition: cfg.src2_p_min or cfg.src2_p_max field absent_
    - _Expected_Behavior: cfg2 constructed without error; secondary source profile generated with fallback values_
    - _Requirements: 2.5_

  - [~] 3.5 Confirm Bug 6 — verify initLogger call site matches (dt, T, N) exactly
    - Inspect `initLogger.m`: confirms signature is `function initLogger(dt, T, N)` — exactly 3 args
    - Inspect call site in `main_simulation_scenario`: `initLogger(dt, cfg.T, N)` — exactly 3 args
    - No code change required if signatures match; add a `narginchk(3,3)` guard to `initLogger` if they do not
    - _Expected_Behavior: initLogger accepts exactly 3 arguments; extra args cause an immediate error_
    - _Requirements: 2.6_

  - [~] 3.6 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Forced Attack ID / n_attacks / Column Names / Quick-Mode Bounds
    - **IMPORTANT**: Re-run the SAME tests from task 1 — do NOT write new tests
    - Run all four exploration tests from step 1 against the fixed code
    - **EXPECTED OUTCOME**: All four tests PASS (confirms all four bugs are fixed)
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [~] 3.7 Verify preservation tests still pass
    - **Property 2: Preservation** - Multi-Attack Random Schedule and Baseline Zero-Attack Behavior
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run all three preservation tests from step 2 against the fixed code
    - **EXPECTED OUTCOME**: All three tests PASS (confirms no regressions)
    - _Requirements: 3.1, 3.4, 3.6_

- [~] 4. Checkpoint — Ensure all tests pass
  - Run the full test suite (exploration + preservation tests)
  - Confirm zero failures; ask the user if any ambiguity arises
  - Optionally run `run_24h_sweep('mode','quick')` to do a live smoke-test of the patched sweep
