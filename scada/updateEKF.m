function ekf = updateEKF(ekf, meas_p, meas_q, true_p, true_q, params, cfg)
% updateEKF  Extended Kalman Filter with physics-derived state transition.
%
%   ekf = updateEKF(ekf, meas_p, meas_q, true_p, true_q, params, cfg)
%
%   UPGRADE FROM PHASE 3 (F = I):
%   ──────────────────────────────
%   The previous implementation used F = I₄₀ (identity), making the EKF
%   a simple measurement smoother with no physics prediction. This means
%   the prediction step adds no information beyond the previous estimate,
%   and the residual sensitivity to slow transient attacks is low.
%
%   PHASE 6 — ANALYTICAL LINEARISED JACOBIAN:
%   ───────────────────────────────────────────
%   The gas network state x = [p (20×1); q (20×1)] evolves as:
%
%     q(k+1) = DW(p(k))     — Darcy-Weisbach flow from current pressure
%     p(k+1) = p(k) + Γ·B·q(k+1)   — mass-balance pressure update
%
%   where:
%     DW_e(p) = sign(ΔP_e)·√|ΔP_e| / K_e,  ΔP_e = B^T·p (pressure drop)
%     Γ = diag(dt·c²/(V_i·10⁵))  ∈ ℝ^{N×N}
%     B = incidence matrix (N×E)
%
%   Linearising DW around operating point p̄:
%     ∂q_e/∂(B^T·p)_e = 1 / (2·K_e·√|ΔP̄_e|)   ≡ w_e
%
%   So:  ∂DW/∂p = diag(w) · B^T   ∈ ℝ^{E×N}
%
%   The 40×40 block Jacobian F = ∂f/∂x is:
%
%     F = [ I_N + Γ·B·diag(w)·B^T ,   0_{N×E} ]
%         [ diag(w)·B^T            ,   0_{E×E} ]
%
%   The zero blocks reflect that q(k+1) depends only on p(k), not q(k).
%   A small flow-inertia damping α·I_E is added to the q–q block to
%   prevent the covariance from collapsing to zero in the flow directions.
%
%   BACKWARD COMPATIBILITY:
%   If params/cfg are not passed (legacy 5-arg call), falls back to F=I.

    nN = numel(meas_p);   % 20
    nE = numel(meas_q);   % 20
    nX = nN + nE;         % 40

    %% ── Build measurement vector ─────────────────────────────────────────
    y = [meas_p(:); meas_q(:)];

    H = eye(nX);           % direct observation of all states
    R = getMeasurementCovariance(ekf, nX);
    Q = getProcessCovariance(ekf, nX);

    %% ── Build F matrix ───────────────────────────────────────────────────
    if nargin >= 6 && ~isempty(params) && nargin >= 7 && ~isempty(cfg)
        F = buildJacobian(ekf.xhat, params, cfg, nN, nE);
    else
        F = eye(nX);   % legacy fallback
    end

    %% ── Prediction step ──────────────────────────────────────────────────
    xhat_pred = F * ekf.xhat;
    P_pred    = F * ekf.P * F' + Q;

    %% ── Innovation ───────────────────────────────────────────────────────
    S   = H * P_pred * H' + R;
    inn = y - H * xhat_pred;      % innovation (pre-update residual)

    %% ── Kalman gain and update ───────────────────────────────────────────
    K_gain  = P_pred * H' / S;
    xhat_up = xhat_pred + K_gain * inn;
    P_up    = (eye(nX) - K_gain * H) * P_pred;

    %% ── Symmetrise P (numerical stability) ──────────────────────────────
    ekf.P = 0.5 * (P_up + P_up');

    %% ── Store state ──────────────────────────────────────────────────────
    ekf.xhat  = xhat_up;
    ekf.xpred = xhat_pred;
    ekf.xhatP = xhat_up(1:nN);       % pressure estimates
    ekf.xhatQ = xhat_up(nN+1:end);   % flow estimates
    ekf.shadow_x = xhat_pred;
    ekf.shadow_pressure = xhat_pred(1:nN);
    ekf.shadow_flow = xhat_pred(nN+1:end);
    ekf.shadow_residual = xhat_up - xhat_pred;
    ekf.shadow_divergence = abs(ekf.shadow_residual(1:nN));

    %% ── Residuals (for IDS features and CUSUM) ───────────────────────────
    ekf.residual  = inn;
    ekf.residualP = inn(1:nN);
    ekf.residualQ = inn(nN+1:end);
    ekf.residP    = ekf.residualP;   % alias used by detectIncidents
    ekf.residQ    = ekf.residualQ;

    %% ── Innovation covariance S (passed to CUSUM) ────────────────────────
    ekf.S = S;

    %% ── Chi-squared bad-data detector statistic ──────────────────────────
    % Normalize each innovation by its heterogeneous sensor variance.
    % Under H0, the expected per-state statistic is approximately 1.
    R_diag = diag(R);
    weighted_sq = (inn .^ 2) ./ max(R_diag, 1e-8);
    ekf.chi2_stat  = mean(weighted_sq);
    ekf.chi2_alarm = (ekf.chi2_stat > 3.0);

    if isfield(ekf, 'adaptive_enable') && ekf.adaptive_enable
        ekf = adaptProcessCovariance(ekf, inn);
    end

    %% ── Divergence guard ─────────────────────────────────────────────────
    if any(~isfinite(ekf.xhat)) || any(diag(ekf.P) < 0)
        logEvent('WARNING','updateEKF','EKF diverged — resetting to measurement', 0, 0);
        ekf.xhat = y;
        ekf.P    = ekf.P0 * eye(nX);
    end
end

%% ── LOCAL: build physics Jacobian ────────────────────────────────────────

function F = buildJacobian(xhat, params, cfg, nN, nE)
% buildJacobian  Compute 40×40 linearised state transition matrix F.
%
%   Uses the current EKF state estimate as the operating point.
%   Near-zero pressure differentials are regularised to avoid singularity.

    p_bar = xhat(1:nN);   % operating-point pressures (bar)

    dt = cfg.dt;
    c  = cfg.c;

    %% Γ: diagonal pressure gain matrix (N×N)
    V_vec = cfg.node_V * ones(nN, 1);   % nodal volumes (m³)
    gamma_vec = dt * c^2 ./ (V_vec * 1e5);
    Gamma = diag(gamma_vec);

    %% Incidence matrix B (N×E)
    B = params.B;   % pre-built in initNetwork

    %% Pressure drop at each edge from operating point
    dp = B' * p_bar;   % E×1 — signed pressure differential

    %% Darcy-Weisbach sensitivity weights  w_e = 1/(2·K_e·√|ΔP_e|)
    %  params.K should be stored by initNetwork (resistance coefficient per edge)
    eps_reg = 0.01;   % regularisation: avoid 1/√0 singularity near zero flow
    if isfield(params, 'K')
        K_vec = params.K(:);
    else
        % Fallback: compute from pipe geometry
        % params.L and params.D are populated by initNetwork (not pipe_L_vec/pipe_D_vec)
        lambda = 0.015;   % approximate Darcy friction factor
        L_vec  = params.L(:);
        D_vec  = params.D(:);
        K_vec  = sqrt(16 * lambda .* L_vec ./ (pi^2 .* D_vec.^5));
    end

    w = 1 ./ (2 .* K_vec .* sqrt(max(eps_reg, abs(dp))));   % E×1

    %% Jacobian of DW flow w.r.t. nodal pressure: J_qp = diag(w)·B^T (E×N)
    J_qp = diag(w) * B';

    %% Flow inertia damping — small α·I prevents covariance collapse
    %  Physical justification: gas column inertia L·∂q/∂t (Euler momentum)
    alpha_inertia = 0.15;

    %% Assemble 40×40 block Jacobian
    %  F = [ I_N + Γ·B·J_qp ,  0      ]
    %      [ J_qp             ,  α·I_E ]
    F_pp = eye(nN) + Gamma * B * J_qp;
    F_pq = zeros(nN, nE);
    F_qp = J_qp;
    F_qq = alpha_inertia * eye(nE);

    F = [F_pp, F_pq; F_qp, F_qq];

end

function R = getMeasurementCovariance(ekf, nX)
    if isfield(ekf, 'R') && isequal(size(ekf.R), [nX, nX])
        R = ekf.R;
    elseif isscalar(ekf.Rk)
        R = ekf.Rk * eye(nX);
    else
        R = ekf.Rk;
    end
end

function Q = getProcessCovariance(ekf, nX)
    if isfield(ekf, 'Q') && isequal(size(ekf.Q), [nX, nX])
        Q = ekf.Q;
    elseif isscalar(ekf.Qn)
        Q = ekf.Qn * eye(nX);
    else
        Q = ekf.Qn;
    end
end

function ekf = adaptProcessCovariance(ekf, innovation)
    innov_var = innovation .^ 2;
    lambda = ekf.adaptive_lambda;
    q_diag = diag(ekf.Q);
    updated_diag = lambda * q_diag + (1 - lambda) * innov_var;
    updated_diag = min(max(updated_diag, ekf.adaptive_floor), ekf.adaptive_cap);
    ekf.Q = diag(updated_diag);
end
