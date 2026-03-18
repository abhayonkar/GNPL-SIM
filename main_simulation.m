%% main_simulation.m
% =========================================================================
%  Gas Pipeline CPS Simulator — Top-Level Entry Point
%  Real-time paced: a 100-min simulation runs in ~100 min wall time.
%
%  Usage:
%    >> main_simulation            % 100 min, 4 attacks, 1 Hz dataset
%    >> main_simulation(60)        % 60 min
%    >> main_simulation(60, false) % 60 min offline
% =========================================================================

function main_simulation(duration_min, use_gateway)

    if nargin < 1, duration_min = 100; end
    if nargin < 2, use_gateway  = true; end

    fprintf('=================================================================\n');
    fprintf('  Gas Pipeline CPS Simulator\n');
    fprintf('  Duration   : %d min\n', duration_min);
    fprintf('  Gateway    : %s\n', string(use_gateway));

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling');

    %% ── Configuration ────────────────────────────────────────────────────
    fprintf('[init] Loading configuration...\n');
    cfg       = simConfig();
    cfg.T     = duration_min * 60;
    dt        = cfg.dt;
    N         = double(round(cfg.T / dt));
    log_every = max(1, cfg.log_every);
    N_log     = floor(N / log_every);
    log_dt    = dt * log_every;

    fprintf('  Physics    : %.2fs dt  (%.0f Hz)\n',    dt, 1/dt);
    fprintf('  Dataset    : %.1fs / row  (%.1f Hz)  →  %d rows\n', log_dt, 1/log_dt, N_log);
    fprintf('  Attacks    : %d\n', cfg.n_attacks);
    fprintf('  Wall time  : ~%d min (real-time paced)\n', duration_min);
    fprintf('=================================================================\n\n');

    %% ── Event logger ─────────────────────────────────────────────────────
    initLogger(dt, cfg.T, N);

    %% ── Network ──────────────────────────────────────────────────────────
    fprintf('[init] Initialising 20-node network...\n');
    [params, state] = initNetwork(cfg);

    %% ── Profiles ─────────────────────────────────────────────────────────
    fprintf('[init] Generating source profiles...\n');
    src_p1 = generateSourceProfile(N, cfg);
    src_p2 = generateSourceProfile(N, cfg);
    demand = ones(N, 1);

    %% ── Equipment ────────────────────────────────────────────────────────
    fprintf('[init] Initialising compressors, PRS, valve...\n');
    [comp1, comp2] = initCompressor(cfg);
    [prs1, prs2]   = initPRS(cfg);
    valve          = initValve(cfg);   %#ok<NASGU>

    %% ── SCADA / EKF ──────────────────────────────────────────────────────
    fprintf('[init] Initialising PLC + EKF...\n');
    plc = initPLC(cfg, state, comp1);
    ekf = initEKF(cfg, state);

    %% ── Attack schedule ──────────────────────────────────────────────────
    fprintf('[init] Scheduling %d attacks over %d min...\n', cfg.n_attacks, duration_min);
    if duration_min < 30
        fprintf('[init] Duration < 30 min — clean baseline (no attacks).\n');
        schedule = initEmptySchedule(N);
    else
        schedule = initAttackSchedule(N, cfg);
    end

    %% ── Log pre-allocation ───────────────────────────────────────────────
    fprintf('[init] Preallocating %d log rows...\n', N_log);
    logs = initLogs(params, ekf, N, cfg);

    %% ── UDP gateway (Java DatagramSocket, no toolbox) ────────────────────
    cfg.use_gateway       = false;
    cfg.gateway_timeout_s = 0.5;

    if use_gateway
        fprintf('[init] Opening UDP gateway (Java sockets)...\n');
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
            fprintf('[init] UDP TX -> 127.0.0.1:5005   RX <- :6006\n');
        catch e_java
            warning('[init] UDP failed: %s — running offline.', e_java.message);
        end
    end

    %% ── Ctrl+C cleanup ───────────────────────────────────────────────────
    logs_ref   = {logs};
    cleanupObj = onCleanup(@() do_cleanup(logs_ref{1}, cfg, params, N, schedule));

    %% ── Run ──────────────────────────────────────────────────────────────
    fprintf('\n[run] Starting — will complete in ~%d min.\n', duration_min);
    fprintf('      Progress printed every 5 simulated minutes.\n');
    fprintf('      Ctrl+C saves partial dataset.\n\n');
    t0 = tic;

    [params, state, comp1, comp2, prs1, prs2, ekf, plc, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule);

    logs_ref{1} = logs;
    elapsed = toc(t0);
    fprintf('\n[done] Wall time: %.1f min  (simulated: %d min  ratio: %.2fx)\n', ...
            elapsed/60, duration_min, elapsed/(duration_min*60));

    %% ── Export ───────────────────────────────────────────────────────────
    fprintf('[export] Writing master_dataset.csv...\n');
    exportDataset(logs, cfg, params, N, schedule);
    fprintf('[export] Done → automated_dataset/master_dataset.csv\n');

    %% ── Close ────────────────────────────────────────────────────────────
    if cfg.use_gateway
        try, cfg.tx_sock.close(); catch, end
        try, cfg.rx_sock.close(); catch, end
    end
    closeLogger(dt, N);
    fprintf('=================================================================\n');
end


function do_cleanup(logs, cfg, params, N, schedule)
    fprintf('\n[cleanup] Saving partial dataset...\n');
    try
        if isfield(logs,'logP') && ~isempty(logs.logP) && any(logs.logP(:,1) ~= 0)
            exportDataset(logs, cfg, params, N, schedule);
            fprintf('[cleanup] Saved.\n');
        else
            fprintf('[cleanup] Logs empty — skipping.\n');
        end
    catch e
        fprintf('[cleanup] Error: %s\n', e.message);
    end
    if isfield(cfg,'tx_sock'), try, cfg.tx_sock.close(); catch, end; end
    if isfield(cfg,'rx_sock'), try, cfg.rx_sock.close(); catch, end; end
end


function schedule = initEmptySchedule(N)
    schedule.nAttacks      = 0;
    schedule.ids           = [];
    schedule.start_s       = [];
    schedule.end_s         = [];
    schedule.dur_s         = [];
    schedule.params        = {};
    schedule.label_id      = zeros(N, 1, 'uint8');
    schedule.label_name    = repmat("Normal", N, 1);
    schedule.label_mitre   = repmat("None",   N, 1);
end