function cfg = simConfig()
% simConfig  Master configuration for the 20-node Indian CGD simulator.
%
% All European / GasLib-24 parameters have been replaced with PNGRB
% T4S-compliant Indian CGD values (ONGC/GAIL natural gas supply).
%
% Phase changelog:
%   Phase 7  : Indian CGD parameterisation, E21/E22 resilience edges
%   Phase A  : Storage loop divergence fix (sto_p_inject/withdraw/k_flow)
%              CUSUM cold-start fix (cusum_slack, cusum_warmup_steps)
%   Phase B  : sim_duration_min, attack_selection, forced_attack_id fields
%
% Verification after edit:
%   >> cfg = simConfig();
%   >> assert(cfg.src_p_barg(1) >= 20 && cfg.src_p_barg(1) <= 26)
%   >> assert(cfg.sto_p_inject == 24.5)
%   >> assert(cfg.cusum_slack  == 2.5)

    % ================================================================
    % NETWORK TOPOLOGY
    % ================================================================
    cfg.n_nodes = 20;
    cfg.n_pipes = 22;   % 20 base + E21 + E22 resilience edges

    % Node type labels — ordered to match nodeNames (S1,J1,CS1,J2,...,D6)
    cfg.nodeTypes = { ...
        'source',                                     ...  % 1:  S1
        'junction',                                   ...  % 2:  J1
        'compressor',                                 ...  % 3:  CS1
        'junction','junction','junction',             ...  % 4-6: J2,J3,J4
        'compressor',                                 ...  % 7:  CS2
        'junction','junction',                        ...  % 8-9: J5,J6
        'prs',                                        ...  % 10: PRS1
        'junction',                                   ...  % 11: J7
        'storage',                                    ...  % 12: STO
        'prs',                                        ...  % 13: PRS2
        'source',                                     ...  % 14: S2
        'demand','demand','demand','demand','demand','demand' ...  % 15-20: D1-D6
    };

    % ================================================================
    % NETWORK TOPOLOGY — Incidence Matrix
    % ================================================================
    % edges(i,:) = [from_node, to_node] for pipe i (1-indexed)
    % 20 edges connecting the 20-node network
    cfg.edges = [
        1,  2;    % E1:  S1 → J1
        2,  3;    % E2:  J1 → CS1
        3,  4;    % E3:  CS1 → J2
        4,  5;    % E4:  J2 → J3
        5,  6;    % E5:  J3 → J4
        6,  7;    % E6:  J4 → CS2
        7,  8;    % E7:  CS2 → J5
        8,  9;    % E8:  J5 → J6
        9, 10;    % E9:  J6 → PRS1
       10, 11;    % E10: PRS1 → J7
       11, 12;    % E11: J7 → STO
       12, 13;    % E12: STO → PRS2
       13, 14;    % E13: PRS2 → S2
       14, 15;    % E14: S2 → D1
       15, 16;    % E15: D1 → D2
       16, 17;    % E16: D2 → D3
       17, 18;    % E17: D3 → D4
       18, 19;    % E18: D4 → D5
       19, 20;    % E19: D5 → D6
        2, 11;    % E20: J1 → J7 (alternate path for resilience)
    ];

    % ================================================================
    % PIPE GEOMETRY  (IS 3589 / API 5L Gr.B, DN50–DN300)
    % ================================================================
    % Lengths [km] — pipes 1–20 + E21 (J4→J7, 8 km) + E22 (J3→J5, 12 km)
    cfg.pipe_L = [ ...
        5.0, 8.0, 6.0, 7.0, 5.5, 9.0, 4.0, 6.5, 8.0, 5.0, ...
        7.0, 6.0, 5.0, 4.5, 8.0, 6.5, 7.0, 5.5, 6.0, 4.0, ...
        8.0, 12.0 ...   % E21, E22
    ]';

    % Diameters [m] — DN50=0.0508 … DN300=0.3048
    cfg.pipe_D = [ ...
        0.2032, 0.3048, 0.2540, 0.2032, 0.1524, 0.3048, 0.2032, 0.1524, ...
        0.2540, 0.1524, 0.2032, 0.1524, 0.1016, 0.1524, 0.2032, 0.1524, ...
        0.1016, 0.1524, 0.1016, 0.0762, ...
        0.1016, 0.0762 ...   % E21 (DN100), E22 (DN80)
    ]';

    cfg.pipe_eff = 0.92;    % Weymouth efficiency factor

    % Pipe material: API 5L Gr.B / IS 3589 Gr.410
    % MAOP per PNGRB T4S: 26 barg (design pressure)
    cfg.pipe_MAOP_barg = 26.0;
    

    % ================================================================
    % NODE AND EDGE NAMES (20-node network topology)  ← ADD THIS SECTION
    % ================================================================
    cfg.nodeNames = ["S1","J1","CS1","J2","J3","J4","CS2","J5","J6","PRS1", ...
                     "J7","STO","PRS2","S2","D1","D2","D3","D4","D5","D6"];
    
    cfg.edgeNames = ["E1","E2","E3","E4","E5","E6","E7","E8","E9","E10", ...
                     "E11","E12","E13","E14","E15","E16","E17","E18","E19","E20"];

    % ================================================================
    % GAS PROPERTIES  (ONGC/GAIL supply, IS 4693)
    % ================================================================
    cfg.gas_SG     = 0.57;          % specific gravity (air=1)
    cfg.Z_factor   = 0.95;          % compressibility at 20 bar / 35°C
    cfg.T_avg_K    = 308.15;        % 35°C → K (conservative summer avg)
    cfg.T_min_K    = 293.15;        % 20°C
    cfg.T_max_K    = 318.15;        % 45°C

    % ================================================================
    % SOURCE / CGS PRESSURES  (barg)
    % ================================================================
    % CGS outlet: 20–26 barg; DRS inlet: 14–18 barg
    cfg.src_p_barg   = [22.0, 21.0];   % S1, S2 nominal setpoints
    cfg.src_p_min    = 20.0;
    cfg.src_p_max    = 26.0;

    % PRS setpoints (barg)
    cfg.prs1_setpoint_barg = 18.0;
    cfg.prs2_setpoint_barg = 14.0;

    % DRS delivery pressure target (barg)
    cfg.drs_p_target_barg  = [16.0, 15.5, 15.0, 14.5];   % DRS1–DRS4

    % ================================================================
    % COMPRESSOR PARAMETERS
    % ================================================================
    cfg.comp_ratio_min = 1.1;
    cfg.comp_ratio_max = 1.6;
    cfg.comp_ratio_nom = [1.3, 1.25];   % CS1, CS2 nominal

    % ================================================================
    % DEMAND / FLOW  (SCMD — standard cubic metres per day, city scale)
    % ================================================================
    cfg.q_min_scmd  = 0;
    cfg.q_max_scmd  = 2000;
    cfg.q_nom_scmd  = 800;      % nominal city demand

    % Demand node daily pattern multipliers (24 values, hourly)
    cfg.demand_profile = [ ...
        0.60 0.55 0.52 0.50 0.52 0.60 ...   % 00–05 h
        0.75 0.90 1.10 1.15 1.10 1.05 ...   % 06–11 h
        1.00 0.95 0.90 0.88 0.90 1.00 ...   % 12–17 h
        1.10 1.20 1.15 1.05 0.90 0.70 ...   % 18–23 h
    ];

    % ================================================================
    % STORAGE NODE PARAMETERS  — Phase A divergence fix
    % ================================================================
    % Previously incorrect values caused J7→70 bar and J5→0.1 bar blowup.
    % Fix: tighten inject/withdraw bounds to within Indian CGD MAOP range.
    cfg.sto_p_inject   = 24.5;   % barg — max injection pressure (≤ MAOP 26)
    cfg.sto_p_withdraw = 16.5;   % barg — min withdrawal pressure (≥ DRS floor)
    cfg.sto_k_flow     = 0.2;    % flow gain coefficient [SCMD/barg]

    cfg.sto_vol_m3     = [5000, 3000];   % STO1, STO2 working volumes [m³]
    cfg.sto_soc_init   = [0.60, 0.55];   % initial state-of-charge [fraction]

    % ================================================================
    % RESILIENCE EDGES  (Phase 7)
    % ================================================================
    % E21: J4 → J7 cross-tie  (pipe index 21, DN100, 8 km)
    % E22: J3 → J5 emergency bypass (pipe index 22, DN80, 12 km)
    % Both OFF by default; PLC-activated via cs2_alarm coil
    cfg.resilience_edge_idx  = [21, 22];
    cfg.resilience_valve_idx = [21, 22];    % Modbus coil addresses 4, 5
    cfg.resilience_default   = [0, 0];      % 0 = closed

    % Isolation valve V_D1 on pipe E10 (Modbus coil 6)
    cfg.isolation_valve_pipe = 10;
    cfg.isolation_valve_coil = 6;

    % ================================================================
    % EKF PARAMETERS
    % ================================================================
    cfg.ekf_n_states   = 40;        % 20 pressures + 20 flows
    cfg.ekf_Q_diag     = 1e-4;      % process noise
    cfg.ekf_R_diag     = 1e-3;      % measurement noise
    cfg.ekf_P0_diag    = 1e-2;      % initial covariance

    % ================================================================
    % CUSUM PARAMETERS  — Phase A cold-start fix
    % ================================================================
    % Old slack=1.0 caused 816 false alarms during normal operation.
    % Raised to 2.5; warmup window skips alarm evaluation for first 300 s.
    cfg.cusum_slack         = 2.5;      % k — allowable slack (sigma units)
    cfg.cusum_threshold     = 12.0;     % h — decision threshold
    cfg.cusum_warmup_steps  = 300;      % steps at cfg.dt before alarms active
    cfg.cusum_reset_on_trip = true;     % reset accumulators after alarm

    % ================================================================
    % NOISE MODEL  (AR(1) — validated by verifyNoiseStats.m)
    % ================================================================
    cfg.noise_ar1_phi   = 0.85;         % AR(1) coefficient
    cfg.noise_sigma_p   = 0.02;         % pressure noise std [barg]
    cfg.noise_sigma_q   = 5.0;          % flow noise std [SCMD]

    % ================================================================
    % SIMULATION TIMING
    % ================================================================
    cfg.dt          = 0.1;              % physics timestep [s]
    cfg.log_every   = 10;              % log every N steps → 1 Hz dataset
    cfg.sim_duration_min = 1440;        % default 24 h in minutes (Phase B field)

    % ================================================================
    % ATTACK CONFIGURATION  (Phase B fields)
    % ================================================================
    cfg.n_attacks          = 8;         % actual number of attacks per sweep
    cfg.attack_selection   = 1:10;      % which attack IDs to include
    cfg.forced_attack_id   = [];        % [] = random; set integer to force

    % ================================================================
    % MODBUS / GATEWAY
    % ================================================================
    cfg.modbus_ip    = '127.0.0.1';
    cfg.modbus_port  = 1502;
    cfg.modbus_unit  = 1;
    cfg.udp_port     = 6006;

    % Holding register map (0-indexed Modbus addresses)
    cfg.reg_sensor_start   = 0;     % addresses 0–59: sensor inputs (×100 scaled)
    cfg.reg_actuator_start = 100;   % addresses 100–111: actuator outputs
    cfg.reg_resilience     = [109, 110, 111];  % E21 valve, E22 valve, V_D1

    % ================================================================
    % DATASET EXPORT
    % ================================================================
    cfg.dataset_dir     = 'dataset/';
    cfg.export_basename = 'cgd_sim';

    % Column schema version (bump when novel columns added in Phase C)
    cfg.schema_version  = 'v2.0-phase-c';

    % ================================================================
    % PHYSICS CONSTANTS  (natural gas at Indian CGD operating conditions)
    % ================================================================
    cfg.p0    = 23.0;    % initial absolute pressure [bara]  (≈ 22 barg nominal)
    cfg.T0    = 308.15;  % initial temperature [K]  (35°C = T_avg_K)
    cfg.rho0  = 209.0;   % reference density parameter [kg·K/m³/bara]
                         %   ρ [kg/m³] = rho0 * P [bara] / T [K]
                         %   At 23 bara, 308 K: ρ ≈ 15.6 kg/m³ (SG=0.57 gas)
    cfg.c     = 420.0;   % speed of sound in natural gas [m/s]
    cfg.gamma = 1.31;    % specific heat ratio Cp/Cv for natural gas

    % ================================================================
    % NODE AND PIPE PROPERTIES
    % ================================================================
    cfg.node_V        = 100.0;          % lumped nodal volume [m³]
    cfg.pipe_rough    = 4.6e-5;         % absolute pipe roughness [m]  (IS 3589/API 5L steel)
    cfg.pipe_L_vec    = cfg.pipe_L(1:cfg.n_nodes);   % 20-edge alias used by some modules
    cfg.pipe_D_vec    = cfg.pipe_D(1:cfg.n_nodes);   % 20-edge alias used by some modules
    cfg.nodeElevation = zeros(1, cfg.n_nodes);        % node elevations [m]  (flat terrain)

    % ================================================================
    % VALVE EDGES  (runSimulation expects 3: E8, E14, E15)
    % ================================================================
    cfg.valveEdges = [8, 14, 15];   % E8 main isolation, E14/E15 distribution control

    % ================================================================
    % SOURCE 2 (S2) PRESSURE LIMITS
    % ================================================================
    cfg.src2_p_min = 20.0;   % [barg]
    cfg.src2_p_max = 26.0;   % [barg]

    % ================================================================
    % COMPRESSOR NODE INDICES AND INDIVIDUAL RATIOS
    % ================================================================
    cfg.comp1_node      = 3;             % CS1 (index in nodeNames)
    cfg.comp2_node      = 7;             % CS2
    cfg.comp1_ratio     = cfg.comp_ratio_nom(1);   % 1.30
    cfg.comp2_ratio     = cfg.comp_ratio_nom(2);   % 1.25
    cfg.comp1_ratio_min = cfg.comp_ratio_min;       % 1.1
    cfg.comp2_ratio_min = cfg.comp_ratio_min;       % 1.1
    cfg.comp1_ratio_max = cfg.comp_ratio_max;       % 1.6
    cfg.comp2_ratio_max = cfg.comp_ratio_max;       % 1.6

    % ================================================================
    % PRS NODE INDICES
    % ================================================================
    cfg.prs1_node = 10;   % PRS1
    cfg.prs2_node = 13;   % PRS2

    % ================================================================
    % PID CONTROLLER GAINS AND SETPOINTS
    % ================================================================
    cfg.pid1_Kp        = 0.10;   % CS1 PID proportional gain
    cfg.pid1_Ki        = 0.01;   % CS1 PID integral gain
    cfg.pid1_Kd        = 0.001;  % CS1 PID derivative gain
    cfg.pid1_setpoint  = 16.0;   % CS1 delivery pressure setpoint [barg] (D1 target)
    cfg.pid2_Kp        = 0.10;   % CS2 PID proportional gain
    cfg.pid2_Ki        = 0.01;   % CS2 PID integral gain
    cfg.pid2_Kd        = 0.001;  % CS2 PID derivative gain
    cfg.pid2_setpoint  = 15.0;   % CS2 delivery pressure setpoint [barg] (D3 target)
    cfg.pid_D1_node    = 15;     % D1 demand node index (delivery pressure reference)
    cfg.pid_D3_node    = 17;     % D3 demand node index (CS2 reference)

    % ================================================================
    % CONTROL THRESHOLDS
    % ================================================================
    cfg.emer_shutdown_p = 28.0;   % [barg]  emergency shutdown threshold (above MAOP)
    cfg.valve_open_lo   = 14.0;   % [barg]  open E8 when J6 pressure drops below this
    cfg.valve_close_hi  = 24.0;   % [barg]  close E8 when J6 pressure rises above this

    % ================================================================
    % STORAGE FLOW LIMITS
    % ================================================================
    cfg.sto_max_flow = 200.0;   % [SCMD]  maximum storage inject/withdraw flow rate
    cfg.sto_capacity = 1.0;     % normalised capacity (inventory range 0–1)

    % ================================================================
    % SOURCE PROFILE PARAMETERS  (generateSourceProfile.m)
    % ================================================================
    cfg.src_slow_amp  = 0.50;   % [barg]  slow oscillation amplitude (~22 min cycle)
    cfg.src_med_amp   = 0.20;   % [barg]  medium oscillation amplitude (~6 min cycle)
    cfg.src_fast_amp  = 0.10;   % [barg]  fast fluctuation amplitude (~75 s cycle)
    cfg.src_trend     = 0.00;   % [barg]  total linear drift over simulation
    cfg.src_rw_amp    = 0.15;   % [barg]  AR(1) random walk amplitude
    cfg.src_ar1_alpha = 0.98;   % AR(1) correlation coefficient for source random walk

    % ================================================================
    % DEMAND PARAMETERS  (defaults; overridden per scenario in sweep)
    % ================================================================
    cfg.dem_base         = 0.60;    % default demand base fraction of q_nom_scmd
    cfg.dem_noise_std    = 0.015;   % demand noise std (fraction of base demand)
    cfg.dem_diurnal_amp  = 0.20;    % diurnal demand amplitude (fraction)
    cfg.dem_spike_enable = false;   % demand spike injection disabled by default

    % ================================================================
    % TURBULENCE AR(1) PARAMETERS  (runSimulation.m roughness/flow AR(1))
    % ================================================================
    cfg.rough_corr     = 0.95;   % AR(1) coefficient for pipe roughness variation
    cfg.rough_var_std  = 0.01;   % relative roughness std (fraction of pipe_rough)
    cfg.flow_turb_corr = 0.85;   % AR(1) coefficient for flow turbulence
    cfg.flow_turb_std  = 5.0;    % [SCMD]  flow turbulence std deviation

    % ================================================================
    % SENSOR NOISE
    % ================================================================
    cfg.sensor_noise       = 0.005;   % multiplicative noise fraction
    cfg.sensor_noise_floor = 0.01;    % absolute noise floor [barg or SCMD]

    % ================================================================
    % ADC QUANTISATION
    % ================================================================
    cfg.adc_enable       = false;    % disabled by default
    cfg.adc_bits         = 12;       % 12-bit ADC resolution
    cfg.adc_p_full_scale = 30.0;     % [barg]   pressure ADC full scale
    cfg.adc_q_full_scale = 2000.0;   % [SCMD]   flow ADC full scale

    % ================================================================
    % ALARM THRESHOLDS
    % ================================================================
    cfg.alarm_P_high = 26.0;    % [barg]  high pressure alarm (MAOP)
    cfg.alarm_P_low  = 14.0;    % [barg]  low pressure alarm (DRS floor)
    cfg.atk_warmup_s = 120.0;   % [s]     pre-attack warm-up period

    % ================================================================
    % PLC PARAMETERS
    % ================================================================
    cfg.plc_period_z1   = 10;          % zone 1 scan period [steps]  (source + CS nodes)
    cfg.plc_period_z2   = 20;          % zone 2 scan period [steps]
    cfg.plc_period_z3   = 50;          % zone 3 scan period [steps]  (delivery nodes)
    cfg.plc_zone1_nodes = [1 3 7];     % zone 1: S1, CS1, CS2
    cfg.plc_zone2_nodes = [2 4 5 6 8 9 10 11 12 13]; % zone 2: junctions + PRS + STO
    cfg.plc_zone3_nodes = [14 15 16 17 18 19 20];     % zone 3: S2 + D1-D6
    cfg.plc_latency     = 1;           % [steps] PLC command latency

    % ================================================================
    % ATTACK PARAMETERS  (defaults; attack-specific values set elsewhere)
    % ================================================================
    cfg.atk7_extra_latency = 5;    % [steps]  extra PLC latency injected by attack 7
    cfg.atk8_edge          = 8;    % edge index targeted by leak attack (A8)
    cfg.atk8_leak_frac     = 0.3;  % fraction of flow lost in A8 leak
    cfg.atk8_ramp_time     = 60.0; % [s]  ramp-up time for A8 leak

    % ================================================================
    % COMPRESSOR HEAD AND EFFICIENCY CURVES  (initCompressor.m)
    % ================================================================
    % H   = a1 + a2*m + a3*m²  [J/kg]   head curve vs inlet flow [SCMD]
    % eta = b1 + b2*m + b3*m²  [-]      efficiency curve vs inlet flow [SCMD]
    % Tuned for centrifugal compressors at Indian CGD scale (40-400 SCMD)
    cfg.comp1_a1 =  50000;    % CS1 head intercept  [J/kg]
    cfg.comp1_a2 =   -100;    % CS1 head slope      [J/kg/SCMD]
    cfg.comp1_a3 =   -0.5;    % CS1 head quadratic  [J/kg/SCMD^2]
    cfg.comp1_b1 =    0.60;   % CS1 efficiency intercept
    cfg.comp1_b2 =    0.010;  % CS1 efficiency slope    [1/SCMD]
    cfg.comp1_b3 =  -2e-4;    % CS1 efficiency quadratic [1/SCMD^2]
    cfg.comp2_a1 =  40000;    % CS2 head intercept  [J/kg]
    cfg.comp2_a2 =   -100;    % CS2 head slope      [J/kg/SCMD]
    cfg.comp2_a3 =   -0.5;    % CS2 head quadratic  [J/kg/SCMD^2]
    cfg.comp2_b1 =    0.60;   % CS2 efficiency intercept
    cfg.comp2_b2 =    0.010;  % CS2 efficiency slope    [1/SCMD]
    cfg.comp2_b3 =  -2e-4;    % CS2 efficiency quadratic [1/SCMD^2]

    % Compressor shaft pulsation and surge margin noise
    cfg.comp_pulsation_amp  = 0.02;    % blade-pass pulsation amplitude (fraction of ratio)
    cfg.comp_pulsation_freq = 25.0;    % [Hz]  blade-pass frequency
    cfg.comp_surge_corr     = 0.90;    % AR(1) correlation for surge margin noise
    cfg.comp_surge_noise    = 0.005;   % surge margin noise std (fraction)

    % ================================================================
    % PRS SETPOINTS AND TUNING  (initPRS.m)
    % ================================================================
    cfg.prs1_setpoint = cfg.prs1_setpoint_barg;   % 18.0 [barg]
    cfg.prs1_deadband = 0.5;    % [barg]  PRS1 deadband
    cfg.prs1_tau      = 30.0;   % [s]     PRS1 throttle time constant
    cfg.prs2_setpoint = cfg.prs2_setpoint_barg;   % 14.0 [barg]
    cfg.prs2_deadband = 0.5;    % [barg]  PRS2 deadband
    cfg.prs2_tau      = 30.0;   % [s]     PRS2 throttle time constant

    % ================================================================
    % PENG-ROBINSON EOS PARAMETERS  (updateDensity.m)
    % ================================================================
    cfg.pr_Tc    = 190.6;    % [K]          CH4 critical temperature
    cfg.pr_Pc    = 46.1;     % [bar]        CH4 critical pressure
    cfg.pr_omega = 0.011;    % [-]          CH4 acentric factor
    cfg.pr_R     = 8.314;    % [J/(mol·K)]  universal gas constant
    cfg.pr_M     = 0.01604;  % [kg/mol]     CH4 molar mass  (SG approx 0.57)
    cfg.rho_comp_corr = 0.98;   % AR(1) correlation for gas composition drift
    cfg.rho_comp_std  = 0.01;   % composition drift std (fraction)

    % ================================================================
    % PRESSURE ACOUSTIC NOISE  (updatePressure.m)
    % ================================================================
    cfg.p_acoustic_corr = 0.90;    % AR(1) correlation for pipe acoustic oscillations
    cfg.p_acoustic_std  = 0.002;   % [bar]  acoustic pressure noise std

    % ================================================================
    % TEMPERATURE NOISE AND JOULE-THOMSON COEFFICIENT  (updateTemperature.m)
    % ================================================================
    cfg.T_jt_coeff  = -0.45;   % [K/bar]  Joule-Thomson coefficient (cooling on pressure drop)
    cfg.T_turb_corr =  0.85;   % AR(1) correlation for turbulent thermal mixing
    cfg.T_turb_std  =  0.05;   % [K]      turbulent thermal noise std

    % ================================================================
    % EKF PARAMETER ALIASES  (initEKF.m uses ekf_P0, ekf_Qn, ekf_Rk)
    % ================================================================
    cfg.ekf_P0 = cfg.ekf_P0_diag;   % scalar initial covariance (-> eye*P0 in initEKF)
    cfg.ekf_Qn = cfg.ekf_Q_diag;    % scalar process noise variance
    cfg.ekf_Rk = cfg.ekf_R_diag;    % scalar measurement noise variance

    % ================================================================
    % PLC VALVE DEFAULT STATE  (initPLC.m)
    % ================================================================
    cfg.valve_open_default = 1;    % 1 = open, 0 = closed (all valves open at start)

    % ================================================================
    % ATTACK-SPECIFIC PARAMETERS  (A1-A10)
    % ================================================================
    % A1: Source pressure spike + oscillation
    cfg.atk1_spike_amp = 1.30;    % spike multiplier (1.30 = +30% of nominal)
    cfg.atk1_osc_freq  = 0.01;    % [Hz]  oscillation frequency during A1

    % A2: Compressor ratio ramp-up (overspeed)
    cfg.atk2_ramp_time    = 30.0;               % [s]  ramp duration
    cfg.atk2_target_ratio = cfg.comp_ratio_max; % ramp to maximum ratio (1.6)

    % A3: Valve forced-state injection
    cfg.atk3_cmd = 0;    % force valve to this state (0=closed, 1=open)

    % A4: Demand injection (false high-demand)
    cfg.atk4_ramp_time    = 60.0;           % [s]  ramp duration
    cfg.atk4_demand_scale = 2.0;            % demand multiplier (2x nominal)
    cfg.dem_max           = cfg.q_max_scmd; % [SCMD]  maximum allowable demand

    % A5: Pressure sensor spoof (single node additive bias)
    cfg.atk5_target_node = 15;     % D1 delivery node
    cfg.atk5_bias_bar    = 2.0;    % [barg]  additive bias

    % A6: Flow meter spoof (scale selected edges to zero)
    cfg.atk6_edges = [7, 8];    % CS2->J5 and J5->J6
    cfg.atk6_scale = 0.0;       % scale factor (0 = zero-out)

    % A9: FDI ramp bias across multiple nodes
    cfg.atk9_ramp_s       = 60.0;           % [s]  ramp time
    cfg.atk9_target_nodes = [15, 16, 17];   % D1, D2, D3
    cfg.atk9_bias_scale   = 0.05;           % fraction of nominal pressure

    % A10: Replay attack - record and inject stale sensor data
    cfg.atk10_buffer_s    = 120.0;      % [s]   buffer duration
    cfg.atk10_inject_mode = 'straight'; % replay injection mode

    % ================================================================
    % ATTACK SCHEDULE PARAMETERS  (initAttackSchedule.m)
    % ================================================================
    cfg.atk_recovery_s = 120.0;   % [s]  attack-free zone at end of simulation
    cfg.atk_min_gap_s  =  60.0;   % [s]  minimum gap between consecutive attacks
    cfg.atk_dur_min_s  =  60.0;   % [s]  minimum attack duration
    cfg.atk_dur_max_s  = 300.0;   % [s]  maximum attack duration

    % ================================================================
    % HISTORIAN PARAMETERS  (updateHistorian.m)
    % ================================================================
    cfg.historian_enable          = false;   % disabled by default
    cfg.historian_deadband_p      = 0.1;     % [barg]  pressure deadband
    cfg.historian_deadband_q      = 10.0;    % [SCMD]  flow deadband
    cfg.historian_deadband_T      = 0.5;     % [K]     temperature deadband
    cfg.historian_max_interval_s  = 300.0;   % [s]     heartbeat interval

    % ================================================================
    % FAULT INJECTION PARAMETERS  (applyFaultInjection.m)
    % ================================================================
    cfg.fault_enable      = false;            % disabled by default
    cfg.fault_stuck_nodes = [15, 16, 17, 18]; % D1-D4 nodes susceptible to stuck faults
    cfg.fault_stuck_prob  = 0.001;            % per-step probability of fault onset
    cfg.fault_stuck_dur_s = 30.0;             % [s]  expected stuck sensor duration
    cfg.fault_loss_prob   = 0.002;            % per-step packet loss probability
    cfg.fault_max_consec  = 3;                % max consecutive packet loss steps

    % ================================================================
    % ADDITIONAL ALARM THRESHOLDS
    % ================================================================
    cfg.alarm_ekf_resid = 2.0;    % [barg]  EKF pressure residual alarm threshold
    cfg.alarm_comp_hi   = 1.55;   % [-]     compressor ratio high alarm

    % ================================================================
    % STORAGE INVENTORY INITIAL VALUE  (default; overridden per scenario by sweep)
    % ================================================================
    cfg.sto_inventory_init = 0.60;   % [0-1]  initial storage fill level

    % ================================================================
    % SCAN JITTER PARAMETERS  (addScanJitter.m)
    % ================================================================
    cfg.jitter_enable        = false;       % disabled by default
    cfg.jitter_platform      = 'codesys';   % 'codesys' or 's7_1200'
    cfg.jitter_codesys_std_ms = 20.0;       % [ms]  CODESYS Windows jitter std
    cfg.jitter_codesys_max_ms = 150.0;      % [ms]  CODESYS max clamp
    cfg.jitter_s7_std_ms      = 1.5;        % [ms]  S7-1200 hardware jitter std
    cfg.jitter_s7_max_ms      = 10.0;       % [ms]  S7-1200 max clamp

end