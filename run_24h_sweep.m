%% run_24h_sweep.m
% =========================================================================
%  Indian CGD Gas Pipeline CPS Simulator
%  24-Hour Baseline Dataset Sweep — Gateway-Enabled (PLC-in-the-loop)
% =========================================================================
%
%  Each scenario runs identically to main_simulation(dur_min, true):
%    • MATLAB computes physics at 10 Hz
%    • Every log_every=10 steps (1 Hz): physics → UDP → gateway.py
%      → Modbus FC16 → CODESYS SoftPLC
%    • CODESYS PID runs on real register values, writes actuator outputs
%    • gateway.py reads FC3 (actuators) + FC1 (coils) → UDP → MATLAB
%    • MATLAB applies PLC actuator commands to next physics step
%
%  Prerequisites:
%    1. CODESYS Control Win — PLC started (F5), Modbus active on
%       127.0.0.1:1502, unit=1
%    2. Python gateway: cd middleware && python gateway.py
%    3. MATLAB working directory at project root
%
%  Usage:
%    >> run_24h_sweep()                    % full sweep, gateway on, 30 min/scenario
%    >> run_24h_sweep('dur_min', 60)       % 60 min/scenario
%    >> run_24h_sweep('resume', 45)        % resume after crash
%    >> run_24h_sweep('mode', 'quick')     % first 30 scenarios
%    >> run_24h_sweep('mode', 'stress')    % stress scenarios only
%    >> run_24h_sweep('gateway', false)    % offline fallback (no PLC)
%    >> run_24h_sweep('fault', true)       % enable comm fault injection
%
%  Runtime with gateway (loopback UDP + Modbus on same PC):
%    Each 30-min scenario: ~14-20 wall seconds (~90-130x real-time)
%    Full ~340-scenario sweep: ~85-115 min wall time
%
%  Output:
%    automated_dataset/baseline/scenario_XXXX.csv  (125 cols, per scenario)
%    automated_dataset/baseline/scenario_index.csv
%    automated_dataset/baseline/sweep_progress.log
%    automated_dataset/ml_dataset_baseline.csv     (assembled master)
%    middleware/logs/modbus_transactions_*.csv      (Modbus protocol layer)
%
% =========================================================================

