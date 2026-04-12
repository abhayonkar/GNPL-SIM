function [flows, dp] = computeFlows(cfg, params, pressures, demands)
% computeFlows  Weymouth steady-state flow solver for the 20-node CGD network.
%
%   [flows, dp] = computeFlows(cfg, params, pressures, demands)
%
%   PHYSICS MODEL — WEYMOUTH EQUATION (PNGRB T4S / IS 14931):
%   ──────────────────────────────────────────────────────────
%   For each pipe edge e connecting nodes i→j:
%
%     Q_e = sign(ΔP_e) · √( K_e · |P_i_abs² − P_j_abs²| )
%
%   where:
%     Q_e      — volumetric flow [SCMD — standard m³/day at 15°C, 101.325 kPa]
%     K_e      — Weymouth conductance [SCMD² / kPa²]
%     P_abs    — absolute pressure [kPa abs] = (P_barg + 1.01325) × 100
%     ΔP_e     — signed pressure drop = P_i_abs − P_j_abs [kPa]
%
%   Weymouth conductance per edge (PNGRB T4S Eq. 4.3):
%     K_e = 433.5² · E² · (Tb/Pb)² · D^(16/3) / (SG · Tf · Z · L)
%
%   where:
%     E  = pipeline efficiency (cfg.pipe_eff = 0.92)
%     Tb = 288.15 K  (base temp, 15°C)
%     Pb = 101.325 kPa  (base pressure)
%     D  = pipe diameter [m]
%     SG = gas specific gravity (cfg.gas_SG = 0.57)
%     Tf = flowing temperature [K]  (cfg.T_avg_K = 308.15 K)
%     Z  = compressibility (cfg.Z_factor = 0.95)
%     L  = pipe length [km]
%
%   INPUTS:
%     cfg       — simConfig struct (pipe_L, pipe_D, gas_SG, T_avg_K,
%                 Z_factor, pipe_eff, edges, n_nodes, n_pipes)
%     params    — params struct with at least:
%                   params.L   — pipe length vector  [km]  (nEdges×1)
%                   params.D   — pipe diameter vector [m]   (nEdges×1)
%                   params.B   — incidence matrix     (nNodes×nEdges)
%                                [built here if absent]
%     pressures — nNodes×1 nodal pressures [barg]
%     demands   — nNodes×1 demand withdrawal [SCMD] (positive = withdrawal)
%
%   OUTPUTS:
%     flows     — nEdges×1 signed volumetric flow [SCMD]
%                 positive = in direction of edge definition (from→to)
%     dp        — nEdges×1 signed pressure drop [barg]
%                 = P_from − P_to (positive = flow assists)
%
%   UNITS NOTE:
%     The simulation uses SCMD throughout (cfg.q_nom_scmd=800).
%     updatePressure converts via coeff = dt·c²/(V·1e5).
%     Noise sigma cfg.noise_sigma_q is in SCMD.
%
%   PHASE 0 FIX (lines 77-78):
%     Added min-guards on L_vec and D_vec before computing K_e.
%     Without these, resilience edges (E21, E22) or any zero/NaN entry
%     produces K_e = Inf → Q = Inf, cascading into the pressure oscillation
%     that caused 97% scenario divergence.
%     L_vec = max(0.1, ...) — minimum 100 m pipe length
%     D_vec = max(0.01, ...) — minimum 10 mm pipe diameter
%
%   Verification:
%     cfg = simConfig();
%     params.L = cfg.pipe_L; params.D = cfg.pipe_D;
%     p_test   = ones(20,1) * 21;   % flat 21 barg
%     [q, dp]  = computeFlows(cfg, params, p_test, zeros(20,1));
%     assert(all(isfinite(q)) && all(isfinite(dp)));
%     assert(numel(q)==20 && numel(dp)==20);
%     assert(all(abs(dp) < 0.01), 'Flat pressure: dp should be near-zero');
%     disp('computeFlows verification PASS');

    % ── Constants ────────────────────────────────────────────────────────
    Tb = 288.15;        % base temperature [K]  (15°C)
    Pb = 101.325;       % base pressure [kPa abs]

    E  = cfg.pipe_eff;  % Weymouth efficiency factor (0.92)
    SG = cfg.gas_SG;    % specific gravity (0.57)
    Tf = cfg.T_avg_K;   % flowing temperature [K]
    Z  = cfg.Z_factor;  % compressibility (0.95)

    nN = cfg.n_nodes;
    nE = min(cfg.n_pipes, 20);  % only base 20 edges for physics solve

    % PHASE 0 FIX: clamp L and D to physical minimums before computing K_e.
    % Original lines were:
    %   L_vec = params.L(1:nE);
    %   D_vec = params.D(1:nE);
    % Without the max() guards, stub or mis-configured edges produce
    % K_e = Inf → Q = Inf, which cascades into pressure oscillation.
    L_vec = max(0.1,  params.L(1:nE));     % min 0.1 km = 100 m  [km]
    D_vec = max(0.01, params.D(1:nE));     % min 0.01 m = 10 mm  [m]

    % ── Build incidence matrix if not pre-built ───────────────────────────
    if isfield(params, 'B') && ~isempty(params.B)
        B = params.B(1:nN, 1:nE);
    else
        B = buildIncidence(cfg, nN, nE);
    end

    % ── Convert pressures: barg → kPa absolute ───────────────────────────
    % P_abs [kPa] = (P_barg + 1.01325) × 100
    p_barg = pressures(:);
    p_abs  = (p_barg + 1.01325) * 100;   % kPa abs, nN×1

    % ── Weymouth conductance per edge ─────────────────────────────────────
    % K_e = (433.5 · E · Tb/Pb)² · D^(16/3) / (SG · Tf · Z · L)
    % Units: [SCMD]² / [kPa]²
    A_wey = (433.5 * E * Tb / Pb)^2;   % scalar coefficient
    K_e   = A_wey .* (D_vec .^ (16/3)) ./ (SG .* Tf .* Z .* L_vec);  % nE×1

    % ── Signed pressure drops per edge ───────────────────────────────────
    % dp_e = P_from_abs - P_to_abs  [kPa]
    % B^T * p_abs gives the drop in the direction of edge definition
    dp_abs = B' * p_abs;    % nE×1, kPa

    % ── Weymouth flow per edge ────────────────────────────────────────────
    % Q_e = sign(dp_e) * sqrt(K_e * |P_from² - P_to²|)
    % |P_from² - P_to²| = |dp_e| * (P_from + P_to) ← factored form
    % This avoids computing P_from/P_to separately and is algebraically exact.
    %
    % P_from = p_abs(from_node), P_to = p_abs(to_node)
    % P_from + P_to = 2 * P_avg  where P_avg is midpoint
    % Compute via incidence: P_avg_e = 0.5 * (|B|^T * p_abs) per edge

    B_abs      = abs(B);                         % unsigned incidence
    p_sum_e    = B_abs' * p_abs;                 % P_from + P_to, nE×1 [kPa]

    % |P_from² − P_to²| = |dp_abs| · (P_from + P_to)
    dp2        = abs(dp_abs) .* p_sum_e;         % nE×1  [kPa²]

    % Q_e [SCMD]
    flows = sign(dp_abs) .* sqrt(K_e .* dp2);   % nE×1

    % ── Pressure drop in barg for output (used by EKF Jacobian) ──────────
    dp = dp_abs / 100;   % kPa → bar  (1 bar ≈ 100 kPa)

    % ── Guard against NaN/Inf (e.g. zero-length pipe or zero pressure) ───
    flows(~isfinite(flows)) = 0;
    dp(~isfinite(dp))       = 0;

    % ── Clamp to physical flow limit (prevent runaway) ────────────────────
    q_max = cfg.q_max_scmd * 5;   % allow 5× nominal as hard ceiling
    flows = max(-q_max, min(q_max, flows));
end


% ── LOCAL: build incidence matrix from cfg.edges ───────────────────────────

function B = buildIncidence(cfg, nN, nE)
% buildIncidence  Construct nN×nE signed incidence matrix from cfg.edges.
%
%   B(i,e) = +1 if edge e departs node i (from-node)
%   B(i,e) = -1 if edge e arrives at node i (to-node)
%
%   cfg.edges must be an nE×2 matrix [from_node, to_node] (1-indexed).

    if ~isfield(cfg, 'edges') || isempty(cfg.edges)
        error('computeFlows:noEdges', ...
            'cfg.edges is required. Add it to simConfig.m (see Phase A fix notes).');
    end

    B = zeros(nN, nE);
    for e = 1:min(nE, size(cfg.edges, 1))
        i_from = cfg.edges(e, 1);
        i_to   = cfg.edges(e, 2);
        if i_from >= 1 && i_from <= nN
            B(i_from, e) =  1;
        end
        if i_to >= 1 && i_to <= nN
            B(i_to,   e) = -1;
        end
    end
end
