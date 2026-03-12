function [q, state] = updateFlow(params, state, valve_states)
% updateFlow  Compute edge mass-flow via Darcy-Weisbach with elevation.
%
%   [q, state] = updateFlow(params, state, valve_states)
%
%   Physics:
%   Darcy-Weisbach with Colebrook-White friction:
%     dP_friction = lambda*(L/D)*(rho*v^2/2)
%
%   Hydrostatic correction (elevation):
%     dP_total = dP_friction + dP_hydro
%     dP_hydro = rho*g*(z_from - z_to)  [assists downhill flow]
%
%   Line pack update (mass balance per segment):
%     dM_e/dt = q_in - q_out
%     Pressure propagation delay emerges naturally from this.

    p = state.p;
    q = zeros(params.nEdges, 1);

    for e = 1:params.nEdges
        D     = params.D(e);
        L     = params.L(e);
        rough = params.rough(e);

        %% Colebrook-White friction factor (2-iteration approximation)
        rel  = rough / (3.7 * D);
        lam0 = (1 / (-2*log10(max(rel, 1e-12))))^2;
        arg  = rel + 2.51 / (1e6 * sqrt(max(lam0, 1e-12)));
        lam  = (1 / (-2*log10(max(arg, 1e-12))))^2;

        %% Resistance coefficient
        K = sqrt(16 * lam * L / (pi^2 * D^5));
        K = max(K, 1e-6);

        %% Pressure difference including hydrostatic correction
        dp_pressure = p(params.edges(e,1))^2 - p(params.edges(e,2))^2;
        dp_hydro    = params.dP_hydro(e);   % bar (signed, assists downhill)
        dp_total    = dp_pressure + 2 * p(params.edges(e,1)) * dp_hydro;

        %% Darcy-Weisbach flow
        q(e) = sign(dp_total) * sqrt(abs(dp_total)) / K;
    end

    %% Apply valve states (multi-valve support)
    for v = 1:numel(params.valveEdges)
        e = params.valveEdges(v);
        q(e) = q(e) * valve_states(v);
    end

    %% AR(1) turbulence noise (added from params.turb_state set externally)
    if isfield(params, 'turb_state')
        q = q + params.turb_state;
    end

    %% Line pack update: dM/dt = rho*(q_in - q_out) per segment
    %  Using rho at mean pressure of edge as approximation
    rho_ref = 0.8 * 0.5*(p(params.edges(:,1)) + p(params.edges(:,2))) / 285;
    dM = rho_ref .* q;   % simplified mass flux
    state.linepack = max(0.01, state.linepack + dM * 0.001);   % slow accumulation

    %% Physical flow clamp
    q = max(-500, min(q, 500));   % kg/s (larger network, higher flows)
end