function run_24h_sweep(varargin)

    %% ── Argument parsing ─────────────────────────────────────────────────
    ap = inputParser();
    addParameter(ap, 'mode',     'full');
    addParameter(ap, 'resume',   1);
    addParameter(ap, 'dur_min',  30);
    addParameter(ap, 'gateway',  true);
    addParameter(ap, 'fault',    false);
    addParameter(ap, 'assemble', true);
    addParameter(ap, 'out_dir',  'automated_dataset');
    parse(ap, varargin{:});
    opt = ap.Results;

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling','processing');

    dirs = setup_dirs(opt.out_dir);

    fprintf('\n');
    fprintf('=================================================================\n');
    fprintf('  Indian CGD Pipeline — 24-Hour Baseline Sweep\n');
    fprintf('  Mode    : %-8s   Duration : %d min/scenario\n', opt.mode, opt.dur_min);
    fprintf('  Gateway : %-5s     Faults   : %s\n', string(opt.gateway), string(opt.fault));
    fprintf('  Resume  : from scenario #%d\n', opt.resume);
    fprintf('  Output  : %s\n', dirs.baseline);
    fprintf('=================================================================\n\n');

    %% ── Pre-flight gateway connectivity check ────────────────────────────
    if opt.gateway
        gw_ok = check_gateway_connectivity();
        if ~gw_ok
            fprintf('\n[sweep] Gateway pre-flight FAILED.\n');
            fprintf('        Checklist:\n');
            fprintf('          1. CODESYS Control Win running, PLC started (F5)\n');
            fprintf('          2. gateway.py running: cd middleware && python gateway.py\n');
            fprintf('          3. No other process bound to UDP port 6006\n');
            fprintf('        To run offline: run_24h_sweep(''gateway'', false)\n\n');
            error('run_24h_sweep:noGateway', 'Gateway unreachable. See checklist above.');
        end
        fprintf('[sweep] Gateway pre-flight PASSED — CODESYS PLC-in-the-loop ready.\n\n');
    else
        fprintf('[sweep] Gateway DISABLED — offline physics only.\n\n');
    end

    %% ── Build and filter scenario matrix ─────────────────────────────────
    fprintf('[sweep] Building scenario matrix...\n');
    scenarios = build_scenario_matrix();
    n_all     = numel(scenarios);

    switch opt.mode
        case 'quick',  scenarios = scenarios(1 : min(30, n_all));
        case 'stress', mask = [scenarios.is_stress]; scenarios = scenarios(mask);
    end
    n_total = numel(scenarios);

    fprintf('[sweep] Scenarios selected : %d\n', n_total);
    fprintf('[sweep] Est. dataset rows  : ~%s (at 1 Hz, %d min/scenario)\n', ...
            fmtnum(n_total * opt.dur_min * 60), opt.dur_min);
    fprintf('[sweep] Est. wall time     : ~%.0f min\n\n', ...
            n_total * opt.dur_min / 100);   % ~100x real-time with gateway

    %% ── Progress log ─────────────────────────────────────────────────────
    log_fid  = fopen(fullfile(dirs.baseline, 'sweep_progress.log'), 'a');
    fprintf(log_fid, '\n=== START %s  mode=%s  dur=%dmin  gw=%s  n=%d ===\n', ...
            datestr(now), opt.mode, opt.dur_min, ...  %#ok<TNOW1,DATST>
            string(opt.gateway), n_total);

    idx_path = fullfile(dirs.baseline, 'scenario_index.csv');
    if opt.resume == 1 || ~exist(idx_path, 'file')
        fid = fopen(idx_path, 'w');
        fprintf(fid, ['scenario_id,source_config,demand_profile,valve_config,' ...
                      'storage_init,cs_mode,is_stress,gateway_active,' ...
                      'status,n_rows,wall_s\n']);
        fclose(fid);
    end

    %% ── Main sweep loop ──────────────────────────────────────────────────
    sweep_t0  = tic;
    completed = 0;
    failed    = 0;
    skipped   = 0;

    for si = opt.resume : n_total

        scen = scenarios(si);
        tag  = '';  if scen.is_stress, tag = ' [STRESS]'; end

        fprintf('[%d/%d] sc=%04d  src=%-8s dem=%-8s valv=%-16s sto=%.1f cs=%-10s%s\n', ...
                si, n_total, scen.id, scen.source_config, scen.demand_profile, ...
                scen.valve_config, scen.storage_init, scen.cs_mode, tag);
        fprintf('         elapsed=%.2fh  ETA=%.2fh\n', ...
                toc(sweep_t0)/3600, sweep_eta(sweep_t0, si-opt.resume, n_total-opt.resume+1));

        %% Skip if already written
        out_csv = fullfile(dirs.baseline, sprintf('scenario_%04d.csv', scen.id));
        if exist(out_csv, 'file')
            info = dir(out_csv);
            if info.bytes > 2000
                fprintf('  [skip] Exists (%s KB)\n', fmtnum(round(info.bytes/1024)));
                skipped = skipped + 1;
                continue;
            end
        end

        %% Build config
        cfg       = build_scenario_config(scen, opt.dur_min, opt.fault);
        sc_t0     = tic;
        n_rows    = 0;
        status    = 'FAILED';
        gw_active = false;

        %% Open gateway sockets for this scenario
        if opt.gateway
            [cfg, gw_active] = open_gateway_sockets(cfg);
            if ~gw_active
                fprintf('  [WARN] Socket open failed — running this scenario offline.\n');
                fprintf(log_fid, '[WARN] sc=%04d socket open failed\n', scen.id);
            end
        end

        %% Execute + export
        try
            [logs, params, N, schedule] = execute_simulation(cfg);
            export_scenario_csv(logs, cfg, params, schedule, scen, out_csv);
            n_rows = logs.N_log;
            status = 'OK';
            completed = completed + 1;
            fprintf('  Done %.1fs → %s rows  (%.0fx real-time)\n', ...
                    toc(sc_t0), fmtnum(n_rows), (opt.dur_min*60)/max(0.1,toc(sc_t0)));
        catch e
            failed = failed + 1;
            fprintf('  [ERROR] %s\n', e.message);
            fprintf(log_fid, '[FAIL] sc=%04d  %s\n', scen.id, e.message);
        end

        %% Close sockets before next scenario
        if opt.gateway && gw_active
            close_gateway_sockets(cfg);
        end

        %% Append to scenario index
        fid = fopen(idx_path, 'a');
        fprintf(fid, '%d,%s,%s,%s,%.1f,%s,%d,%d,%s,%d,%.2f\n', ...
                scen.id, scen.source_config, scen.demand_profile, ...
                scen.valve_config, scen.storage_init, scen.cs_mode, ...
                scen.is_stress, gw_active, status, n_rows, toc(sc_t0));
        fclose(fid);

        fprintf(log_fid, '[%s] %s sc=%04d  gw=%d  rows=%d  wall=%.1fs\n', ...
                datestr(now,'HH:MM:SS'), status, scen.id, ...  %#ok<DATST>
                gw_active, n_rows, toc(sc_t0));

        %% 2-second inter-scenario pause when gateway is active.
        %  Allows CODESYS PID integrators to wind down before the next
        %  scenario writes fresh initial values to the Modbus registers.
        %  Without this, residual integral wind-up from scenario N causes
        %  a transient spike in the first few seconds of scenario N+1.
        if opt.gateway && gw_active
            pause(2);
        end

    end % scenario loop

    %% ── Summary ──────────────────────────────────────────────────────────
    wall_h = toc(sweep_t0) / 3600;
    fprintf('\n=================================================================\n');
    fprintf('  SWEEP COMPLETE\n');
    fprintf('  Completed : %d   Failed : %d   Skipped : %d\n', completed, failed, skipped);
    fprintf('  Wall time : %.2f hours\n', wall_h);
    fprintf('=================================================================\n\n');
    fprintf(log_fid, '=== END  ok=%d  fail=%d  wall=%.2fh ===\n', completed, failed, wall_h);
    fclose(log_fid);

    %% ── Assemble master CSV ──────────────────────────────────────────────
    if opt.assemble
        assemble_baseline_dataset(dirs.baseline, ...
            fullfile(opt.out_dir, 'ml_dataset_baseline.csv'));
    end
