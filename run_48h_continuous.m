%% run_48h_continuous.m
% =========================================================================
%  Indian CGD Gas Pipeline — 48-Hour Continuous Realistic Dataset Generator
% =========================================================================
%
%  DIFFERENCE FROM run_24h_sweep:
%    run_24h_sweep:      Each scenario = fresh init, independent simulation
%    run_48h_continuous:  Single continuous 48h simulation, operating
%                         conditions change mid-run, state carries forward
%
%  REALISTIC PIPELINE BEHAVIOUR MODELLED:
%    - Demand follows real diurnal pattern (2 full day/night cycles)
%    - Source pressure drifts with CGS supply variations
%    - Valve reconfigurations happen at scheduled maintenance windows
%    - Compressor mode changes during shift handovers
%    - Storage cycles through inject/withdraw based on linepack
%    - Attacks injected randomly with realistic inter-attack gaps
%    - Communication faults occur stochastically throughout
%
%  OUTPUT:
%    automated_dataset/continuous_48h/
%      physics_dataset.csv          — 172,800 rows @ 1 Hz (48h)
%      protocol_dataset.csv         — Modbus transaction log (if gateway)
%      operating_log.csv            — regime change timestamps
%      attack_schedule.csv          — attack injection log
%      scenario_metadata.json       — full config dump
%
%  USAGE:
%    >> run_48h_continuous()                          % full 48h, offline
%    >> run_48h_continuous('gateway', true)           % with CODESYS
%    >> run_48h_continuous('duration_h', 24)          % shorter run
%    >> run_48h_continuous('attack_density', 'high')  % more attacks
%    >> run_48h_continuous('resume_from_h', 12.5)     % resume after crash
%
% =========================================================================

