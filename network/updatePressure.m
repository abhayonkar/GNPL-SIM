function [p, p_acoustic] = updatePressure(params, p, q, demand_vec, p_acoustic_prev, cfg)
% updatePressure  Nodal mass-balance pressure update with acoustic noise.
%
%   [p, p_acoustic] = updatePressure(params, p, q, demand_vec, p_acoustic_prev, cfg)
%
%   demand_vec: nNodes x 1 vector (non-zero only at demand nodes)
%
%   Physics:
%     dp/dt = (c^2 / V) * net_mass_inflow
%   Line pack modifies effective nodal volume — larger V at high linepack.
%
%   Bounds: [0.1, 70] bar (transmission network, higher than distribution)

    %% Core mass-balance (lumped parameter)
    p = p + (params.c^2 ./ params.V) .* (params.B * q);

    %% Apply demand withdrawals (demand nodes only)
    p = p - demand_vec * 0.005;   % scaled withdrawal per step

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