end


% =========================================================================
%  SECTION 1 — GATEWAY MANAGEMENT
% =========================================================================

function ok = check_gateway_connectivity()
% check_gateway_connectivity  Two-stage pre-flight check before the sweep.
%
%  Stage 1: raw TCP connect to CODESYS on port 1502. Fast — just checks
%  the socket is open. Does not read any Modbus data.
%
%  Stage 2: send a zeroed 61-float64 UDP packet (488 bytes) to gateway.py
%  on port 5005, then listen on port 6006 for the 16-float64 reply (128
%  bytes). The gateway echoes actuator defaults immediately. This confirms
%  the full round-trip: MATLAB ↔ gateway.py ↔ CODESYS Modbus.
%
%  Port 6006 is unbound here before the sweep starts; each scenario's
%  open_gateway_sockets() will bind it fresh.

    ok = false;

    %% Stage 1 — CODESYS TCP
    fprintf('[preflight] Stage 1: CODESYS TCP 127.0.0.1:1502 ... ');
    try
        s = java.net.Socket();
        s.connect(java.net.InetSocketAddress('127.0.0.1', 1502), 2000);
        s.close();
        fprintf('OPEN\n');
    catch
        fprintf('UNREACHABLE\n');
        fprintf('[preflight]   → Start CODESYS, open PLC_PRG, press F5.\n');
        return;
    end

    %% Stage 2 — UDP round-trip through gateway.py
    fprintf('[preflight] Stage 2: UDP round-trip via gateway.py port 5005 ... ');
    try
        test_payload = zeros(61, 1, 'double');
        test_bytes   = typecast(test_payload, 'int8');

        tx = java.net.DatagramSocket();
        rx = java.net.DatagramSocket(6006);
        rx.setSoTimeout(2000);

        tx_addr = java.net.InetSocketAddress( ...
                    java.net.InetAddress.getByName('127.0.0.1'), 5005);
        tx.send(java.net.DatagramPacket(test_bytes, length(test_bytes), tx_addr));

        buf = zeros(1, 128, 'int8');
        pkt = java.net.DatagramPacket(buf, 128);
        rx.receive(pkt);

        rx.close(); tx.close();
        fprintf('OK (%d bytes received)\n', pkt.getLength());
        ok = true;

    catch e
        if exist('rx','var'), try, rx.close(); catch, end; end
        if exist('tx','var'), try, tx.close(); catch, end; end
        if contains(e.message, 'timeout') || contains(e.message, 'Timeout')
            fprintf('TIMEOUT\n');
            fprintf('[preflight]   → Is gateway.py running? python middleware/gateway.py\n');
        else
            fprintf('ERROR: %s\n', e.message);
        end
    end
