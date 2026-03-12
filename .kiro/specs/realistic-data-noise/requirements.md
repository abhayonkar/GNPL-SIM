# Requirements Document

## Introduction

This document specifies requirements for adding realistic noise and variation to the natural gas pipeline simulation system. Currently, simulation parameters (pressure, temperature, flow, density) remain constant over time, producing unrealistic datasets. This feature will introduce physically-motivated noise models to create realistic time-varying data that better represents actual pipeline behavior.

## Glossary

- **Simulation_System**: The MATLAB-based natural gas pipeline CPS simulator that generates datasets
- **Physics_Noise_Module**: Component responsible for applying realistic variations to physical parameters
- **Sensor_Noise**: Random measurement errors added to sensor readings
- **Process_Noise**: Natural variations in physical processes (turbulence, thermal fluctuations, composition drift)
- **Temporal_Correlation**: Statistical dependency between consecutive time steps (AR models)
- **Configuration_Parameter**: User-adjustable setting in simConfig.m that controls noise characteristics
- **Dataset_Exporter**: The exportDataset.m module that writes CSV files
- **Steady_State**: Condition where parameters remain constant over time without variation

## Requirements

### Requirement 1: Pressure Variation

**User Story:** As a simulation user, I want pressure readings to vary realistically over time, so that the dataset reflects actual pipeline pressure dynamics.

#### Acceptance Criteria

1. WHEN the Simulation_System updates pressure, THE Physics_Noise_Module SHALL apply acoustic micro-oscillations to each node pressure value
2. THE Physics_Noise_Module SHALL use temporally correlated noise with autocorrelation coefficient between 0.80 and 0.95 for pressure variations
3. THE Physics_Noise_Module SHALL apply pressure noise with standard deviation between 0.001 and 0.005 bar
4. WHEN pressure noise is applied, THE Simulation_System SHALL preserve mass balance constraints across the network
5. FOR ALL simulation timesteps, pressure values SHALL remain within physically valid bounds (0.1 bar to 15 bar)

### Requirement 2: Flow Rate Variation

**User Story:** As a simulation user, I want flow rate measurements to exhibit turbulent fluctuations, so that the data captures realistic pipeline flow behavior.

#### Acceptance Criteria

1. WHEN the Simulation_System updates flow rates, THE Physics_Noise_Module SHALL apply turbulent noise to each edge flow value
2. THE Physics_Noise_Module SHALL model flow turbulence using AR(1) process with correlation coefficient between 0.85 and 0.95
3. THE Physics_Noise_Module SHALL apply fractional flow noise with standard deviation between 0.005 and 0.015 (0.5% to 1.5%)
4. WHEN flow is near zero, THE Physics_Noise_Module SHALL scale noise amplitude proportionally to avoid negative flow values
5. THE Physics_Noise_Module SHALL maintain independent turbulence states for each pipeline edge

### Requirement 3: Temperature Variation

**User Story:** As a simulation user, I want temperature readings to vary due to thermal processes, so that the dataset reflects realistic thermal dynamics.

#### Acceptance Criteria

1. WHEN the Simulation_System updates temperature, THE Physics_Noise_Module SHALL apply Joule-Thomson cooling effects based on pressure changes
2. THE Physics_Noise_Module SHALL apply turbulent thermal mixing noise with standard deviation between 0.03 K and 0.10 K
3. THE Physics_Noise_Module SHALL use temporally correlated thermal noise with autocorrelation coefficient between 0.80 and 0.90
4. FOR ALL nodes, temperature values SHALL remain within physically valid bounds (250 K to 320 K)
5. WHEN pressure drops occur, THE Physics_Noise_Module SHALL apply cooling proportional to the pressure drop magnitude

### Requirement 4: Density Variation

**User Story:** As a simulation user, I want density values to vary due to gas composition changes, so that the dataset reflects realistic gas property variations.

#### Acceptance Criteria

1. WHEN the Simulation_System updates density, THE Physics_Noise_Module SHALL apply composition drift noise
2. THE Physics_Noise_Module SHALL model composition drift using AR(1) process with correlation coefficient greater than 0.995
3. THE Physics_Noise_Module SHALL apply fractional density noise with standard deviation between 0.002 and 0.006 (0.2% to 0.6%)
4. THE Physics_Noise_Module SHALL compute density variations consistent with pressure and temperature via real-gas equations
5. FOR ALL nodes, density values SHALL remain positive and within physically valid bounds (0.01 to 2.0 relative units)

### Requirement 5: Compressor Dynamics Variation

**User Story:** As a simulation user, I want compressor parameters to exhibit realistic mechanical variations, so that the dataset captures actual compressor behavior.

#### Acceptance Criteria

1. WHEN the Simulation_System updates compressor state, THE Physics_Noise_Module SHALL apply shaft pulsation noise to compression ratio
2. THE Physics_Noise_Module SHALL model shaft pulsation at frequency between 1.5 Hz and 3.0 Hz
3. THE Physics_Noise_Module SHALL apply compression ratio noise with standard deviation between 0.005 and 0.015 (0.5% to 1.5%)
4. THE Physics_Noise_Module SHALL apply stochastic surge margin noise with standard deviation between 0.003 and 0.010
5. WHEN compressor is active, THE Physics_Noise_Module SHALL ensure compression ratio remains within operational bounds (1.10 to 2.00)

### Requirement 6: Pipe Roughness Drift