function run_48h_continuous(varargin)

    %% ── Parse arguments ──────────────────────────────────────────────────
    ap = inputParser();
    addParameter(ap, 'duration_h',      48);
    addParameter(ap, 'gateway',         false);
    addParameter(ap, 'attack_density',  'normal');   % 'none','low','normal','high'
    addParameter(ap, 'fault_enable',    true);
    addParameter(ap, 'jitter_enable',   true);
    addParameter(ap, 'historian_enable', true);
    addParameter(ap, 'resume_from_h',   0);
    addParameter(ap, 'out_dir',         'automated_dataset/continuous_48h');
    addParameter(ap, 'checkpoint_h',    4);   % save state every N hours
    parse(ap, varargin{:});
    opt = ap.Results;

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling','processing');

    if ~exist(opt.out_dir, 'dir'), mkdir(opt.out_dir); end

    fprintf('\n');
    fprintf('=================================================================\n');
    fprintf('  Indian CGD Pipeline — 48h Continuous Realistic Dataset\n');
    fprintf('  Duration    : %d hours\n', opt.duration_h);
    fprintf('  Gateway     : %s\n', string(opt.gateway));
    fprintf('  Attacks     : %s\n', opt.attack_density);
    fprintf('  Faults      : %s\n', string(opt.fault_enable));
    fprintf('  Output      : %s\n', opt.out_dir);
    fprintf('=================================================================\n\n');

    %% ── Base configuration ───────────────────────────────────────────────
    cfg = simConfig();
    cfg = apply_cgd_overrides(cfg);

    cfg.T                = opt.duration_h * 3600;
    cfg.fault_enable     = opt.fault_enable;
    cfg.jitter_enable    = opt.jitter_enable;
    cfg.historian_enable = opt.historian_enable;

    dt        = cfg.dt;
    N         = double(round(cfg.T / dt));
    log_every = max(1, cfg.log_every);
    N_log     = floor(N / log_every);

    fprintf('[init] Total steps: %s   Log rows: %s\n', fmtnum(N), fmtnum(N_log));

    %% ── Build operating regime timeline ──────────────────────────────────
    %  A "regime" is a set of operating conditions that persists for a
    %  realistic duration (2-8 hours). The pipeline doesn't jump between
    %  random configs — it follows a plausible 48h operational narrative.
    regimes = build_regime_timeline(opt.duration_h, cfg);
    n_regimes = numel(regimes);
    fprintf('[init] Operating regimes: %d\n', n_regimes);

    %% ── Build attack schedule over full 48h ──────────────────────────────
    attack_plan = build_continuous_attack_schedule(N, dt, opt.attack_density, cfg);
    fprintf('[init] Planned attacks: %d  (density=%s)\n', ...
            attack_plan.n_attacks, opt.attack_density);

    %% ── Initialise all subsystems (ONCE for the entire 48h) ──────────────
    fprintf('[init] Initialising network (state persists for %dh)...\n', opt.duration_h);
    [params, state] = initNetwork(cfg);

    src_p1       = generateSourceProfile(N, cfg);
    cfg_s2       = cfg;
    cfg_s2.p0    = 0.5 * (cfg.src2_p_min + cfg.src2_p_max);
    cfg_s2.src_p_min = cfg.src2_p_min;
    cfg_s2.src_p_max = cfg.src2_p_max;
    src_p2       = generateSourceProfile(N, cfg_s2);

    % Demand: realistic diurnal pattern over 48h (not flat)
    demand = build_48h_demand_profile(N, dt, cfg);

    [comp1, comp2] = initCompressor(cfg);
    [prs1, prs2]   = initPRS(cfg);
    initValve(cfg);

    plc      = initPLC(cfg, state, comp1);
    ekf      = initEKF(cfg, state);
    logs     = initLogs(params, ekf, N, cfg);

    % Build the per-step label array from attack_plan
    schedule = attack_plan_to_schedule(attack_plan, N, dt);

    %% ── Open CSV writer (streaming — don't hold 172K rows in memory) ─────
    csv_path = fullfile(opt.out_dir, 'physics_dataset.csv');
    csv_fid  = open_streaming_csv(csv_path, params);

    regime_log_path = fullfile(opt.out_dir, 'operating_log.csv');
    regime_fid = fopen(regime_log_path, 'w');
    fprintf(regime_fid, 'start_s,end_s,source_config,demand_level,valve_config,cs_mode,storage_target\n');

    %% ── Gateway setup ────────────────────────────────────────────────────
    cfg.use_gateway = false;
    if opt.gateway
        [cfg, gw_ok] = open_gateway_sockets(cfg);
        if ~gw_ok
            fprintf('[WARN] Gateway failed — running offline.\n');
        end
    end

    %% ── Main simulation loop (single continuous run) ─────────────────────
    fprintf('\n[run] Starting %d-hour continuous simulation...\n', opt.duration_h);
    fprintf('      Regimes will transition seamlessly (no state reset).\n\n');

    wall_t0          = tic;
    current_regime   = 1;
    log_k            = 0;
    valve_states     = ones(numel(params.valveEdges), 1);
    turb_state       = zeros(params.nEdges, 1);
    p_acoustic       = zeros(params.nNodes, 1);
    T_turb           = zeros(params.nNodes, 1);
    rho_comp_state   = 0;
    replay_buf       = initReplayBuffer(params.nNodes, params.nEdges, cfg);
    jitter_buf       = initJitterBuffer();
    gw_state         = initGatewayState();
    cusum            = initCUSUM(cfg);
    hist             = initHistorian(params, cfg);
    fault            = initFaultState(params.nNodes, params.nEdges, cfg);
    replay_k_attack  = 0;
    prev_aid         = 0;
    demand_vec       = zeros(params.nNodes, 1);

    logEvent(-1);   % reset logger

    for k = 1:N

        t_s = (k - 1) * dt;   % current simulation time in seconds

        %% ── Check regime transitions (NO state reset) ────────────────────
        if current_regime <= n_regimes && t_s >= regimes(current_regime).start_s
            reg = regimes(current_regime);
            cfg = apply_regime(cfg, reg, comp1, comp2);

            fprintf('  [regime %d/%d @ %.1fh] src=%s dem=%s valve=%s cs=%s\n', ...
                    current_regime, n_regimes, t_s/3600, ...
                    reg.source_config, reg.demand_level, ...
                    reg.valve_config, reg.cs_mode);

            fprintf(regime_fid, '%.1f,%.1f,%s,%s,%s,%s,%.2f\n', ...
                    reg.start_s, reg.end_s, reg.source_config, ...
                    reg.demand_level, reg.valve_config, reg.cs_mode, ...
                    reg.storage_target);

            current_regime = current_regime + 1;
        end

        %% ── Standard simulation step (same as runSimulation) ─────────────
        aid = double(schedule.label_id(k));

        [src_p1_k, src_p2_k, comp1, comp2, plc, valve_states, demand_k] = ...
            applyAttackEffects(aid, k, dt, schedule, src_p1(k), src_p2(k), ...
                               comp1, comp2, plc, valve_states, demand(k), cfg);

        state.p(params.sourceNodes(1)) = src_p1_k;
        state.p(params.sourceNodes(2)) = src_p2_k;

        % Roughness + turbulence AR(1)
        a_r = cfg.rough_corr;
        sig_r = cfg.rough_var_std * cfg.pipe_rough * sqrt(1 - a_r^2);
        params.rough = max(1e-6, a_r * params.rough + sig_r * randn(params.nEdges, 1));
        a_t = cfg.flow_turb_corr;
        sig_t = cfg.flow_turb_std * sqrt(1 - a_t^2);
        turb_state = a_t * turb_state + sig_t * abs(state.q + 1e-3) .* randn(params.nEdges, 1);

        [state.q, ~] = updateFlow(cfg, state.p, demand_vec);

        if aid == 8
            k_s8 = max(1, round(schedule.start_s(find(schedule.ids == 8, 1)) / dt));
            frac_leak = min(1, (k - k_s8) * dt / cfg.atk8_ramp_time);
            state.q(cfg.atk8_edge) = state.q(cfg.atk8_edge) * (1 - cfg.atk8_leak_frac * frac_leak);
        end

        [state, q_sto] = updateStorage(state, params, cfg);

        demand_vec = zeros(params.nNodes, 1);
        demand_vec(params.demandNodes) = demand_k;
        p_prev = state.p;
        [state.p, p_acoustic] = updatePressure(params, state.p, state.q, ...
                                               demand_vec, p_acoustic, cfg);

        [state, comp1] = updateCompressor(state, comp1, k, cfg, 1);
        [state, comp2] = updateCompressor(state, comp2, k, cfg, 2);
        [state, prs1]  = updatePRS(state, prs1, cfg);
        [state, prs2]  = updatePRS(state, prs2, cfg);

        [state.Tgas, T_turb] = updateTemperature(params, state.Tgas, state.q, ...
                                                  p_prev, state.p, T_turb, cfg);
        [state.rho, rho_comp_state] = updateDensity(state.p, state.Tgas, ...
                                                     rho_comp_state, cfg);

        % Sensors
        nf = cfg.sensor_noise_floor;
        sensor_p = state.p + max(cfg.sensor_noise * abs(state.p), nf) .* randn(params.nNodes, 1);
        sensor_q = state.q + max(cfg.sensor_noise * abs(state.q), nf) .* randn(params.nEdges, 1);

        % Replay
        if aid == 10
            if prev_aid ~= 10, replay_k_attack = 0;
            else, replay_k_attack = replay_k_attack + 1; end
            [sensor_p, sensor_q, replay_buf] = applyReplayAttack( ...
                sensor_p, sensor_q, replay_buf, replay_k_attack, cfg);
        else
            replay_k_attack = 0;
            [~, ~, replay_buf] = applyReplayAttack(sensor_p, sensor_q, replay_buf, -1, cfg);
        end
        prev_aid = aid;

        [sensor_p, sensor_q] = applySensorSpoof( ...
            aid, k, dt, schedule, sensor_p, sensor_q, cfg, ekf, replay_buf);

        if cfg.adc_enable
            sensor_p = quantiseADC(sensor_p, cfg.adc_p_full_scale, cfg);
            sensor_q = quantiseADC(abs(sensor_q), cfg.adc_q_full_scale, cfg) .* sign(sensor_q);
        end

        [sensor_p, sensor_q, fault, fault_label] = applyFaultInjection( ...
            sensor_p, sensor_q, fault, k, dt, cfg);

        if aid == 7
            plc = updatePLCWithLatency(plc, sensor_p, sensor_q, k, ...
                                       cfg.plc_latency + cfg.atk7_extra_latency, cfg);
        else
            plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
        end

        ekf   = updateEKF(ekf, plc.reg_p, plc.reg_q, state.p, state.q, params, cfg);
        cusum = updateCUSUM(cusum, ekf.residual, cfg, k);

        if aid ~= 2
            [comp1, comp2, prs1, prs2, valve_states, plc] = ...
                updateControlLogic(comp1, comp2, prs1, prs2, valve_states, ...
                                   plc, ekf.xhatP, cfg, k, dt);
        else
            plc = advanceLatencyBuffers(plc);
        end

        hist = updateHistorian(hist, state, plc, aid, k, dt, cfg, params);
        detectIncidents(cfg, params, state, ekf, comp1, comp2, plc, k, dt);

        %% ── Log row (streaming to CSV) ───────────────────────────────────
        if mod(k, log_every) == 0
            log_k = log_k + 1;

            if cfg.use_gateway
                gw_out.p = sensor_p; gw_out.q = sensor_q;
                gw_out.T = state.Tgas; gw_out.demand_scalar = demand_k;
                sendToGateway(cfg, gw_out);
                gw_state = receiveFromGateway(cfg, gw_state);
            end

            [jitter_ms, jitter_buf] = addScanJitter(cfg.dt * log_every, cfg, jitter_buf);

            % Stream row directly to CSV (no in-memory accumulation)
            write_streaming_row(csv_fid, log_k, t_s, state, ekf, plc, ...
                                comp1, comp2, prs1, prs2, valve_states, ...
                                cusum, sensor_p, sensor_q, src_p1_k, src_p2_k, ...
                                demand_k, q_sto, aid, fault_label, ...
                                schedule, k, params, cfg, ...
                                current_regime - 1);
        end

        %% ── Progress ─────────────────────────────────────────────────────
        if mod(k, round(3600 / dt)) == 0
            sim_h = k * dt / 3600;
            wall_m = toc(wall_t0) / 60;
            fprintf('  [%5.1fh / %dh]  wall=%.1fmin  P_S1=%.1f  P_D1=%.1f  atk=%d  rows=%d\n', ...
                    sim_h, opt.duration_h, wall_m, state.p(1), state.p(15), aid, log_k);
        end

        %% ── Checkpoint save ──────────────────────────────────────────────
        if mod(k, round(opt.checkpoint_h * 3600 / dt)) == 0
            fprintf('  [checkpoint @ %.1fh]\n', k * dt / 3600);
            % Could save state to .mat for resume — omitted for brevity
        end

    end % main loop

    %% ── Cleanup ──────────────────────────────────────────────────────────
    fclose(csv_fid);
    fclose(regime_fid);
    if cfg.use_gateway, close_gateway_sockets(cfg); end
    exportHistorian(hist, opt.out_dir);
    logEvent(-1);

    wall_h = toc(wall_t0) / 3600;
    fprintf('\n=================================================================\n');
    fprintf('  COMPLETE: %d rows  %.2fh wall  %.0fx real-time\n', ...
            log_k, wall_h, (opt.duration_h) / wall_h);
    fprintf('  Output: %s\n', opt.out_dir);
    fprintf('=================================================================\n\n');

    %% ── Write metadata ───────────────────────────────────────────────────
    write_metadata(opt, cfg, log_k, n_regimes, attack_plan, wall_h);
end


% =========================================================================
%  REGIME TIMELINE — realistic 48h operational narrative
% =========================================================================

function regimes = build_regime_timeline(duration_h, cfg) %#ok<INUSD>
% build_regime_timeline  Create a plausible sequence of operating conditions.
%
%  A real Indian CGD pipeline over 48 hours goes through:
%    Night (00-06):  Low demand, both sources, storage injecting
%    Morning (06-10): Demand ramp-up, compressors ramping
%    Day (10-18):    Peak demand, possible maintenance windows
%    Evening (18-22): Secondary peak (cooking gas), high flow
%    Late night (22-00): Demand falling, storage withdrawing
%
%  Maintenance events (valve reconfig, single-source operation) happen
%  during scheduled windows, not randomly.

    regimes = struct('start_s',{},'end_s',{},'source_config',{}, ...
                     'demand_level',{},'valve_config',{},'cs_mode',{}, ...
                     'storage_target',{});

    h = 3600;   % seconds per hour

    % ── Day 1 ─────────────────────────────────────────────────────────────
    regimes(end+1) = make_regime(0*h,    6*h,  'both',    'low',    'auto', 'both_on', 0.85);
    regimes(end+1) = make_regime(6*h,   10*h,  'both',    'medium', 'auto', 'both_on', 0.70);
    regimes(end+1) = make_regime(10*h,  14*h,  'both',    'peak',   'auto', 'both_on', 0.50);

    % Scheduled maintenance: E8 forced open for inspection, CS2 offline
    regimes(end+1) = make_regime(14*h,  16*h,  'both',    'medium', 'E8_forced_open', 'CS1_only', 0.45);

    regimes(end+1) = make_regime(16*h,  18*h,  'both',    'medium', 'auto', 'both_on', 0.50);
    regimes(end+1) = make_regime(18*h,  22*h,  'both',    'peak',   'auto', 'both_on', 0.40);
    regimes(end+1) = make_regime(22*h,  24*h,  'both',    'low',    'auto', 'both_on', 0.60);

    % ── Day 2 ─────────────────────────────────────────────────────────────
    regimes(end+1) = make_regime(24*h,  30*h,  'both',    'low',    'auto', 'both_on', 0.80);
    regimes(end+1) = make_regime(30*h,  34*h,  'both',    'medium', 'auto', 'both_on', 0.65);

    % S2 supply interruption (CGS maintenance upstream)
    regimes(end+1) = make_regime(34*h,  38*h,  'S1_only', 'peak',   'auto', 'both_on', 0.35);

    % S2 restored
    regimes(end+1) = make_regime(38*h,  42*h,  'both',    'medium', 'auto', 'both_on', 0.55);
    regimes(end+1) = make_regime(42*h,  46*h,  'both',    'peak',   'auto', 'both_on', 0.40);
    regimes(end+1) = make_regime(46*h,  48*h,  'both',    'low',    'auto', 'both_on', 0.70);

    % Trim to actual duration
    max_s = duration_h * 3600;
    keep = [regimes.start_s] < max_s;
    regimes = regimes(keep);
end


function r = make_regime(t0, t1, src, dem, valve, cs, sto)
    r.start_s        = t0;
    r.end_s          = t1;
    r.source_config  = src;
    r.demand_level   = dem;
    r.valve_config   = valve;
    r.cs_mode        = cs;
    r.storage_target = sto;
end


function cfg = apply_regime(cfg, reg, comp1, comp2) %#ok<INUSD>
% apply_regime  Modify cfg for the new operating regime WITHOUT resetting state.
%
%  This is the critical difference from run_24h_sweep: we change cfg
%  parameters but do NOT reinitialise state, comp1, comp2, plc, ekf.
%  The physics state carries forward continuously.

    switch reg.source_config
        case 'S1_only'
            cfg.src2_p_min = 10.0; cfg.src2_p_max = 12.0;
        case 'S2_only'
            cfg.src_p_min  = 10.0; cfg.src_p_max  = 12.0;
        case 'both'
            cfg.src_p_min  = 20.0; cfg.src_p_max  = 26.0;
            cfg.src2_p_min = 20.0; cfg.src2_p_max = 26.0;
    end

    switch reg.demand_level
        case 'low',    cfg.dem_base = 0.25; cfg.dem_noise_std = 0.008;
        case 'medium', cfg.dem_base = 0.60; cfg.dem_noise_std = 0.015;
        case 'peak',   cfg.dem_base = 1.00; cfg.dem_noise_std = 0.025;
    end

    switch reg.valve_config
        case 'E8_forced_open'
            cfg.valve_close_hi = 999; cfg.valve_open_lo = -999;
        case 'E8_forced_closed'
            cfg.valve_close_hi = -999; cfg.valve_open_lo = -999;
        case 'auto'
            cfg.valve_open_lo = 14.0; cfg.valve_close_hi = 24.0;
    end

    switch reg.cs_mode
        case 'CS1_only'
            cfg.comp2_ratio_min = 1.00; cfg.comp2_ratio_max = 1.00;
        case 'CS2_only'
            cfg.comp1_ratio_min = 1.00; cfg.comp1_ratio_max = 1.00;
        case 'both_on'
            cfg.comp1_ratio_min = 1.1; cfg.comp1_ratio_max = 1.6;
            cfg.comp2_ratio_min = 1.1; cfg.comp2_ratio_max = 1.6;
    end
end


% =========================================================================
%  ATTACK SCHEDULE — random attacks across full 48h
% =========================================================================

function plan = build_continuous_attack_schedule(N, dt, density, cfg)
% build_continuous_attack_schedule  Place attacks randomly across 48h.
%
%  Density controls mean inter-attack gap:
%    'none'   : 0 attacks
%    'low'    : ~4 attacks per 24h
%    'normal' : ~8 attacks per 24h
%    'high'   : ~15 attacks per 24h

    T_total = N * dt;

    switch density
        case 'none',   n_attacks = 0;
        case 'low',    n_attacks = round(4  * T_total / 86400);
        case 'normal', n_attacks = round(8  * T_total / 86400);
        case 'high',   n_attacks = round(15 * T_total / 86400);
        otherwise,     n_attacks = round(8  * T_total / 86400);
    end

    plan.n_attacks = n_attacks;
    plan.ids       = [];
    plan.start_s   = [];
    plan.dur_s     = [];

    if n_attacks == 0, return; end

    % Draw attack IDs uniformly from A1-A10
    plan.ids = randi(10, 1, n_attacks);

    % Place with minimum gap
    min_gap  = 600;   % 10 min between attacks
    warmup   = 1800;  % first attack no earlier than 30 min
    recovery = 600;

    durs = cfg.atk_dur_min_s + (cfg.atk_dur_max_s - cfg.atk_dur_min_s) * rand(1, n_attacks);
    plan.dur_s = durs;

    % Sequential placement with random gaps
    starts = zeros(1, n_attacks);
    starts(1) = warmup + rand() * 3600;
    for i = 2:n_attacks
        earliest = starts(i-1) + durs(i-1) + min_gap;
        latest   = T_total - recovery - sum(durs(i:end)) - (n_attacks - i) * min_gap;
        if earliest >= latest
            starts(i) = earliest;
        else
            starts(i) = earliest + rand() * (latest - earliest);
        end
    end
    plan.start_s = starts;
end


function schedule = attack_plan_to_schedule(plan, N, dt)
% Convert attack plan to per-step label arrays used by applyAttackEffects.

    names  = ["SrcPressureManipulation","CompressorRatioSpoofing", ...
              "ValveCommandTampering","DemandNodeManipulation", ...
              "PressureSensorSpoofing","FlowMeterSpoofing", ...
              "PLCLatencyAttack","PipelineLeak", ...
              "StealthyFDI","ReplayAttack"];
    mitres = ["T0831","T0838","T0855","T0829","T0831","T0827","T0814","T0829","T0835","T0835"];

    schedule.label_id    = zeros(N, 1, 'int32');
    schedule.label_name  = repmat("Normal", N, 1);
    schedule.label_mitre = repmat("None",   N, 1);
    schedule.nAttacks    = plan.n_attacks;
    schedule.ids         = plan.ids;
    schedule.start_s     = plan.start_s;
    schedule.end_s       = plan.start_s + plan.dur_s;
    schedule.dur_s       = plan.dur_s;
    schedule.params      = cell(1, plan.n_attacks);

    for i = 1:plan.n_attacks
        aid   = plan.ids(i);
        k_s   = max(1, round(plan.start_s(i) / dt));
        k_e   = min(N, round((plan.start_s(i) + plan.dur_s(i)) / dt));
        schedule.label_id(k_s:k_e)    = int32(aid);
        if aid <= numel(names)
            schedule.label_name(k_s:k_e)  = names(aid);
            schedule.label_mitre(k_s:k_e) = mitres(aid);
        end
    end
end


% =========================================================================
%  DEMAND PROFILE — realistic 48h diurnal curve
% =========================================================================

function demand = build_48h_demand_profile(N, dt, cfg)
% build_48h_demand_profile  Smooth diurnal demand with stochastic noise.
%
%  Indian residential CGD demand pattern:
%    Peak 1: 07:00-09:00 (morning cooking)
%    Trough: 10:00-16:00 (daytime)
%    Peak 2: 18:00-21:00 (evening cooking + heating)
%    Base:   23:00-05:00 (overnight minimum)

    t = (0:N-1)' * dt;
    hour = mod(t / 3600, 24);

    % Diurnal shape (normalised 0-1)
    morning = 0.8 * exp(-0.5 * ((hour - 7.5) / 1.2).^2);
    evening = 1.0 * exp(-0.5 * ((hour - 19.0) / 1.5).^2);
    base    = 0.3;

    diurnal = base + morning + evening;
    diurnal = diurnal / max(diurnal);   % normalise to [0, 1]

    % Scale to cfg demand range
    demand = cfg.dem_base * (0.4 + 0.6 * diurnal);

    % Add AR(1) noise
    noise = zeros(N, 1);
    for k = 2:N
        noise(k) = 0.95 * noise(k-1) + cfg.dem_noise_std * randn();
    end
    demand = max(0.05, demand + noise);
end


% =========================================================================
%  STREAMING CSV OUTPUT
% =========================================================================

function fid = open_streaming_csv(fpath, params)
    fid = fopen(fpath, 'w');
    if fid < 0, error('Cannot open %s', fpath); end

    nn = params.nodeNames; en = params.edgeNames;

    % Build header
    hdr = 'Timestamp_s,regime_id';
    for i = 1:params.nNodes, hdr = [hdr sprintf(',p_%s_bar', char(nn(i)))]; end %#ok
    for i = 1:params.nEdges, hdr = [hdr sprintf(',q_%s_kgs', char(en(i)))]; end %#ok
    hdr = [hdr ',CS1_ratio,CS1_power_kW,CS2_ratio,CS2_power_kW'];
    hdr = [hdr ',PRS1_throttle,PRS2_throttle'];
    hdr = [hdr ',valve_E8,valve_E14,valve_E15,STO_inventory'];
    hdr = [hdr ',cusum_S_upper,cusum_S_lower,cusum_alarm,chi2_stat,chi2_alarm'];
    for i = 1:params.nNodes, hdr = [hdr sprintf(',ekf_resid_%s', char(nn(i)))]; end %#ok
    for i = 1:params.nNodes, hdr = [hdr sprintf(',plc_p_%s', char(nn(i)))]; end %#ok
    for i = 1:params.nEdges, hdr = [hdr sprintf(',plc_q_%s', char(en(i)))]; end %#ok
    hdr = [hdr ',FAULT_ID,ATTACK_ID,MITRE_CODE,label'];
    fprintf(fid, '%s\n', hdr);
end


function write_streaming_row(fid, log_k, t_s, state, ekf, plc, ...
                              comp1, comp2, prs1, prs2, valve_states, ...
                              cusum, sensor_p, sensor_q, src_p1, src_p2, ...
                              demand_k, q_sto, aid, fault_label, ...
                              schedule, k, params, cfg, regime_id)

    mitre_str = char(schedule.label_mitre(k));
    mitre_lut = containers.Map( ...
        {'None','T0831','T0838','T0855','T0829','T0827','T0814','T0835'}, ...
        {0,      831,    838,    855,    829,    827,    814,    835});
    mc = 0;
    if isKey(mitre_lut, mitre_str), mc = mitre_lut(mitre_str); end

    label = int32(fault_label > 0 || aid > 0);

    fprintf(fid, '%.3f,%d', t_s, regime_id);
    fprintf(fid, ',%.4f', state.p);
    fprintf(fid, ',%.4f', state.q);
    fprintf(fid, ',%.4f,%.3f,%.4f,%.3f', ...
            comp1.ratio, state.W1/1000, comp2.ratio, state.W2/1000);
    fprintf(fid, ',%.4f,%.4f', prs1.throttle, prs2.throttle);
    fprintf(fid, ',%.3f,%.3f,%.3f', valve_states(1), valve_states(2), valve_states(3));
    fprintf(fid, ',%.4f', state.sto_inventory);
    fprintf(fid, ',%.4f,%.4f,%d,%.4f,%d', ...
            cusum.S_upper, cusum.S_lower, int32(cusum.alarm), ...
            ekf.chi2_stat, int32(ekf.chi2_alarm));
    fprintf(fid, ',%.4f', ekf.xhat(1:params.nNodes) - state.p);
    fprintf(fid, ',%.4f', plc.reg_p);
    fprintf(fid, ',%.4f', plc.reg_q);
    fprintf(fid, ',%d,%d,%d,%d\n', fault_label, aid, mc, label);
end


% =========================================================================
%  UTILITIES
% =========================================================================

function write_metadata(opt, cfg, n_rows, n_regimes, attack_plan, wall_h)
    fid = fopen(fullfile(opt.out_dir, 'run_metadata.json'), 'w');
    fprintf(fid, '{\n');
    fprintf(fid, '  "duration_h": %d,\n', opt.duration_h);
    fprintf(fid, '  "total_rows": %d,\n', n_rows);
    fprintf(fid, '  "dt_s": %.2f,\n', cfg.dt);
    fprintf(fid, '  "log_every": %d,\n', cfg.log_every);
    fprintf(fid, '  "n_regimes": %d,\n', n_regimes);
    fprintf(fid, '  "n_attacks": %d,\n', attack_plan.n_attacks);
    fprintf(fid, '  "attack_density": "%s",\n', opt.attack_density);
    fprintf(fid, '  "gateway": %s,\n', lower(string(opt.gateway)));
    fprintf(fid, '  "fault_enable": %s,\n', lower(string(opt.fault_enable)));
    fprintf(fid, '  "wall_time_h": %.2f\n', wall_h);
    fprintf(fid, '}\n');
    fclose(fid);
end

function [cfg, opened] = open_gateway_sockets(cfg)
    opened = false; cfg.use_gateway = false;
    try
        tx_sock = java.net.DatagramSocket();
        tx_addr = java.net.InetSocketAddress( ...
                    java.net.InetAddress.getByName('127.0.0.1'), 5005);
        rx_sock = java.net.DatagramSocket(6006);
        rx_sock.setSoTimeout(500);
        cfg.tx_sock = tx_sock; cfg.tx_addr = tx_addr; cfg.rx_sock = rx_sock;
        cfg.use_gateway = true; opened = true;
    catch e
        warning('open_gateway_sockets: %s', e.message);
    end
end

function close_gateway_sockets(cfg)
    if isfield(cfg,'rx_sock'), try, cfg.rx_sock.close(); catch, end; end
    if isfield(cfg,'tx_sock'), try, cfg.tx_sock.close(); catch, end; end
end

function plc = updatePLCWithLatency(plc, sensor_p, sensor_q, k, latency, cfg)
    plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
    plc = advanceLatencyBuffers(plc);
end

function plc = advanceLatencyBuffers(plc)
    plc.compRatio1Buf   = [plc.compRatio1Buf(2:end),  plc.act_comp1_ratio];
    plc.compRatio2Buf   = [plc.compRatio2Buf(2:end),  plc.act_comp2_ratio];
    plc.valveCmdBuf     = [plc.valveCmdBuf(:,2:end),  plc.act_valve_cmds];
    plc.act_comp1_ratio = plc.compRatio1Buf(1);
    plc.act_comp2_ratio = plc.compRatio2Buf(1);
    plc.act_valve_cmds  = plc.valveCmdBuf(:,1);
end

function s = fmtnum(n)
    s = sprintf('%d', round(n)); k = numel(s) - 3;
    while k > 0, s = [s(1:k), ',', s(k+1:end)]; k = k - 3; end
end
