function [prs1, prs2] = initPRS(cfg)
% initPRS  Initialise two pressure regulating station structs.
%
%   [prs1, prs2] = initPRS(cfg)
%
%   A PRS maintains downstream pressure at a setpoint by throttling
%   a control valve. It is the primary pressure reduction point between
%   high-pressure transmission and medium/low-pressure distribution.

    prs1.node      = cfg.prs1_node;
    prs1.setpoint  = cfg.prs1_setpoint;
    prs1.deadband  = cfg.prs1_deadband;
    prs1.tau       = cfg.prs1_tau;
    prs1.throttle  = 0.8;          % initial throttle position (0-1)
    prs1.online    = true;

    prs2.node      = cfg.prs2_node;
    prs2.setpoint  = cfg.prs2_setpoint;
    prs2.deadband  = cfg.prs2_deadband;
    prs2.tau       = cfg.prs2_tau;
    prs2.throttle  = 0.8;
    prs2.online    = true;
end