function [flows, dp] = updateFlow(cfg, pressures, demands)
% updateFlow  Compatibility wrapper for the 20-node CGD physics engine.
%
% Signature accepted by runSimulation.m (legacy 3-arg call):
%   [flows, dp] = updateFlow(cfg, pressures, demands)
%
% Internally delegates to computeFlows.m which carries the full
% Darcy-Weisbach / Weymouth implementation.
%
% HARD RULES (do not modify this wrapper):
%   - params.L  : pipe length vector  (NOT params.pipe_L_vec)
%   - params.D  : pipe diameter vector (NOT params.pipe_D_vec)
%   - All pressures are in barg; internal conversions to Pa happen
%     inside computeFlows.m
%
% Verification:
%   >> [f, dp] = updateFlow(cfg, ones(20,1)*20, ones(20,1)*100)
%   f and dp must be 20-element column vectors, no NaN, no Inf.

    % ----------------------------------------------------------------
    % 1. Build params struct expected by computeFlows
    % ----------------------------------------------------------------
    params = struct();
    params.L = cfg.pipe_L;          % [km] — Nx1 vector
    params.D = cfg.pipe_D;          % [m]  — Nx1 vector
    params.SG   = cfg.gas_SG;       % 0.57 for ONGC/GAIL
    params.Tf   = cfg.T_avg_K;      % average temperature [K]
    params.Z    = cfg.Z_factor;     % 0.95 at 20 bar / 35°C
    params.E    = cfg.pipe_eff;     % pipeline efficiency (0.9 default)

    % ----------------------------------------------------------------
    % 2. Delegate
    % ----------------------------------------------------------------
    [flows, dp] = computeFlows(cfg, params, pressures, demands);

    % ----------------------------------------------------------------
    % 3. Sanity guard — surface NaN/Inf immediately rather than
    %    propagating silently into EKF / CUSUM
    % ----------------------------------------------------------------
    if any(~isfinite(flows)) || any(~isfinite(dp))
        warning('updateFlow:nonfinite', ...
            'Non-finite values detected after computeFlows — check pressure inputs.');
        flows(~isfinite(flows)) = 0;
        dp(~isfinite(dp))       = 0;
    end
end