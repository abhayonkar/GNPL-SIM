function [state, prs] = updatePRS(state, prs, cfg)
% updatePRS  Update pressure regulating station — clamp downstream pressure.
%
%   [state, prs] = updatePRS(state, prs, cfg)
%
%   PRS behaviour:
%     If p_upstream > setpoint + deadband:
%       Throttle valve to reduce p_downstream toward setpoint
%       Throttle moves with time constant tau (first-order response)
%     If p_upstream <= setpoint:
%       PRS fully open (passes through pressure)
%
%   The PRS introduces a pressure discontinuity at the node: upstream
%   sees high pressure, downstream sees regulated pressure. This is the
%   characteristic signature of a real PRS in SCADA data.

    if ~prs.online
        return;
    end

    n = prs.node;
    p_up = state.p(n);   % pressure at PRS node (upstream side)

    %% Target throttle based on error from setpoint
    error = p_up - prs.setpoint;
    if error > prs.deadband
        % Need to throttle - how much depends on excess pressure
        throttle_target = max(0.1, prs.setpoint / p_up);
    else
        throttle_target = 1.0;   % fully open
    end

    %% First-order throttle response (avoids instantaneous jumps)
    alpha = cfg.dt / prs.tau;
    alpha = min(1, max(0, alpha));
    prs.throttle = prs.throttle + alpha * (throttle_target - prs.throttle);
    prs.throttle = max(0.05, min(prs.throttle, 1.0));

    %% Apply throttle: reduce pressure at PRS node to regulated value
    p_regulated = min(p_up, prs.setpoint + prs.deadband);
    p_regulated = max(p_regulated, p_up * prs.throttle);
    state.p(n) = p_regulated;
    state.p(n) = max(0.1, min(state.p(n), 70));
end