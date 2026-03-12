function logs = updateLogs(logs, state, ekf, plc, comp1, comp2, prs1, prs2, ...
                            valve_states, params, k, sensor_p, sensor_q, ...
                            src_p1, src_p2, demand, q_sto)
% updateLogs  Append full system state to pre-allocated log arrays.

    %% Physical state
    logs.logP(:,k)        = state.p;
    logs.logQ(:,k)        = state.q;
    logs.logTemp(:,k)     = state.Tgas;
    logs.logRho(:,k)      = state.rho;
    logs.logLinePack(:,k) = state.linepack;

    %% Compressor 1
    logs.logPow1(k)       = state.W1;
    logs.logHead1(k)      = state.H1;
    logs.logEff1(k)       = state.eta1;
    logs.logCompRatio1(k) = comp1.ratio;

    %% Compressor 2
    logs.logPow2(k)       = state.W2;
    logs.logHead2(k)      = state.H2;
    logs.logEff2(k)       = state.eta2;
    logs.logCompRatio2(k) = comp2.ratio;

    %% PRS
    logs.logPRS1Throttle(k) = prs1.throttle;
    logs.logPRS2Throttle(k) = prs2.throttle;
    logs.logValveStates(:,k) = valve_states(:);

    %% Storage
    logs.logStoInventory(k) = state.sto_inventory;
    logs.logStoFlow(k)      = q_sto;

    %% Source / demand
    logs.logSrcP1(k)  = src_p1;
    logs.logSrcP2(k)  = src_p2;
    logs.logDemand(k) = demand;

    %% Roughness
    logs.logRough(:,k) = params.rough;

    %% EKF
    logs.logEst(:,k)  = ekf.xhat;
    logs.logResP(:,k) = ekf.xhat(1:params.nNodes) - state.p;
    logs.logResQ(:,k) = ekf.xhat(params.nNodes+1:end) - state.q;

    %% PLC sensor bus
    logs.logPlcP(:,k) = plc.reg_p;
    logs.logPlcQ(:,k) = plc.reg_q;

    %% Actuator commands
    logs.logActComp1(k)  = plc.act_comp1_ratio;
    logs.logActComp2(k)  = plc.act_comp2_ratio;
    logs.logActValve(:,k) = plc.act_valve_cmds(:);

    %% Spoofed sensors
    if nargin >= 13 && ~isempty(sensor_p)
        logs.logSpoofP(:,k) = sensor_p;
    end
    if nargin >= 13 && ~isempty(sensor_q)
        logs.logSpoofQ(:,k) = sensor_q;
    end
end