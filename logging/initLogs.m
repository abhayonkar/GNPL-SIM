function logs = initLogs(params, ekf, N, cfg)
% initLogs  Preallocate all log arrays for the decimated dataset.
%
%   N_log = floor(N / cfg.log_every) rows allocated.
%   For 100 min at 10 Hz physics, log_every=10 → N_log = 6000 rows.
%
%   PHASE 5: adds logJitter_ms for scan-cycle timing artefacts.

    nN = params.nNodes;
    nE = params.nEdges;
    nX = ekf.nx;

    N_log = floor(N / max(1, cfg.log_every));

    logs.logP        = zeros(nN, N_log);
    logs.logQ        = zeros(nE, N_log);
    logs.logTemp     = zeros(nN, N_log);
    logs.logRho      = zeros(nN, N_log);
    logs.logLinePack = zeros(nE, N_log);

    logs.logPow1       = zeros(1, N_log);
    logs.logHead1      = zeros(1, N_log);
    logs.logEff1       = zeros(1, N_log);
    logs.logCompRatio1 = zeros(1, N_log);
    logs.logPow2       = zeros(1, N_log);
    logs.logHead2      = zeros(1, N_log);
    logs.logEff2       = zeros(1, N_log);
    logs.logCompRatio2 = zeros(1, N_log);

    logs.logPRS1Throttle = zeros(1, N_log);
    logs.logPRS2Throttle = zeros(1, N_log);
    logs.logValveStates  = zeros(numel(params.valveEdges), N_log);
    logs.logStoInventory = zeros(1, N_log);
    logs.logStoFlow      = zeros(1, N_log);
    logs.logSrcP1        = zeros(1, N_log);
    logs.logSrcP2        = zeros(1, N_log);
    logs.logDemand       = zeros(1, N_log);
    logs.logRough        = zeros(nE, N_log);

    logs.logEst  = zeros(nX, N_log);
    logs.logResP = zeros(nN, N_log);
    logs.logResQ = zeros(nE, N_log);
    logs.logPlcP = zeros(nN, N_log);
    logs.logPlcQ = zeros(nE, N_log);

    logs.logActComp1 = zeros(1, N_log);
    logs.logActComp2 = zeros(1, N_log);
    logs.logActValve = zeros(numel(params.valveEdges), N_log);
    logs.logSpoofP   = zeros(nN, N_log);
    logs.logSpoofQ   = zeros(nE, N_log);

    logs.logAttackId   = zeros(1, N_log, 'int32');
    logs.logAttackName = repmat("Normal", 1, N_log);
    logs.logMitreId    = repmat("None",   1, N_log);

    %% Phase 5 — jitter offset per logged row (milliseconds)
    %  Actual timestamp = (log_k - 1) * log_dt + logJitter_ms/1000
    logs.logJitter_ms = zeros(1, N_log);

    logs.N_log     = N_log;
    logs.log_every = max(1, cfg.log_every);
end