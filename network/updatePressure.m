function [p, p_acoustic] = updatePressure(params, p, q, demand_vec, p_acoustic_prev, cfg)
% updatePressure  Nodal mass-balance pressure update with acoustic noise.
%
%   [p, p_acoustic] = updatePressure(params, p, q, demand_vec, p_acoustic_prev, cfg)
%
%   Physics:
%     dp = (dt * c² / (V * 1e5)) * net_mass_inflow   [bar]
%
%   The coefficient dt*c²/(V*1e5) converts from SI (Pa) to bar and accounts
%   for the timestep. Without dt/1e5 the coefficient is ~20000x too large,
%   causing immediate saturation to the pressure clamp.
%
%   Demand withdrawal:
%     A small explicit sink at demand nodes (models gas consumed by customers).
%     Coefficient tuned so PID can easily compensate:
%     ~0.0001 bar/step = 0.001 bar/s = 0.06 bar/min at 10 Hz.
%
%   Bounds: [0.1, 70] bar (20-node transmission network).

    %% Corrected mass-balance coefficient  [bar / (kg/s)]
    %   c  [m/s], V [m³], dt [s], 1e5 converts Pa → bar
    %   coeff = dt * c² / (V * 1e5)
    %   For c=350, V=6, dt=0.1: coeff = 0.1*122500/(6*1e5) ≈ 0.0204 bar/(kg/s)
    coeff = (cfg.dt * params.c^2) ./ (params.V * 1e5);   % nNodes × 1

    %% Core mass-balance update
    p = p + coeff .* (params.B * q);

    %% Demand withdrawal (small explicit sink at demand nodes)
    %  This models gas consumed by customers. Physically: gas enters the demand
    %  node from pipes but a fraction is "consumed" (drops out of the network).
    %  Rate: cfg.dt * 0.0001 bar/step keeps the PID well within control range.
    if any(demand_vec ~= 0)
        p = p - demand_vec * (cfg.dt * 0.0001);
    end

    %% Acoustic micro-oscillations AR(1) per node
    if nargin >= 5 && ~isempty(p_acoustic_prev)
        a      = cfg.p_acoustic_corr;
        sigma  = cfg.p_acoustic_std * sqrt(1 - a^2);
        p_acoustic = a * p_acoustic_prev + sigma * randn(params.nNodes, 1);
    else
        p_acoustic = zeros(params.nNodes, 1);
    end
    p = p + p_acoustic;

    %% Physical pressure clamp [0.1, 70] bar
    p = max(0.1, min(p, 70));
end