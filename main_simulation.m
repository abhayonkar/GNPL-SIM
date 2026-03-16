%% main_simulation.m
% =========================================================================
%  Gas Pipeline CPS Simulator — Top-Level Entry Point
% =========================================================================
%  Thin wrapper: initialises all subsystems, opens UDP gateway,
%  delegates the simulation loop to runSimulation.m, exports dataset.
%
%  Prerequisites:
%    1. CODESYS running (F5 in CODESYS IDE)
%    2. Python gateway:  cd middleware && python gateway.py
%    3. MATLAB working directory = Sim/ (project root)
%
%  Usage:
%    >> main_simulation            % 300 min with gateway
%    >> main_simulation(60)        % 60 min with gateway
%    >> main_simulation(60, false) % 60 min offline (no UDP)
% =========================================================================

function main_simulation(duration_min, use_gateway)

    if nargin < 1, duration_min = 300; end
    if nargin < 2, use_gateway  = true; end

    fprintf('=================================================================\n');
    fprintf('  Gas Pipeline CPS Simulator\n');
    fprintf('  Duration : %d min\n', duration_min);
    fprintf('  Gateway  : %s\n', string(use_gateway));
    fprintf('=================================================================\n\n');

    %% ── paths ───────────────────────────────────────────────────────────
    addpath('config');
    addpath('network');
    addpath('equipment');
    addpath('scada');
    addpath('control');
    addpath('attacks');
    addpath('logging');
    addpath('export');
    addpath('middleware');
    addpath('profiling');

    %% ── configuration ───────────────────────────────────────────────────
    fprintf('[init] Loading configuration...\n');
    cfg   = simConfig();
    cfg.T = duration_min * 60;
    dt    = cfg.dt;
    N     = double(round(cfg.T / dt));   % plain scalar double for for-loop

    %% ── network + initial state ─────────────────────────────────────────
    fprintf('[init] Initialising 20-node network...\n');
    [params, state] = initNetwork(cfg);

    %% ── source + demand profiles ────────────────────────────────────────
    %  runSimulation expects two separate N×1 source pressure vectors.
    %  Two independent calls give S1 and S2 different random realisations.
    fprintf('[init] Generating profiles...\n');
    src_p1 = generateSourceProfile(N, cfg);   % source node 1  (S1)
    src_p2 = generateSourceProfile(N, cfg);   % source node 14 (S2)
    demand = ones(N, 1);

    %% ── compressors ─────────────────────────────────────────────────────
    %  Keep comp1 and comp2 as separate structs — runSimulation takes both.
    fprintf('[init] Initialising compressors...\n');
    [comp1, comp2] = initCompressor(cfg);

    %% ── PRS (pressure regulating stations) ──────────────────────────────
    %  runSimulation positional args 6 and 7 are prs1 and prs2.
    fprintf('[init] Initialising PRS...\n');
    [prs1, prs2] = initPRS(cfg);

    %% ── valve (managed internally by runSimulation via params.valveEdges)
    valve = initValve(cfg);   %#ok<NASGU>  kept for reference / future use

    %% ── PLC (SCADA telemetry model) ─────────────────────────────────────
    fprintf('[init] Initialising PLC...\n');
    plc = initPLC(cfg, state, comp1);

    %% ── EKF ─────────────────────────────────────────────────────────────
    fprintf('[init] Initialising EKF...\n');
    ekf = initEKF(cfg, state);

    %% ── attack schedule ─────────────────────────────────────────────────
    fprintf('[init] Initialising attack schedule...\n');
    if duration_min < 30
        fprintf('[init] Duration < 30 min — clean baseline only (no attacks).\n');
        schedule = initEmptySchedule(N);
    else
        schedule = initAttackSchedule(N, cfg);
    end

    %% ── logs ────────────────────────────────────────────────────────────
    fprintf('[init] Preallocating logs (%d steps)...\n', N);
    logs = initLogs(params, ekf, N);

    %% ── UDP gateway ─────────────────────────────────────────────────────
    if use_gateway
        fprintf('[init] Opening UDP link to Python gateway...\n');
        try
            % R2021a+ style first
            u_tx = udpport();
            connect(u_tx, '127.0.0.1', 5005);
            u_rx = udpport('LocalPort', 6006);
            configureTimeout(u_rx, 0.05);
            fprintf('[init] UDP TX -> 127.0.0.1:5005   UDP RX <- :6006\n');
            cfg.u_tx        = u_tx;
            cfg.u_rx        = u_rx;
            cfg.use_gateway = true;
        catch
            try
                % Legacy R2020b and below
                u_tx = udp('127.0.0.1', 5005, 'LocalPort', 0);
                fopen(u_tx);
                u_rx = udp('127.0.0.1', 6006, 'LocalPort', 6006, 'Timeout', 0.05);
                fopen(u_rx);
                fprintf('[init] UDP (legacy) TX -> 5005   RX <- 6006\n');
                cfg.u_tx        = u_tx;
                cfg.u_rx        = u_rx;
                cfg.use_gateway = true;
            catch e2
                warning('UDP init failed: %s — running offline.', e2.message);
                cfg.use_gateway = false;
            end
        end
    else
        cfg.use_gateway = false;
    end

    %% ── register Ctrl+C cleanup ─────────────────────────────────────────
    logs_ref   = {logs};
    cleanupObj = onCleanup(@() do_cleanup(logs_ref{1}, cfg, params, N, schedule));

    %% ── run ─────────────────────────────────────────────────────────────
    fprintf('\n[run] Starting simulation (%d steps @ %.0f Hz)...\n', N, 1/dt);
    fprintf('      Ctrl+C saves partial dataset and exits.\n\n');
    t0 = tic;

    % ── Call signature matches runSimulation.m exactly: ──────────────────
    %   function [params,state,comp1,comp2,prs1,prs2,ekf,plc,logs] =
    %       runSimulation(cfg, params, state,
    %                     comp1, comp2, prs1, prs2,
    %                     ekf, plc, logs,
    %                     N, src_p1, src_p2, demand, schedule)
    [params, state, comp1, comp2, prs1, prs2, ekf, plc, logs] = runSimulation( ...
        cfg, params, state, ...
        comp1, comp2, prs1, prs2, ...
        ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule);

    logs_ref{1} = logs;
    elapsed = toc(t0);
    fprintf('\n[done] Simulation complete. Wall time: %.1fs\n', elapsed);

    %% ── export ──────────────────────────────────────────────────────────
    fprintf('[export] Writing master_dataset.csv...\n');
    exportDataset(logs, cfg, params, N, schedule);
    fprintf('[export] Done. >> automated_dataset/master_dataset.csv\n');

    %% ── close UDP ───────────────────────────────────────────────────────
    if cfg.use_gateway
        try, clear u_tx; catch, end
        try, clear u_rx; catch, end
    end

    fprintf('=================================================================\n');
end


function do_cleanup(logs, cfg, params, N, schedule)
    fprintf('\n[cleanup] Saving partial dataset...\n');
    try
        if isfield(logs, 'logPow') && ~isempty(logs.logPow) && any(logs.logP(:,1) ~= 0)
            exportDataset(logs, cfg, params, N, schedule);
            fprintf('[cleanup] Saved to automated_dataset/\n');
        else
            fprintf('[cleanup] Logs empty — skipping export.\n');
        end
    catch e
        fprintf('[cleanup] Export error: %s\n', e.message);
    end
end


function schedule = initEmptySchedule(N)
% initEmptySchedule  Returns a zero-attack schedule for short / clean runs.
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