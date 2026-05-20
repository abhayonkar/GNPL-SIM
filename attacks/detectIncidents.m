function detectIncidents(cfg, params, state, ekf, comp1, comp2, plc, k, dt, aid, fault_label)
% detectIncidents  Evaluate alarm conditions and emit logEvent entries.
%
% Alarm warm-up uses cfg.atk_warmup_s when present. This prevents normal
% startup transients and EKF settling from being reported as incidents in
% clean baseline runs.

    persistent highPressureActive lowPressureActive ekfDivActive comp1HiActive comp2HiActive prevValveCmds

    if isempty(highPressureActive) || numel(highPressureActive) ~= params.nNodes
        highPressureActive = false(params.nNodes, 1);
    end
    if isempty(lowPressureActive) || numel(lowPressureActive) ~= params.nNodes
        lowPressureActive = false(params.nNodes, 1);
    end
    if isempty(ekfDivActive),        ekfDivActive        = false; end
    if isempty(comp1HiActive),       comp1HiActive       = false; end
    if isempty(comp2HiActive),       comp2HiActive       = false; end
    if isempty(prevValveCmds),       prevValveCmds       = plc.act_valve_cmds; end

    if nargin < 10, aid = 1; end
    if nargin < 11, fault_label = 0; end
    abnormal_active = aid > 0 || fault_label > 0;

    alarm_start_step = 0;
    if isfield(cfg, 'atk_warmup_s')
        alarm_start_step = round(cfg.atk_warmup_s / dt);
    end
    in_alarm_warmup = k < alarm_start_step;

    for n = 1:params.nNodes
        if ~in_alarm_warmup && state.p(n) > cfg.alarm_P_high
            if ~highPressureActive(n)
                highPressureActive(n) = true;
                logEvent('WARNING', 'detectIncidents', ...
                         sprintf('High pressure at node %s: %.3f bar (limit %.1f bar)', ...
                                 params.nodeNames(n), state.p(n), cfg.alarm_P_high), k, dt);
            end
        else
            highPressureActive(n) = false;
        end

        if ~in_alarm_warmup && state.p(n) < cfg.alarm_P_low
            if ~lowPressureActive(n)
                lowPressureActive(n) = true;
                logEvent('WARNING', 'detectIncidents', ...
                         sprintf('Low pressure at node %s: %.3f bar (limit %.1f bar)', ...
                                 params.nodeNames(n), state.p(n), cfg.alarm_P_low), k, dt);
            end
        else
            lowPressureActive(n) = false;
        end
    end

    residP_alarm = abs(ekf.residP);
    if isfield(cfg, 'nodeTypes')
        prs_nodes = strcmp(cfg.nodeTypes(:), 'prs');
        residP_alarm(prs_nodes) = 0;
    end

    if abnormal_active && ~in_alarm_warmup && any(residP_alarm > cfg.alarm_ekf_resid)
        if ~ekfDivActive
            ekfDivActive = true;
            [maxR, idx] = max(residP_alarm);
            logEvent('WARNING', 'detectIncidents', ...
                     sprintf('EKF residual divergence at node %s: %.4f bar (threshold %.2f bar)', ...
                             params.nodeNames(idx), maxR, cfg.alarm_ekf_resid), k, dt);
        end
    else
        ekfDivActive = false;
    end

    if abnormal_active && ~in_alarm_warmup && comp1.ratio >= cfg.alarm_comp_hi
        if ~comp1HiActive
            comp1HiActive = true;
            logEvent('WARNING', 'detectIncidents', ...
                     sprintf('CS1 ratio near ceiling: %.4f (max %.2f)', ...
                             comp1.ratio, comp1.ratio_max), k, dt);
        end
    else
        comp1HiActive = false;
    end

    if abnormal_active && ~in_alarm_warmup && comp2.ratio >= cfg.alarm_comp_hi
        if ~comp2HiActive
            comp2HiActive = true;
            logEvent('WARNING', 'detectIncidents', ...
                     sprintf('CS2 ratio near ceiling: %.4f (max %.2f)', ...
                             comp2.ratio, comp2.ratio_max), k, dt);
        end
    else
        comp2HiActive = false;
    end

    valveNames = ["E8", "E14", "E15"];
    for v = 1:numel(plc.act_valve_cmds)
        if abnormal_active && ~in_alarm_warmup && plc.act_valve_cmds(v) ~= prevValveCmds(v)
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
