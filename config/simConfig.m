function cfg = simConfig()
% simConfig  Single source of truth for all simulation parameters.
%
%  KEY LOGGING PARAMETERS:
%    cfg.log_every   — physics runs at 10 Hz (dt=0.1s), but only every
%                      log_every-th step is written to the dataset.
%                      log_every=10 → 1 Hz dataset rows (1 s timestep).
%                      Set to 1 to log every step at 10 Hz.
%
%    cfg.n_attacks   — number of attack windows to schedule.
%                      Set to 3 or 4 for a 100-min simulation.
%
%  Sections:
%    1.Time  2.Topology  3.Pipes  4.InitState  5.Compressors
%    6.PRS   7.Storage   8.EKF   9.PLC  10.PID  11.Noise
%    12.Alarms  13.SourceProfile  14.AttackSchedule  15.AttackParams

    %% 1. Time
    cfg.dt       = 0.1;          % physics time step (s)  — do NOT change
    cfg.T        = 100 * 60;     % total simulation time (100 min default)
    cfg.log_every = 10;          % log every N steps  →  1 Hz dataset rows
                                 % (10 steps × 0.1 s/step = 1.0 s per row)

    %% 2. Network topology -------------------------------------------------
    cfg.nodeNames = ["S1","J1","CS1","J2","J3","J4","CS2","J5", ...
                     "J6","PRS1","J7","STO","PRS2","S2", ...
                     "D1","D2","D3","D4","D5","D6"];

    cfg.nodeTypes = ["source","junction","compressor","junction", ...
                     "junction","junction","compressor","junction", ...
                     "junction","prs","junction","storage","prs","source", ...
                     "demand","demand","demand","demand","demand","demand"];

    cfg.edges = [
         1  2;   % E1:  S1   -> J1
         2  3;   % E2:  J1   -> CS1
         3  4;   % E3:  CS1  -> J2
         4  5;   % E4:  J2   -> J3
         5  6;   % E5:  J3   -> J4
         6  7;   % E6:  J4   -> CS2
         7  8;   % E7:  CS2  -> J5
         4  9;   % E8:  J2   -> J6   (valve)
         9 10;   % E9:  J6   -> PRS1
        10 15;   % E10: PRS1 -> D1
        10 16;   % E11: PRS1 -> D2
         5 11;   % E12: J3   -> J7
        14 11;   % E13: S2   -> J7
        11 12;   % E14: J7   -> STO  (valve)
        12  8;   % E15: STO  -> J5   (valve)
         8 13;   % E16: J5   -> PRS2
        13 17;   % E17: PRS2 -> D3
        13 18;   % E18: PRS2 -> D4
         6 19;   % E19: J4   -> D5
        11 20;   % E20: J7   -> D6
    ];

    cfg.edgeNames = ["E1","E2","E3","E4","E5","E6","E7","E8","E9","E10", ...
                     "E11","E12","E13","E14","E15","E16","E17","E18","E19","E20"];

    cfg.valveEdges    = [8, 14, 15];
    cfg.nodeElevation = [120, 100, 80, 70, 60, 50, 45, 35, ...
                          90,  85, 55, 20, 25, 75, ...
                          80,  75, 20, 15, 40, 50];

    %% 3. Pipe physical properties
    cfg.pipe_D     = 0.8;
    cfg.pipe_L     = 40e3;
    cfg.pipe_rough = 20e-6;
    cfg.node_V     = 6;
    cfg.c          = 350;
    cfg.gamma      = 1.3;

    cfg.pipe_L_vec = [50e3, 5e3, 5e3, 45e3, 45e3, 5e3, 5e3, ...
                      30e3, 30e3, 20e3, 20e3, ...
                      35e3, 40e3, 10e3, 10e3, ...
                      5e3, 25e3, 25e3, 15e3, 20e3];

    cfg.pipe_D_vec = [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, ...
                      0.6, 0.6, 0.5, 0.5, ...
                      0.6, 0.7, 0.5, 0.5, ...
                      0.7, 0.5, 0.5, 0.4, 0.4];

    %% 4. Initial state
    cfg.p0   = 50.0;
    cfg.T0   = 285;
    cfg.rho0 = 0.8;

    %% 5. Compressor stations
    cfg.comp1_node      = 3;
    cfg.comp1_ratio     = 1.25;
    cfg.comp1_ratio_min = 1.05;
    cfg.comp1_ratio_max = 1.80;
    cfg.comp1_a1 =  800;  cfg.comp1_a2 = -0.8;   cfg.comp1_a3 = -0.002;
    cfg.comp1_b1 = 0.82;  cfg.comp1_b2 = -0.002; cfg.comp1_b3 = -0.0001;

    cfg.comp2_node      = 7;
    cfg.comp2_ratio     = 1.15;
    cfg.comp2_ratio_min = 1.02;
    cfg.comp2_ratio_max = 1.60;
    cfg.comp2_a1 =  500;  cfg.comp2_a2 = -0.5;   cfg.comp2_a3 = -0.001;
    cfg.comp2_b1 = 0.80;  cfg.comp2_b2 = -0.002; cfg.comp2_b3 = -0.0001;

    cfg.comp_pulsation_amp  = 0.008;
    cfg.comp_pulsation_freq = 2.0;
    cfg.comp_surge_noise    = 0.005;
    cfg.comp_surge_corr     = 0.92;

    %% 6. Pressure Regulating Stations
    cfg.prs1_node     = 10;  cfg.prs1_setpoint = 30.0;
    cfg.prs1_deadband = 0.5; cfg.prs1_tau      = 5.0;

    cfg.prs2_node     = 13;  cfg.prs2_setpoint = 25.0;
    cfg.prs2_deadband = 0.5; cfg.prs2_tau      = 5.0;

    %% 7. Underground Storage
    cfg.sto_node           = 12;
    cfg.sto_capacity       = 1e9;
    cfg.sto_inventory_init = 0.60;
    cfg.sto_p_inject       = 52.0;
    cfg.sto_p_withdraw     = 46.0;
    cfg.sto_max_flow       = 5.0;
    cfg.sto_k_flow         = 0.5;

    %% 8. EKF
    cfg.ekf_P0 = 0.1;
    cfg.ekf_Qn = 1e-4;
    cfg.ekf_Rk = 0.1;

    %% 9. PLC / SCADA
    cfg.plc_period_z1  = 10;
    cfg.plc_period_z2  = 15;
    cfg.plc_period_z3  = 20;
    cfg.plc_latency    = 3;
    cfg.valve_open_default = 1;
    cfg.plc_period     = cfg.plc_period_z1;   % legacy alias

    %% 10. Control (PID)
    cfg.pid1_Kp = 0.4;  cfg.pid1_Ki = 0.008; cfg.pid1_Kd = 0.08;
    cfg.pid1_setpoint = 30.0;

    cfg.pid2_Kp = 0.3;  cfg.pid2_Ki = 0.005; cfg.pid2_Kd = 0.05;
    cfg.pid2_setpoint = 25.0;

    cfg.pid_D1_node   = 15;
    cfg.pid_D3_node   = 17;
    cfg.pid_PRS1_node = 10;
    cfg.pid_PRS2_node = 13;

    cfg.emer_shutdown_p = 65.0;
    cfg.alarm_P_high    = 60.0;
    cfg.alarm_P_low     = 15.0;
    cfg.alarm_ekf_resid = 2.0;
    cfg.alarm_comp_hi   = 1.75;
    cfg.valve_close_hi  = 52.0;
    cfg.valve_open_lo   = 44.0;

    %% 11. Physics noise
    cfg.sensor_noise       = 0.001;
    cfg.sensor_noise_floor = 0.0001;
    cfg.p_acoustic_std     = 0.005;
    cfg.p_acoustic_corr    = 0.88;
    cfg.flow_turb_std      = 0.008;
    cfg.flow_turb_corr     = 0.90;
    cfg.rough_var_std      = 0.10;
    cfg.rough_corr         = 0.9995;
    cfg.T_jt_coeff         = -0.45;
    cfg.T_turb_std         = 0.05;
    cfg.T_turb_corr        = 0.88;
    cfg.rho_comp_std       = 0.004;
    cfg.rho_comp_corr      = 0.9998;

    %% 12. Source profiles
    cfg.src_slow_amp   = 3.0;
    cfg.src_med_amp    = 1.5;
    cfg.src_fast_amp   = 0.5;
    cfg.src_trend      = 1.0;
    cfg.src_rw_amp     = 1.5;
    cfg.src_ar1_alpha  = 0.997;
    cfg.src_p_min      = 45.0;
    cfg.src_p_max      = 58.0;
    cfg.src2_p_min     = 42.0;
    cfg.src2_p_max     = 55.0;
    cfg.dem_base       = 0.60;
    cfg.dem_diurnal_amp    = 0.25;
    cfg.dem_diurnal_period = 86400;
    cfg.dem_morning_peak   = 7.0;
    cfg.dem_evening_peak   = 18.0;
    cfg.dem_noise_std      = 0.02;
    cfg.dem_min            = 0.10;
    cfg.dem_max            = 1.20;

    %% 13. Attack scheduling
    %  n_attacks: total attacks to place within the simulation window.
    %             3 or 4 is appropriate for a 100-min run — gives enough
    %             spacing (≥ 5 min gaps) without crowding the timeline.
    cfg.n_attacks      = 4;         % <── change to 3 if you want 3 attacks

    cfg.atk_warmup_s   = 10 * 60;   % 10 min warmup before first attack
    cfg.atk_recovery_s =  5 * 60;   % 5 min tail after last attack
    cfg.atk_min_gap_s  =  5 * 60;   % minimum gap between attacks
    cfg.atk_dur_min_s  = 180;       % shortest attack: 3 min
    cfg.atk_dur_max_s  = 480;       % longest attack:  8 min

    %% 14. Attack effect parameters
    cfg.atk1_spike_amp = 1.30;  cfg.atk1_osc_freq = 1/120;
    cfg.atk2_target_ratio = 1.70;  cfg.atk2_ramp_time = 90;
    cfg.atk3_cmd = 0;  cfg.atk3_valve_idx = 1;
    cfg.atk4_demand_scale = 2.5;  cfg.atk4_ramp_time = 60;
    cfg.atk5_target_node = 4;  cfg.atk5_bias_bar = -8.0;
    cfg.atk6_edges = [4, 5];  cfg.atk6_scale = 0.40;
    cfg.atk7_extra_latency = 50;
    cfg.atk8_edge = 12;  cfg.atk8_leak_frac = 0.45;  cfg.atk8_ramp_time = 60;
    cfg.atk9_target_nodes = [4, 5, 8];  cfg.atk9_bias_scale = 0.05;
    cfg.atk10_buffer_s = 60;

    %% 15. Peng-Robinson EOS
    cfg.pr_Tc    = 190.6;
    cfg.pr_Pc    = 46.1;
    cfg.pr_omega = 0.011;
    cfg.pr_M     = 0.01604;
    cfg.pr_R     = 8.314;
end