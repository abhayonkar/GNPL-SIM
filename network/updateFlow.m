function [q, state] = updateFlow(params, state, valve_states)
% updateFlow  Compute edge mass-flow via Darcy-Weisbach with elevation.
%
%   [q, state] = updateFlow(params, state, valve_states)
%
%   COMPRESSOR EDGE FIX:
%   Darcy-Weisbach treats all edges as passive pipes driven by pressure gradient.
%   For compressor edges the outlet pressure is HIGHER than inlet (the compressor
%   does work), so the formula would compute backward flow (outlet→inlet).
%   Fix: after Darcy-Weisbach, override compressor inlet flow = outlet flow.
%   This enforces mass conservation at the compressor node (no storage there).

    p = state.p;
    q = zeros(params.nEdges, 1);

    for e = 1:params.nEdges
        D     = params.D(e);
        L     = params.L(e);
        rough = params.rough(e);

        %% Colebrook-White friction factor (2-iteration)
        rel  = rough / (3.7 * D);
        lam0 = (1 / (-2*log10(max(rel, 1e-12))))^2;
        arg  = rel + 2.51 / (1e6 * sqrt(max(lam0, 1e-12)));
        lam  = (1 / (-2*log10(max(arg, 1e-12))))^2;

        %% Resistance coefficient
        K = sqrt(16 * lam * L / (pi^2 * D^5));
        K = max(K, 1e-6);

        %% Pressure difference including hydrostatic correction
        dp_pressure = p(params.edges(e,1))^2 - p(params.edges(e,2))^2;
        dp_hydro    = params.dP_hydro(e);
        dp_total    = dp_pressure + 2 * p(params.edges(e,1)) * dp_hydro;

        %% Darcy-Weisbach flow
        q(e) = sign(dp_total) * sqrt(abs(dp_total)) / K;
    end

    %% Compressor edge mass-conservation override ─────────────────────────
    %  A compressor adds pressure, so its outlet > inlet. The passive D-W
    %  formula would see a negative gradient and return backward flow, which
    %  is physically wrong. Instead: compressor inlet flow = outlet flow
    %  (mass conservation — compressor node has no gas storage).
    for i = 1:numel(params.compNodes)
        cs_node  = params.compNodes(i);
        inlet_e  = find(params.edges(:,2) == cs_node, 1);   % edge entering CS
        outlet_e = find(params.edges(:,1) == cs_node, 1);   % edge leaving CS
        if ~isempty(inlet_e) && ~isempty(outlet_e)
            % Outlet flow is determined by downstream pressure gradient (correct).
            % Inlet flow must equal outlet flow by mass conservation.
            q(inlet_e) = q(outlet_e);
        end
    end

    %% Apply valve states (valve_states = 0 closes the edge)
    for v = 1:numel(params.valveEdges)
        e    = params.valveEdges(v);
        q(e) = q(e) * valve_states(v);
    end

    %% AR(1) turbulence noise (set externally in params.turb_state)
    if isfield(params, 'turb_state')
        q = q + params.turb_state;
    end

    %% Line pack update: slow mass accumulation per segment
    rho_ref     = 0.8 * 0.5*(p(params.edges(:,1)) + p(params.edges(:,2))) / 285;
    dM          = rho_ref .* q;
    state.linepack = max(0.01, state.linepack + dM * 0.001);

    %% Physical flow clamp
    q = max(-500, min(q, 500));
end