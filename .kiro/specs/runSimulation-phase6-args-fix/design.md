# runSimulation Phase 6 Argument Fix - Bugfix Design

## Overview

This bugfix addresses a function signature mismatch in runSimulation.m Phase 6 where `updateCUSUM` is called with 5 arguments but expects only 4. The error causes 100% failure rate across all simulation scenarios. The fix involves correcting the function call to pass the EKF residual vector instead of the entire ekf struct, removing the extraneous dt parameter, and ensuring the step counter k is passed as the 4th argument.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when updateCUSUM is called with 5 arguments (cusum, ekf, cfg, k, dt) instead of 4
- **Property (P)**: The desired behavior - updateCUSUM should be called with exactly 4 arguments (cusum, residual, cfg, step) matching its function signature
- **Preservation**: All other Phase 6 function calls and CUSUM detection logic that must remain unchanged by the fix
- **updateCUSUM**: The function in `scada/updateCUSUM.m` that implements a two-sided CUSUM detector with cold-start warmup guard
- **ekf.residual**: The 40×1 innovation vector (pre-update residual) computed by updateEKF, stored in the ekf struct
- **Phase 6**: The main simulation loop in runSimulation.m that executes time-step updates for network state, EKF estimation, CUSUM detection, and attack effects

## Bug Details

### Bug Condition

The bug manifests when runSimulation Phase 6 reaches line 171 and attempts to call updateCUSUM. The function call passes 5 arguments (cusum, ekf, cfg, k, dt) but the function signature expects only 4 arguments (cusum, residual, cfg, step). MATLAB immediately throws "Too many input arguments" error, terminating the simulation.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type FunctionCall
  OUTPUT: boolean
  
  RETURN input.functionName == 'updateCUSUM'
         AND input.argumentCount == 5
         AND input.arguments == [cusum, ekf, cfg, k, dt]
         AND expectedSignature(updateCUSUM).argumentCount == 4
END FUNCTION
```

### Examples

- **Baseline sweep scenario 1**: Simulation starts, reaches Phase 6 line 171, calls `updateCUSUM(cusum, ekf, cfg, k, dt)`, MATLAB throws error "Too many input arguments", simulation terminates with 0 rows generated
- **Baseline sweep scenario 24**: Same failure pattern - error at line 171, zero data generated
- **Any simulation run**: 100% failure rate at the same location with identical error message
- **Edge case - first timestep (k=1)**: Even during the first iteration when k=1, the error occurs before any CUSUM logic executes

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- CUSUM warmup period logic must continue to suppress alarms during the first N timesteps as designed
- Two-sided CUSUM algorithm (S_pos, S_neg tracking) must continue to detect anomalies correctly after warmup
- All other Phase 6 function calls (updateEKF, updatePLC, applyAttackEffects, etc.) must continue to receive correct arguments
- Historian data export and logging functionality must remain unchanged

**Scope:**
All function calls in runSimulation.m that do NOT involve updateCUSUM should be completely unaffected by this fix. This includes:
- updateEKF call on line 169
- updatePLC, applyAttackEffects, detectIncidents, and other Phase 6 functions
- Data logging and export operations
- Control logic and network state updates

## Hypothesized Root Cause

Based on the bug description and code analysis, the root cause is:

1. **Incorrect Argument Passing**: The developer passed the entire `ekf` struct as the second argument instead of extracting `ekf.residual`
   - updateCUSUM expects a scalar or Nx1 residual vector
   - The call passes the entire ekf struct containing xhat, P, residual, S, chi2_stat, etc.

2. **Extra Parameter**: The call includes `dt` as a 5th argument, but updateCUSUM does not use or expect a time-step parameter
   - The function signature has no dt parameter
   - CUSUM detection operates on residual magnitudes, not time deltas

3. **Incorrect Step Parameter Position**: The step counter `k` is passed as the 4th argument, but with dt also present, the argument positions are misaligned
   - With 5 arguments, k is in position 4 and dt is in position 5
   - The function expects step in position 4 (which would be correct if dt were removed)

## Correctness Properties

Property 1: Bug Condition - Correct updateCUSUM Function Call

_For any_ simulation timestep where updateCUSUM is invoked, the fixed runSimulation SHALL call updateCUSUM with exactly 4 arguments in the correct order: (cusum, ekf.residual, cfg, k), where ekf.residual is the 40×1 innovation vector and k is the integer step counter.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Preservation - Other Phase 6 Function Calls

_For any_ function call in runSimulation Phase 6 that is NOT updateCUSUM, the fixed code SHALL produce exactly the same function invocations with the same arguments as the original code, preserving all existing Phase 6 logic for EKF updates, PLC communication, attack effects, and data logging.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `runSimulation.m`

**Function**: Main simulation loop (Phase 6 section)

**Specific Changes**:
1. **Replace ekf with ekf.residual**: Change the second argument from the entire ekf struct to ekf.residual
   - Before: `cusum = updateCUSUM(cusum, ekf, cfg, k, dt);`
   - After: `cusum = updateCUSUM(cusum, ekf.residual, cfg, k);`

2. **Remove dt parameter**: Delete the 5th argument (dt) from the function call
   - updateCUSUM does not use time-step information
   - The function signature has only 4 parameters

3. **Verify k is the step counter**: Confirm that k is the correct 1-based integer step counter
   - k should increment from 1 to nSteps in the simulation loop
   - This matches the expected "step" parameter in updateCUSUM signature

4. **No changes to updateCUSUM.m**: The function signature is correct and should not be modified
   - Function expects: (cusum, residual, cfg, step)
   - This is the correct design for CUSUM detection

5. **No changes to updateEKF.m**: The ekf.residual field is correctly populated
   - updateEKF stores the innovation vector in ekf.residual (line 73)
   - This is a 40×1 vector suitable for CUSUM processing

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code (confirming the error occurs), then verify the fix works correctly and preserves existing behavior.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm that the "Too many input arguments" error occurs at line 171 when updateCUSUM is called with 5 arguments.

**Test Plan**: Write a minimal test that simulates the Phase 6 execution path up to the updateCUSUM call. Use a mock or minimal configuration to reach line 171. Run this test on the UNFIXED code to observe the error and confirm the root cause.

**Test Cases**:
1. **Minimal Simulation Test**: Create a minimal runSimulation call with cfg.nSteps=1, observe error at line 171 (will fail on unfixed code)
2. **Argument Count Inspection**: Use MATLAB debugger or try-catch to capture the exact error message "Too many input arguments" (will fail on unfixed code)
3. **Function Signature Verification**: Inspect updateCUSUM.m signature to confirm it expects 4 arguments, not 5 (static verification)
4. **EKF Residual Availability**: Verify that ekf.residual exists and is a 40×1 vector after updateEKF call (should pass - confirms residual is available)

**Expected Counterexamples**:
- Error message: "Error using updateCUSUM - Too many input arguments"
- Error location: runSimulation.m line 171
- Possible causes: incorrect argument count (5 instead of 4), passing ekf instead of ekf.residual, including extraneous dt parameter

### Fix Checking

**Goal**: Verify that for all simulation timesteps where updateCUSUM is called, the fixed function call uses exactly 4 arguments in the correct format.

**Pseudocode:**
```
FOR ALL timestep k IN [1, nSteps] DO
  result := runSimulation_fixed(cfg)
  ASSERT updateCUSUM was called with 4 arguments
  ASSERT argument_2 is ekf.residual (40×1 vector)
  ASSERT argument_4 is k (integer step counter)
  ASSERT no MATLAB error occurs
