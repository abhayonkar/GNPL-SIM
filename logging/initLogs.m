function logs = initLogs(params, ekf, N, cfg)
% initLogs  Preallocate all log arrays.
%
%  Phase 6 additions:
%    logFaultId      — fault label per row (0=none, 1=loss, 2=stuck)
%    logCUSUM_upper  — CUSUM upper arm statistic
%    logCUSUM_lower  — CUSUM lower arm statistic
%    logCUSUM_alarm  — CUSUM alarm flag
%    logChi2         — EKF chi-squared bad-data statistic
%    logChi2_alarm   — chi-squared alarm flag

    nN = params.nNodes;
    nE = params.nEdges;
    nX = ekf.nx;

    N_log = floor(N / max(1, cfg.log_every));

    %% Physical state
    logs.logP        = zeros(nN, N_log);
    logs.logQ        = zeros(nE, N_log);
    logs.logTemp     = zeros(nN, N_log);
    logs.logRho      = zeros(nN, N_log);
    logs.logLinePack = zeros(nE, N_log);

    %% Compressors
    logs.logPow1       = zeros(1, N_log);
    logs.logHead1      = zeros(1, N_log);
    logs.logEff1       = zeros(1, N_log);
    logs.logCompRatio1 = zeros(1, N_log);
    logs.logPow2       = zeros(1, N_log);
    logs.logHead2      = zeros(1, N_log);
    logs.logEff2       = zeros(1, N_log);
    logs.logCompRatio2 = zeros(1, N_log);

    %% Control and equipment
    logs.logPRS1Throttle = zeros(1, N_log);
    logs.logPRS2Throttle = zeros(1, N_log);
    logs.logValveStates  = zeros(numel(params.valveEdges), N_log);
    logs.logStoInventory = zeros(1, N_log);
    logs.logStoFlow      = zeros(1, N_log);
    logs.logSrcP1        = zeros(1, N_log);
    logs.logSrcP2        = zeros(1, N_log);
    logs.logDemand       = zeros(1, N_log);
    logs.logRough        = zeros(nE, N_log);

    %% EKF + PLC bus
    logs.logEst  = zeros(nX, N_log);
    logs.logResP = zeros(nN, N_log);
    logs.logResQ = zeros(nE, N_log);
    logs.logPlcP = zeros(nN, N_log);
    logs.logPlcQ = zeros(nE, N_log);

    %% Actuator + spoof forensics
    logs.logActComp1 = zeros(1, N_log);
    logs.logActComp2 = zeros(1, N_log);
    logs.logActValve = zeros(numel(params.valveEdges), N_log);
    logs.logSpoofP   = zeros(nN, N_log);
    logs.logSpoofQ   = zeros(nE, N_log);

    %% Attack labels
    logs.logAttackId   = zeros(1, N_log, 'int32');
    logs.logAttackName = repmat("Normal", 1, N_log);
    logs.logMitreId    = repmat("None",   1, N_log);

    %% Phase 5: jitter
    logs.logJitter_ms = zeros(1, N_log);

    %% Phase 6: fault, CUSUM, chi-squared
    logs.logFaultId      = zeros(1, N_log, 'int32');
    logs.logCUSUM_upper  = zeros(1, N_log);
    logs.logCUSUM_lower  = zeros(1, N_log);
    logs.logCUSUM_alarm  = false(1, N_log);
    logs.logChi2         = zeros(1, N_log);
    logs.logChi2_alarm   = false(1, N_log);

    %% Metadata
    logs.N_log     = N_log;
    logs.log_every = max(1, cfg.log_every);
end