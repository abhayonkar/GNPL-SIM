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
%   Phase 0  : PHYSICS DIVERGENCE FIX
%              - node_V: 100 → 500 m³  (primary oscillation fix)
%              - updatePressure relax=0.3, diffusion alpha=0.05, clamp [12,28]
%              - p_acoustic_std corrected to match original 0.002
%              - atk_dur_min/max: 60/300 s (from original, not overridden)
%
% Verification after edit:
%   >> cfg = simConfig();
%   >> assert(cfg.node_V == 500,      'node_V must be 500 for Phase 0 stability')
%   >> assert(cfg.sto_p_inject == 24.5)
%   >> assert(cfg.cusum_slack  == 2.5)
%   >> assert(cfg.flow_turb_std == 5.0, 'flow_turb_std is SCMD not fraction')

    % ================================================================
    % NETWORK TOPOLOGY
    % ================================================================
    cfg.n_nodes = 20;
    cfg.n_pipes = 22;   % 20 base + E21 + E22 resilience edges

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
        'demand','demand','demand','demand','demand','demand' ... % 15-20: D1-D6
    };

    % ================================================================
    % NETWORK TOPOLOGY — Incidence Matrix
    % ================================================================
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
        2, 11;    % E20: J1 → J7 (alternate resilience path)
    ];

    % ================================================================
    % PIPE GEOMETRY  (IS 3589 / API 5L Gr.B, DN50–DN300)
    % ================================================================
    cfg.pipe_L = [ ...
        5.0, 8.0, 6.0, 7.0, 5.5, 9.0, 4.0, 6.5, 8.0, 5.0, ...
        7.0, 6.0, 5.0, 4.5, 8.0, 6.5, 7.0, 5.5, 6.0, 4.0, ...
        8.0, 12.0 ...   % E21, E22
    ]';

    cfg.pipe_D = [ ...
        0.2032, 0.3048, 0.2540, 0.2032, 0.1524, 0.3048, 0.2032, 0.1524, ...
        0.2540, 0.1524, 0.2032, 0.1524, 0.1016, 0.1524, 0.2032, 0.1524, ...
        0.1016, 0.1524, 0.1016, 0.0762, ...
        0.1016, 0.0762 ...   % E21 (DN100), E22 (DN80)
    ]';

    cfg.pipe_eff      = 0.92;
    cfg.pipe_MAOP_barg = 26.0;

    % ================================================================
    % NODE AND EDGE NAMES
    % ================================================================
    cfg.nodeNames = ["S1","J1","CS1","J2","J3","J4","CS2","J5","J6","PRS1", ...
                     "J7","STO","PRS2","S2","D1","D2","D3","D4","D5","D6"];
    cfg.edgeNames = ["E1","E2","E3","E4","E5","E6","E7","E8","E9","E10", ...
                     "E11","E12","E13","E14","E15","E16","E17","E18","E19","E20"];

    % ================================================================
    % GAS PROPERTIES  (ONGC/GAIL supply, IS 4693)
    % ================================================================
    cfg.gas_SG     = 0.57;
    cfg.Z_factor   = 0.95;
    cfg.T_avg_K    = 308.15;
    cfg.T_min_K    = 293.15;
    cfg.T_max_K    = 318.15;

    % ================================================================
    % SOURCE / CGS PRESSURES  (barg)
    % ================================================================
    cfg.src_p_barg   = [22.0, 21.0];
    cfg.src_p_min    = 20.0;
    cfg.src_p_max    = 26.0;
    cfg.prs1_setpoint_barg = 18.0;
    cfg.prs2_setpoint_barg = 14.0;
    cfg.drs_p_target_barg  = [16.0, 15.5, 15.0, 14.5];

    % ================================================================
    % COMPRESSOR PARAMETERS
    % ================================================================
    cfg.comp_ratio_min = 1.1;
    cfg.comp_ratio_max = 1.6;
    cfg.comp_ratio_nom = [1.3, 1.25];

    % ================================================================
    % DEMAND / FLOW  (SCMD)
    % ================================================================
    cfg.q_min_scmd  = 0;
    cfg.q_max_scmd  = 2000;
    cfg.q_nom_scmd  = 800;
    cfg.demand_profile = [ ...
        0.60 0.55 0.52 0.50 0.52 0.60 ...
        0.75 0.90 1.10 1.15 1.10 1.05 ...
        1.00 0.95 0.90 0.88 0.90 1.00 ...
        1.10 1.20 1.15 1.05 0.90 0.70 ...
    ];

    % ================================================================
    % STORAGE NODE PARAMETERS  — Phase A divergence fix
    % ================================================================
    cfg.sto_p_inject   = 24.5;
    cfg.sto_p_withdraw = 16.5;
    cfg.sto_k_flow     = 0.2;
    cfg.sto_vol_m3     = [5000, 3000];
    cfg.sto_soc_init   = [0.60, 0.55];

    % ================================================================
    % RESILIENCE EDGES  (Phase 7)
    % ================================================================
    cfg.resilience_edge_idx  = [21, 22];
    cfg.resilience_valve_idx = [21, 22];
    cfg.resilience_default   = [0, 0];
    cfg.isolation_valve_pipe = 10;
    cfg.isolation_valve_coil = 6;

    % ================================================================
    % EKF PARAMETERS
    % ================================================================
    cfg.ekf_n_states = 40;
    cfg.ekf_Q_diag   = 1e-4;
    cfg.ekf_R_diag   = 1e-3;
    cfg.ekf_P0_diag  = 1e-2;

    % ================================================================
    % CUSUM PARAMETERS  — Phase A cold-start fix
    % ================================================================
    cfg.cusum_slack         = 2.5;
    cfg.cusum_threshold     = 12.0;
    cfg.cusum_warmup_steps  = 300;
    cfg.cusum_reset_on_trip = true;

    % ================================================================
    % NOISE MODEL  (AR(1))
    % ================================================================
    cfg.noise_ar1_phi = 0.85;
    cfg.noise_sigma_p = 0.02;
    cfg.noise_sigma_q = 5.0;

    % ================================================================
    % SIMULATION TIMING
    % ================================================================
    cfg.dt               = 0.1;
    cfg.log_every        = 10;
    cfg.sim_duration_min = 1440;

    % ================================================================
    % ATTACK CONFIGURATION  (Phase B fields)
    % ================================================================
    cfg.n_attacks        = 8;
    cfg.attack_selection = 1:10;
    cfg.forced_attack_id = [];

    % ================================================================
    % MODBUS / GATEWAY
    % ================================================================
    cfg.modbus_ip    = '127.0.0.1';
    cfg.modbus_port  = 1502;
    cfg.modbus_unit  = 1;
    cfg.udp_port     = 6006;
    cfg.reg_sensor_start   = 0;
    cfg.reg_actuator_start = 100;
    cfg.reg_resilience     = [109, 110, 111];

    % ================================================================
    % DATASET EXPORT
    % ================================================================
    cfg.dataset_dir     = 'dataset/';
    cfg.export_basename = 'cgd_sim';
    cfg.schema_version  = 'v2.0-phase-0-fixed';

    % ================================================================
    % PHYSICS CONSTANTS
    % ================================================================
    cfg.p0    = 23.0;
    cfg.T0    = 308.15;
    cfg.rho0  = 209.0;
    cfg.c     = 420.0;
    cfg.gamma = 1.31;

    % ================================================================
    % NODE AND PIPE PROPERTIES
    % ================================================================
    %
    % PHASE 0 FIX: node_V 100 → 500 m³
    % At V=100: coeff = dt*c²/(V*1e5) = 1.76e-3 → oscillation
    % At V=500: coeff = 3.53e-4 → stable for Indian CGD 14-26 bar range
    %
    cfg.node_V        = 500.0;          % ← PHASE 0 FIX (was 100)
    cfg.pipe_rough    = 4.6e-5;
    cfg.pipe_L_vec    = cfg.pipe_L(1:cfg.n_nodes);
    cfg.pipe_D_vec    = cfg.pipe_D(1:cfg.n_nodes);
    cfg.nodeElevation = zeros(1, cfg.n_nodes);

    % ================================================================
    % VALVE EDGES
    % ================================================================
    cfg.valveEdges = [8, 14, 15];

    % ================================================================
    % SOURCE 2 PRESSURE LIMITS
    % ================================================================
    cfg.src2_p_min = 20.0;
    cfg.src2_p_max = 26.0;

    % ================================================================
    % COMPRESSOR NODE INDICES AND INDIVIDUAL RATIOS
    % ================================================================
    cfg.comp1_node      = 3;
    cfg.comp2_node      = 7;
    cfg.comp1_ratio     = cfg.comp_ratio_nom(1);
    cfg.comp2_ratio     = cfg.comp_ratio_nom(2);
    cfg.comp1_ratio_min = cfg.comp_ratio_min;
    cfg.comp2_ratio_min = cfg.comp_ratio_min;
    cfg.comp1_ratio_max = cfg.comp_ratio_max;
    cfg.comp2_ratio_max = cfg.comp_ratio_max;

    % ================================================================
    % PRS NODE INDICES
    % ================================================================
    cfg.prs1_node = 10;
    cfg.prs2_node = 13;

    % ================================================================
    % PID CONTROLLER GAINS AND SETPOINTS
    % ================================================================
    cfg.pid1_Kp       = 0.10;
    cfg.pid1_Ki       = 0.01;
    cfg.pid1_Kd       = 0.001;
    cfg.pid1_setpoint = 16.0;   % [barg]  D1 target
    cfg.pid2_Kp       = 0.10;
    cfg.pid2_Ki       = 0.01;
    cfg.pid2_Kd       = 0.001;
    cfg.pid2_setpoint = 15.0;   % [barg]  D3 target
    cfg.pid_D1_node   = 15;
    cfg.pid_D3_node   = 17;

    % ================================================================
    % CONTROL THRESHOLDS
    % ================================================================
    cfg.emer_shutdown_p = 28.0;   % [barg]
    cfg.valve_open_lo   = 14.0;   % [barg]
    cfg.valve_close_hi  = 24.0;   % [barg]

    % ================================================================
    % STORAGE FLOW LIMITS
    % ================================================================
    cfg.sto_max_flow    = 200.0;   % [SCMD]
    cfg.sto_capacity    = 1.0;     % normalised capacity (0-1)
    cfg.sto_inventory_init = 0.60; % initial fill level [0-1]

    % ================================================================
    % SOURCE PROFILE PARAMETERS  (generateSourceProfile.m)
    % ================================================================
    cfg.src_slow_amp  = 0.50;   % [barg]  slow oscillation amplitude
    cfg.src_med_amp   = 0.20;   % [barg]  medium oscillation amplitude
    cfg.src_fast_amp  = 0.10;   % [barg]  fast fluctuation amplitude
    cfg.src_trend     = 0.00;   % [barg]  total linear drift over simulation
    cfg.src_rw_amp    = 0.15;   % [barg]  AR(1) random walk amplitude
    cfg.src_ar1_alpha = 0.98;   % AR(1) correlation coefficient

    % ================================================================
    % DEMAND PARAMETERS
    % ================================================================
    cfg.dem_base         = 0.60;
    cfg.dem_noise_std    = 0.015;
    cfg.dem_diurnal_amp  = 0.20;
    cfg.dem_spike_enable = false;

    % ================================================================
    % TURBULENCE AR(1) PARAMETERS
    % ================================================================
    % NOTE: flow_turb_std is in SCMD (not a fraction)
    cfg.rough_corr     = 0.95;    % AR(1) coefficient for pipe roughness
    cfg.rough_var_std  = 0.01;    % relative roughness std (fraction of pipe_rough)
    cfg.flow_turb_corr = 0.85;    % AR(1) coefficient for flow turbulence
    cfg.flow_turb_std  = 5.0;     % [SCMD]  flow turbulence std deviation

    % ================================================================
    % SENSOR NOISE
    % ================================================================
    cfg.sensor_noise       = 0.005;   % multiplicative noise fraction
    cfg.sensor_noise_floor = 0.01;    % absolute noise floor [barg or SCMD]

    % ================================================================
    % ADC QUANTISATION
    % ================================================================
    cfg.adc_enable       = false;
    cfg.adc_bits         = 12;
    cfg.adc_p_full_scale = 30.0;    % [barg]   (NOTE: 30, not 40)
    cfg.adc_q_full_scale = 2000.0;  % [SCMD]   (NOTE: 2000, not 3000)

    % ================================================================
    % ALARM THRESHOLDS
    % ================================================================
    cfg.alarm_P_high    = 26.0;    % [barg]  high pressure alarm (MAOP)
    cfg.alarm_P_low     = 14.0;    % [barg]  low pressure alarm (DRS floor)
    cfg.atk_warmup_s    = 120.0;   % [s]     pre-attack warm-up period
    cfg.alarm_ekf_resid = 2.0;     % [barg]  EKF pressure residual alarm
    cfg.alarm_comp_hi   = 1.55;    % [-]     compressor ratio high alarm

    % ================================================================
    % PLC PARAMETERS
    % ================================================================
    cfg.plc_period_z1    = 10;           % zone 1 scan period [steps]
    cfg.plc_period_z2    = 20;           % zone 2 scan period [steps]
    cfg.plc_period_z3    = 50;           % zone 3 scan period [steps]
    cfg.plc_zone1_nodes  = [1 3 7];      % S1, CS1, CS2
    cfg.plc_zone2_nodes  = [2 4 5 6 8 9 10 11 12 13];  % junctions + PRS + STO
    cfg.plc_zone3_nodes  = [14 15 16 17 18 19 20];      % S2 + D1-D6
    cfg.plc_latency      = 1;            % [steps] PLC command latency
    cfg.valve_open_default = 1;          % 1=open, 0=closed (all valves open at start)

    % ================================================================
    % ATTACK-SPECIFIC PARAMETERS  (A1-A10)
    % ================================================================
    % A1: Source pressure spike + oscillation
    cfg.atk1_spike_amp = 1.30;
    cfg.atk1_osc_freq  = 0.01;    % [Hz]

    % A2: Compressor ratio ramp-up
    cfg.atk2_ramp_time    = 30.0;
    cfg.atk2_target_ratio = cfg.comp_ratio_max;   % 1.6

    % A3: Valve forced-state injection
    cfg.atk3_cmd = 0;    % 0=closed, 1=open

    % A4: Demand injection
    cfg.atk4_ramp_time    = 60.0;
    cfg.atk4_demand_scale = 2.0;
    cfg.dem_max           = cfg.q_max_scmd;

    % A5: Pressure sensor spoof
    cfg.atk5_target_node = 15;
    cfg.atk5_bias_bar    = 2.0;

    % A6: Flow meter spoof
    cfg.atk6_edges = [7, 8];
    cfg.atk6_scale = 0.0;

    % A7: PLC latency
    cfg.atk7_extra_latency = 5;    % [steps]

    % A8: Pipeline leak
    cfg.atk8_edge      = 8;
    cfg.atk8_leak_frac = 0.3;
    cfg.atk8_ramp_time = 60.0;

    % A9: FDI ramp bias
    cfg.atk9_ramp_s       = 60.0;
    cfg.atk9_target_nodes = [15, 16, 17];
    cfg.atk9_bias_scale   = 0.05;

    % A10: Replay attack
    cfg.atk10_buffer_s    = 120.0;
    cfg.atk10_inject_mode = 'straight';

    % ================================================================
    % ATTACK SCHEDULE PARAMETERS  (initAttackSchedule.m)
    % ================================================================
    cfg.atk_recovery_s = 120.0;
    cfg.atk_min_gap_s  =  60.0;
    cfg.atk_dur_min_s  =  60.0;   % [s]  (original values)
    cfg.atk_dur_max_s  = 300.0;   % [s]

    % ================================================================
    % COMPRESSOR HEAD AND EFFICIENCY CURVES  (initCompressor.m)
    % ================================================================
    cfg.comp1_a1 =  50000;    cfg.comp1_a2 =   -100;    cfg.comp1_a3 =   -0.5;
    cfg.comp1_b1 =    0.60;   cfg.comp1_b2 =    0.010;  cfg.comp1_b3 =  -2e-4;
    cfg.comp2_a1 =  40000;    cfg.comp2_a2 =   -100;    cfg.comp2_a3 =   -0.5;
    cfg.comp2_b1 =    0.60;   cfg.comp2_b2 =    0.010;  cfg.comp2_b3 =  -2e-4;
    cfg.comp_pulsation_amp  = 0.02;
    cfg.comp_pulsation_freq = 25.0;    % [Hz]
    cfg.comp_surge_corr     = 0.90;
    cfg.comp_surge_noise    = 0.005;

    % ================================================================
    % PRS SETPOINTS AND TUNING  (initPRS.m)
    % ================================================================
    cfg.prs1_setpoint = cfg.prs1_setpoint_barg;   % 18.0
    cfg.prs1_deadband = 0.5;
    cfg.prs1_tau      = 30.0;
    cfg.prs2_setpoint = cfg.prs2_setpoint_barg;   % 14.0
    cfg.prs2_deadband = 0.5;
    cfg.prs2_tau      = 30.0;

    % ================================================================
    % PENG-ROBINSON EOS PARAMETERS  (updateDensity.m)
    % ================================================================
    cfg.pr_Tc    = 190.6;    % [K]
    cfg.pr_Pc    = 46.1;     % [bar]
    cfg.pr_omega = 0.011;
    cfg.pr_R     = 8.314;    % [J/(mol·K)]
    cfg.pr_M     = 0.01604;  % [kg/mol]
    cfg.rho_comp_corr = 0.98;
    cfg.rho_comp_std  = 0.01;

    % ================================================================
    % PRESSURE ACOUSTIC NOISE  (updatePressure.m)
    % ================================================================
    cfg.p_acoustic_corr = 0.90;
    cfg.p_acoustic_std  = 0.002;   % [bar]  (original value — not 0.005)

    % ================================================================
    % TEMPERATURE NOISE AND JOULE-THOMSON COEFFICIENT  (updateTemperature.m)
    % ================================================================
    cfg.T_jt_coeff  = -0.45;   % [K/bar]
    cfg.T_turb_corr =  0.85;
    cfg.T_turb_std  =  0.05;   % [K]

    % ================================================================
    % EKF PARAMETER ALIASES  (initEKF.m)
    % ================================================================
    cfg.ekf_P0 = cfg.ekf_P0_diag;
    cfg.ekf_Qn = cfg.ekf_Q_diag;
    cfg.ekf_Rk = cfg.ekf_R_diag;

    % ================================================================
    % HISTORIAN PARAMETERS  (updateHistorian.m)
    % ================================================================
    cfg.historian_enable         = false;
    cfg.historian_deadband_p     = 0.1;
    cfg.historian_deadband_q     = 10.0;
    cfg.historian_deadband_T     = 0.5;
    cfg.historian_max_interval_s = 300.0;

    % ================================================================
    % FAULT INJECTION PARAMETERS  (applyFaultInjection.m)
    % ================================================================
    cfg.fault_enable      = false;
    cfg.fault_stuck_nodes = [15, 16, 17, 18];
    cfg.fault_stuck_prob  = 0.001;
    cfg.fault_stuck_dur_s = 30.0;
    cfg.fault_loss_prob   = 0.002;
    cfg.fault_max_consec  = 3;

    % ================================================================
    % SCAN JITTER PARAMETERS  (addScanJitter.m)
    % ================================================================
    cfg.jitter_enable         = false;
    cfg.jitter_platform       = 'codesys';
    cfg.jitter_codesys_std_ms = 20.0;
    cfg.jitter_codesys_max_ms = 150.0;
    cfg.jitter_s7_std_ms      = 1.5;
    cfg.jitter_s7_max_ms      = 10.0;

end
