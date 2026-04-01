function fault = initFaultState(nN, nE, cfg)
    fault.last_p       = cfg.p0 * ones(nN, 1);
    fault.last_q       = zeros(nE, 1);
    fault.stuck_active = false(nN, 1);
    fault.stuck_rem    = zeros(nN, 1);
    fault.consec_drops = 0;
end