# Bugfix Requirements Document

## Introduction

This document specifies the fix for the "Too many input arguments" error that occurs in runSimulation Phase 6, causing 100% failure rate across all simulation scenarios in the 24-hour baseline sweep. The error originates from an incorrect function call to `updateCUSUM` that passes 5 arguments when the function signature expects only 4 arguments.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN runSimulation Phase 6 executes the main simulation loop THEN the system crashes with "Too many input arguments" error at the updateCUSUM call

1.2 WHEN any baseline sweep scenario is executed THEN the system fails immediately after logging "Phase 6 start" with zero simulation data generated

1.3 WHEN updateCUSUM is called with 5 arguments (cusum, ekf, cfg, k, dt) THEN MATLAB throws "Too many input arguments" error because the function signature expects 4 arguments

### Expected Behavior (Correct)

2.1 WHEN runSimulation Phase 6 executes the main simulation loop THEN the system SHALL call updateCUSUM with exactly 4 arguments matching the function signature (cusum, residual, cfg, step)

2.2 WHEN any baseline sweep scenario is executed THEN the system SHALL complete the simulation successfully and generate the expected dataset rows

2.3 WHEN updateCUSUM is called THEN the system SHALL pass the EKF residual (not the entire ekf struct) as the second argument and SHALL NOT pass the dt parameter

### Unchanged Behavior (Regression Prevention)

3.1 WHEN updateCUSUM processes residuals during the warmup period THEN the system SHALL CONTINUE TO suppress alarms as designed

3.2 WHEN updateCUSUM detects anomalies after the warmup period THEN the system SHALL CONTINUE TO trigger alarms correctly using the two-sided CUSUM algorithm

3.3 WHEN other Phase 6 functions (updateEKF, updatePLC, applyAttackEffects, etc.) are called THEN the system SHALL CONTINUE TO receive the correct number and type of arguments

3.4 WHEN the simulation completes successfully THEN the system SHALL CONTINUE TO export historian data and log files as expected