**User Story:** As a simulation user, I want pipe roughness to drift slowly over time, so that the dataset reflects wall fouling and erosion effects.

#### Acceptance Criteria

1. WHEN the Simulation_System updates pipe properties, THE Physics_Noise_Module SHALL apply roughness drift to each edge
2. THE Physics_Noise_Module SHALL model roughness drift using AR(1) process with correlation coefficient greater than 0.999
3. THE Physics_Noise_Module SHALL apply fractional roughness noise with standard deviation between 0.05 and 0.15 (5% to 15%)
4. FOR ALL edges, roughness values SHALL remain positive and greater than 1e-6 meters
5. THE Physics_Noise_Module SHALL maintain independent roughness drift states for each pipeline edge

### Requirement 7: Configuration Management

**User Story:** As a simulation developer, I want to configure noise parameters centrally, so that I can easily adjust noise characteristics without modifying multiple files.

#### Acceptance Criteria

1. THE Configuration_Parameter values for all noise models SHALL be defined in simConfig.m
2. WHEN a Configuration_Parameter is modified, THE Simulation_System SHALL use the updated value in subsequent simulation runs
3. THE Configuration_Parameter structure SHALL include amplitude, correlation, and frequency parameters for each noise type
4. THE Configuration_Parameter values SHALL have descriptive comments explaining physical meaning and typical ranges
5. WHERE noise is disabled for testing, THE Configuration_Parameter SHALL support zero amplitude values

### Requirement 8: Noise State Persistence

**User Story:** As a simulation developer, I want noise states to persist across timesteps, so that temporal correlations are maintained throughout the simulation.

#### Acceptance Criteria

1. WHEN the Simulation_System initializes, THE Physics_Noise_Module SHALL create persistent state variables for all AR processes
2. WHEN the Simulation_System advances one timestep, THE Physics_Noise_Module SHALL update all noise states before applying to physical variables
3. THE Physics_Noise_Module SHALL maintain separate state vectors for flow turbulence, acoustic pressure, thermal noise, and composition drift
4. FOR ALL AR(1) processes, THE Physics_Noise_Module SHALL compute stationary variance using formula: sigma_stationary = sigma_innovation / sqrt(1 - alpha^2)
5. WHEN simulation completes, THE Physics_Noise_Module SHALL not persist noise states to disk (each run starts fresh)

### Requirement 9: Sensor Noise Enhancement

**User Story:** As a simulation user, I want sensor noise to be proportional to measured values, so that the dataset reflects realistic measurement uncertainty.

#### Acceptance Criteria

1. WHEN the Simulation_System reads sensors, THE Physics_Noise_Module SHALL apply multiplicative noise proportional to the measured value
2. THE Physics_Noise_Module SHALL apply sensor noise with fractional standard deviation between 0.0005 and 0.002 (0.05% to 0.2%)
3. THE Physics_Noise_Module SHALL apply independent noise samples to each sensor at each timestep
4. WHEN sensor values are near zero, THE Physics_Noise_Module SHALL add minimum absolute noise floor of 0.0001 units
5. THE Physics_Noise_Module SHALL apply sensor noise after process noise but before attack effects

### Requirement 10: Dataset Export Verification

**User Story:** As a simulation user, I want to verify that exported datasets contain realistic variations, so that I can confirm the noise models are working correctly.

#### Acceptance Criteria

1. WHEN the Dataset_Exporter writes CSV files, THE exported data SHALL contain time-varying values for all physical parameters
2. FOR ALL pressure columns in exported CSV, THE standard deviation SHALL be greater than 0.001 bar during normal operation
3. FOR ALL flow columns in exported CSV, THE coefficient of variation SHALL be greater than 0.005 during normal operation
4. FOR ALL temperature columns in exported CSV, THE standard deviation SHALL be greater than 0.03 K during normal operation
5. THE Dataset_Exporter SHALL not apply additional noise beyond what the Physics_Noise_Module provides

### Requirement 11: Attack Scenario Compatibility

**User Story:** As a simulation user, I want noise models to remain active during attack scenarios, so that attack detection algorithms must distinguish attacks from normal variations.

#### Acceptance Criteria

1. WHEN an attack is active, THE Physics_Noise_Module SHALL continue applying all noise models
2. WHEN attack effects modify parameters, THE Physics_Noise_Module SHALL apply noise after attack modifications
3. THE Physics_Noise_Module SHALL not modify attack-specific parameters defined in attack configuration
4. FOR ALL attack scenarios, THE noise amplitude SHALL remain consistent with normal operation periods
5. WHEN comparing attack vs normal data, THE noise characteristics SHALL be statistically indistinguishable

### Requirement 12: Numerical Stability

**User Story:** As a simulation developer, I want noise models to maintain numerical stability, so that simulations complete successfully without errors.

#### Acceptance Criteria

1. WHEN the Physics_Noise_Module applies noise, THE Simulation_System SHALL not produce NaN or Inf values
2. WHEN AR(1) correlation coefficients are configured, THE Physics_Noise_Module SHALL verify values are between 0 and 1
3. WHEN noise amplitudes are configured, THE Physics_Noise_Module SHALL verify values are non-negative
4. IF a physical constraint is violated after noise application, THE Physics_Noise_Module SHALL clamp values to valid bounds
5. THE Physics_Noise_Module SHALL use MATLAB's randn function for Gaussian noise generation with implicit seeding
