function cfg = simConfig()
% simConfig  Single source of truth for all simulation parameters.
%
%  NEW IN PHASE 5:
%    Section 16 — ADC quantisation (R2): simulates real PLC ADC resolution
%    Section 17 — Scan-cycle jitter  (R3): per-platform timing artefacts
%    Section 18 — A9 FDI parameters  (R1): stealthy triangle attack
%    Section 19 — A10 Replay params  (R4): rolling buffer replay

    %% 1. Time
    cfg.dt        = 0.1;
    cfg.T         = 100 * 60;
    cfg.log_every = 10;          % 1 Hz dataset rows

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

    %% 6. Pressure Regulating Stations
    cfg.prs1_node=10; cfg.prs1_setpoint=30.0; cfg.prs1_deadband=0.5; cfg.prs1_tau=5.0;
    cfg.prs2_node=13; cfg.prs2_setpoint=25.0; cfg.prs2_deadband=0.5; cfg.prs2_tau=5.0;

    %% 7. Underground Storage
    cfg.sto_node=12; cfg.sto_capacity=1e9; cfg.sto_inventory_init=0.60;
    cfg.sto_p_inject=52.0; cfg.sto_p_withdraw=46.0;
    cfg.sto_max_flow=5.0;  cfg.sto_k_flow=0.5;

    %% 8. EKF
    cfg.ekf_P0=0.1; cfg.ekf_Qn=1e-4; cfg.ekf_Rk=0.1;

    %% 9. PLC / SCADA
    cfg.plc_period_z1=10; cfg.plc_period_z2=15; cfg.plc_period_z3=20;
    cfg.plc_latency=3; cfg.valve_open_default=1;
    cfg.plc_period=cfg.plc_period_z1;

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
    cfg.n_attacks     = 4;
    cfg.atk_warmup_s  = 10*60;
    cfg.atk_recovery_s = 5*60;
    cfg.atk_min_gap_s  = 5*60;
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

    %% ── PHASE 5 ADDITIONS ────────────────────────────────────────────────

    %% 16. ADC Quantisation (R2) ─────────────────────────────────────────
    %  Simulates real PLC analog-to-digital converter resolution.
    %  Applied to sensor_p and sensor_q AFTER noise, AFTER spoofing.
    %
    %  Platform profiles:
    %    'codesys'  — INT16 range [-32768, 32767]; raw counts = 32767
    %                 CODESYS uses full signed INT16 for analog I/O
    %    's7_1200'  — Siemens SM1231 maps 0–10V → 0–27648 (not 0–65535)
    %                 This creates a characteristic stepped distribution
    %                 that differs from CODESYS — critical for portability
    %
    %  Full-scale values define the physical range each ADC channel spans.
    %  A value outside [0, full_scale] clips to the nearest rail.

    cfg.adc_enable   = true;          % set false to disable quantisation
    cfg.adc_platform = 'codesys';     % 'codesys' or 's7_1200'

    % Physical full-scale ranges per variable type
    cfg.adc_p_full_scale = 70.0;      % bar   — transmission pressure max
    cfg.adc_q_full_scale = 500.0;     % kg/s  — max expected flow magnitude
    cfg.adc_T_full_scale = 400.0;     % K     — temperature max

    % Platform-specific ADC count limits
    cfg.adc_counts_codesys = 32767;   % INT16 max (CODESYS raw)
    cfg.adc_counts_s7      = 27648;   % Siemens SM1231 analog input max
                                      % S7-1200 maps 0–10V → 0–27648

    %% 17. Scan-cycle jitter (R3) ────────────────────────────────────────
    %  Simulates per-platform timing artefacts in the polling interval.
    %  CODESYS soft-PLC on Windows: broad jitter (OS scheduling)
    %  S7-1200 hardware:            tight jitter (real-time kernel)
    %
    %  Jitter is added to inter-arrival timestamps in the dataset only
    %  (does not affect physics; purely a dataset realism feature).

    cfg.jitter_enable          = true;
    cfg.jitter_platform        = 'codesys';   % 'codesys' or 's7_1200'
    cfg.jitter_codesys_mean_ms = 0.0;         % zero mean (symmetric)
    cfg.jitter_codesys_std_ms  = 20.0;        % ±20 ms typical Windows soft-PLC
    cfg.jitter_codesys_max_ms  = 150.0;       % occasional OS preemption spike
    cfg.jitter_s7_mean_ms      = 0.0;
    cfg.jitter_s7_std_ms       = 1.5;         % ±1.5 ms S7-1200 hardware
    cfg.jitter_s7_max_ms       = 10.0;        % rare watchdog reschedule

    %% 18. A9 — Stealthy FDI (Liu-Ning-Reiter construction) (R1) ─────────
    %  Triangle attack on 3 topologically adjacent nodes.
    %  Attack vector a = H*c where H = I (identity observation model).
    %  Result: EKF innovation residual is IDENTICAL with and without attack.
    %  Detection requires physics cross-validation or spatial redundancy.
    %
    %  target_nodes: indices into the 20-node pressure vector
    %    Node 4 = J2 (main trunk junction)
    %    Node 5 = J3 (storage branch junction)
    %    Node 8 = J5 (compressor CS2 outlet)
    %  bias_scale: fraction of estimated nodal pressure injected as bias
    %  ramp_s: linear ramp duration — avoids rate-of-change detection

    cfg.atk9_target_nodes = [4, 5, 8];   % J2, J3, J5 — triangle subgraph
    cfg.atk9_bias_scale   = 0.05;        % 5% of nominal pressure per node
    cfg.atk9_ramp_s       = 30;          % ramp bias over 30 s

    %% 19. A10 — Replay Attack (Mo & Sinopoli formulation) ────────────────
    %  Rolling buffer records T_buf seconds of normal sensor readings.
    %  During attack: all correlated channels replaced with buffer content.
    %  ALL sensor channels replaced simultaneously — partial replacement
    %  is detectable via cross-channel inconsistency.
    %
    %  Frozen-noise-realisation signature: the same noise sequence repeats
    %  with period T_buf. Detectable via autocorrelation analysis.
    %
    %  buffer_s:    recording window (seconds of physics data to buffer)
    %  inject_mode: 'loop'   — replay buffer cyclically for attack duration
    %               'single' — replay buffer once then hold last value

    cfg.atk10_buffer_s   = 60;         % 60 s buffer (600 steps at 10 Hz)
    cfg.atk10_inject_mode = 'loop';    % cyclically replay the buffer
end