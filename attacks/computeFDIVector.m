function [a_p, a_q, c_vec] = computeFDIVector(ekf, cfg, k, dt)
% computeFDIVector  Construct a stealthy False Data Injection attack vector.
%
%   [a_p, a_q, c_vec] = computeFDIVector(ekf, cfg, k, dt)
%
%   THEORY (Liu, Ning & Reiter 2011):
%   ─────────────────────────────────
%   Let the EKF observation model be:
%       y = H * x + v,   H = I_40  (identity, direct observation)
%
%   An attacker adds a vector a to measurements:
%       y_a = y + a
%
%   The corrupted EKF innovation is:
%       r_a = y_a - H * x_hat = (y + a) - H * x_hat
%           = r + a
%
%   To make r_a = r (zero additional residual), we need:
%       a = H * c   for some nonzero c ∈ R^40
%
%   Since H = I_40:
%       a = c   (the attack vector equals c directly)
%
%   The state estimate is corrupted by:
%       x_hat_a = x_hat + K * H * c ≈ x_hat + c
%       (since K*H ≈ I for a well-tuned EKF)
%
%   TRIANGLE ATTACK CONSTRUCTION:
%   ─────────────────────────────
%   c is constructed as a sparse vector non-zero only at the three target
%   pressure node indices (J2=4, J3=5, J5=8). This confines the attack to
%   a topologically closed triangle subgraph, satisfying algebraic
%   consistency while minimising the number of compromised channels.
%
%   The bias is ramped linearly over cfg.atk9_ramp_s seconds to avoid
%   triggering rate-of-change detectors.
%
%   OUTPUTS:
%     a_p   — 20×1 pressure measurement perturbation (bar)
%     a_q   — 20×1 flow measurement perturbation (kg/s) — zeros for A9
%     c_vec — full 40×1 state-space perturbation vector [c_p; c_q]

    nN = 20;   % nodes
    nE = 20;   % edges

    %% Bias magnitude: ramp from 0 to full bias over atk9_ramp_s seconds
    ramp_steps = max(1, round(cfg.atk9_ramp_s / dt));
    ramp_frac  = min(1.0, k / ramp_steps);   % k here is steps since attack start

    %% Nominal pressure estimate at target nodes (from EKF)
    p_hat = ekf.xhatP;   % 20×1 pressure estimates

    %% Build the sparse c vector for pressure channels
    c_p = zeros(nN, 1);
    for i = 1:numel(cfg.atk9_target_nodes)
        node_idx      = cfg.atk9_target_nodes(i);
        nominal_p     = max(1.0, p_hat(node_idx));
        bias_magnitude = cfg.atk9_bias_scale * nominal_p;   % e.g. 5% of 50 bar = 2.5 bar
        c_p(node_idx) = bias_magnitude * ramp_frac;
    end

    %% Flow channels: keep zero (attack only corrupts pressure sensors)
    %  Corrupting both pressure and flow simultaneously would violate
    %  the Darcy-Weisbach mass balance and become detectable via physics
    %  cross-validation. Pressure-only FDI is harder to detect.
    c_q = zeros(nE, 1);

    %% Full state-space perturbation vector [pressures; flows]
    c_vec = [c_p; c_q];

    %% Since H = I_40, the measurement attack vector a = H*c = c
    a_p = c_p;   % perturbation added to pressure sensor readings
    a_q = c_q;   % perturbation added to flow sensor readings (zeros)

    %% Verify: EKF residual impact
    %  r_a = r + H*c - H*c = r  (invariant to attack by construction)
    %  This is not computed here but is proved by the construction above.
end