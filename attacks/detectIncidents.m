function detectIncidents(cfg, params, state, ekf, comp, plc, k, dt)
% detectIncidents  Evaluate all alarm conditions and emit logEvent entries.
%
%   detectIncidents(cfg, params, state, ekf, comp, plc, k, dt)
%
%   This function is stateless: alarm de-bounce / edge-detection is handled
%   via persistent variables that are keyed by the calling simulation
%   (they reset when MATLAB is restarted or the persistent is cleared).
%
%   Alarms
%   ------
%   1. High nodal pressure  (> cfg.alarm_P_high)
%   2. Low nodal pressure   (< cfg.alarm_P_low)
%   3. EKF residual divergence  (|residP| > cfg.alarm_ekf_resid)
%   4. Compressor ratio near ceiling  (>= cfg.alarm_comp_hi)
%   5. Valve state transition  (act_valve_cmd changed vs previous step)

    persistent highPressureActive ekfDivActive compHiActive prevValveCmd;

    if isempty(highPressureActive), highPressureActive = false; end
    if isempty(ekfDivActive),       ekfDivActive       = false; end
    if isempty(compHiActive),       compHiActive       = false; end
    if isempty(prevValveCmd),       prevValveCmd       = plc.act_valve_cmd; end

    %% 1 & 2. Pressure limits -------------------------------------------------
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

    %% 3. EKF residual divergence ---------------------------------------------
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

    %% 4. Compressor near ceiling ---------------------------------------------
    if comp.ratio >= cfg.alarm_comp_hi
        if ~compHiActive
            compHiActive = true;
            logEvent('WARNING', 'detectIncidents', ...
                     sprintf('Compressor ratio near ceiling: %.4f (limit %.2f)', ...
                             comp.ratio, comp.ratio_max), k, dt);
        end
    else
        compHiActive = false;
    end

    %% 5. Valve state transition -----------------------------------------------
    if plc.act_valve_cmd ~= prevValveCmd
        if plc.act_valve_cmd == 0
            logEvent('WARNING', 'detectIncidents', ...
                     'Valve CLOSED (act_valve_cmd = 0)', k, dt);
        else
            logEvent('INFO', 'detectIncidents', ...
                     'Valve OPENED (act_valve_cmd = 1)', k, dt);
        end
        prevValveCmd = plc.act_valve_cmd;
    end
end
