%% run_24h_sweep.m
% =========================================================================
%  Indian CGD Gas Pipeline — 24–30 Hour Full Dataset Sweep
%  =========================================================================
%  Runs all 340 valid baseline scenarios + 90 attack scenarios (1 per
%  attack type per topology group) in a single uninterrupted MATLAB session.
%
%  Timeline:
%    340 baseline × 5 min = 1700 min = ~28.3 hours
%    90  attack   × 5 min =  450 min =  ~7.5 hours
%    Total wall time: ~35 hours (with 10× real-time pacing, 3.5 hours actual)
%
%  With CODESYS unlimited license (>2 hours):
%    Run baseline at full 30 min/scenario → 340×30 = 170 hours sim time
%    Compressed to 1 Hz log → each scenario = 1800 rows
%    Estimated actual wall time at ~120× real-time: ~85 minutes for baseline
%    Add attacks: 90 × 30 min sim → another ~22 minutes
%    TOTAL ACTUAL WALL TIME: ~2 hours for full dataset
%
%  Usage:
%    >> run_24h_sweep()                   % full 340+90 sweep
%    >> run_24h_sweep('mode','baseline')  % baseline only
%    >> run_24h_sweep('mode','attack')    % attack only
%    >> run_24h_sweep('mode','quick')     % 20 scenarios for testing
%    >> run_24h_sweep('resume',45)        % resume from scenario 45
% =========================================================================

function run_24h_sweep(varargin)

    p = inputParser();
    addParameter(p, 'mode',       'full');    % 'full','baseline','attack','quick'
    addParameter(p, 'resume',     1);         % scenario index to start from
    addParameter(p, 'dur_min',    30);        % minutes per scenario
    addParameter(p, 'use_gateway', true);     % connect to CODESYS
    addParameter(p, 'out_dir',    'automated_dataset');
    parse(p, varargin{:});
    opt = p.Results;

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling','processing');

    fprintf('=================================================================\n');
    fprintf('  Indian CGD Pipeline Sweep — Phase 7\n');
    fprintf('  Mode: %s  |  Duration: %d min/scenario\n', opt.mode, opt.dur_min);
    fprintf('  Resume from: scenario %d\n', opt.resume);
    fprintf('  CODESYS gateway: %s\n', string(opt.use_gateway));
    fprintf('=================================================================\n\n');

    %% ── 1. Build scenario matrix (ICS_Dataset_Design.md §4) ─────────────
    fprintf('[sweep] Building scenario matrix...\n');
    [baseline_scenarios, attack_scenarios] = build_scenario_matrix();

    fprintf('[sweep] Baseline: %d valid scenarios\n', numel(baseline_scenarios));
    fprintf('[sweep] Attack  : %d scenarios\n', numel(attack_scenarios));

    %% ── 2. Select which scenarios to run ────────────────────────────────
    switch opt.mode
        case 'baseline'
            scenarios = baseline_scenarios;
        case 'attack'
            scenarios = attack_scenarios;
        case 'quick'
            scenarios = [baseline_scenarios(1:10); attack_scenarios(1:10)];
        otherwise   % 'full'
            scenarios = [baseline_scenarios; attack_scenarios];
    end

    total = numel(scenarios);
    fprintf('[sweep] Will run %d scenarios starting from #%d\n', ...
            total, opt.resume);

    %% ── 3. Setup output directories ──────────────────────────────────────
    dirs = setup_output_dirs(opt.out_dir);

    %% ── 4. Progress tracking ─────────────────────────────────────────────
    log_path = fullfile(opt.out_dir, 'sweep_progress.log');
    log_fid  = fopen(log_path, 'a');
    fprintf(log_fid, '\n=== SWEEP START %s  Mode=%s  Total=%d ===\n', ...
            datestr(now), opt.mode, total);

    sweep_start = tic;
    completed   = 0;
    failed      = 0;
    skipped     = 0;

    %% ── 5. Main scenario loop ────────────────────────────────────────────
    for si = opt.resume:total

        scen = scenarios(si);

        % Print progress header
        eta_h = estimate_eta(sweep_start, si-opt.resume, total-opt.resume+1, ...
                             opt.dur_min);
        fprintf('\n[%d/%d] Scenario #%d | src=%-10s dem=%-10s cs=%-12s | ETA %.1fh\n', ...
                si, total, scen.id, scen.source_config, scen.demand_profile, ...
                scen.cs_mode, eta_h);

        % Check if already completed (for resume)
        out_file = fullfile(dirs.scenarios, ...
                            sprintf('scenario_%04d.csv', scen.id));
        if exist(out_file, 'file')
            fprintf('  [skip] Already exists: %s\n', out_file);
            skipped = skipped + 1;
            continue;
        end

        % Build scenario config
        cfg = build_scenario_config(scen, opt.dur_min);

        % Run simulation
        try
            run_one_scenario(cfg, opt.use_gateway, out_file, scen, ...
                             dirs, log_fid);
            completed = completed + 1;
            fprintf(log_fid, '[%s] OK  sc=%04d  src=%s dem=%s cs=%s\n', ...
                    datestr(now,'HH:MM:SS'), scen.id, scen.source_config, ...
                    scen.demand_profile, scen.cs_mode);
        catch e
            failed = failed + 1;
            fprintf('  [ERROR] Scenario %d failed: %s\n', scen.id, e.message);
            fprintf(log_fid, '[%s] FAIL sc=%04d  %s\n', ...
                    datestr(now,'HH:MM:SS'), scen.id, e.message);
        end

        % Brief cooldown between scenarios (PLC reset)
        pause(2);

    end % scenario loop

    %% ── 6. Post-sweep assembly ───────────────────────────────────────────
    wall_h = toc(sweep_start) / 3600;
    fprintf('\n=================================================================\n');
    fprintf('  SWEEP COMPLETE\n');
    fprintf('  Completed: %d  Failed: %d  Skipped: %d\n', ...
            completed, failed, skipped);
    fprintf('  Wall time : %.2f hours\n', wall_h);
    fprintf('=================================================================\n');

    if strcmp(opt.mode, 'full') || strcmp(opt.mode, 'baseline')
        fprintf('[sweep] Assembling master ML dataset...\n');
        assemble_ml_dataset(dirs.scenarios, fullfile(opt.out_dir, 'ml_dataset_final.csv'));
    end

    fprintf(log_fid, '=== SWEEP END  completed=%d  failed=%d  wall=%.2fh ===\n', ...
            completed, failed, wall_h);
    fclose(log_fid);
