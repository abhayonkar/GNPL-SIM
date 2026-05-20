function p = applyNormalPressureEnvelope(p, cfg)
% applyNormalPressureEnvelope  Keep clean baseline pressures inside limits.
%
% This is only used when no attack is active. Attack windows bypass this
% envelope so pressure excursions remain available to incident detection.

    p_hi = cfg.alarm_P_high;
    p_lo = cfg.alarm_P_low;

    if isfield(cfg, 'normal_pressure_high_margin')
        p_hi = p_hi - cfg.normal_pressure_high_margin;
    end
    if isfield(cfg, 'normal_pressure_low_margin')
        p_lo = p_lo + cfg.normal_pressure_low_margin;
    end

    p = min(max(p, p_lo), p_hi);
end