end


function [cfg, opened] = open_gateway_sockets(cfg)
% open_gateway_sockets  Open Java UDP sockets for one scenario's runtime.
%
%  Port layout (matches main_simulation.m exactly):
%    TX: ephemeral port → sends physics to gateway on 127.0.0.1:5005
%    RX: 6006           → receives actuator reply from gateway
%
%  Returns opened=false and cfg.use_gateway=false on failure so the
%  scenario degrades to offline mode rather than crashing the sweep.

    opened          = false;
    cfg.use_gateway = false;

    try
        tx_sock = java.net.DatagramSocket();
        tx_addr = java.net.InetSocketAddress( ...
                    java.net.InetAddress.getByName('127.0.0.1'), 5005);
        rx_sock = java.net.DatagramSocket(6006);
        rx_sock.setSoTimeout(500);

        cfg.tx_sock     = tx_sock;
        cfg.tx_addr     = tx_addr;
        cfg.rx_sock     = rx_sock;
        cfg.use_gateway = true;
        opened          = true;

    catch e
        warning('open_gateway_sockets: %s', e.message);
    end
end


function close_gateway_sockets(cfg)
% close_gateway_sockets  Release UDP sockets after a scenario completes.
%
%  Closing rx_sock (port 6006) before open_gateway_sockets() is called
%  for the next scenario is critical — if 6006 is still bound when the
%  next scenario tries to bind it, the bind throws immediately and that
%  scenario falls back to offline mode.

    if isfield(cfg, 'rx_sock'), try, cfg.rx_sock.close(); catch, end; end
    if isfield(cfg, 'tx_sock'), try, cfg.tx_sock.close(); catch, end; end
end


% =========================================================================
%  SECTION 2 — SCENARIO MATRIX
% =========================================================================

function scenarios = build_scenario_matrix()

    source_cfgs  = {'both', 'S1_only', 'S2_only'};
    demand_profs = {'low', 'medium', 'peak', 'uneven', 'spike'};
    valve_cfgs   = {'auto', 'E8_forced_open', 'E8_forced_closed'};
    storage_vals = [0.1, 0.5, 0.9];
    cs_modes     = {'both_on', 'CS1_only', 'CS2_only'};

    sid      = 0;
    n_pruned = 0;
    list     = struct('id',{},'source_config',{},'demand_profile',{}, ...
                      'valve_config',{},'storage_init',{},'cs_mode',{}, ...
                      'is_stress',{});

    for si = 1:numel(source_cfgs)
      for di = 1:numel(demand_profs)
        for vi = 1:numel(valve_cfgs)
          for sti = 1:numel(storage_vals)
            for ci = 1:numel(cs_modes)

              src  = source_cfgs{si};
              dem  = demand_profs{di};
              valv = valve_cfgs{vi};
              sto  = storage_vals(sti);
              csm  = cs_modes{ci};

              if ~is_valid_scenario(src, dem, valv, sto, csm)
                  n_pruned = n_pruned + 1;
                  continue;
              end

              sid      = sid + 1;
              sc.id             = sid;
              sc.source_config  = src;
              sc.demand_profile = dem;
              sc.valve_config   = valv;
              sc.storage_init   = sto;
              sc.cs_mode        = csm;
              sc.is_stress      = is_stress_scenario(src, dem, sto, csm);
              list(end+1)       = sc; %#ok<AGROW>

            end
          end
        end
      end
    end

    scenarios = list;
    fprintf('[sweep] Valid : %d   Pruned : %d   (of %d combinations)\n', ...
            numel(scenarios), n_pruned, numel(scenarios) + n_pruned);
