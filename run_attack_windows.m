%% run_attack_windows.m
% =========================================================================
%  Indian CGD Gas Pipeline — Attack Windows Dataset Generator
%
%  Generates the attack_windows dataset: multi-scenario sweep where each
%  30-min scenario contains randomised attacks (A1–A10).
%
%  Output:
%    automated_dataset/attack_windows/
%      scenario_XXXX.csv         — per-scenario files (125+ cols)
%      scenario_index.csv        — scenario metadata
%      physics_dataset_windows.csv — assembled master (all scenarios)
%      sweep_progress.log
%
%  Usage:
%    >> run_attack_windows()                       % full sweep, offline
%    >> run_attack_windows('resume', 50)           % resume from scenario 50
%    >> run_attack_windows('dur_min', 60)          % 60 min per scenario
%    >> run_attack_windows('mode', 'quick')        % first 30 scenarios
%    >> run_attack_windows('gateway', true)        % with CODESYS
%    >> run_attack_windows('n_attacks', 10)        % 10 attacks per scenario
%
%  Differences from run_24h_sweep (baseline):
%    - Each scenario has attacks (n_attacks per cfg.n_attacks)
%    - Attack parameters randomised per scenario via randomize_attack_params
%    - Output directory: automated_dataset/attack_windows/ (not baseline/)
%    - Assembled output: physics_dataset_windows.csv
% =========================================================================

