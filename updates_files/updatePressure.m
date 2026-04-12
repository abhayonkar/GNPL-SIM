function [p, p_acoustic] = updatePressure(params, p, q, demand_vec, p_acoustic_prev, cfg)
% updatePressure  Nodal mass-balance pressure update with stability fixes.
%
%   [p, p_acoustic] = updatePressure(params, p, q, demand_vec, p_acoustic_prev, cfg)
%
%   PHASE 0 FIXES APPLIED (root cause: Indian CGD pressures 14-26 bar are
%   much lower than European 40-85 bar, making the raw coefficient 3-5x
%   too large for the same pipe geometry, causing sign oscillation):
%
%   FIX 1 — Under-relaxation (relax = 0.3)
%     Only 30% of the computed pressure delta is applied per step.
%     Equivalent to a first-order low-pass filter on the pressure update.
%     Eliminates the alternating floor/ceiling pattern (D1=0.1, D2=70, D1=0.1...)
%     seen when relax=1.0 (which was the implicit pre-fix behaviour).
%
%   FIX 2 — Neighbour diffusion (alpha = 0.05)
%     After the mass-balance update, one sweep of edge-aligned averaging
%     smooths any remaining node-to-node gradient spikes. This is analogous
%     to numerical viscosity in FVM solvers and is physically justified:
%     real pipeline gas has linepack that damps instantaneous swings.
%
%   FIX 3 — Realistic CGD clamp [12, 28] bar
%     Old clamp was [0.1, 70] — physically meaningless for Indian CGD.
%     PNGRB T4S operating range: 14-26 barg nominal, safety margins ±2 bar.
%     Clamping at 12/28 triggers shutdown logic in updateControlLogic.m
%     (cfg.emer_shutdown_p = 28.0, cfg.valve_open_lo = 14.0).
%
%   Physics (unchanged):
%     dp = relax * (dt * c² / (V * 1e5)) * net_mass_inflow   [bar]
%
%   Verification after fix:
%     Run run_24h_sweep('mode','quick','gateway',false,'dur_min',30)
%     Expect: ALL pressure warnings gone, p_mean in 16-24 bar range.

    % ── Mass-balance coefficient  [bar / (kg/s)] ─────────────────────────
    %   coeff = dt * c² / (V * 1e5)
    %   At c=420 m/s, V=500 m³, dt=0.1s:
    %     coeff = 0.1 * 176400 / (500 * 1e5) = 3.53e-4  bar/(kg/s)   ← STABLE
    %   Old value (V=100): coeff = 1.76e-3  ← 5× too large → oscillation
    coeff = (cfg.dt .* params.c.^2) ./ (params.V .* 1e5);   % nNodes×1

    % ── FIX 1: Under-relaxation ──────────────────────────────────────────
    relax = 0.3;   % 30% of computed update applied per step
    dp    = coeff .* (params.B * q);
    p     = p + relax * dp;

    % ── Demand withdrawal (small explicit sink at demand nodes) ───────────
    if any(demand_vec ~= 0)
        p = p - demand_vec * (cfg.dt * 0.0001);
    end

    % ── FIX 2: Neighbour diffusion (one edge-aligned sweep) ───────────────
    %   Smooths node-to-node gradient spikes without changing net pressure.
    %   alpha = 0.05 means 5% of each adjacent pressure difference is
    %   redistributed per step — small enough to not damp real dynamics.
    alpha = 0.05;
    n_diff_edges = min(params.nEdges, size(cfg.edges, 1));
    for e = 1:n_diff_edges
        i_from = cfg.edges(e, 1);
        i_to   = cfg.edges(e, 2);
        if i_from < 1 || i_from > params.nNodes, continue; end
        if i_to   < 1 || i_to   > params.nNodes, continue; end
        d       = p(i_from) - p(i_to);
        p(i_from) = p(i_from) - alpha * d;
        p(i_to)   = p(i_to)   + alpha * d;
    end

    % ── Acoustic micro-oscillations AR(1) per node ───────────────────────
    if nargin >= 5 && ~isempty(p_acoustic_prev)
        a         = cfg.p_acoustic_corr;
        sigma     = cfg.p_acoustic_std * sqrt(1 - a^2);
        p_acoustic = a * p_acoustic_prev + sigma * randn(params.nNodes, 1);
    else
        p_acoustic = zeros(params.nNodes, 1);
    end
    p = p + p_acoustic;

    % ── FIX 3: Realistic CGD pressure clamp [12, 28] bar ─────────────────
    %   Old: max(0.1, min(p, 70)) — allowed physically impossible values
    %   New: max(12,  min(p, 28)) — PNGRB T4S compliant range with ±2 margins
    %   Safety margin below 14 barg (valve_open_lo) and above 26 barg (MAOP)
    p = max(12.0, min(p, 28.0));
end