end


function ok = is_valid_scenario(src, dem, valv, sto, csm)
    ok = true;
    if strcmp(src,'S1_only') && strcmp(csm,'CS2_only'),           ok=false; return; end
    if strcmp(src,'S2_only') && strcmp(csm,'CS1_only'),           ok=false; return; end
    if strcmp(valv,'E8_forced_closed') && strcmp(csm,'CS1_only'), ok=false; return; end
    if strcmp(src,'S2_only') && strcmp(dem,'peak') && sto < 0.2,  ok=false; return; end
end


function stress = is_stress_scenario(src, dem, sto, csm)
    stress = ...
        (sto < 0.2 && strcmp(dem,'peak'))              || ...
        (sto < 0.2 && strcmp(dem,'spike'))             || ...
        (strcmp(src,'S2_only') && strcmp(dem,'peak'))  || ...
        (strcmp(csm,'CS1_only') && strcmp(dem,'peak')) || ...
        (strcmp(csm,'CS2_only') && strcmp(dem,'spike'));
end


% =========================================================================
%  SECTION 3 — CONFIGURATION
% =========================================================================

function cfg = build_scenario_config(scen, dur_min, fault_en)
% build_scenario_config  Construct a full cfg for one scenario.
%
%  NOTE: Indian CGD parameter overrides (Phase A) are commented out until
%  the storage loop divergence is fixed. Running with European p0=50 bar
%  keeps the storage inject/withdraw thresholds (52/46 bar) stable.
%  Uncomment the apply_cgd_overrides() call once Phase A is verified clean
%  with run_24h_sweep('mode','quick').

    cfg   = simConfig();
    cfg = apply_cgd_overrides(cfg);   % ← Phase A: uncomment after storage fix

    cfg.T = dur_min * 60;

    cfg.scenario_id             = scen.id;
    cfg.scenario_source_config  = scen.source_config;
    cfg.scenario_demand_profile = scen.demand_profile;
    cfg.scenario_valve_config   = scen.valve_config;
    cfg.scenario_storage_init   = scen.storage_init;
    cfg.scenario_cs_mode        = scen.cs_mode;

    cfg.sto_inventory_init = scen.storage_init;

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

    cfg.n_attacks           = 8;
    cfg.forced_attack_id    = [];
    cfg.fault_enable        = fault_en;
    cfg.historian_enable    = false;   % suppress per-scenario historian files
    cfg = randomize_attack_params(cfg, scen.id); 
    %% Gateway fields — populated by open_gateway_sockets() if gateway=true
    cfg.use_gateway       = false;
    cfg.gateway_timeout_s = 0.5;
end


% =========================================================================
%  SECTION 4 — SIMULATION EXECUTION
% =========================================================================

