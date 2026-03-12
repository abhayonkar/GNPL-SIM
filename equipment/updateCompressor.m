function [state, comp] = updateCompressor(state, comp, k, cfg, comp_id)
% updateCompressor  Update one compressor station (call separately for CS1/CS2).
%
%   [state, comp] = updateCompressor(state, comp, k, cfg, comp_id)
%
%   comp_id: 1 = CS1 (primary), 2 = CS2 (secondary)
%   Results stored in state.W1/H1/eta1 or state.W2/H2/eta2.

    if ~comp.online
        return;
    end

    %% Inlet flow (edge entering compressor node)
    %  CS1 node=3: inlet edge E2 (edge 2)
    %  CS2 node=7: inlet edge E6 (edge 6)
    inlet_edge = comp.node - 1;   % works for CS1(3)->E2, CS2(7)->E6
    mflow = abs(state.q(inlet_edge)) + 1e-3;

    %% Head curve H = a1 + a2*m + a3*m^2 (J/kg)
    H = comp.a1 + comp.a2*mflow + comp.a3*mflow^2;
    H = max(0, H);

    %% Efficiency curve eta = b1 + b2*m + b3*m^2
    eta = comp.b1 + comp.b2*mflow + comp.b3*mflow^2;
    eta = max(0.10, min(eta, 0.95));

    %% Shaft pulsation (blade-pass frequency)
    t = k * cfg.dt;
    pulsation = cfg.comp_pulsation_amp * sin(2*pi * cfg.comp_pulsation_freq * t);

    %% Surge margin noise AR(1)
    a_s = cfg.comp_surge_corr;
    sigma_s = cfg.comp_surge_noise * sqrt(1 - a_s^2);
    comp.surge_state = a_s * comp.surge_state + sigma_s * randn();

    %% Effective ratio with noise
    ratio_eff = comp.ratio * (1 + pulsation + comp.surge_state);
    ratio_eff = max(comp.ratio_min, min(ratio_eff, comp.ratio_max));

    %% Shaft power W = m*H/eta
    W = mflow * H / eta;

    %% Apply pressure boost at compressor node
    state.p(comp.node) = state.p(comp.node) * ratio_eff;
    state.p(comp.node) = max(0.1, min(state.p(comp.node), 70));

    %% Store to correct state fields
    if comp_id == 1
        state.W1 = W; state.H1 = H; state.eta1 = eta;
    else
        state.W2 = W; state.H2 = H; state.eta2 = eta;
    end
end