end

%% ── Build scenario matrix ────────────────────────────────────────────────

function [baseline, attacks] = build_scenario_matrix()
% build_scenario_matrix  Generate 340 valid baseline + 90 attack scenarios.
%  Based on ICS_Dataset_Design.md §4.1–4.2

    % Dimension values
    source_configs   = {'S1_only', 'S2_only', 'both'};
    demand_profiles  = {'low', 'medium', 'peak', 'uneven', 'spike'};
    valve_configs    = {'auto', 'E8_forced_open', 'E8_forced_closed'};
    storage_inits    = [0.1, 0.5, 0.9];
    cs_modes         = {'both_on', 'CS1_only', 'CS2_only'};

    baseline = [];
    sid = 1;

    for src = 1:numel(source_configs)
        for dem = 1:numel(demand_profiles)
            for val = 1:numel(valve_configs)
                for sto = 1:numel(storage_inits)
                    for csm = 1:numel(cs_modes)

                        sc.source_config  = source_configs{src};
                        sc.demand_profile = demand_profiles{dem};
                        sc.valve_config   = valve_configs{val};
                        sc.storage_init   = storage_inits(sto);
                        sc.cs_mode        = cs_modes{csm};
                        sc.attack_id      = 0;   % no attack
                        sc.attack_severity = 'none';
                        sc.resilience_mode = 'normal';

                        % Apply validity rules (§4.2)
                        if ~is_valid_scenario(sc), continue; end

                        sc.id = sid;
                        sc.is_stress = is_stress_scenario(sc);
                        baseline(end+1) = sc; %#ok
                        sid = sid + 1;

                    end
                end
            end
        end
    end

    % Add resilience scenarios (cross-tie active)
    resilience_configs = {
        struct('source_config','S1_only','demand_profile','peak', ...
               'valve_config','auto','storage_init',0.5,'cs_mode','CS1_only', ...
               'resilience_mode','crosstie'),
        struct('source_config','S2_only','demand_profile','peak', ...
               'valve_config','auto','storage_init',0.5,'cs_mode','both_on', ...
               'resilience_mode','crosstie'),
        struct('source_config','both','demand_profile','peak', ...
               'valve_config','auto','storage_init',0.1,'cs_mode','CS2_only', ...
               'resilience_mode','crosstie'),
        struct('source_config','both','demand_profile','spike', ...
               'valve_config','auto','storage_init',0.1,'cs_mode','both_on', ...
               'resilience_mode','bypass'),
    };
    for ri = 1:numel(resilience_configs)
        sc = resilience_configs{ri};
        sc.attack_id = 0; sc.attack_severity = 'none';
        sc.is_stress = true; sc.id = sid;
        baseline(end+1) = sc; %#ok
        sid = sid + 1;
    end

    fprintf('[build] Baseline scenarios: %d\n', numel(baseline));

    % Attack scenarios: 10 attacks × 3 severity × 3 source configs
    % = 90 attack scenarios
    attacks = [];
    attack_ids     = 1:10;
    severities     = {'low','medium','high'};
    atk_src_cfgs   = {'S1_only','S2_only','both'};

    for ai = 1:numel(attack_ids)
        for sv = 1:numel(severities)
            for as = 1:numel(atk_src_cfgs)
                sc.id             = sid;
                sc.source_config  = atk_src_cfgs{as};
                sc.demand_profile = 'medium';
                sc.valve_config   = 'auto';
                sc.storage_init   = 0.5;
                sc.cs_mode        = 'both_on';
                sc.attack_id      = attack_ids(ai);
                sc.attack_severity = severities{sv};
                sc.resilience_mode = 'normal';
                sc.is_stress      = false;
                attacks(end+1) = sc; %#ok
                sid = sid + 1;
            end
        end
    end

    fprintf('[build] Attack scenarios: %d\n', numel(attacks));