function [logs, params, N, schedule] = execute_simulation(cfg)
% execute_simulation  Initialise all subsystems and hand off to runSimulation.
%
%  When cfg.use_gateway = true (set by open_gateway_sockets before this
%  call), runSimulation automatically activates its gateway path:
%    step 22 inside runSimulation:
%      sendToGateway(cfg, gw_out)       — 488 bytes UDP → gateway.py
%      receiveFromGateway(cfg, gw_prev) — 128 bytes UDP ← gateway.py
%  The round-trip adds ~1 ms per logged step on loopback.
%  For a 30-min scenario (1800 logged steps) this is ~1.8 s overhead — 
%  negligible. The PLC's actuator outputs (compressor ratios, valve cmds)
%  are applied to the physics state at the start of the next logged step.

    dt = cfg.dt;
    N  = double(round(cfg.T / dt));

    logEvent(-1);   % reset persistent logger state from any previous scenario

    [params, state] = initNetwork(cfg);

    src_p1 = generateSourceProfile(N, cfg);

    cfg_s2           = cfg;
    cfg_s2.p0        = 0.5 * (cfg.src2_p_min + cfg.src2_p_max);
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
    initValve(cfg); %#ok

    plc      = initPLC(cfg, state, comp1);
    ekf      = initEKF(cfg, state);
    schedule = make_empty_schedule(N);
    logs     = initLogs(params, ekf, N, cfg);

    [params, ~, ~, ~, ~, ~, ~, ~, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule);

    logEvent(-1);
end


function schedule = make_empty_schedule(N)
    schedule.nAttacks    = 0;
    schedule.ids         = [];
    schedule.start_s     = [];
    schedule.end_s       = [];
    schedule.dur_s       = [];
    schedule.params      = {};
    schedule.label_id    = zeros(N, 1, 'int32');
    schedule.label_name  = repmat("Normal", N, 1);
    schedule.label_mitre = repmat("None",   N, 1);
end


% =========================================================================
%  SECTION 5 — CSV EXPORT (125 columns)
% =========================================================================

function export_scenario_csv(logs, cfg, params, schedule, scen, fpath) %#ok<INUSL>

    N_log  = logs.N_log;
    log_dt = cfg.dt * max(1, cfg.log_every);
    t_vec  = (0:N_log-1)' * log_dt;
    nn     = params.nodeNames;
    en     = params.edgeNames;

    %% Header
    hdr = 'Timestamp_s,scenario_id,source_config,demand_profile,valve_config,storage_init,cs_mode';
    for i=1:params.nNodes, hdr=[hdr sprintf(',p_%s_bar',  char(nn(i)))]; end %#ok<AGROW>
    for i=1:params.nEdges, hdr=[hdr sprintf(',q_%s_kgs',  char(en(i)))]; end %#ok<AGROW>
    hdr=[hdr ',CS1_ratio,CS1_power_kW,CS2_ratio,CS2_power_kW'];
    hdr=[hdr ',PRS1_throttle,PRS2_throttle'];
    hdr=[hdr ',valve_E8,valve_E14,valve_E15,STO_inventory'];
    hdr=[hdr ',cusum_S_upper,cusum_S_lower,cusum_alarm,chi2_stat,chi2_alarm'];
    for i=1:params.nNodes, hdr=[hdr sprintf(',ekf_resid_%s', char(nn(i)))]; end %#ok<AGROW>
    for i=1:params.nNodes, hdr=[hdr sprintf(',plc_p_%s',     char(nn(i)))]; end %#ok<AGROW>
    for i=1:params.nEdges, hdr=[hdr sprintf(',plc_q_%s',     char(en(i)))]; end %#ok<AGROW>
    hdr=[hdr ',FAULT_ID,ATTACK_ID,MITRE_CODE,prop_origin_node,prop_hop_node,prop_delay_s,prop_cascade_step,label'];

    %% Pre-extract
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
                   scen.demand_profile, scen.valve_config, ...
                   scen.storage_init, scen.cs_mode);

    %% Write
    fid = fopen(fpath, 'w');
    if fid < 0, error('Cannot open %s', fpath); end
    fprintf(fid, '%s\n', hdr);

    for k = 1:N_log
        fprintf(fid, '%.3f,%s', t_vec(k), meta);
        fprintf(fid, ',%.4f', logs.logP(:,k));
        fprintf(fid, ',%.4f', logs.logQ(:,k));
        fprintf(fid, ',%.4f,%.3f,%.4f,%.3f', ...
            logs.logCompRatio1(k), logs.logPow1(k)/1000, ...
            logs.logCompRatio2(k), logs.logPow2(k)/1000);
        fprintf(fid, ',%.4f,%.4f', logs.logPRS1Throttle(k), logs.logPRS2Throttle(k));
        fprintf(fid, ',%.3f,%.3f,%.3f', logV(1,k), logV(2,k), logV(3,k));
        fprintf(fid, ',%.4f', logs.logStoInventory(k));
        fprintf(fid, ',%.4f,%.4f,%d,%.4f,%d', ...
            logCU(k), logCL(k), int32(logCA(k)), logChi2(k), int32(logChi2A(k)));
        fprintf(fid, ',%.4f', logs.logResP(:,k));
        fprintf(fid, ',%.4f', logs.logPlcP(:,k));
        fprintf(fid, ',%.4f', logs.logPlcQ(:,k));
        % ATTACK_ID and MITRE_CODE
        atk_id = logs.logAttackId(k);
        mitre_str = char(logs.logMitreId(k));
        mitre_lut = containers.Map( ...
            {'None','T0831','T0838','T0855','T0829','T0827','T0814'}, ...
            {0,      831,    838,    855,    829,    827,    814});
        mc = 0;
        if isKey(mitre_lut, mitre_str), mc = mitre_lut(mitre_str); end
        % Phase C propagation columns
        p_orig = 0; p_hop = 0; p_del = 0.0; p_cas = 0;
        if isfield(logs,'logPropOrigin') && numel(logs.logPropOrigin) >= k
            p_orig = logs.logPropOrigin(k);
            p_hop  = logs.logPropHop(k);
            p_del  = logs.logPropDelay(k);
            p_cas  = logs.logPropCascade(k);
        end
        % label = 1 if fault OR attack, else 0
        label = int32(logFault(k) > 0 || atk_id > 0);
        fprintf(fid, ',%d,%d,%d,%d,%d,%.3f,%d,%d\n', ...
                logFault(k), atk_id, mc, p_orig, p_hop, p_del, p_cas, label);
    end
    fclose(fid);
