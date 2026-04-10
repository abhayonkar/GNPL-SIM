# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Too Many Input Arguments Error
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: For this deterministic bug, scope the property to the concrete failing case at line 171 to ensure reproducibility
  - Test that runSimulation Phase 6 calls updateCUSUM with exactly 4 arguments (cusum, ekf.residual, cfg, k)
  - Test that the second argument is ekf.residual (40×1 vector), not the entire ekf struct
  - Test that no dt parameter is passed as a 5th argument
  - Create a minimal simulation configuration (cfg.nSteps=1) to reach line 171
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS with "Too many input arguments" error at line 171 (this is correct - it proves the bug exists)
  - Document counterexamples found: error message, error location, argument count mismatch
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Other Phase 6 Function Calls
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-updateCUSUM function calls in Phase 6
  - Verify updateEKF is called with (ekf, plc.reg_p, plc.reg_q, state.p, state.q, params, cfg)
  - Verify other Phase 6 functions (updatePLC, applyAttackEffects, detectIncidents) receive correct arguments
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code (skip the updateCUSUM call to avoid the error, or use try-catch)
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [ ] 3. Fix for updateCUSUM argument mismatch

  - [x] 3.1 Implement the fix in runSimulation.m line 171
    - Change second argument from ekf to ekf.residual
    - Remove the 5th argument (dt)
    - Verify k is the correct step counter (4th argument)
    - Change: `cusum = updateCUSUM(cusum, ekf, cfg, k, dt);`
    - To: `cusum = updateCUSUM(cusum, ekf.residual, cfg, k);`
    - _Bug_Condition: isBugCondition(input) where input.functionName == 'updateCUSUM' AND input.argumentCount == 5_
    - _Expected_Behavior: updateCUSUM called with exactly 4 arguments (cusum, ekf.residual, cfg, k) matching function signature_
    - _Preservation: All other Phase 6 function calls (updateEKF, updatePLC, etc.) remain unchanged_
    - _Requirements: 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4_

  - [x] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Correct updateCUSUM Function Call
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - Verify no "Too many input arguments" error occurs
    - Verify updateCUSUM is called with 4 arguments
    - Verify ekf.residual is correctly extracted and passed
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Other Phase 6 Function Calls
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm updateEKF and other Phase 6 functions still receive correct arguments
    - Confirm CUSUM warmup and detection logic still works correctly
    - Confirm all tests still pass after fix (no regressions)

- [x] 4. Checkpoint - Ensure all tests pass
  - Run all tests (bug condition + preservation)
  - Verify simulation completes successfully with the fix
  - Verify expected number of historian rows are generated
  - Ask the user if questions arise
