function cfg = simConfig()
% simConfig  Single source of truth for all simulation parameters.
%
%  Phase 6 additions:
%    Section 20 — CUSUM detector parameters
%    Section 21 — Historian / deadband compression
%    Section 22 — Fault injection (packet loss, stuck sensor)

    %% 1. Time
    cfg.dt        = 0.1;
    cfg.T         = 100 * 60;
    cfg.log_every = 10;

    %% 2. Network topology
    cfg.nodeNames = ["S1","J1","CS1","J2","J3","J4","CS2","J5", ...
                     "J6","PRS1","J7","STO","PRS2","S2", ...
                     "D1","D2","D3","D4","D5","D6"];
    cfg.nodeTypes = ["source","junction","compressor","junction", ...
                     "junction","junction","compressor","junction", ...
                     "junction","prs","junction","storage","prs","source", ...
                     "demand","demand","demand","demand","demand","demand"];
    cfg.edges = [
         1  2;  2  3;  3  4;  4  5;  5  6;  6  7;  7  8;
         4  9;  9 10; 10 15; 10 16;  5 11; 14 11; 11 12;
        12  8;  8 13; 13 17; 13 18;  6 19; 11 20;
    ];
    cfg.edgeNames = ["E1","E2","E3","E4","E5","E6","E7","E8","E9","E10", ...
                     "E11","E12","E13","E14","E15","E16","E17","E18","E19","E20"];
    cfg.valveEdges    = [8, 14, 15];
    cfg.nodeElevation = [120,100,80,70,60,50,45,35,90,85, ...
                          55, 20,25,75,80,75,20,15,40,50];

    %% 3. Pipe physical properties
    cfg.pipe_D     = 0.8;
    cfg.pipe_L     = 40e3;
    cfg.pipe_rough = 20e-6;
    cfg.node_V     = 6;
    cfg.c          = 350;
    cfg.gamma      = 1.3;
    cfg.pipe_L_vec = [50e3,5e3,5e3,45e3,45e3,5e3,5e3, ...
                      30e3,30e3,20e3,20e3, ...
                      35e3,40e3,10e3,10e3, ...
                      5e3,25e3,25e3,15e3,20e3];
    cfg.pipe_D_vec = [0.9,0.9,0.9,0.9,0.9,0.9,0.9, ...
                      0.6,0.6,0.5,0.5, ...
                      0.6,0.7,0.5,0.5, ...
                      0.7,0.5,0.5,0.4,0.4];

    %% 4. Initial state
    cfg.p0   = 50.0;
    cfg.T0   = 285;
    cfg.rho0 = 0.8;

    %% 5. Compressor stations
    cfg.comp1_node=3; cfg.comp1_ratio=1.25; cfg.comp1_ratio_min=1.05; cfg.comp1_ratio_max=1.80;
    cfg.comp1_a1=800;  cfg.comp1_a2=-0.8;   cfg.comp1_a3=-0.002;
    cfg.comp1_b1=0.82; cfg.comp1_b2=-0.002; cfg.comp1_b3=-0.0001;
    cfg.comp2_node=7;  cfg.comp2_ratio=1.15; cfg.comp2_ratio_min=1.02; cfg.comp2_ratio_max=1.60;
    cfg.comp2_a1=500;  cfg.comp2_a2=-0.5;   cfg.comp2_a3=-0.001;
    cfg.comp2_b1=0.80; cfg.comp2_b2=-0.002; cfg.comp2_b3=-0.0001;
    cfg.comp_pulsation_amp=0.008; cfg.comp_pulsation_freq=2.0;
    cfg.comp_surge_noise=0.005;   cfg.comp_surge_corr=0.92;

    %% 6. PRS
    cfg.prs1_node=10; cfg.prs1_setpoint=30.0; cfg.prs1_deadband=0.5; cfg.prs1_tau=5.0;
    cfg.prs2_node=13; cfg.prs2_setpoint=25.0; cfg.prs2_deadband=0.5; cfg.prs2_tau=5.0;

    %% 7. Storage
    cfg.sto_node=12; cfg.sto_capacity=1e9; cfg.sto_inventory_init=0.60;
    cfg.sto_p_inject=52.0; cfg.sto_p_withdraw=46.0;
    cfg.sto_max_flow=5.0;  cfg.sto_k_flow=0.5;

    %% 8. EKF
    cfg.ekf_P0=0.1; cfg.ekf_Qn=1e-4; cfg.ekf_Rk=0.1;

    %% 9. PLC / SCADA — zone periods in physics steps
    cfg.plc_period_z1 = 10;   % zone 1: every 10 steps = 1.0 s  (critical nodes)
    cfg.plc_period_z2 = 15;   % zone 2: every 15 steps = 1.5 s  (mid-priority)
    cfg.plc_period_z3 = 20;   % zone 3: every 20 steps = 2.0 s  (low-priority)
    cfg.plc_latency   = 3;
    cfg.valve_open_default = 1;
    cfg.plc_period    = cfg.plc_period_z1;   % legacy alias

    %  Node zone assignments (1-based node indices → zone 1/2/3)
    %  Zone 1: source + compressor + delivery nodes (high criticality)
    %  Zone 2: junction + PRS nodes (medium criticality)
    %  Zone 3: storage + secondary junction nodes (low criticality)
    cfg.plc_zone1_nodes = [1,3,7,14,15,16,17,18,19,20];   % S1,CS1,CS2,S2,D1-D6
    cfg.plc_zone2_nodes = [2,4,5,6,8,9,10,13];            % junctions + PRS nodes
    cfg.plc_zone3_nodes = [11,12];                          % J7, STO

    %% 10. Control (PID)
    cfg.pid1_Kp=0.4; cfg.pid1_Ki=0.008; cfg.pid1_Kd=0.08; cfg.pid1_setpoint=30.0;
    cfg.pid2_Kp=0.3; cfg.pid2_Ki=0.005; cfg.pid2_Kd=0.05; cfg.pid2_setpoint=25.0;
    cfg.pid_D1_node=15; cfg.pid_D3_node=17; cfg.pid_PRS1_node=10; cfg.pid_PRS2_node=13;
    cfg.emer_shutdown_p=65.0; cfg.alarm_P_high=60.0; cfg.alarm_P_low=15.0;
    cfg.alarm_ekf_resid=2.0;  cfg.alarm_comp_hi=1.75;
    cfg.valve_close_hi=52.0;  cfg.valve_open_lo=44.0;

    %% 11. Physics noise
    cfg.sensor_noise=0.001; cfg.sensor_noise_floor=0.0001;
    cfg.p_acoustic_std=0.005; cfg.p_acoustic_corr=0.88;
    cfg.flow_turb_std=0.008;  cfg.flow_turb_corr=0.90;
    cfg.rough_var_std=0.10;   cfg.rough_corr=0.9995;
    cfg.T_jt_coeff=-0.45; cfg.T_turb_std=0.05; cfg.T_turb_corr=0.88;
    cfg.rho_comp_std=0.004; cfg.rho_comp_corr=0.9998;

    %% 12. Source profiles
    cfg.src_slow_amp=3.0; cfg.src_med_amp=1.5; cfg.src_fast_amp=0.5;
    cfg.src_trend=1.0;    cfg.src_rw_amp=1.5;  cfg.src_ar1_alpha=0.997;
    cfg.src_p_min=45.0; cfg.src_p_max=58.0;
    cfg.src2_p_min=42.0; cfg.src2_p_max=55.0;
    cfg.dem_base=0.60; cfg.dem_diurnal_amp=0.25; cfg.dem_diurnal_period=86400;
    cfg.dem_morning_peak=7.0; cfg.dem_evening_peak=18.0;
    cfg.dem_noise_std=0.02; cfg.dem_min=0.10; cfg.dem_max=1.20;

    %% 13. Attack scheduling
    cfg.n_attacks      = 4;
    cfg.atk_warmup_s   = 10*60;
    cfg.atk_recovery_s =  5*60;
    cfg.atk_min_gap_s  =  5*60;
    cfg.atk_dur_min_s  = 180;
    cfg.atk_dur_max_s  = 480;

    %% 14. Attack effect parameters (A1–A8)
    cfg.atk1_spike_amp=1.30;  cfg.atk1_osc_freq=1/120;
    cfg.atk2_target_ratio=1.70; cfg.atk2_ramp_time=90;
    cfg.atk3_cmd=0; cfg.atk3_valve_idx=1;
    cfg.atk4_demand_scale=2.5; cfg.atk4_ramp_time=60;
    cfg.atk5_target_node=4;   cfg.atk5_bias_bar=-8.0;
    cfg.atk6_edges=[4,5];     cfg.atk6_scale=0.40;
    cfg.atk7_extra_latency=50;
    cfg.atk8_edge=12; cfg.atk8_leak_frac=0.45; cfg.atk8_ramp_time=60;

    %% 15. Peng-Robinson EOS
    cfg.pr_Tc=190.6; cfg.pr_Pc=46.1; cfg.pr_omega=0.011;
    cfg.pr_M=0.01604; cfg.pr_R=8.314;

    %% 16. ADC Quantisation (Phase 5 / R2)
    cfg.adc_enable          = true;
    cfg.adc_platform        = 'codesys';   % 'codesys' or 's7_1200'
    cfg.adc_p_full_scale    = 70.0;
    cfg.adc_q_full_scale    = 500.0;
    cfg.adc_T_full_scale    = 400.0;
    cfg.adc_counts_codesys  = 32767;
    cfg.adc_counts_s7       = 27648;

    %% 17. Scan-cycle jitter (Phase 5 / R3)
    cfg.jitter_enable          = true;
    cfg.jitter_platform        = 'codesys';
    cfg.jitter_codesys_mean_ms = 0.0;
    cfg.jitter_codesys_std_ms  = 20.0;
    cfg.jitter_codesys_max_ms  = 150.0;
    cfg.jitter_s7_mean_ms      = 0.0;
    cfg.jitter_s7_std_ms       = 1.5;
    cfg.jitter_s7_max_ms       = 10.0;

    %% 18. A9 Stealthy FDI (Phase 5 / R1)
    cfg.atk9_target_nodes = [4, 5, 8];
    cfg.atk9_bias_scale   = 0.05;
    cfg.atk9_ramp_s       = 30;

    %% 19. A10 Replay (Phase 5)
    cfg.atk10_buffer_s    = 60;
    cfg.atk10_inject_mode = 'loop';

    %% ── PHASE 6 ADDITIONS ────────────────────────────────────────────────

    %% 20. CUSUM Detector (Phase 6 / R4)
    %  Cumulative-sum sequential change-point detector on EKF innovations.
    %  Runs in parallel with EKF threshold alarm — provides a paired
    %  statistical test for the thesis results section.
    %
    %  slack:     allowance subtracted each step (controls sensitivity vs
    %             false-alarm rate). Typical: 0.5–1.5 × noise std.
    %  threshold: CUSUM statistic alarm level. Larger = fewer false alarms.
    %             Set by ARL (average run length) analysis offline.
    %  reset_on_alarm: if true, CUSUM resets to 0 after each alarm
    %                  (one-sided CUSUM with reset = CUSUM Page test)

    cfg.cusum_enable      = true;
    cfg.cusum_slack       = 1.0;    % in normalised innovation units
    cfg.cusum_threshold   = 10.0;   % alarm when S(k) > threshold
    cfg.cusum_reset_on_alarm = true;

    %% 21. Historian / Deadband Compression (Phase 6)
    %  Real SCADA historians record a new value only when the measurement
    %  changes by more than a deadband threshold since last stored value.
    %  This produces an irregular-timestep secondary dataset.
    %
    %  Output file: automated_dataset/historian_*.csv
    %  Format: [Timestamp_s, NodeName, Value, Unit, ATTACK_ID]
    %          (one row per change event, not per timestep)

    cfg.historian_enable         = true;
    cfg.historian_deadband_p     = 0.10;    % bar   — pressure deadband
    cfg.historian_deadband_q     = 0.50;    % kg/s  — flow deadband
    cfg.historian_deadband_T     = 0.20;    % K     — temperature deadband
    cfg.historian_max_interval_s = 60.0;    % force write at least every 60s

    %% 22. Fault Injection — Packet Loss + Stuck Sensor (Phase 6)
    %  Simulates communication faults independent of cyberattacks.
    %  Fault events are labelled separately from attack labels (FAULT_ID).
    %
    %  PACKET LOSS: sensor reading is dropped; PLC retains last-known value.
    %    loss_prob: per-step Bernoulli probability of a packet drop
    %    max_consec: maximum consecutive steps before comms declared failed
    %
    %  STUCK SENSOR: sensor freezes at its last valid reading.
    %    stuck_prob:  probability per step of a sensor getting stuck
    %    stuck_dur_s: typical stuck duration (exponential distribution mean)
    %    stuck_nodes: subset of nodes that can get stuck (high-wear sensors)

    cfg.fault_enable         = true;
    cfg.fault_loss_prob      = 0.002;    % 0.2% per step ≈ 1 drop per 8 min
    cfg.fault_max_consec     = 5;        % 5 consecutive drops = comm fault
    cfg.fault_stuck_prob     = 0.0005;   % 0.05% per step ≈ 1 stuck per 33 min
    cfg.fault_stuck_dur_s    = 30;       % mean stuck duration = 30 s
    cfg.fault_stuck_nodes    = [1,3,7,15,17];   % S1, CS1, CS2, D1, D3
end