function run_attack_windows(varargin)

    ap = inputParser();
    addParameter(ap, 'mode',      'full');
    addParameter(ap, 'resume',    1);
    addParameter(ap, 'dur_min',   30);
    addParameter(ap, 'gateway',   false);
    addParameter(ap, 'fault',     false);
    addParameter(ap, 'assemble',  true);
    addParameter(ap, 'n_attacks', 0);   % 0 = use randomized value from randomize_attack_params
    addParameter(ap, 'out_dir',   'automated_dataset/attack_windows');
    parse(ap, varargin{:});
    opt = ap.Results;

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling','processing');

    if ~exist(opt.out_dir, 'dir'), mkdir(opt.out_dir); end

    fprintf('\n=================================================================\n');
    fprintf('  Indian CGD Pipeline — Attack Windows Sweep\n');
    fprintf('  Mode    : %-8s   Duration : %d min/scenario\n', opt.mode, opt.dur_min);
    atk_desc = 'randomized (4-10)'; if opt.n_attacks > 0, atk_desc = num2str(opt.n_attacks); end
    fprintf('  Attacks : %s per scenario  Gateway: %s\n', atk_desc, string(opt.gateway));
    fprintf('  Output  : %s\n', opt.out_dir);
    fprintf('=================================================================\n\n');

    %% ── Pre-flight ───────────────────────────────────────────────────────
    if opt.gateway
        gw_ok = check_gateway_connectivity();
        if ~gw_ok
            fprintf('[sweep] Gateway failed. Run offline: run_attack_windows(''gateway'', false)\n');
            error('Gateway unreachable.');
        end
        fprintf('[sweep] Gateway pre-flight PASSED.\n\n');
    end

    %% ── Scenario matrix (same as run_24h_sweep) ──────────────────────────
    fprintf('[sweep] Building scenario matrix...\n');
    scenarios = build_scenario_matrix();
    n_all = numel(scenarios);

    switch opt.mode
        case 'quick',  scenarios = scenarios(1 : min(30, n_all));
        case 'stress', mask = [scenarios.is_stress]; scenarios = scenarios(mask);
    end
    n_total = numel(scenarios);
    fprintf('[sweep] Scenarios selected: %d\n\n', n_total);

    %% ── Progress log ─────────────────────────────────────────────────────
    log_fid  = fopen(fullfile(opt.out_dir, 'sweep_progress.log'), 'a');
    fprintf(log_fid, '\n=== START %s  mode=%s  n=%d ===\n', ...
            datestr(now), opt.mode, n_total); %#ok

    idx_path = fullfile(opt.out_dir, 'scenario_index.csv');
    if opt.resume == 1 || ~exist(idx_path, 'file')
        fid = fopen(idx_path, 'w');
        fprintf(fid, 'scenario_id,source_config,demand_profile,valve_config,storage_init,cs_mode,n_attacks,status,n_rows,wall_s\n');
        fclose(fid);
    end

    %% ── Main sweep loop ──────────────────────────────────────────────────
    sweep_t0  = tic;
    completed = 0; failed = 0; skipped = 0;

    for si = opt.resume : n_total

        scen = scenarios(si);
        fprintf('[%d/%d] sc=%04d  src=%-8s dem=%-8s sto=%.1f cs=%-10s\n', ...
                si, n_total, scen.id, scen.source_config, scen.demand_profile, ...
                scen.storage_init, scen.cs_mode);

        out_csv = fullfile(opt.out_dir, sprintf('scenario_%04d.csv', scen.id));
        if exist(out_csv, 'file')
            info = dir(out_csv);
            if info.bytes > 5000
                fprintf('  [skip] Exists (%d KB)\n', round(info.bytes/1024));
                skipped = skipped + 1;
                continue;
            end
        end

        %% Build config with randomized attacks
        cfg = build_attack_scenario_config(scen, opt.dur_min, opt.fault, opt.n_attacks);

        sc_t0 = tic; n_rows = 0; status = 'FAILED'; gw_active = false;

        if opt.gateway
            [cfg, gw_active] = open_gateway_sockets(cfg);
        end

        try
            [logs, params, N, schedule] = execute_attack_simulation(cfg);
            export_attack_scenario_csv(logs, cfg, params, schedule, scen, out_csv);
            n_rows = logs.N_log;
            status = 'OK';
            completed = completed + 1;
            fprintf('  Done %.1fs → %d rows  (%d attacks injected)\n', ...
                    toc(sc_t0), n_rows, schedule.nAttacks);
        catch e
            failed = failed + 1;
            fprintf('  [ERROR] %s\n', e.message);
            fprintf(log_fid, '[FAIL] sc=%04d  %s\n', scen.id, e.message);
        end

        if opt.gateway && gw_active
            close_gateway_sockets(cfg);
            pause(2);
        end

        fid = fopen(idx_path, 'a');
        fprintf(fid, '%d,%s,%s,%s,%.1f,%s,%d,%s,%d,%.2f\n', ...
                scen.id, scen.source_config, scen.demand_profile, scen.valve_config, ...
                scen.storage_init, scen.cs_mode, cfg.n_attacks, status, n_rows, toc(sc_t0));
        fclose(fid);
        fprintf(log_fid, '[%s] %s sc=%04d  rows=%d  wall=%.1fs\n', ...
                datestr(now,'HH:MM:SS'), status, scen.id, n_rows, toc(sc_t0)); %#ok
    end

    %% ── Summary ──────────────────────────────────────────────────────────
    wall_h = toc(sweep_t0) / 3600;
    fprintf('\n=================================================================\n');
    fprintf('  SWEEP COMPLETE: %d ok  %d failed  %d skipped  %.2fh wall\n', ...
            completed, failed, skipped, wall_h);
    fprintf('=================================================================\n\n');
    fprintf(log_fid, '=== END ok=%d fail=%d wall=%.2fh ===\n', completed, failed, wall_h);
    fclose(log_fid);

    if opt.assemble
        assemble_attack_dataset(opt.out_dir, ...
            fullfile(opt.out_dir, 'physics_dataset_windows.csv'));
    end
end


% =========================================================================
%  CONFIG — attack-enabled scenario
% =========================================================================

