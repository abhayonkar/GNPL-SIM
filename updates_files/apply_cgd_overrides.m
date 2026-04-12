function cfg = apply_cgd_overrides(cfg)
% apply_cgd_overrides  Enforce Phase 0 stability values and fill any
%                      missing fields before a 48h or windowed sweep.
%
%   cfg = apply_cgd_overrides(cfg)
%
%   Called by run_48h_continuous (line 70) and run_attack_windows
%   immediately after simConfig().  Uses isfield guards so it is safe
%   to call even when simConfig is already fully updated.
%
%   Every default here matches the original simConfig.m values.
%   The ONLY intentional change from simConfig defaults is node_V = 500.

    % ── Phase 0: Primary stability fix ───────────────────────────────────
    cfg.node_V = 500.0;   % MUST be 500 — do not soften this

    % Acoustic noise (match original simConfig value exactly)
    if ~isfield(cfg, 'p_acoustic_corr'), cfg.p_acoustic_corr = 0.90;  end
    if ~isfield(cfg, 'p_acoustic_std'),  cfg.p_acoustic_std  = 0.002; end  % [bar]

    % ── Attack schedule fields ────────────────────────────────────────────
    % These match the original simConfig atk_dur values (60/300 s).
    % run_48h_continuous overrides them via build_continuous_attack_schedule
    % but they must exist as a fallback.
    if ~isfield(cfg, 'atk_recovery_s'), cfg.atk_recovery_s = 120.0; end
    if ~isfield(cfg, 'atk_min_gap_s'),  cfg.atk_min_gap_s  =  60.0; end
    if ~isfield(cfg, 'atk_dur_min_s'),  cfg.atk_dur_min_s  =  60.0; end  % [s]
    if ~isfield(cfg, 'atk_dur_max_s'),  cfg.atk_dur_max_s  = 300.0; end  % [s]

    % ── Demand noise fields ───────────────────────────────────────────────
    if ~isfield(cfg, 'dem_base'),         cfg.dem_base         = 0.60;  end
    if ~isfield(cfg, 'dem_noise_std'),    cfg.dem_noise_std    = 0.015; end
    if ~isfield(cfg, 'dem_diurnal_amp'),  cfg.dem_diurnal_amp  = 0.20;  end
    if ~isfield(cfg, 'dem_spike_enable'), cfg.dem_spike_enable = false;  end

    % ── Roughness / turbulence AR(1) ──────────────────────────────────────
    % IMPORTANT: flow_turb_std is in SCMD (not a fraction).
    % Original simConfig value is 5.0 SCMD.
    if ~isfield(cfg, 'rough_corr'),     cfg.rough_corr     = 0.95;  end
    if ~isfield(cfg, 'rough_var_std'),  cfg.rough_var_std  = 0.01;  end  % fraction
    if ~isfield(cfg, 'flow_turb_corr'), cfg.flow_turb_corr = 0.85;  end
    if ~isfield(cfg, 'flow_turb_std'),  cfg.flow_turb_std  = 5.0;   end  % [SCMD]

    % ── Sensor noise ─────────────────────────────────────────────────────
    if ~isfield(cfg, 'sensor_noise'),       cfg.sensor_noise       = 0.005; end
    if ~isfield(cfg, 'sensor_noise_floor'), cfg.sensor_noise_floor = 0.01;  end

    % ── PLC / latency ────────────────────────────────────────────────────
    if ~isfield(cfg, 'plc_latency'),        cfg.plc_latency        = 1;    end
    if ~isfield(cfg, 'atk7_extra_latency'), cfg.atk7_extra_latency = 5;    end

    % ── Storage ───────────────────────────────────────────────────────────
    if ~isfield(cfg, 'sto_inventory_init'), cfg.sto_inventory_init = 0.60; end
    if ~isfield(cfg, 'sto_max_flow'),       cfg.sto_max_flow       = 200.0;end
    if ~isfield(cfg, 'sto_capacity'),       cfg.sto_capacity       = 1.0;  end

    % ── ADC (original values) ─────────────────────────────────────────────
    if ~isfield(cfg, 'adc_enable'),         cfg.adc_enable         = false; end
    if ~isfield(cfg, 'adc_bits'),           cfg.adc_bits           = 12;    end
    if ~isfield(cfg, 'adc_p_full_scale'),   cfg.adc_p_full_scale   = 30.0;  end  % NOT 40
    if ~isfield(cfg, 'adc_q_full_scale'),   cfg.adc_q_full_scale   = 2000.0;end  % NOT 3000

    % ── Source 2 pressure limits ──────────────────────────────────────────
    if ~isfield(cfg, 'src2_p_min'), cfg.src2_p_min = 20.0; end
    if ~isfield(cfg, 'src2_p_max'), cfg.src2_p_max = 26.0; end

    % ── Per-compressor ratio limits ───────────────────────────────────────
    if ~isfield(cfg, 'comp1_ratio_min'), cfg.comp1_ratio_min = 1.1;  end
    if ~isfield(cfg, 'comp1_ratio_max'), cfg.comp1_ratio_max = 1.6;  end
    if ~isfield(cfg, 'comp2_ratio_min'), cfg.comp2_ratio_min = 1.1;  end
    if ~isfield(cfg, 'comp2_ratio_max'), cfg.comp2_ratio_max = 1.6;  end
    if ~isfield(cfg, 'comp1_ratio'),     cfg.comp1_ratio     = 1.3;  end
    if ~isfield(cfg, 'comp2_ratio'),     cfg.comp2_ratio     = 1.25; end

    % ── Source profile parameters ─────────────────────────────────────────
    if ~isfield(cfg, 'src_slow_amp'),  cfg.src_slow_amp  = 0.50;  end
    if ~isfield(cfg, 'src_med_amp'),   cfg.src_med_amp   = 0.20;  end
    if ~isfield(cfg, 'src_fast_amp'),  cfg.src_fast_amp  = 0.10;  end
    if ~isfield(cfg, 'src_trend'),     cfg.src_trend     = 0.00;  end
    if ~isfield(cfg, 'src_rw_amp'),    cfg.src_rw_amp    = 0.15;  end
    if ~isfield(cfg, 'src_ar1_alpha'), cfg.src_ar1_alpha = 0.98;  end

    % ── Alarm thresholds ──────────────────────────────────────────────────
    if ~isfield(cfg, 'alarm_P_high'),    cfg.alarm_P_high    = 26.0; end
    if ~isfield(cfg, 'alarm_P_low'),     cfg.alarm_P_low     = 14.0; end
    if ~isfield(cfg, 'atk_warmup_s'),    cfg.atk_warmup_s    = 120.0;end
    if ~isfield(cfg, 'alarm_ekf_resid'), cfg.alarm_ekf_resid = 2.0;  end
    if ~isfield(cfg, 'alarm_comp_hi'),   cfg.alarm_comp_hi   = 1.55; end

    % ── PLC zone configuration ────────────────────────────────────────────
    if ~isfield(cfg, 'plc_period_z1'),   cfg.plc_period_z1   = 10;              end
    if ~isfield(cfg, 'plc_period_z2'),   cfg.plc_period_z2   = 20;              end
    if ~isfield(cfg, 'plc_period_z3'),   cfg.plc_period_z3   = 50;              end
    if ~isfield(cfg, 'plc_zone1_nodes'), cfg.plc_zone1_nodes = [1 3 7];         end
    if ~isfield(cfg, 'plc_zone2_nodes'), cfg.plc_zone2_nodes = [2 4 5 6 8 9 10 11 12 13]; end
    if ~isfield(cfg, 'plc_zone3_nodes'), cfg.plc_zone3_nodes = [14 15 16 17 18 19 20]; end
    if ~isfield(cfg, 'valve_open_default'), cfg.valve_open_default = 1;          end

    % ── Compressor curves ─────────────────────────────────────────────────
    if ~isfield(cfg, 'comp1_a1'), cfg.comp1_a1 =  50000; end
    if ~isfield(cfg, 'comp1_a2'), cfg.comp1_a2 =   -100; end
    if ~isfield(cfg, 'comp1_a3'), cfg.comp1_a3 =   -0.5; end
    if ~isfield(cfg, 'comp1_b1'), cfg.comp1_b1 =   0.60; end
    if ~isfield(cfg, 'comp1_b2'), cfg.comp1_b2 =  0.010; end
    if ~isfield(cfg, 'comp1_b3'), cfg.comp1_b3 =  -2e-4; end
    if ~isfield(cfg, 'comp2_a1'), cfg.comp2_a1 =  40000; end
    if ~isfield(cfg, 'comp2_a2'), cfg.comp2_a2 =   -100; end
    if ~isfield(cfg, 'comp2_a3'), cfg.comp2_a3 =   -0.5; end
    if ~isfield(cfg, 'comp2_b1'), cfg.comp2_b1 =   0.60; end
    if ~isfield(cfg, 'comp2_b2'), cfg.comp2_b2 =  0.010; end
    if ~isfield(cfg, 'comp2_b3'), cfg.comp2_b3 =  -2e-4; end
    if ~isfield(cfg, 'comp_pulsation_amp'),  cfg.comp_pulsation_amp  = 0.02;  end
    if ~isfield(cfg, 'comp_pulsation_freq'), cfg.comp_pulsation_freq = 25.0;  end
    if ~isfield(cfg, 'comp_surge_corr'),     cfg.comp_surge_corr     = 0.90;  end
    if ~isfield(cfg, 'comp_surge_noise'),    cfg.comp_surge_noise    = 0.005; end

    % ── PRS tuning ────────────────────────────────────────────────────────
    if ~isfield(cfg, 'prs1_deadband'), cfg.prs1_deadband = 0.5;  end
    if ~isfield(cfg, 'prs1_tau'),      cfg.prs1_tau      = 30.0; end
    if ~isfield(cfg, 'prs2_deadband'), cfg.prs2_deadband = 0.5;  end
    if ~isfield(cfg, 'prs2_tau'),      cfg.prs2_tau      = 30.0; end

    % ── Peng-Robinson EOS ─────────────────────────────────────────────────
    if ~isfield(cfg, 'pr_Tc'),        cfg.pr_Tc        = 190.6;  end
    if ~isfield(cfg, 'pr_Pc'),        cfg.pr_Pc        = 46.1;   end
    if ~isfield(cfg, 'pr_omega'),     cfg.pr_omega     = 0.011;  end
    if ~isfield(cfg, 'pr_R'),         cfg.pr_R         = 8.314;  end
    if ~isfield(cfg, 'pr_M'),         cfg.pr_M         = 0.01604;end
    if ~isfield(cfg, 'rho_comp_corr'),cfg.rho_comp_corr= 0.98;   end
    if ~isfield(cfg, 'rho_comp_std'), cfg.rho_comp_std = 0.01;   end

    % ── Temperature ───────────────────────────────────────────────────────
    if ~isfield(cfg, 'T_jt_coeff'),  cfg.T_jt_coeff  = -0.45;  end
    if ~isfield(cfg, 'T_turb_corr'), cfg.T_turb_corr =  0.85;  end
    if ~isfield(cfg, 'T_turb_std'),  cfg.T_turb_std  =  0.05;  end

    % ── EKF aliases ───────────────────────────────────────────────────────
    if ~isfield(cfg, 'ekf_P0'), cfg.ekf_P0 = cfg.ekf_P0_diag; end
    if ~isfield(cfg, 'ekf_Qn'), cfg.ekf_Qn = cfg.ekf_Q_diag;  end
    if ~isfield(cfg, 'ekf_Rk'), cfg.ekf_Rk = cfg.ekf_R_diag;  end
end
