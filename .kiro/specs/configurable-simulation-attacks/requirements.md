# Requirements Document

## Introduction

This feature enables users to configure simulation time and attack scheduling parameters instead of using hardcoded values. Currently, simulation time is fixed at 300 minutes and exactly 8 attacks are always scheduled. This feature allows users to specify custom simulation durations and select which attacks (single or multiple) should be included in the simulation, with attacks scheduled randomly within the configured time window.

## Glossary

- **Simulation_System**: The MATLAB-based gas pipeline simulation framework that models physical behavior and attack scenarios
- **Attack_Scheduler**: The component (initAttackSchedule.m) responsible for placing attacks randomly within the simulation timeline
- **Configuration_Module**: The component (simConfig.m) that provides simulation parameters
- **Attack_Type**: One of 8 predefined attack scenarios (SrcPressureManipulation, CompressorRatioSpoofing, ValveCommandTampering, DemandNodeManipulation, PressureSensorSpoofing, FlowMeterSpoofing, PLCLatencyAttack, PipelineLeak)
- **Simulation_Duration**: Total time span of the simulation in minutes
- **Attack_Selection**: User-specified list of Attack_Types to include in the simulation
- **Valid_Attack_ID**: Integer identifier from 1 to 8 corresponding to an Attack_Type

## Requirements

### Requirement 1: Configurable Simulation Duration

**User Story:** As a researcher, I want to specify custom simulation durations, so that I can generate datasets of varying lengths for different experimental scenarios.

#### Acceptance Criteria

1. THE Configuration_Module SHALL accept a Simulation_Duration parameter in minutes
2. WHEN Simulation_Duration is provided, THE Configuration_Module SHALL use the provided value instead of the hardcoded 300 minutes
3. THE Configuration_Module SHALL validate that Simulation_Duration is greater than 10 minutes
4. THE Configuration_Module SHALL validate that Simulation_Duration is less than 10000 minutes
5. IF Simulation_Duration is outside valid range, THEN THE Configuration_Module SHALL return an error message indicating the valid range
6. WHERE Simulation_Duration is not provided, THE Configuration_Module SHALL use 300 minutes as the default value

### Requirement 2: Configurable Attack Selection

**User Story:** As a security analyst, I want to specify which attacks to include in the simulation, so that I can focus on specific attack scenarios or test single attack types in isolation.

#### Acceptance Criteria

1. THE Attack_Scheduler SHALL accept an Attack_Selection parameter containing one or more Valid_Attack_IDs
2. WHEN Attack_Selection contains a single Valid_Attack_ID, THE Attack_Scheduler SHALL schedule only that attack type
3. WHEN Attack_Selection contains multiple Valid_Attack_IDs, THE Attack_Scheduler SHALL schedule all specified attack types
4. THE Attack_Scheduler SHALL validate that all values in Attack_Selection are Valid_Attack_IDs
5. IF Attack_Selection contains an invalid identifier, THEN THE Attack_Scheduler SHALL return an error message listing the valid identifiers
6. WHERE Attack_Selection is not provided, THE Attack_Scheduler SHALL schedule all 8 attack types as default behavior

### Requirement 3: Random Attack Placement

**User Story:** As a data scientist, I want attacks to be placed randomly within the simulation timeline, so that I can generate diverse training datasets without temporal bias.

#### Acceptance Criteria

1. WHEN Attack_Selection is provided, THE Attack_Scheduler SHALL place selected attacks at random times within the simulation window
2. THE Attack_Scheduler SHALL ensure no two attacks overlap in time
3. THE Attack_Scheduler SHALL maintain minimum gap of 5 minutes between consecutive attacks
4. THE Attack_Scheduler SHALL place first attack no earlier than 5 minutes after simulation start
5. THE Attack_Scheduler SHALL ensure last attack ends at least 5 minutes before simulation end
6. THE Attack_Scheduler SHALL randomize the order of attacks so they do not appear in sequential ID order
7. THE Attack_Scheduler SHALL assign random durations to each attack within the configured range of 270 to 405 seconds

### Requirement 4: Attack Scheduling Validation

**User Story:** As a simulation operator, I want the system to validate that selected attacks can fit within the simulation duration, so that I receive clear feedback when my configuration is infeasible.

#### Acceptance Criteria

1. WHEN Attack_Selection and Simulation_Duration are provided, THE Attack_Scheduler SHALL calculate whether all selected attacks can fit within the available time window
2. THE Attack_Scheduler SHALL account for warmup time, recovery time, minimum gaps, and attack durations in feasibility calculation
3. IF selected attacks cannot fit within Simulation_Duration, THEN THE Attack_Scheduler SHALL return an error message indicating the minimum required simulation time
4. THE Attack_Scheduler SHALL attempt up to 1000 random placements before declaring the configuration infeasible
5. WHEN attack placement succeeds, THE Attack_Scheduler SHALL log the placement details including attack IDs, start times, and durations

### Requirement 5: Configuration Interface

**User Story:** As a developer, I want a clear interface for passing simulation and attack parameters, so that I can easily integrate this feature into existing workflows.

#### Acceptance Criteria

1. THE Configuration_Module SHALL accept Simulation_Duration as an optional parameter in the configuration structure
2. THE Configuration_Module SHALL accept Attack_Selection as an optional parameter in the configuration structure
3. WHEN parameters are provided via configuration structure, THE Simulation_System SHALL use those values throughout the simulation
4. THE Configuration_Module SHALL document the parameter format and valid ranges in function comments
5. THE Configuration_Module SHALL preserve all existing configuration parameters and default behaviors when new parameters are not provided

### Requirement 6: Backward Compatibility

**User Story:** As an existing user, I want my current simulation scripts to continue working without modification, so that I can adopt the new feature incrementally.

#### Acceptance Criteria

1. WHEN neither Simulation_Duration nor Attack_Selection are provided, THE Simulation_System SHALL execute with the original hardcoded values (300 minutes, 8 attacks)
2. THE Simulation_System SHALL maintain identical output format and structure regardless of whether custom parameters are used
3. THE Simulation_System SHALL preserve all existing attack scheduling rules including warmup, recovery, gaps, and duration ranges
4. FOR ALL valid configurations, THE Simulation_System SHALL produce output files with the same schema as the original implementation