function cfg = build_attack_scenario_config(scen, dur_min, fault_en, n_atk)

    cfg   = simConfig();
    cfg   = apply_cgd_overrides(cfg);
    cfg   = randomize_attack_params(cfg, scen.id);   % ← randomize per scenario

    cfg.T             = dur_min * 60;
    if n_atk > 0
        cfg.n_attacks = n_atk;   % explicit user override; else keep randomized value
    end
    cfg.forced_attack_id = [];
    cfg.attack_selection = 1:10;
    cfg.fault_enable  = fault_en;
    cfg.historian_enable = false;
    cfg.use_gateway   = false;
    cfg.gateway_timeout_s = 0.5;

    cfg.scenario_id             = scen.id;
    cfg.scenario_source_config  = scen.source_config;
    cfg.scenario_demand_profile = scen.demand_profile;
    cfg.scenario_valve_config   = scen.valve_config;
    cfg.scenario_storage_init   = scen.storage_init;
    cfg.scenario_cs_mode        = scen.cs_mode;
    cfg.sto_inventory_init      = scen.storage_init;

    switch scen.source_config
        case 'S1_only', cfg.src2_p_min = 10.0; cfg.src2_p_max = 12.0;
        case 'S2_only', cfg.src_p_min  = 10.0; cfg.src_p_max  = 12.0;
    end

    switch scen.demand_profile
        case 'low',    cfg.dem_base = 0.25; cfg.dem_noise_std = 0.008;
        case 'medium', cfg.dem_base = 0.60; cfg.dem_noise_std = 0.015;
        case 'peak',   cfg.dem_base = 1.00; cfg.dem_noise_std = 0.025;
        case 'uneven', cfg.dem_base = 0.60; cfg.dem_diurnal_amp = 0.38;
                       cfg.dem_noise_std = 0.030;
        case 'spike',  cfg.dem_base = 0.55; cfg.dem_noise_std = 0.020;
                       cfg.dem_spike_enable = true;
    end

    switch scen.valve_config
        case 'E8_forced_open'
            cfg.valve_open_default = 1;
            cfg.valve_close_hi = 999; cfg.valve_open_lo = -999;
        case 'E8_forced_closed'
            cfg.valve_open_default = 0;
            cfg.valve_close_hi = -999; cfg.valve_open_lo = -999;
    end

    switch scen.cs_mode
        case 'CS1_only'
            cfg.comp2_ratio = 1.00; cfg.comp2_ratio_min = 1.00;
            cfg.comp2_ratio_max = 1.00;
        case 'CS2_only'
            cfg.comp1_ratio = 1.00; cfg.comp1_ratio_min = 1.00;
            cfg.comp1_ratio_max = 1.00;
    end
end


% =========================================================================
%  SIMULATION EXECUTION — with attacks
% =========================================================================

function [logs, params, N, schedule] = execute_attack_simulation(cfg)

    dt = cfg.dt;
    N  = double(round(cfg.T / dt));

    logEvent(-1);

    [params, state] = initNetwork(cfg);

    src_p1 = generateSourceProfile(N, cfg);
    cfg_s2 = cfg;
    cfg_s2.p0 = 0.5 * (cfg.src2_p_min + cfg.src2_p_max);
    cfg_s2.src_p_min = cfg.src2_p_min;
    cfg_s2.src_p_max = cfg.src2_p_max;
    src_p2 = generateSourceProfile(N, cfg_s2);

    demand = ones(N, 1);
    if isfield(cfg,'dem_spike_enable') && cfg.dem_spike_enable
        for s_idx = 1:2
            t_spike = max(1, round(N * (0.28 + 0.38*(s_idx-1))));
            dur_k   = round(90 / dt);
            demand(t_spike : min(N, t_spike+dur_k-1)) = ...
                demand(t_spike : min(N, t_spike+dur_k-1)) * 2.3;
        end
    end

    [comp1, comp2] = initCompressor(cfg);
    [prs1, prs2]   = initPRS(cfg);
    initValve(cfg);

    plc      = initPLC(cfg, state, comp1);
    ekf      = initEKF(cfg, state);
    logs     = initLogs(params, ekf, N, cfg);

    %% Build attack schedule (uses cfg.n_attacks, randomized params)
    schedule = initAttackSchedule(N, cfg);

    [params, ~, ~, ~, ~, ~, ~, ~, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule);

    logEvent(-1);
end


% =========================================================================
%  CSV EXPORT — attack scenario
% =========================================================================