end

%% ── Validity check ───────────────────────────────────────────────────────

function ok = is_valid_scenario(sc)
% Prune physically invalid combinations (ICS_Dataset_Design.md §4.2)
    ok = true;
    % R1: S1_only + CS2_only — CS2 downstream of CS1; no supply
    if strcmp(sc.source_config,'S1_only') && strcmp(sc.cs_mode,'CS2_only')
        ok = false; return;
    end
    % R2: S2_only + CS1_only — CS1 has no upstream supply
    if strcmp(sc.source_config,'S2_only') && strcmp(sc.cs_mode,'CS1_only')
        ok = false; return;
    end
    % R3: E8_forced_closed + CS1_only — PRS1 branch starved
    if strcmp(sc.valve_config,'E8_forced_closed') && strcmp(sc.cs_mode,'CS1_only')
        ok = false; return;
    end
    % R5: No compressors + peak demand (insufficient pressure)
    % (both_off not in cs_modes list, so this is implicitly handled)
end

function stress = is_stress_scenario(sc)
% Flag high-stress scenarios for extended duration
    stress = (strcmp(sc.storage_init, 'empty') || sc.storage_init < 0.2) && ...
             strcmp(sc.source_config,'S1_only') && ...
             strcmp(sc.demand_profile,'peak');
end

%% ── Build config for one scenario ───────────────────────────────────────