end


% =========================================================================
%  SECTION 6 — MASTER CSV ASSEMBLY
% =========================================================================

function assemble_baseline_dataset(scen_dir, out_path)
    files = dir(fullfile(scen_dir, 'scenario_*.csv'));
    if isempty(files), fprintf('[assemble] No files found.\n'); return; end
    [~,ord] = sort({files.name}); files = files(ord);

    fprintf('[assemble] Concatenating %d files → %s\n', numel(files), out_path);
    fout = fopen(out_path,'w'); hdr_written=false; total_rows=0; t0=tic;

    for i=1:numel(files)
        fid=fopen(fullfile(files(i).folder,files(i).name),'r'); if fid<0, continue; end
        hdr=fgetl(fid);
        if ~hdr_written, fprintf(fout,'%s\n',hdr); hdr_written=true; end
        while ~feof(fid)
            ln=fgetl(fid);
            if ischar(ln) && ~isempty(strtrim(ln))
                fprintf(fout,'%s\n',ln); total_rows=total_rows+1;
            end
        end
        fclose(fid);
        if mod(i,50)==0
            fprintf('[assemble]   %d/%d  (%s rows)\n',i,numel(files),fmtnum(total_rows));
        end
    end
    fclose(fout);
    info=dir(out_path);
    fprintf('[assemble] Done %.1fs → %s rows | %.1f MB\n', ...
            toc(t0), fmtnum(total_rows), info.bytes/1048576);
end


% =========================================================================
%  SECTION 7 — UTILITIES
% =========================================================================

function dirs = setup_dirs(base)
    dirs.root     = base;
    dirs.baseline = fullfile(base,'baseline');
    for f=fieldnames(dirs)', d=dirs.(f{1}); if ~exist(d,'dir'), mkdir(d); end; end
end

function eta_h = sweep_eta(t_start, n_done, n_remaining)
    if n_done<=0, eta_h=n_remaining*20/3600; return; end
    eta_h = n_remaining * (toc(t_start)/n_done) / 3600;
end

function s = fmtnum(n)
    s=sprintf('%d',round(n)); k=numel(s)-3;
    while k>0, s=[s(1:k),',',s(k+1:end)]; k=k-3; end
end