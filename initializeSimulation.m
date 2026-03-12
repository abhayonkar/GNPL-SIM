function [params, state, comp, valve, ekf, plc, logs] = initializeSimulation(N)
    %% Network
    params.nodeNames = ["S1","J1","J2","J3","J4","J5","D1","D2"];
    params.nNodes = numel(params.nodeNames);
    params.edges = [1 2; 2 3; 3 4; 3 5; 5 6; 4 7; 6 8];
    params.edgeNames = ["E1","E2","E3","E4","ValveLine","E6","E7"];
    params.nEdges = size(params.edges,1);

    %% Incidence Matrix B
    params.B = zeros(params.nNodes, params.nEdges);
    for e = 1:params.nEdges
        params.B(params.edges(e,1), e) = 1;
        params.B(params.edges(e,2), e) = -1;
    end

    %% Physical Parameters
    params.D = 0.8 * ones(params.nEdges,1);
    params.L = 40e3 * ones(params.nEdges,1);
    params.rough = 20e-6 * ones(params.nEdges,1);
    params.V = 6 * ones(params.nNodes,1);
    params.c = 350;
    params.gamma = 1.3;

    %% State Initialization
    state.p = 4.5 * ones(params.nNodes,1);
    state.q = zeros(params.nEdges,1);
    state.Tgas = 288 * ones(params.nNodes,1);
    state.rho = 0.8 * state.p ./ state.Tgas;

    %% Compressor
    comp.node = 2;
    comp.ratio = 1.25;
    comp.a1 = 500; comp.a2 = -0.5; comp.a3 = -0.001;
    comp.b1 = 0.80; comp.b2 = -0.002; comp.b3 = -0.0001;

    %% Valve
    valve.edge = 5;
    valve.open = 1;

    %% EKF
    ekf.nx = params.nNodes + params.nEdges;
    ekf.xhat = [state.p; state.q];
    ekf.P = eye(ekf.nx)*0.01;
    ekf.Qn = eye(ekf.nx)*1e-5;
    ekf.Rk = eye(ekf.nx)*0.01;
    ekf.C = eye(ekf.nx);
    ekf.xhatP = state.p;
    ekf.xhatQ = state.q;

    %% PLC Telemetry Layer
    plc.period = 10;
    plc.latency = 2;
    plc.reg_p = state.p;
    plc.reg_q = state.q;
    plc.act_comp_ratio = comp.ratio;
    plc.act_valve_cmd = 1;
    plc.compRatioBuf = repmat(comp.ratio, 1, plc.latency+1);
    plc.valveCmdBuf = repmat(1,1, plc.latency+1);

    %% Log Structures
    logs.logP = zeros(params.nNodes, N);
    logs.logQ = zeros(params.nEdges, N);
    logs.logTemp = zeros(params.nNodes, N);
    logs.logRho = zeros(params.nNodes, N);
    logs.logEst = zeros(ekf.nx, N);
    logs.logResP = zeros(params.nNodes, N);
    logs.logResQ = zeros(params.nEdges, N);
    logs.logPow = zeros(1, N);
    logs.logHead = zeros(1, N);
    logs.logEff = zeros(1, N);
    logs.logRough = zeros(params.nEdges, N);
    logs.logCompRatio = zeros(1, N);
    logs.logValveCmd = zeros(1, N);
    logs.logPlcP = zeros(params.nNodes, N);
    logs.logPlcQ = zeros(params.nEdges, N);
    logs.logActComp = zeros(1, N);
    logs.logActValve = zeros(1, N);

    %% Dataset export fields  (populated in runSimulation)
    logs.logAttackId   = zeros(1, N);               % integer attack ID per step
    logs.logAttackName = repmat("Normal", 1, N);     % attack name string per step
    logs.logMitreId    = repmat("None",   1, N);     % MITRE ID string per step
    logs.logSrcP       = zeros(1, N);               % actual source pressure after attack
    logs.logDemand     = zeros(1, N);               % demand signal per step
end