function [comp, valve, plc] = updateControlLogic(comp, valve, plc, xhatP, cfg, k, dt)
% updateControlLogic  PID pressure control + safety interlocks.
%
%   [comp, valve, plc] = updateControlLogic(comp, valve, plc, xhatP, cfg, k, dt)
%
%   All gains, setpoints, and thresholds are read from cfg (simConfig) so
%   tuning only requires editing one file.
%
%   PID controls the compression ratio to maintain pressure at node D1.
%   Valve logic maintains pressure in the J3 branch.
%   Emergency shutdown triggers if D1 pressure exceeds cfg.emer_shutdown_p.

    if nargin < 6, k  = 0;   end
    if nargin < 7, dt = 0.1; end

    persistent integral_error;
    if isempty(integral_error), integral_error = 0; end

    %% PID compressor control ------------------------------------------------
    error            = cfg.pid_setpoint - xhatP(cfg.pid_D1_node);
    integral_error   = integral_error + error;
    derivative_error = error;   % simplified (no previous error stored)

    raw_ratio = comp.ratio ...
                + cfg.pid_Kp * error ...
                + cfg.pid_Ki * integral_error ...
                + cfg.pid_Kd * derivative_error;

    % Clamp and log limit hits
    if raw_ratio < comp.ratio_min
        comp.ratio = comp.ratio_min;
        logEvent('WARNING', 'updateControlLogic', ...
                 sprintf('Compressor ratio clamped to minimum (%.2f)', comp.ratio_min), k, dt);
    elseif raw_ratio > comp.ratio_max
        comp.ratio = comp.ratio_max;
        logEvent('WARNING', 'updateControlLogic', ...
                 sprintf('Compressor ratio clamped to maximum (%.2f)', comp.ratio_max), k, dt);
    else
        comp.ratio = raw_ratio;
    end

    %% Valve / safety logic ---------------------------------------------------
    if xhatP(cfg.pid_D1_node) > cfg.emer_shutdown_p
        plc.act_valve_cmd = 0;
        logEvent('CRITICAL', 'updateControlLogic', ...
                 sprintf('EMERGENCY SHUTDOWN - Pressure at D1 = %.3f bar exceeds %.1f bar MAOP limit', ...
                         xhatP(cfg.pid_D1_node), cfg.emer_shutdown_p), k, dt);
    else
        if xhatP(cfg.pid_J3_node) < cfg.valve_open_lo
            plc.act_valve_cmd = 1;
        elseif xhatP(cfg.pid_J3_node) > cfg.valve_close_hi
            plc.act_valve_cmd = 0;
        end
    end

    %% Advance PLC latency buffers --------------------------------------------
    plc.compRatioBuf   = [plc.compRatioBuf(2:end),  comp.ratio];
    plc.valveCmdBuf    = [plc.valveCmdBuf(2:end),   plc.act_valve_cmd];
    plc.act_comp_ratio = plc.compRatioBuf(1);
    plc.act_valve_cmd  = plc.valveCmdBuf(1);
end
