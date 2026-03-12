function plc = initPLC(cfg, state, comp)
% initPLC  Build the PLC / SCADA telemetry layer struct.
%
%   plc = initPLC(cfg, state, comp)
%
%   The PLC models:
%     - Discrete sensor polling at cfg.plc_period steps
%     - Actuator command latency of cfg.plc_latency steps
%       (commands pass through a shift-register buffer before taking effect)

    plc.period  = cfg.plc_period;
    plc.latency = cfg.plc_latency;

    % Sensor register mirrors (last polled values)
    plc.reg_p = state.p;
    plc.reg_q = state.q;

    % Actuator outputs (after latency buffer)
    plc.act_comp_ratio = comp.ratio;
    plc.act_valve_cmd  = cfg.valve_open_default;

    % Latency shift-register buffers
    %   Buffer length = latency + 1 so index 1 is the "oldest" command
    %   and is applied this step, while index end is the freshest command.
    plc.compRatioBuf = repmat(comp.ratio,              1, plc.latency + 1);
    plc.valveCmdBuf  = repmat(cfg.valve_open_default,  1, plc.latency + 1);
end
