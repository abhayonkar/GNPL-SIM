function cfg = simConfig()
% simConfig  Single source of truth for all simulation parameters.
%
%  20-Node GasLib-inspired network:
%    2 sources (S1, S2)
%    2 compressor stations (CS1 at node 3, CS2 at node 7)
%    7 junctions (J1-J7)
%    2 pressure regulating stations (PRS1, PRS2)
%    1 underground storage cavern (STO)
%    6 demand nodes (D1-D6)
%    1 loop (STO->J5 closes the network)
%
%  Sections:
%    1.Time  2.Topology  3.Pipes  4.InitState  5.Compressors
%    6.PRS   7.Storage   8.EKF   9.PLC  10.PID  11.Noise
%    12.Alarms  13.SourceProfile  14.AttackSchedule  15.AttackParams

    %% 1. Time
    cfg.dt = 0.1;           % simulation time step (s)
    cfg.T  = 300 * 60;      % total simulation time (300 min default)

    %% 2. Network topology -------------------------------------------------
    cfg.nodeNames = ["S1","J1","CS1","J2","J3","J4","CS2","J5", ...
                     "J6","PRS1","J7","STO","PRS2","S2", ...
                     "D1","D2","D3","D4","D5","D6"];

    cfg.nodeTypes = ["source","junction","compressor","junction", ...
                     "junction","junction","compressor","junction", ...
                     "junction","prs","junction","storage","prs","source", ...
                     "demand","demand","demand","demand","demand","demand"];

    % Edge list [from_node, to_node]
    cfg.edges = [
         1  2;   % E1:  S1   -> J1    main trunk in
         2  3;   % E2:  J1   -> CS1   into compressor 1
         3  4;   % E3:  CS1  -> J2    out of compressor 1
         4  5;   % E4:  J2   -> J3    main trunk
         5  6;   % E5:  J3   -> J4    main trunk
         6  7;   % E6:  J4   -> CS2   into compressor 2
         7  8;   % E7:  CS2  -> J5    out of compressor 2
         4  9;   % E8:  J2   -> J6    upper branch
         9 10;   % E9:  J6   -> PRS1  upper branch regulator
        10 15;   % E10: PRS1 -> D1    demand node 1
        10 16;   % E11: PRS1 -> D2    demand node 2
         5 11;   % E12: J3   -> J7    storage branch
        14 11;   % E13: S2   -> J7    second source injection
        11 12;   % E14: J7   -> STO   into storage
        12  8;   % E15: STO  -> J5    storage loop closure
         8 13;   % E16: J5   -> PRS2  lower branch regulator
        13 17;   % E17: PRS2 -> D3    demand node 3
        13 18;   % E18: PRS2 -> D4    demand node 4
         6 19;   % E19: J4   -> D5    mid-trunk demand
        11 20;   % E20: J7   -> D6    storage branch demand
    ];

    cfg.edgeNames = ["E1","E2","E3","E4","E5","E6","E7","E8","E9","E10", ...
                     "E11","E12","E13","E14","E15","E16","E17","E18","E19","E20"];

    % Valve edges (controllable isolation valves)
    cfg.valveEdges = [8, 14, 15];   % E8 (upper branch), E14 (to storage), E15 (from storage)

    % Node elevation profile (metres above sea level)
    % Realistic: sources upland, demand nodes lowland
    cfg.nodeElevation = [120, 100, 80, 70, 60, 50, 45, 35, ...
                          90,  85, 55, 20, 25, 75, ...
                          80,  75, 20, 15, 40, 50];  % 20 values

    %% 3. Pipe physical properties
    cfg.pipe_D     = 0.8;      % diameter (m) - same for all edges (can be vector)
    cfg.pipe_L     = 40e3;     % length (m) per edge
    cfg.pipe_rough = 20e-6;    % absolute roughness (m)
    cfg.node_V     = 6;        % nodal volume (m^3)
    cfg.c          = 350;      % acoustic speed (m/s)
    cfg.gamma      = 1.3;      % heat capacity ratio (natural gas)

    % Per-edge pipe lengths (m) - varies by branch
    cfg.pipe_L_vec = [50e3, 5e3, 5e3, 45e3, 45e3, 5e3, 5e3, ...
                      30e3, 30e3, 20e3, 20e3, ...
                      35e3, 40e3, 10e3, 10e3, ...
                      5e3, 25e3, 25e3, 15e3, 20e3];   % 20 values

    % Per-edge diameters (m) - main trunk wider than branches
    cfg.pipe_D_vec = [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, ...  % main trunk
                      0.6, 0.6, 0.5, 0.5, ...                   % upper branch
                      0.6, 0.7, 0.5, 0.5, ...                   % storage branch
                      0.7, 0.5, 0.5, 0.4, 0.4];                 % lower + demand

    %% 4. Initial state
    cfg.p0   = 50.0;   % bar  (transmission pressure)
    cfg.T0   = 285;    % K    (ground temperature)
    cfg.rho0 = 0.8;    % relative density reference

    %% 5. Compressor stations
    % CS1 (node 3) - primary station
    cfg.comp1_node      = 3;
    cfg.comp1_ratio     = 1.25;
    cfg.comp1_ratio_min = 1.05;
    cfg.comp1_ratio_max = 1.80;
    cfg.comp1_a1 =  800;  cfg.comp1_a2 = -0.8;   cfg.comp1_a3 = -0.002;
    cfg.comp1_b1 = 0.82;  cfg.comp1_b2 = -0.002; cfg.comp1_b3 = -0.0001;

    % CS2 (node 7) - secondary station (lower ratio, boost before distribution)
    cfg.comp2_node      = 7;
    cfg.comp2_ratio     = 1.15;
    cfg.comp2_ratio_min = 1.02;
    cfg.comp2_ratio_max = 1.60;
    cfg.comp2_a1 =  500;  cfg.comp2_a2 = -0.5;   cfg.comp2_a3 = -0.001;
    cfg.comp2_b1 = 0.80;  cfg.comp2_b2 = -0.002; cfg.comp2_b3 = -0.0001;

    % Shared compressor noise params
    cfg.comp_pulsation_amp  = 0.008;   % ratio jitter amplitude
    cfg.comp_pulsation_freq = 2.0;     % Hz blade-pass
    cfg.comp_surge_noise    = 0.005;   % surge margin std
    cfg.comp_surge_corr     = 0.92;    % AR(1) surge correlation

    %% 6. Pressure Regulating Stations
    % PRS1 (node 10) - upper branch, steps from ~50bar to ~30bar
    cfg.prs1_node          = 10;
    cfg.prs1_setpoint      = 30.0;   % bar downstream target
    cfg.prs1_deadband      = 0.5;    % bar deadband
    cfg.prs1_tau           = 5.0;    % s response time constant

    % PRS2 (node 13) - lower branch, steps from ~45bar to ~25bar
    cfg.prs2_node          = 13;
    cfg.prs2_setpoint      = 25.0;   % bar downstream target
    cfg.prs2_deadband      = 0.5;    % bar deadband
    cfg.prs2_tau           = 5.0;    % s response time constant

    %% 7. Underground Storage
    cfg.sto_node           = 12;
    cfg.sto_capacity       = 1e9;    % m^3 (normalized; working inventory)
    cfg.sto_inventory_init = 0.60;   % fraction of capacity (60% initially)
    cfg.sto_p_inject       = 52.0;   % bar - inject when network p > this
    cfg.sto_p_withdraw     = 46.0;   % bar - withdraw when network p < this
    cfg.sto_max_flow       = 5.0;    % kg/s max inject/withdraw rate
    cfg.sto_k_flow         = 0.5;    % flow coefficient (kg/s per bar)

    %% 8. EKF
    cfg.ekf_P0 = 0.1;    % initial covariance
    cfg.ekf_Qn = 1e-4;   % process noise
    cfg.ekf_Rk = 0.1;    % measurement noise

    %% 9. PLC / SCADA
    % Zone-based: Zone1=compressors, Zone2=distribution, Zone3=storage
    cfg.plc_period_z1  = 10;   % steps between polls (compressor zone)
    cfg.plc_period_z2  = 15;   % distribution zone (slightly slower)
    cfg.plc_period_z3  = 20;   % storage zone (slowest)
    cfg.plc_latency    = 3;    % actuator command delay steps

    % Legacy single-plc compatibility
    cfg.plc_period = cfg.plc_period_z1;

    %% 10. Control (PID) - per zone
    % Zone 1: CS1 pressure control (target D1/D2 pressure)
    cfg.pid1_Kp       = 0.4;
    cfg.pid1_Ki       = 0.008;
    cfg.pid1_Kd       = 0.08;
    cfg.pid1_setpoint = 30.0;   % bar at PRS1 downstream

    % Zone 2: CS2 + valve control
    cfg.pid2_Kp       = 0.3;
    cfg.pid2_Ki       = 0.005;
    cfg.pid2_Kd       = 0.05;
    cfg.pid2_setpoint = 25.0;   % bar at PRS2 downstream

    % Control node indices
    cfg.pid_D1_node   = 15;    % D1 pressure feedback for CS1 PID
    cfg.pid_D3_node   = 17;    % D3 pressure feedback for CS2 PID
    cfg.pid_PRS1_node = 10;    % PRS1 node
    cfg.pid_PRS2_node = 13;    % PRS2 node

    % Safety
    cfg.emer_shutdown_p = 65.0;  % bar MAOP emergency shutdown
    cfg.alarm_P_high    = 60.0;  % bar high pressure alarm
    cfg.alarm_P_low     = 15.0;  % bar low pressure alarm
    cfg.alarm_ekf_resid = 2.0;   % bar EKF residual alarm
    cfg.alarm_comp_hi   = 1.75;  % compressor ratio ceiling alarm
    cfg.valve_close_hi  = 52.0;  % bar - close valve
    cfg.valve_open_lo   = 44.0;  % bar - open valve

    %% 11. Physics noise (prevents flat steady-state)
    cfg.sensor_noise       = 0.001;    % fractional std (0.1%)
    cfg.sensor_noise_floor = 0.0001;   % absolute noise floor

    % Acoustic pressure micro-oscillations AR(1)
    cfg.p_acoustic_std  = 0.005;  % bar (larger network = more wave energy)
    cfg.p_acoustic_corr = 0.88;

    % Flow turbulence AR(1) per edge
    cfg.flow_turb_std  = 0.008;
    cfg.flow_turb_corr = 0.90;

    % Roughness drift AR(1) per edge
    cfg.rough_var_std  = 0.10;
    cfg.rough_corr     = 0.9995;

    % Joule-Thomson + thermal AR(1) per node
    cfg.T_jt_coeff  = -0.45;   % K/bar
    cfg.T_turb_std  = 0.05;    % K
    cfg.T_turb_corr = 0.88;

    % Gas composition drift AR(1)
    cfg.rho_comp_std  = 0.004;
    cfg.rho_comp_corr = 0.9998;

    %% 12. Source profiles
    cfg.src_slow_amp   = 3.0;    % bar (larger network, larger amplitude)
    cfg.src_med_amp    = 1.5;
    cfg.src_fast_amp   = 0.5;
    cfg.src_trend      = 1.0;
    cfg.src_rw_amp     = 1.5;
    cfg.src_ar1_alpha  = 0.997;
    cfg.src_p_min      = 45.0;   % bar
    cfg.src_p_max      = 58.0;   % bar

    % S2 (second source) slightly lower pressure
    cfg.src2_p_min     = 42.0;
    cfg.src2_p_max     = 55.0;

    % Diurnal demand profile
    cfg.dem_base       = 0.60;    % base demand scalar
    cfg.dem_diurnal_amp = 0.25;   % amplitude of daily cycle
    cfg.dem_diurnal_period = 86400; % s (24 hours)
    cfg.dem_morning_peak = 7.0;   % hour of morning peak
    cfg.dem_evening_peak = 18.0;  % hour of evening peak
    cfg.dem_noise_std  = 0.02;
    cfg.dem_min        = 0.10;
    cfg.dem_max        = 1.20;

    %% 13. Attack scheduling (randomised)
    cfg.atk_warmup_s   = 10 * 60;   % 10 min warmup
    cfg.atk_recovery_s =  5 * 60;   % 5 min recovery tail
    cfg.atk_min_gap_s  =  5 * 60;   % 5 min minimum gap
    cfg.atk_dur_min_s  = 180;        % 3 min shortest attack
    cfg.atk_dur_max_s  = 480;        % 8 min longest attack

    %% 14. Attack effect parameters
    % A1 Source Pressure Manipulation (T0831)
    cfg.atk1_spike_amp = 1.30;
    cfg.atk1_osc_freq  = 1/120;

    % A2 Compressor Ratio Spoofing (T0838) - targets CS1
    cfg.atk2_target_ratio = 1.70;
    cfg.atk2_ramp_time    = 90;    % s

    % A3 Valve Command Tampering (T0855) - targets upper branch valve (E8)
    cfg.atk3_cmd       = 0;
    cfg.atk3_valve_idx = 1;        % index into cfg.valveEdges

    % A4 Demand Node Manipulation (T0829)
    cfg.atk4_demand_scale = 2.5;
    cfg.atk4_ramp_time    = 60;

    % A5 Pressure Sensor Spoofing (T0831) - J2 (node 4)
    cfg.atk5_target_node = 4;
    cfg.atk5_bias_bar    = -8.0;   % bar (larger for 50 bar network)

    % A6 Flow Meter Spoofing (T0827) - E4, E5
    cfg.atk6_edges = [4, 5];
    cfg.atk6_scale = 0.40;

    % A7 PLC Latency/DoS (T0814)
    cfg.atk7_extra_latency = 50;

    % A8 Pipeline Leak (T0829) - E12 (storage branch)
    cfg.atk8_edge      = 12;
    cfg.atk8_leak_frac = 0.45;
    cfg.atk8_ramp_time = 60;

    % A9 False Data Injection (computeFDIVector)
    cfg.atk9_target_nodes = [4, 5, 8];   % J2, J3, J5 - triangle FDI
    cfg.atk9_bias_scale   = 0.05;        % 5% bias magnitude

    % A10 Replay Attack
    cfg.atk10_buffer_s = 60;             % seconds of history to replay

    %% 15. Peng-Robinson EOS parameters (natural gas / methane dominant)
    cfg.pr_Tc    = 190.6;    % K   critical temperature
    cfg.pr_Pc    = 46.1;     % bar critical pressure
    cfg.pr_omega = 0.011;    % acentric factor
    cfg.pr_M     = 0.01604;  % kg/mol molar mass (CH4)
    cfg.pr_R     = 8.314;    % J/(mol K) universal gas constant
end