function export_attack_scenario_csv(logs, cfg, params, schedule, scen, fpath)

    N_log  = logs.N_log;
    log_dt = cfg.dt * max(1, cfg.log_every);
    t_vec  = (0:N_log-1)' * log_dt;
    nn     = params.nodeNames;
    en     = params.edgeNames;

    hdr = 'Timestamp_s,scenario_id,source_config,demand_profile,valve_config,storage_init,cs_mode';
    for i=1:params.nNodes, hdr=[hdr sprintf(',p_%s_bar',char(nn(i)))]; end %#ok
    for i=1:params.nEdges, hdr=[hdr sprintf(',q_%s_kgs',char(en(i)))]; end %#ok
    hdr=[hdr ',CS1_ratio,CS1_power_kW,CS2_ratio,CS2_power_kW'];
    hdr=[hdr ',valve_E8,valve_E14,valve_E15,STO_inventory'];
    hdr=[hdr ',cusum_S_upper,cusum_S_lower,cusum_alarm,chi2_stat,chi2_alarm'];
    for i=1:params.nNodes, hdr=[hdr sprintf(',ekf_resid_%s',char(nn(i)))]; end %#ok
    for i=1:params.nNodes, hdr=[hdr sprintf(',plc_p_%s',char(nn(i)))]; end %#ok
    for i=1:params.nEdges, hdr=[hdr sprintf(',plc_q_%s',char(en(i)))]; end %#ok
    hdr=[hdr ',FAULT_ID,ATTACK_ID,ATTACK_NAME,MITRE_ID,label'];

    if isfield(logs,'logValveStates') && size(logs.logValveStates,1)>=3
        logV = logs.logValveStates;
    else
        logV = ones(3,N_log);
    end
    logCU=zeros(1,N_log); logCL=zeros(1,N_log);
    logCA=false(1,N_log); logChi2=zeros(1,N_log); logChi2A=false(1,N_log);
    if isfield(logs,'logCUSUM_upper')
        logCU=logs.logCUSUM_upper; logCL=logs.logCUSUM_lower; logCA=logs.logCUSUM_alarm;
    end
    if isfield(logs,'logChi2'), logChi2=logs.logChi2; logChi2A=logs.logChi2_alarm; end
    logFault=zeros(1,N_log,'int32');
    if isfield(logs,'logFaultId'), logFault=logs.logFaultId; end

    meta = sprintf('%d,%s,%s,%s,%.1f,%s', scen.id, scen.source_config, ...
                   scen.demand_profile, scen.valve_config, scen.storage_init, scen.cs_mode);

    fid = fopen(fpath, 'w');
    if fid < 0, error('Cannot open %s', fpath); end
    fprintf(fid, '%s\n', hdr);

    for k = 1:N_log
        atk_id = logs.logAttackId(k);
        label  = int32(logFault(k) > 0 || atk_id > 0);

        fprintf(fid, '%.3f,%s', t_vec(k), meta);
        fprintf(fid, ',%.4f', logs.logP(:,k));
        fprintf(fid, ',%.4f', logs.logQ(:,k));
        fprintf(fid, ',%.4f,%.3f,%.4f,%.3f', ...
            logs.logCompRatio1(k), logs.logPow1(k)/1000, ...
            logs.logCompRatio2(k), logs.logPow2(k)/1000);
        fprintf(fid, ',%.3f,%.3f,%.3f', logV(1,k), logV(2,k), logV(3,k));
        fprintf(fid, ',%.4f', logs.logStoInventory(k));
        fprintf(fid, ',%.4f,%.4f,%d,%.4f,%d', ...
            logCU(k), logCL(k), int32(logCA(k)), logChi2(k), int32(logChi2A(k)));
        fprintf(fid, ',%.4f', logs.logResP(:,k));
        fprintf(fid, ',%.4f', logs.logPlcP(:,k));
        fprintf(fid, ',%.4f', logs.logPlcQ(:,k));
        fprintf(fid, ',%d,%d,%s,%s,%d\n', ...
                logFault(k), atk_id, ...
                char(logs.logAttackName(k)), char(logs.logMitreId(k)), label);
    end
    fclose(fid);
end


% =========================================================================
%  ASSEMBLY — concatenate all scenario CSVs
% =========================================================================

function assemble_attack_dataset(scen_dir, out_path)
    files = dir(fullfile(scen_dir, 'scenario_*.csv'));
    if isempty(files)
        fprintf('[assemble] No scenario CSVs found in %s\n', scen_dir);
        return;
    end
    [~,ord] = sort({files.name}); files = files(ord);

    fprintf('[assemble] Concatenating %d files → %s\n', numel(files), out_path);
    fout = fopen(out_path,'w'); hdr_written=false; total_rows=0; t0=tic;

    for i=1:numel(files)
        fid = fopen(fullfile(files(i).folder, files(i).name),'r');
        if fid < 0, continue; end
        hdr = fgetl(fid);
        if ~hdr_written && ischar(hdr)
            fprintf(fout,'%s\n',hdr); hdr_written=true;
        end
        while ~feof(fid)
            ln = fgetl(fid);
            if ischar(ln) && ~isempty(strtrim(ln))
                fprintf(fout,'%s\n',ln); total_rows=total_rows+1;
            end
        end
        fclose(fid);
        if mod(i,50)==0
            fprintf('[assemble]   %d/%d  (%d rows)\n',i,numel(files),total_rows);
        end
    end
    fclose(fout);
    info = dir(out_path);
    fprintf('[assemble] Done %.1fs → %d rows | %.1f MB\n', ...
            toc(t0), total_rows, info.bytes/1048576);