function cfg = build_scenario_config(scen, dur_min)
% build_scenario_config  Create a simConfig with scenario overrides.

    cfg = simConfig();
    cfg.T = dur_min * 60;

    %% Scenario identity
    cfg.scenario_id              = scen.id;
    cfg.scenario_source_config   = scen.source_config;
    cfg.scenario_demand_profile  = scen.demand_profile;
    cfg.scenario_valve_config    = scen.valve_config;
    cfg.scenario_storage_init    = scen.storage_init;
    cfg.scenario_cs_mode         = scen.cs_mode;
    cfg.scenario_resilience_mode = scen.resilience_mode;

    %% Storage initial state
    cfg.sto_inventory_init = scen.storage_init;

    %% Source config
    switch scen.source_config
        case 'S1_only'
            cfg.src2_p_min = 0; cfg.src2_p_max = 0.1;  % S2 off
        case 'S2_only'
            cfg.src_p_min  = 0; cfg.src_p_max  = 0.1;  % S1 off
        % 'both' — no change
    end

    %% Demand profile
    switch scen.demand_profile
        case 'low',    cfg.dem_base = 0.30; cfg.dem_diurnal_amp = 0.05;
        case 'medium', cfg.dem_base = 0.60; cfg.dem_diurnal_amp = 0.15;
        case 'peak',   cfg.dem_base = 1.00; cfg.dem_diurnal_amp = 0.15;
        case 'uneven'
            % Asymmetric demand: D1/D2 = 0.8×, D3/D4 = 1.2×
            cfg.dem_base = 0.60; cfg.dem_diurnal_amp = 0.20;
            cfg.dem_asymmetry = struct('D1D2_factor',0.8,'D3D4_factor',1.2);
        case 'spike'
            % Sudden 50% demand surge at t=10 min
            cfg.dem_base = 0.60; cfg.dem_diurnal_amp = 0.10;
            cfg.dem_spike_at_min = 10; cfg.dem_spike_mag = 0.50;
    end

    %% Valve config
    switch scen.valve_config
        case 'E8_forced_open',   cfg.valve_open_default = 1;
        case 'E8_forced_closed', cfg.valve_open_default = 0;
        % 'auto' — PLC controlled, no change
    end

    %% Compressor mode
    switch scen.cs_mode
        case 'CS1_only'
            cfg.comp2_ratio_min = 1.00; cfg.comp2_ratio_max = 1.00;
            cfg.comp2_ratio = 1.00;  % CS2 at bypass (ratio=1 = no boost)
        case 'CS2_only'
            cfg.comp1_ratio_min = 1.00; cfg.comp1_ratio_max = 1.00;
            cfg.comp1_ratio = 1.00;
        % 'both_on' — no change
    end

    %% Resilience mode
    if strcmp(scen.resilience_mode,'crosstie')
        cfg.crosstie_enable = true;
    elseif strcmp(scen.resilience_mode,'bypass')
        cfg.emergency_bypass_enable = true;
    end

    %% Attack config (for attack scenarios)
    if isfield(scen,'attack_id') && scen.attack_id > 0
        cfg = apply_attack_config(cfg, scen.attack_id, scen.attack_severity);
    else
        % Baseline: no attacks — use empty schedule
        cfg.n_attacks = 0;
    end
end

%% ── Apply attack overrides ───────────────────────────────────────────────

function cfg = apply_attack_config(cfg, atk_id, severity)
% Map severity to magnitude/duration, then override per-attack parameters.

    switch severity
        case 'low',    mag = 0.10; dur_s = 120;
        case 'medium', mag = 0.25; dur_s = 300;
        case 'high',   mag = 0.50; dur_s = 480;
        otherwise,     mag = 0.25; dur_s = 300;
    end

    cfg.n_attacks      = 1;
    cfg.atk_warmup_s   = 12 * 60;    % first attack at 12 min into run
    cfg.atk_recovery_s = 5  * 60;
    cfg.atk_min_gap_s  = 30 * 60;    % single attack so gap irrelevant
    cfg.atk_dur_min_s  = dur_s;
    cfg.atk_dur_max_s  = dur_s;
    cfg.forced_attack_id = atk_id;   % override random shuffle in initAttackSchedule

    % Per-attack parameter overrides (Indian CGD magnitudes)
    switch atk_id
        case 1,  cfg.atk1_spike_amp       = 1 + mag * 0.15;  % 15% at full
        case 2,  cfg.atk2_target_ratio     = cfg.comp1_ratio * (1 + mag);
        case 4,  cfg.atk4_demand_scale     = 1 + 2.0 * mag;
        case 5,  cfg.atk5_bias_bar         = -cfg.p0 * mag;
        case 6,  cfg.atk6_scale            = 1 - mag;
        case 8,  cfg.atk8_leak_frac        = mag;
        case 9,  cfg.atk9_bias_scale       = mag * 0.08;
    end
