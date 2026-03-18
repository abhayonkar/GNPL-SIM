function [state, comp] = updateCompressor(state, comp, k, cfg, comp_id)
% updateCompressor  Update one compressor station.
%
%   [state, comp] = updateCompressor(state, comp, k, cfg, comp_id)
%
%   PRESSURE MODEL:
%     p_outlet = p_inlet_node * ratio_eff
%
%   The inlet node is the node that FEEDS into the compressor (e.g. J1 for CS1).
%   This is computed once from cfg.edges during each call.
%
%   The OLD formulation was:
%     state.p(comp.node) = state.p(comp.node) * ratio_eff   ← WRONG
%   That multiplies the OUTLET by ratio each timestep → exponential runaway.
%
%   The CORRECT formulation is:
%     state.p(comp.node) = state.p(upstream_node) * ratio_eff
%   which sets the outlet as a fixed multiple of the inlet each step.

    if ~comp.online
        return;
    end

    %% Inlet edge and upstream node
    %  inlet_edge index = comp.node - 1 (valid for CS1=node3→edge2, CS2=node7→edge6)
    inlet_edge    = comp.node - 1;
    upstream_node = cfg.edges(inlet_edge, 1);   % "from" column of edge table

    %% Inlet mass flow rate
    mflow = abs(state.q(inlet_edge)) + 1e-3;

    %% Head curve: H = a1 + a2*m + a3*m²  (J/kg)
    H   = comp.a1 + comp.a2*mflow + comp.a3*mflow^2;
    H   = max(0, H);

    %% Efficiency curve: eta = b1 + b2*m + b3*m²
    eta = comp.b1 + comp.b2*mflow + comp.b3*mflow^2;
    eta = max(0.10, min(eta, 0.95));

    %% Shaft pulsation (blade-pass frequency AR noise)
    t         = k * cfg.dt;
    pulsation = cfg.comp_pulsation_amp * sin(2*pi * cfg.comp_pulsation_freq * t);

    %% Surge margin noise AR(1)
    a_s             = cfg.comp_surge_corr;
    sigma_s         = cfg.comp_surge_noise * sqrt(1 - a_s^2);
    comp.surge_state = a_s * comp.surge_state + sigma_s * randn();

    %% Effective ratio (clamped to operational bounds)
    ratio_eff = comp.ratio * (1 + pulsation + comp.surge_state);
    ratio_eff = max(comp.ratio_min, min(ratio_eff, comp.ratio_max));

    %% Shaft power
    W = mflow * H / eta;

    %% Set outlet pressure = inlet × ratio  (CORRECT: applied once per step)
    p_inlet          = state.p(upstream_node);
    state.p(comp.node) = max(0.1, min(p_inlet * ratio_eff, 70));

    %% Store metrics
    if comp_id == 1
        state.W1 = W; state.H1 = H; state.eta1 = eta;
    else
        state.W2 = W; state.H2 = H; state.eta2 = eta;
    end
end