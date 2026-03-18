function logs = initLogs(params, ekf, N, cfg)
% initLogs  Preallocate all log arrays.
%
%   logs = initLogs(params, ekf, N, cfg)
%
%   Logging is decimated: only every cfg.log_every physics steps is
%   written to the dataset, giving a 1/log_every Hz dataset sample rate.
%
%   N_log = floor(N / cfg.log_every)   rows are allocated.
%
%   For a 100-min simulation at dt=0.1 s (N=60000 steps) with
%   log_every=10: N_log = 6000 rows  (one row per second).

    nN = params.nNodes;   % 20
    nE = params.nEdges;   % 20
    nX = ekf.nx;          % 40

    % Number of logged rows (decimated)
    if nargin >= 4 && isfield(cfg, 'log_every') && cfg.log_every > 1
        N_log = floor(N / cfg.log_every);
    else
        N_log = N;   % backward-compatible: log every step
    end

    %% Physical state
    logs.logP        = zeros(nN, N_log);
    logs.logQ        = zeros(nE, N_log);
    logs.logTemp     = zeros(nN, N_log);
    logs.logRho      = zeros(nN, N_log);
    logs.logLinePack = zeros(nE, N_log);

    %% Compressor 1
    logs.logPow1       = zeros(1, N_log);
    logs.logHead1      = zeros(1, N_log);
    logs.logEff1       = zeros(1, N_log);
    logs.logCompRatio1 = zeros(1, N_log);

    %% Compressor 2
    logs.logPow2       = zeros(1, N_log);
    logs.logHead2      = zeros(1, N_log);
    logs.logEff2       = zeros(1, N_log);
    logs.logCompRatio2 = zeros(1, N_log);

    %% PRS and valve states
    logs.logPRS1Throttle = zeros(1, N_log);
    logs.logPRS2Throttle = zeros(1, N_log);
    logs.logValveStates  = zeros(numel(params.valveEdges), N_log);

    %% Storage
    logs.logStoInventory = zeros(1, N_log);
    logs.logStoFlow      = zeros(1, N_log);

    %% Source / demand
    logs.logSrcP1  = zeros(1, N_log);
    logs.logSrcP2  = zeros(1, N_log);
    logs.logDemand = zeros(1, N_log);

    %% Roughness
    logs.logRough = zeros(nE, N_log);

    %% EKF
    logs.logEst  = zeros(nX, N_log);
    logs.logResP = zeros(nN, N_log);
    logs.logResQ = zeros(nE, N_log);

    %% PLC sensor bus
    logs.logPlcP = zeros(nN, N_log);
    logs.logPlcQ = zeros(nE, N_log);

    %% Actuator commands
    logs.logActComp1  = zeros(1, N_log);
    logs.logActComp2  = zeros(1, N_log);
    logs.logActValve  = zeros(numel(params.valveEdges), N_log);

    %% Spoofed sensors (A5/A6 forensics)
    logs.logSpoofP = zeros(nN, N_log);
    logs.logSpoofQ = zeros(nE, N_log);

    %% Attack labels
    logs.logAttackId   = zeros(1, N_log, 'int32');
    logs.logAttackName = repmat("Normal", 1, N_log);
    logs.logMitreId    = repmat("None",   1, N_log);

    %% Store N_log for convenience (used in exportDataset)
    logs.N_log    = N_log;
    logs.log_every = max(1, floor(N / N_log));   % recover decimation factor
end