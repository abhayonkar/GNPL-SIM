function [comp1, comp2, prs1, prs2, valve_states, plc] = ...
        updateControlLogic(comp1, comp2, prs1, prs2, valve_states, ...
                           plc, xhatP, cfg, k, dt)
% updateControlLogic  Dual PID pressure control + PRS + safety interlocks.
%
%   [comp1, comp2, prs1, prs2, valve_states, plc] =
%       updateControlLogic(comp1, comp2, prs1, prs2, valve_states,
%                          plc, xhatP, cfg, k, dt)
%
%   CS1 PID : maintains pressure at D1 (node cfg.pid_D1_node) at pid1_setpoint
%   CS2 PID : maintains pressure at D3 (node cfg.pid_D3_node) at pid2_setpoint
%   PRS1/2  : throttle updated based on downstream pressure deviation
%   Valve   : valve_states(1) = E8 opened/closed by J6 (node 9) pressure
%   Emergency shutdown: if D1 pressure > cfg.emer_shutdown_p
%
%   cfg fields used:
%     pid1_Kp/Ki/Kd, pid1_setpoint, pid_D1_node   (CS1)
%     pid2_Kp/Ki/Kd, pid2_setpoint, pid_D3_node   (CS2)
%     valve_open_lo, valve_close_hi, emer_shutdown_p

    if nargin < 9,  k  = 0;   end
    if nargin < 10, dt = 0.1; end

    persistent int_err1 int_err2 prev_err1 prev_err2
    if isempty(int_err1),  int_err1  = 0; end
    if isempty(int_err2),  int_err2  = 0; end
    if isempty(prev_err1), prev_err1 = 0; end
    if isempty(prev_err2), prev_err2 = 0; end

    %% ── CS1 PID — D1 pressure at pid1_setpoint ───────────────────────────
    err1      = cfg.pid1_setpoint - xhatP(cfg.pid_D1_node);
    int_err1  = int_err1 + err1 * dt;
    deriv1    = (err1 - prev_err1) / dt;
    prev_err1 = err1;

    raw1 = comp1.ratio ...
         + cfg.pid1_Kp * err1 ...
         + cfg.pid1_Ki * int_err1 ...
         + cfg.pid1_Kd * deriv1;

    if raw1 < comp1.ratio_min
        comp1.ratio = comp1.ratio_min;
        logEvent('WARNING', 'updateControlLogic', ...
                 sprintf('CS1 ratio clamped to min %.2f', comp1.ratio_min), k, dt);
    elseif raw1 > comp1.ratio_max
        comp1.ratio = comp1.ratio_max;
        logEvent('WARNING', 'updateControlLogic', ...
                 sprintf('CS1 ratio clamped to max %.2f', comp1.ratio_max), k, dt);
    else
        comp1.ratio = raw1;
    end

    %% ── CS2 PID — D3 pressure at pid2_setpoint ───────────────────────────
    if isfield(cfg, 'pid2_Kp')
        err2      = cfg.pid2_setpoint - xhatP(cfg.pid_D3_node);
        int_err2  = int_err2 + err2 * dt;
        deriv2    = (err2 - prev_err2) / dt;
        prev_err2 = err2;

        raw2 = comp2.ratio ...
             + cfg.pid2_Kp * err2 ...
             + cfg.pid2_Ki * int_err2 ...
             + cfg.pid2_Kd * deriv2;

        comp2.ratio = max(comp2.ratio_min, min(comp2.ratio_max, raw2));
    end

    %% ── PRS1 throttle ────────────────────────────────────────────────────
    if prs1.online && length(xhatP) >= prs1.node
        p_down1       = xhatP(prs1.node);
        err_prs1      = prs1.setpoint - p_down1;
        delta1        = (dt / prs1.tau) * err_prs1 / max(1, prs1.setpoint);
        prs1.throttle = max(0, min(1, prs1.throttle + delta1));
    end

    %% ── PRS2 throttle ────────────────────────────────────────────────────
    if prs2.online && length(xhatP) >= prs2.node
        p_down2       = xhatP(prs2.node);
        err_prs2      = prs2.setpoint - p_down2;
        delta2        = (dt / prs2.tau) * err_prs2 / max(1, prs2.setpoint);
        prs2.throttle = max(0, min(1, prs2.throttle + delta2));
    end

    %% ── Valve E8 + emergency shutdown ────────────────────────────────────
    if xhatP(cfg.pid_D1_node) > cfg.emer_shutdown_p
        valve_states(:) = 0;   % close all valves on emergency shutdown
        logEvent('CRITICAL', 'updateControlLogic', ...
                 sprintf('EMERGENCY SHUTDOWN — D1 = %.2f bar > %.1f bar MAOP', ...
                         xhatP(cfg.pid_D1_node), cfg.emer_shutdown_p), k, dt);
    else
        % Valve E8 (valve_states index 1) controlled by node 9 (J6) pressure
        if length(xhatP) >= 9
            p_J6 = xhatP(9);
            if p_J6 < cfg.valve_open_lo
                valve_states(1) = 1;
            elseif p_J6 > cfg.valve_close_hi
                valve_states(1) = 0;
            end
            % E14 (storage inject) and E15 (storage withdraw) are left to
            % storage logic; pass through unchanged.
        end
    end

    %% ── Advance PLC latency buffers ──────────────────────────────────────
    %   Buffer names match runSimulation's advanceLatencyBuffers helper.
    plc.compRatio1Buf  = [plc.compRatio1Buf(2:end),  comp1.ratio];
    plc.compRatio2Buf  = [plc.compRatio2Buf(2:end),  comp2.ratio];
    plc.valveCmdBuf    = [plc.valveCmdBuf(:,2:end),  valve_states];

    plc.act_comp1_ratio = plc.compRatio1Buf(1);
    plc.act_comp2_ratio = plc.compRatio2Buf(1);
    plc.act_valve_cmds  = plc.valveCmdBuf(:, 1);
end