function detectIncidents(cfg, params, state, ekf, comp1, comp2, plc, k, dt)
% detectIncidents  Evaluate all alarm conditions and emit logEvent entries.
%
%   detectIncidents(cfg, params, state, ekf, comp1, comp2, plc, k, dt)
%
%   This function is stateless: alarm de-bounce / edge-detection is handled
%   via persistent variables that reset on MATLAB restart or 'clear all'.
%
%   Alarms
%   ------
%   1. High nodal pressure      (> cfg.alarm_P_high)
%   2. Low nodal pressure       (< cfg.alarm_P_low)
%   3. EKF residual divergence  (|residP| > cfg.alarm_ekf_resid)
%   4. CS1 ratio near ceiling   (>= cfg.alarm_comp_hi)
%   5. CS2 ratio near ceiling   (>= cfg.alarm_comp_hi)
%   6. Valve state transition   (any element of act_valve_cmds changed)

    persistent highPressureActive ekfDivActive comp1HiActive comp2HiActive prevValveCmds

    if isempty(highPressureActive),  highPressureActive  = false; end
    if isempty(ekfDivActive),        ekfDivActive        = false; end
    if isempty(comp1HiActive),       comp1HiActive       = false; end
    if isempty(comp2HiActive),       comp2HiActive       = false; end
    if isempty(prevValveCmds),       prevValveCmds       = plc.act_valve_cmds; end

    %% 1 & 2. Pressure limits ─────────────────────────────────────────────
    for n = 1:params.nNodes
        if state.p(n) > cfg.alarm_P_high
            if ~highPressureActive
                highPressureActive = true;
                logEvent('WARNING', 'detectIncidents', ...
                         sprintf('High pressure at node %s: %.3f bar (limit %.1f bar)', ...
                                 params.nodeNames(n), state.p(n), cfg.alarm_P_high), k, dt);
            end
        else
            highPressureActive = false;
        end

        if state.p(n) < cfg.alarm_P_low
            logEvent('WARNING', 'detectIncidents', ...
                     sprintf('Low pressure at node %s: %.3f bar (limit %.1f bar)', ...
                             params.nodeNames(n), state.p(n), cfg.alarm_P_low), k, dt);
        end
    end

    %% 3. EKF residual divergence ──────────────────────────────────────────
    if any(abs(ekf.residP) > cfg.alarm_ekf_resid)
        if ~ekfDivActive
            ekfDivActive = true;
            [maxR, idx] = max(abs(ekf.residP));
            logEvent('WARNING', 'detectIncidents', ...
                     sprintf('EKF residual divergence at node %s: %.4f bar (threshold %.2f bar)', ...
                             params.nodeNames(idx), maxR, cfg.alarm_ekf_resid), k, dt);
        end
    else
        ekfDivActive = false;
    end

    %% 4. CS1 ratio near ceiling ───────────────────────────────────────────
    if comp1.ratio >= cfg.alarm_comp_hi
        if ~comp1HiActive
            comp1HiActive = true;
            logEvent('WARNING', 'detectIncidents', ...
                     sprintf('CS1 ratio near ceiling: %.4f (max %.2f)', ...
                             comp1.ratio, comp1.ratio_max), k, dt);
        end
    else
        comp1HiActive = false;
    end

    %% 5. CS2 ratio near ceiling ───────────────────────────────────────────
    if comp2.ratio >= cfg.alarm_comp_hi
        if ~comp2HiActive
            comp2HiActive = true;
            logEvent('WARNING', 'detectIncidents', ...
                     sprintf('CS2 ratio near ceiling: %.4f (max %.2f)', ...
                             comp2.ratio, comp2.ratio_max), k, dt);
        end
    else
        comp2HiActive = false;
    end

    %% 6. Valve state transitions ──────────────────────────────────────────
    valveNames = ["E8", "E14", "E15"];
    for v = 1:numel(plc.act_valve_cmds)
        if plc.act_valve_cmds(v) ~= prevValveCmds(v)
            if plc.act_valve_cmds(v) == 0
                logEvent('WARNING', 'detectIncidents', ...
                         sprintf('Valve %s CLOSED (cmd=0)', valveNames(v)), k, dt);
            else
                logEvent('INFO', 'detectIncidents', ...
                         sprintf('Valve %s OPENED (cmd=%.2f)', valveNames(v), ...
                                 plc.act_valve_cmds(v)), k, dt);
            end
        end
    end
    prevValveCmds = plc.act_valve_cmds;
end