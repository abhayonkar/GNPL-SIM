function logs = initLogs(params, ekf, N)
% initLogs  Preallocate all log arrays for N simulation steps.
%
%   Additions over 8-node version:
%     - Dual compressor (comp1, comp2)
%     - PRS throttle positions
%     - Storage inventory
%     - Line pack per segment
%     - Second source pressure

    nN = params.nNodes;   % 20
    nE = params.nEdges;   % 20
    nX = ekf.nx;          % 40 (20 pressures + 20 flows)

    %% Physical state
    logs.logP       = zeros(nN, N);
    logs.logQ       = zeros(nE, N);
    logs.logTemp    = zeros(nN, N);
    logs.logRho     = zeros(nN, N);
    logs.logLinePack = zeros(nE, N);   % NEW: line pack per segment

    %% Compressor 1 (CS1)
    logs.logPow1      = zeros(1, N);
    logs.logHead1     = zeros(1, N);
    logs.logEff1      = zeros(1, N);
    logs.logCompRatio1 = zeros(1, N);

    %% Compressor 2 (CS2)
    logs.logPow2      = zeros(1, N);
    logs.logHead2     = zeros(1, N);
    logs.logEff2      = zeros(1, N);
    logs.logCompRatio2 = zeros(1, N);

    %% PRS and valve states
    logs.logPRS1Throttle = zeros(1, N);
    logs.logPRS2Throttle = zeros(1, N);
    logs.logValveStates  = zeros(numel(params.valveEdges), N);

    %% Storage
    logs.logStoInventory = zeros(1, N);
    logs.logStoFlow      = zeros(1, N);

    %% Source pressures
    logs.logSrcP1 = zeros(1, N);   % S1
    logs.logSrcP2 = zeros(1, N);   % S2
    logs.logDemand = zeros(1, N);

    %% Roughness
    logs.logRough = zeros(nE, N);

    %% EKF
    logs.logEst  = zeros(nX, N);
    logs.logResP = zeros(nN, N);
    logs.logResQ = zeros(nE, N);

    %% PLC sensor bus
    logs.logPlcP = zeros(nN, N);
    logs.logPlcQ = zeros(nE, N);

    %% Actuator commands
    logs.logActComp1  = zeros(1, N);
    logs.logActComp2  = zeros(1, N);
    logs.logActValve  = zeros(numel(params.valveEdges), N);

    %% Spoofed sensors (A5/A6 forensics)
    logs.logSpoofP = zeros(nN, N);
    logs.logSpoofQ = zeros(nE, N);

    %% Attack labels
    logs.logAttackId   = zeros(1, N, 'int32');
    logs.logAttackName = repmat("Normal", 1, N);
    logs.logMitreId    = repmat("None",   1, N);
end