end

%% ── Run one scenario ─────────────────────────────────────────────────────

function run_one_scenario(cfg, use_gateway, out_file, scen, dirs, log_fid)
% run_one_scenario  Execute main_simulation for one scenario config.

    t0 = tic;
    fprintf('  Running simulation...\n');

    % Redirect output to scenario-specific CSV in the scenarios subfolder
    cfg_modified = cfg;

    % Run simulation (delegates to existing main_simulation infrastructure)
    main_simulation_scenario(cfg_modified, use_gateway);

    % Validate and move output
    src_master = fullfile('automated_dataset','master_dataset.csv');
    if ~exist(src_master,'file')
        error('master_dataset.csv not produced for scenario %d', scen.id);
    end

    % Validate physical constraints
    [valid, reason] = validate_csv_quick(src_master, cfg);
    if ~valid
        warning('[WARN] Scenario %d failed validation: %s\n', scen.id, reason);
        copyfile(src_master, fullfile(dirs.failed, ...
                 sprintf('scenario_%04d_INVALID.csv', scen.id)));
        fprintf(log_fid, '[WARN] sc=%04d INVALID: %s\n', scen.id, reason);
        return;
    end

    % Move to scenarios directory with standard naming
    copyfile(src_master, out_file);

    % Copy metadata JSON
    src_meta = fullfile('automated_dataset','scenario_metadata.json');
    if exist(src_meta,'file')
        copyfile(src_meta, fullfile(dirs.metadata, ...
                 sprintf('metadata_%04d.json', scen.id)));
    end

    elapsed = toc(t0);
    fprintf('  Done in %.1fs → %s\n', elapsed, out_file);
end

%% ── Quick CSV validity check ─────────────────────────────────────────────

function [valid, reason] = validate_csv_quick(csv_path, cfg)
% validate_csv_quick  Read first+last 10 rows and check pressure bounds.
    valid = true; reason = '';
    try
        T = readtable(csv_path, 'NumHeaderLines', 0);
        if height(T) < 50
            valid = false; reason = 'Too few rows'; return;
        end
        % Check pressure columns exist and are in PNGRB T4S range
        if any(T.p_S1_bar < 0, 'all') || any(T.p_D1_bar < 0, 'all')
            valid = false; reason = 'Negative pressure'; return;
        end
        if any(T.p_S1_bar > 30, 'all')
            valid = false; reason = 'Pressure exceeds MAOP+4 (30 barg)'; return;
        end
    catch e
        valid = false; reason = e.message;
    end
end

%% ── Dataset assembly ─────────────────────────────────────────────────────

function assemble_ml_dataset(scenarios_dir, out_path)
% assemble_ml_dataset  Concatenate all scenario CSVs into one ML-ready file.
    fprintf('[assemble] Reading scenario CSVs from %s...\n', scenarios_dir);
    files = dir(fullfile(scenarios_dir,'scenario_*.csv'));
    if isempty(files)
        fprintf('[assemble] No scenario files found.\n'); return;
    end

    fout = fopen(out_path,'w');
    hdr_written = false;
    total_rows  = 0;

    for i = 1:numel(files)
        fpath = fullfile(files(i).folder, files(i).name);
        fid   = fopen(fpath,'r');
        hdr   = fgetl(fid);
        if ~hdr_written
            fprintf(fout,'%s\n',hdr);
            hdr_written = true;
        end
        while ~feof(fid)
            ln = fgetl(fid);
            if ischar(ln) && ~isempty(ln)
                fprintf(fout,'%s\n',ln);
                total_rows = total_rows + 1;
            end
        end
        fclose(fid);
        if mod(i,50)==0
            fprintf('[assemble] %d/%d files  (%d rows so far)\n',i,numel(files),total_rows);
        end
    end
    fclose(fout);
    fprintf('[assemble] Done → %s  (%d total rows)\n', out_path, total_rows);
