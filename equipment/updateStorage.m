function [state, q_sto] = updateStorage(state, params, cfg)
% updateStorage  Underground storage cavern — bidirectional flow control.
%
%   [state, q_sto] = updateStorage(state, params, cfg)
%
%   Storage behaviour (realistic):
%     HIGH network pressure (> sto_p_inject):
%       Compressor pushes gas INTO storage — withdraws from network
%       state.sto_inventory increases
%
%     LOW network pressure (< sto_p_withdraw):
%       Storage releases gas INTO network — boosts downstream pressure
%       state.sto_inventory decreases
%
%     NORMAL pressure: storage idle
%
%   This creates the characteristic saw-tooth inventory pattern visible
%   in real linepack/storage SCADA data — injecting during high supply
%   (night/summer) and withdrawing during high demand (morning/winter).

    n_sto = params.storageNodes(1);   % STO node index
    p_net = state.p(n_sto);          % network pressure at storage node

    q_sto = 0;   % net flow from storage into network (kg/s, positive=injection)

    if p_net > cfg.sto_p_inject
        %% Injection mode: push excess network gas into storage
        q_inject = min(cfg.sto_k_flow * (p_net - cfg.sto_p_inject), cfg.sto_max_flow);
        q_sto = -q_inject;   % flow leaving network (negative from network perspective)

        %% Inventory increases
        delta_inv = q_inject * cfg.dt / cfg.sto_capacity;
        state.sto_inventory = min(1.0, state.sto_inventory + delta_inv);

        %% Network pressure at STO node slightly reduced
        state.p(n_sto) = state.p(n_sto) - 0.001 * q_inject;

    elseif p_net < cfg.sto_p_withdraw && state.sto_inventory > 0.05
        %% Withdrawal mode: release stored gas into network
        q_withdraw = min(cfg.sto_k_flow * (cfg.sto_p_withdraw - p_net), cfg.sto_max_flow);
        q_withdraw = min(q_withdraw, state.sto_inventory * cfg.sto_capacity / cfg.dt);
        q_sto = q_withdraw;   % flow entering network (positive)

        %% Inventory decreases
        delta_inv = q_withdraw * cfg.dt / cfg.sto_capacity;
        state.sto_inventory = max(0.0, state.sto_inventory - delta_inv);

        %% Network pressure at STO node slightly boosted
        state.p(n_sto) = state.p(n_sto) + 0.001 * q_withdraw;
    end

    %% Apply net flow onto storage edges per canonical_architecture.json:
    %  E12 (index 12): STO→PRS2  — withdrawal flow out of storage to network
    %  E11 (index 11): J7→STO    — injection flow from network into storage
    %  (E14=S2→D1 and E15=D1→D2 are demand distribution edges, not storage)
    if q_sto > 0   % storage withdrawing to network via STO→PRS2
        state.q(12) = state.q(12) + q_sto;
    else           % network injecting to storage via J7→STO
        state.q(11) = state.q(11) + abs(q_sto);
    end

    state.p(n_sto) = max(0.1, min(state.p(n_sto), 70));
end