END FOR
```

### Preservation Checking

**Goal**: Verify that for all function calls in Phase 6 that are NOT updateCUSUM, the fixed code produces the same function invocations as the original code.

**Pseudocode:**
```
FOR ALL function_call IN Phase6_functions WHERE function_call.name != 'updateCUSUM' DO
  ASSERT runSimulation_original(cfg).function_call == runSimulation_fixed(cfg).function_call
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across different simulation configurations
- It catches edge cases that manual unit tests might miss (e.g., different nSteps, attack schedules, network topologies)
- It provides strong guarantees that behavior is unchanged for all non-updateCUSUM function calls

**Test Plan**: Observe behavior on UNFIXED code first for other Phase 6 functions (updateEKF, updatePLC, etc.), then write property-based tests capturing that those function calls remain identical after the fix.

**Test Cases**:
1. **updateEKF Preservation**: Verify updateEKF is called with (ekf, plc.reg_p, plc.reg_q, state.p, state.q, params, cfg) before and after fix
2. **CUSUM Warmup Preservation**: Verify that CUSUM warmup logic (first N steps) continues to suppress alarms correctly
3. **CUSUM Detection Preservation**: Verify that CUSUM detection after warmup continues to trigger alarms correctly for anomalous residuals
4. **Historian Logging Preservation**: Verify that historian data export produces the same number of rows and columns after fix

### Unit Tests

- Test that updateCUSUM is called with exactly 4 arguments in a minimal simulation
- Test that ekf.residual is correctly extracted and passed (verify it's a 40×1 vector)
- Test that k (step counter) is correctly passed as the 4th argument
- Test that no "Too many input arguments" error occurs after fix

### Property-Based Tests

- Generate random simulation configurations (varying nSteps, dt, network sizes) and verify updateCUSUM is always called with 4 arguments
- Generate random EKF states and verify ekf.residual is always extracted correctly
- Test that CUSUM detection behavior (warmup, alarm triggering) is preserved across many scenarios

### Integration Tests

- Run a full baseline sweep scenario (24 hours) and verify it completes without error
- Verify that the expected number of historian rows are generated (nSteps rows)
- Verify that CUSUM alarms are logged correctly in the event log
- Compare output datasets before and after fix to ensure preservation of non-CUSUM behavior
