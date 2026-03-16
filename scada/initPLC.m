function plc = initPLC(cfg, state, comp1)
% initPLC  Build the PLC / SCADA telemetry layer struct.
%
%   plc = initPLC(cfg, state, comp1)
%
%   The PLC models:
%     - Discrete sensor polling at cfg.plc_period_z1 steps
%     - Actuator command latency of cfg.plc_latency steps
%       (commands pass through shift-register buffers before taking effect)
%
%   Buffer field names must match runSimulation's advanceLatencyBuffers
%   and updateControlLogic exactly:
%     plc.compRatio1Buf   – CS1 ratio latency buffer  (1 × latency+1)
%     plc.compRatio2Buf   – CS2 ratio latency buffer  (1 × latency+1)
%     plc.valveCmdBuf     – valve command buffer       (3 × latency+1)
%     plc.act_comp1_ratio – effective CS1 ratio after latency
%     plc.act_comp2_ratio – effective CS2 ratio after latency
%     plc.act_valve_cmds  – effective valve positions  (3×1)

    plc.period  = cfg.plc_period_z1;
    plc.latency = cfg.plc_latency;

    % Sensor register mirrors (last polled values)
    plc.reg_p = state.p;
    plc.reg_q = state.q;

    % Buffer length: latency+1 so index 1 is the oldest (applied) command
    L = cfg.plc_latency + 1;

    % --- CS1 ---
    plc.compRatio1Buf   = repmat(comp1.ratio,           1, L);
    plc.act_comp1_ratio = comp1.ratio;

    % --- CS2: use cfg.comp2_ratio if available, else same as CS1 ---
    if isfield(cfg, 'comp2_ratio')
        r2 = cfg.comp2_ratio;
    else
        r2 = comp1.ratio;
    end
    plc.compRatio2Buf   = repmat(r2, 1, L);
    plc.act_comp2_ratio = r2;

    % --- Valves: 3 valves [E8, E14, E15], all open by default ---
    v0 = cfg.valve_open_default;          % scalar default (e.g. 1)
    plc.valveCmdBuf    = repmat(v0 * ones(3,1), 1, L);   % 3×L
    plc.act_valve_cmds = v0 * ones(3, 1);                 % 3×1
end