function [comp1, comp2, prs1, prs2, valve_states, plc] = ...
        updateControlLogic(comp1, comp2, prs1, prs2, valve_states, ...
                           plc, xhatP, cfg, k, dt)
% updateControlLogic  Dual PID pressure control + PRS + safety interlocks.
%
%   CLAMP WARNING SUPPRESSION:
%     Compressor ratio clamping is expected during PID wind-up and under
%     some attack scenarios. Logging it every single step generates tens
%     of thousands of identical warnings and was the primary cause of
%     simulation slowdown. The clamp event is now logged only on the
%     TRANSITION into the clamped state (edge detect), not continuously.

    if nargin < 9,  k  = 0;   end
    if nargin < 10, dt = 0.1; end

    persistent int_err1 int_err2 prev_err1 prev_err2
    persistent cs1_was_clamped_min cs1_was_clamped_max
    persistent cs2_was_clamped_min cs2_was_clamped_max

    if isempty(int_err1),            int_err1            = 0;     end
    if isempty(int_err2),            int_err2            = 0;     end
    if isempty(prev_err1),           prev_err1           = 0;     end
    if isempty(prev_err2),           prev_err2           = 0;     end
    if isempty(cs1_was_clamped_min), cs1_was_clamped_min = false; end
    if isempty(cs1_was_clamped_max), cs1_was_clamped_max = false; end
    if isempty(cs2_was_clamped_min), cs2_was_clamped_min = false; end
    if isempty(cs2_was_clamped_max), cs2_was_clamped_max = false; end

    %% ── CS1 PID ──────────────────────────────────────────────────────────
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
        if ~cs1_was_clamped_min   % log only on entry into clamped state
            logEvent('WARNING', 'updateControlLogic', ...
                     sprintf('CS1 ratio clamped to min %.2f (PID wind-up / low demand)', ...
                             comp1.ratio_min), k, dt);
            cs1_was_clamped_min = true;
        end
        cs1_was_clamped_max = false;
    elseif raw1 > comp1.ratio_max
        comp1.ratio = comp1.ratio_max;
        if ~cs1_was_clamped_max
            logEvent('WARNING', 'updateControlLogic', ...
                     sprintf('CS1 ratio clamped to max %.2f', comp1.ratio_max), k, dt);
            cs1_was_clamped_max = true;
        end
        cs1_was_clamped_min = false;
    else
        comp1.ratio = raw1;
        cs1_was_clamped_min = false;   % clear flags when in normal range
        cs1_was_clamped_max = false;
    end

    %% ── CS2 PID ──────────────────────────────────────────────────────────
    if isfield(cfg, 'pid2_Kp')
        err2      = cfg.pid2_setpoint - xhatP(cfg.pid_D3_node);
        int_err2  = int_err2 + err2 * dt;
        deriv2    = (err2 - prev_err2) / dt;
        prev_err2 = err2;

        raw2 = comp2.ratio ...
             + cfg.pid2_Kp * err2 ...
             + cfg.pid2_Ki * int_err2 ...
             + cfg.pid2_Kd * deriv2;

        if raw2 < comp2.ratio_min
            comp2.ratio = comp2.ratio_min;
            if ~cs2_was_clamped_min
                logEvent('WARNING', 'updateControlLogic', ...
                         sprintf('CS2 ratio clamped to min %.2f', comp2.ratio_min), k, dt);
                cs2_was_clamped_min = true;
            end
            cs2_was_clamped_max = false;
        elseif raw2 > comp2.ratio_max
            comp2.ratio = comp2.ratio_max;
            if ~cs2_was_clamped_max
                logEvent('WARNING', 'updateControlLogic', ...
                         sprintf('CS2 ratio clamped to max %.2f', comp2.ratio_max), k, dt);
                cs2_was_clamped_max = true;
            end
            cs2_was_clamped_min = false;
        else
            comp2.ratio = max(comp2.ratio_min, min(comp2.ratio_max, raw2));
            cs2_was_clamped_min = false;
            cs2_was_clamped_max = false;
        end
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
        valve_states(:) = 0;
        logEvent('CRITICAL', 'updateControlLogic', ...
                 sprintf('EMERGENCY SHUTDOWN — D1 = %.2f bar > %.1f bar MAOP', ...
                         xhatP(cfg.pid_D1_node), cfg.emer_shutdown_p), k, dt);
    else
        if length(xhatP) >= 9
            p_J6 = xhatP(9);
            if p_J6 < cfg.valve_open_lo
                valve_states(1) = 1;
            elseif p_J6 > cfg.valve_close_hi
                valve_states(1) = 0;
            end
        end
    end

    %% ── Advance PLC latency buffers ──────────────────────────────────────
    plc.compRatio1Buf  = [plc.compRatio1Buf(2:end),  comp1.ratio];
    plc.compRatio2Buf  = [plc.compRatio2Buf(2:end),  comp2.ratio];
    plc.valveCmdBuf    = [plc.valveCmdBuf(:,2:end),  valve_states];

    plc.act_comp1_ratio = plc.compRatio1Buf(1);
    plc.act_comp2_ratio = plc.compRatio2Buf(1);
    plc.act_valve_cmds  = plc.valveCmdBuf(:, 1);
end