function cfg = randomize_attack_params(cfg, scenario_id)
% randomize_attack_params  Per-scenario attack parameter randomization.
%
%   cfg = randomize_attack_params(cfg, scenario_id)
%
%   Call from build_scenario_config immediately after applying overrides:
%     cfg = apply_cgd_overrides(cfg);
%     cfg = randomize_attack_params(cfg, scen.id);  ← ADD THIS LINE
%
%   Uses scenario_id as RNG seed → reproducible per scenario,
%   different across scenarios → diverse training distribution.
%
%   WHAT VARIES per scenario:
%     A1: spike amplitude, oscillation frequency
%     A2: target ratio, ramp time
%     A3: valve leak fraction, cycle period (NEW continuous ramp)
%     A4: demand scale, ramp time
%     A5: target node, bias magnitude, oscillation
%     A6: target edges, scale factor
%     A7: extra latency steps
%     A8: target edge, leak fraction
%     A9: target nodes, bias scale
%     A10: buffer duration
%     n_attacks: 4–10 per scenario

    rng(scenario_id * 42 + 7, 'twister');   % reproducible

    %% ── A1: Source Pressure Spike ────────────────────────────────────────
    cfg.atk1_spike_amp  = 1.15 + rand() * 0.25;   % [1.15, 1.40]
    cfg.atk1_osc_freq   = 0.005 + rand() * 0.015; % [0.005, 0.020] Hz
    cfg.atk1_spike_dur_s = 90 + rand() * 120;      % [90, 210]s  WAS fixed 60

    %% ── A2: Compressor Ratio Spoofing ────────────────────────────────────
    % Reduced max vs original (1.85 was too easy → F1=1.0)
    cfg.atk2_target_ratio = 1.40 + rand() * 0.15; % [1.40, 1.55]
    cfg.atk2_ramp_time    = 20   + rand() * 40;    % [20, 60]s

    %% ── A3: Valve Command Tampering — RAMP (fixes F1=0) ──────────────────
    % Binary instant close → F1=0. Ramp gives temporal gradient.
    cfg.atk3_ramp_time    = 20 + rand() * 30;      % [20, 50]s ramp from open to partial
    cfg.atk3_leak_frac    = 0.1 + rand() * 0.3;   % [0.1, 0.4] partial open during hold
    cfg.atk3_cycle_period = 60 + rand() * 60;      % [60, 120]s toggle cycle
    cfg.atk3_cmd          = 0;                     % still force closed at end of ramp

    %% ── A4: Demand Node Manipulation ─────────────────────────────────────
    cfg.atk4_demand_scale = 1.5 + rand() * 1.0;   % [1.5, 2.5]x
    cfg.atk4_ramp_time    = 30  + rand() * 60;     % [30, 90]s

    %% ── A5: Pressure Sensor Spoofing — stronger + varied node ────────────
    demand_nodes = [15, 16, 17, 18, 19, 20];       % D1–D6
    cfg.atk5_target_node = demand_nodes(randi(numel(demand_nodes)));
    cfg.atk5_bias_bar    = 2.0 + rand() * 3.0;    % [2.0, 5.0] WAS fixed 2.0
    cfg.atk5_osc_amp     = 0.5 + rand() * 1.5;    % [0.5, 2.0] NEW sinusoidal component
    cfg.atk5_osc_freq    = 0.02 + rand() * 0.08;  % [0.02, 0.10] Hz

    %% ── A6: Flow Meter Spoofing — not full zero (too easy) ───────────────
    all_edges = [1,2,3,4,5,6,7,8,9,10];
    n_targets = 1 + randi(2);                      % 1–3 edges affected
    cfg.atk6_edges = sort(all_edges(randperm(numel(all_edges), n_targets)));
    cfg.atk6_scale = 0.2 + rand() * 0.6;           % [0.2, 0.8]  WAS 0.0 (too easy)

    %% ── A7: PLC Latency Attack ────────────────────────────────────────────
    cfg.atk7_extra_latency = 3 + randi(8);         % [3, 10] extra steps

    %% ── A8: Pipeline Leak ────────────────────────────────────────────────
    main_edges = [3, 4, 5, 6, 7, 8];
    cfg.atk8_edge      = main_edges(randi(numel(main_edges)));
    cfg.atk8_leak_frac = 0.15 + rand() * 0.35;    % [0.15, 0.50]
    cfg.atk8_ramp_time = 30  + rand() * 60;        % [30, 90]s

    %% ── A9: Stealthy FDI ─────────────────────────────────────────────────
    % Pick 3 random nodes for the attack triangle (must stay realistic)
    candidate_nodes = [4, 5, 6, 8, 9, 10, 11, 15, 16, 17];
    cfg.atk9_target_nodes = sort(candidate_nodes(randperm(numel(candidate_nodes), 3)));
    cfg.atk9_bias_scale   = 0.03 + rand() * 0.07; % [3%, 10%]
    cfg.atk9_ramp_s       = 30   + rand() * 60;   % [30, 90]s

    %% ── A10: Replay Attack ────────────────────────────────────────────────
    cfg.atk10_buffer_s = 60 + rand() * 120;        % [60, 180]s buffer

    %% ── Attack count + selection ─────────────────────────────────────────
    cfg.n_attacks = 4 + randi(7);                  % [4, 10] per scenario
    % All 10 attack types available
    cfg.attack_selection = 1:10;
    cfg.forced_attack_id = [];                     % random each time

    fprintf('[randomize] sc=%d  n_atk=%d  A5node=%d  A6scale=%.2f  A8edge=%d  A9nodes=%s\n', ...
            scenario_id, cfg.n_attacks, cfg.atk5_target_node, cfg.atk6_scale, ...
            cfg.atk8_edge, mat2str(cfg.atk9_target_nodes));
end