end


% =========================================================================
%  SCENARIO MATRIX  (reused from run_24h_sweep)
% =========================================================================

function scenarios = build_scenario_matrix()
    source_cfgs  = {'both', 'S1_only', 'S2_only'};
    demand_profs = {'low', 'medium', 'peak', 'uneven', 'spike'};
    valve_cfgs   = {'auto', 'E8_forced_open', 'E8_forced_closed'};
    storage_vals = [0.1, 0.5, 0.9];
    cs_modes     = {'both_on', 'CS1_only', 'CS2_only'};

    sid=0; n_pruned=0;
    list = struct('id',{},'source_config',{},'demand_profile',{},...
                  'valve_config',{},'storage_init',{},'cs_mode',{},'is_stress',{});

    for si=1:numel(source_cfgs)
      for di=1:numel(demand_profs)
        for vi=1:numel(valve_cfgs)
          for sti=1:numel(storage_vals)
            for ci=1:numel(cs_modes)
              src=source_cfgs{si}; dem=demand_profs{di}; valv=valve_cfgs{vi};
              sto=storage_vals(sti); csm=cs_modes{ci};

              if ~is_valid(src,dem,valv,sto,csm), n_pruned=n_pruned+1; continue; end

              sid=sid+1;
              sc.id=sid; sc.source_config=src; sc.demand_profile=dem;
              sc.valve_config=valv; sc.storage_init=sto; sc.cs_mode=csm;
              sc.is_stress = (sto<0.2&&strcmp(dem,'peak')) || ...
                             (strcmp(src,'S2_only')&&strcmp(dem,'peak')) || ...
                             (strcmp(csm,'CS1_only')&&strcmp(dem,'peak'));
              list(end+1)=sc; %#ok
            end
          end
        end
      end
    end
    scenarios=list;
    fprintf('[sweep] Valid:%d Pruned:%d\n', numel(scenarios), n_pruned);
end

function ok=is_valid(src,dem,valv,sto,csm)
    ok=true;
    if strcmp(src,'S1_only')&&strcmp(csm,'CS2_only'),           ok=false; return; end
    if strcmp(src,'S2_only')&&strcmp(csm,'CS1_only'),           ok=false; return; end
    if strcmp(valv,'E8_forced_closed')&&strcmp(csm,'CS1_only'), ok=false; return; end
    if strcmp(src,'S2_only')&&strcmp(dem,'peak')&&sto<0.2,      ok=false; return; end
end

% Gateway helpers (identical to run_24h_sweep)
function ok=check_gateway_connectivity()
    ok=false;
    try
        s=java.net.Socket(); s.connect(java.net.InetSocketAddress('127.0.0.1',1502),2000); s.close();
    catch, return; end
    try
        tx=java.net.DatagramSocket(); rx=java.net.DatagramSocket(6006); rx.setSoTimeout(2000);
        tx_addr=java.net.InetSocketAddress(java.net.InetAddress.getByName('127.0.0.1'),5005);
        tb=typecast(zeros(61,1,'double'),'int8');
        tx.send(java.net.DatagramPacket(tb,length(tb),tx_addr));
        pkt=java.net.DatagramPacket(zeros(1,128,'int8'),128); rx.receive(pkt);
        rx.close(); tx.close(); ok=true;
    catch, if exist('rx','var'),try,rx.close();catch,end;end; end
end
function [cfg,opened]=open_gateway_sockets(cfg)
    opened=false; cfg.use_gateway=false;
    try
        tx=java.net.DatagramSocket();
        tx_addr=java.net.InetSocketAddress(java.net.InetAddress.getByName('127.0.0.1'),5005);
        rx=java.net.DatagramSocket(6006); rx.setSoTimeout(500);
        cfg.tx_sock=tx; cfg.tx_addr=tx_addr; cfg.rx_sock=rx;
        cfg.use_gateway=true; opened=true;
    catch e, warning('open_gateway_sockets: %s',e.message); end
end
function close_gateway_sockets(cfg)
    if isfield(cfg,'rx_sock'),try,cfg.rx_sock.close();catch,end;end
    if isfield(cfg,'tx_sock'),try,cfg.tx_sock.close();catch,end;end
end
