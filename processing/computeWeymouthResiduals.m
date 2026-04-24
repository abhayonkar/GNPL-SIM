function [resid_p, resid_q] = computeWeymouthResiduals(ekf, state, params, cfg)
% computeWeymouthResiduals  Weymouth physics residual for anomaly detection.
%
%   [resid_p, resid_q] = computeWeymouthResiduals(ekf, state, params, cfg)
%
%   CONCEPT:
%   ────────
%   The Weymouth equation predicts flow on each edge given the nodal pressures.
%   If an attack manipulates sensor readings (pressure spoof, flow meter spoof,
%   FDI), the reported sensor values will be inconsistent with the physics —
%   the predicted flow from the EKF pressure estimate will differ from the
%   measured (possibly spoofed) flow on the PLC bus.
%
%   Two residual vectors are computed:
%
%   1. PRESSURE RESIDUAL (resid_p, 20×1):
%      resid_p(i) = p_ekf(i) - p_weymouth_implied(i)
%      where p_weymouth_implied is the nodal pressure that would produce
%      the observed PLC flow readings under Weymouth physics.
%      This detects: pressure sensor spoofing (A5), FDI attacks (A9).
%
%   2. FLOW RESIDUAL (resid_q, 20×1):
%      resid_q(e) = q_plc(e) - q_weymouth(p_ekf, e)
%      where q_weymouth is the Weymouth-predicted flow given EKF pressures.
%      This detects: flow meter spoofing (A6), source manipulation (A1),
%      compressor ratio spoofing (A2), pipeline leaks (A8).
%
%   DETECTION ADVANTAGE (from Paper 1 results):
%   The Weymouth residual detects attacks 4.2× earlier than Modbus-only
%   monitoring because it combines pressure and flow physics simultaneously,
%   making it impossible to spoof both channels consistently without
%   satisfying the Weymouth equation across all 20 edges.
%
%   INPUTS:
%     ekf    — EKF struct with fields xhatP (20×1) and xhatQ (20×1)
%     state  — physics state struct with fields p (20×1) and q (20×1)
%     params — network params struct (B, L, D, nEdges, nNodes)
%     cfg    — simConfig struct
%
%   OUTPUTS:
%     resid_p — 20×1 nodal pressure residual [barg]
%     resid_q — 20×1 edge flow residual [SCMD]

    nN = params.nNodes;   % 20
    nE = params.nEdges;   % 20

    %% EKF-estimated pressures and flows
    p_ekf = ekf.xhatP(1:nN);   % 20×1 barg
    q_ekf = ekf.xhatQ(1:nE);   % 20×1 SCMD

    %% Weymouth-predicted flow from EKF pressures
    %   q_wey(e) = sign(dP_e) * sqrt(K_e * |P_up^2 - P_dn^2|)
    %   Uses same formula as computeFlows but operates on EKF estimates,
    %   not the full solver. This is intentionally lightweight — one
    %   vectorised calculation per logged step.
    Tb = 288.15; Pb = 101.325;
    E  = cfg.pipe_eff;
    SG = cfg.gas_SG;
    Tf = cfg.T_avg_K;
    Z  = cfg.Z_factor;

    A_wey = (433.5 * E * Tb / Pb)^2;
    L_vec = params.L(1:nE);         % km
    D_vec = params.D(1:nE);         % m
    K_e   = A_wey .* (D_vec.^(16/3)) ./ (SG .* Tf .* Z .* L_vec);

    p_abs  = (p_ekf + 1.01325) * 100;         % kPa abs
    dp_abs = params.B' * p_abs;               % pressure drop per edge [kPa]
    p_sum  = abs(params.B)' * p_abs;          % P_up + P_dn per edge [kPa]

    q_wey  = sign(dp_abs) .* sqrt(max(0, K_e .* abs(dp_abs) .* p_sum));  % SCMD

    %% Unit conversion: state.q is in kg/s; Weymouth K_e is calibrated for SCMD
    %  Standard gas density at (Tb, Pb):
    %    rho_std = Pb * (SG * M_air) / (R_gas * Tb)   [kg/m3]
    %  where M_air = 28.97 kg/kmol (molar mass of dry air)
    %        R_gas = 8.314 kPa·m3/(kmol·K)
    %  Conversion: q_SCMD = q_kgs * 86400 / rho_std
    M_air        = 28.97;                                     % kg/kmol
    R_gas        = 8.314;                                     % kPa·m3/(kmol·K)
    rho_std_kgm3 = Pb * (SG * M_air) / (R_gas * Tb);         % kg/m3
    kgs_to_scmd  = 86400 / rho_std_kgm3;                     % SCMD per (kg/s)

    %% Flow residual: PLC reading vs Weymouth prediction
    q_plc      = state.q(1:nE);           % kg/s (PLC bus reading)
    q_plc_scmd = q_plc * kgs_to_scmd;    % SCMD — same units as q_wey
    resid_q    = (q_plc_scmd - q_wey) / kgs_to_scmd;  % residual in kg/s

    %% Pressure residual: EKF estimate vs physics-implied pressure
    %  Invert Weymouth to find what pressure each edge "should" have
    %  given the observed PLC flow. For each edge e:
    %    q_plc_scmd(e)^2 = K_e * (P_up^2 - P_dn^2)
    %    P_up^2 - P_dn^2 = q_plc_scmd(e)^2 / K_e  (= Δ(P^2))
    %  This gives a constraint on the pressure difference per edge.
    %  The nodal pressure residual is the EKF estimate minus the value
    %  implied by the least-squares solution to all edge constraints.
    %
    %  Least-squares inversion: min ||p - p_implied||^2
    %    subject to: B^T * p_abs_implied^2 = q_plc_scmd^2 / K_e
    %  This is a linear system in p_abs^2. Solve via pseudoinverse.
    %  For numerical stability, clamp the right-hand side.

    rhs = (q_plc_scmd.^2) ./ max(1e-6, K_e);   % Δ(P^2) per edge [kPa^2]

    % Pseudoinverse solution for p_abs_implied^2
    p2_implied = max(0, pinv(full(params.B')) * rhs);   % nN×1 [kPa^2]
    p_implied_abs  = sqrt(max(0, p2_implied));           % kPa abs
    p_implied_barg = max(0, p_implied_abs / 100 - 1.01325);  % barg

    resid_p = p_ekf - p_implied_barg;   % 20×1 barg

    %% Guard against NaN/Inf
    resid_p(~isfinite(resid_p)) = 0;
    resid_q(~isfinite(resid_q)) = 0;
end