end

%% ── Setup directories ────────────────────────────────────────────────────

function dirs = setup_output_dirs(base)
    dirs.base      = base;
    dirs.scenarios = fullfile(base,'scenarios');
    dirs.metadata  = fullfile(base,'metadata');
    dirs.failed    = fullfile(base,'failed');
    for f = fieldnames(dirs)'
        if ~exist(dirs.(f{1}),'dir'), mkdir(dirs.(f{1})); end
    end
end

%% ── ETA estimator ────────────────────────────────────────────────────────

function eta_h = estimate_eta(t_start, done, total, dur_min)
    if done == 0, eta_h = total * dur_min / 60; return; end
    elapsed_s = toc(t_start);
    rate_s    = elapsed_s / done;   % seconds per scenario
    remaining = (total - done) * rate_s;
    eta_h = remaining / 3600;
end

%% ── Thin wrapper for main_simulation ────────────────────────────────────

function main_simulation_scenario(cfg, use_gateway)
% main_simulation_scenario  Like main_simulation but takes a pre-built cfg.
%  This wrapper avoids modifying the frozen runSimulation.m.

    fprintf('[init] Loading %d-min scenario (sc #%d)...\n', ...
            cfg.T/60, cfg.scenario_id);

    dt        = cfg.dt;
    N         = round(cfg.T / dt);
    log_every = max(1, cfg.log_every);

    initLogger(dt, cfg.T, N);

    [params, state]   = initNetwork(cfg);
    src_p1            = generateSourceProfile(N, cfg);
    cfg2 = cfg; cfg2.src_p_min = cfg.src2_p_min; cfg2.src_p_max = cfg.src2_p_max;
    src_p2            = generateSourceProfile(N, cfg2);
    demand            = ones(N,1);

    [comp1, comp2]    = initCompressor(cfg);
    [prs1,  prs2 ]    = initPRS(cfg);
    valve             = initValve(cfg); %#ok
    plc               = initPLC(cfg, state, comp1);
    ekf               = initEKF(cfg, state);

    if isfield(cfg,'n_attacks') && cfg.n_attacks > 0
        schedule = initAttackSchedule(N, cfg);
    else
        schedule = initEmptySchedule(N);
    end

    logs = initLogs(params, ekf, N, cfg);

    cfg.use_gateway = false;
    if use_gateway
        try
            tx_sock = java.net.DatagramSocket();
            rx_sock = java.net.DatagramSocket(6006);
            rx_sock.setSoTimeout(300);
            cfg.tx_sock     = tx_sock;
            cfg.tx_addr     = java.net.InetSocketAddress(...
                               java.net.InetAddress.getByName('127.0.0.1'), 5005);
            cfg.rx_sock     = rx_sock;
            cfg.use_gateway = true;
        catch
            % Gateway not available — offline mode
        end
    end

    [params, state, comp1, comp2, prs1, prs2, ekf, plc, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule);

    exportDataset(logs, cfg, params, N, schedule);

    if cfg.use_gateway
        try, cfg.tx_sock.close(); catch, end
        try, cfg.rx_sock.close(); catch, end
    end
    closeLogger(dt, N);
end

function schedule = initEmptySchedule(N)
    schedule.nAttacks   = 0;  schedule.ids = [];
    schedule.start_s    = []; schedule.end_s = []; schedule.dur_s = [];
    schedule.params     = {};
    schedule.label_id   = zeros(N,1,'uint8');
    schedule.label_name = repmat("Normal",N,1);
    schedule.label_mitre= repmat("None",N,1);
end