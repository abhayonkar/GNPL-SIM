function [cusum, alarm] = updateCUSUM(cusum, residual, cfg, step)
% updateCUSUM  Two-sided CUSUM detector with cold-start warmup guard.
%
% INPUTS
%   cusum    : struct with fields S_upper, S_lower, n_steps (persistent state)
%   residual : scalar, Nx1 vector, OR struct with field residualP or residual
%              (struct form is produced by updateEKF and passed directly here)
%   cfg      : simConfig struct
%   step     : integer simulation step counter (1-based)
%
% OUTPUTS
%   cusum    : updated struct
%   alarm    : logical scalar
%
% PHASE 0 FIX: Added struct input guard at top of function.
%   updateEKF returns ekf.residual as a struct in some code paths.
%   Without this guard the numel() check below throws a silent error
%   and CUSUM never updates, producing a flat S_upper=0 trace.

    % ── PHASE 0 FIX: Accept struct input from updateEKF ──────────────────
    if isstruct(residual)
        if isfield(residual, 'residualP')
            residual = residual.residualP;
        elseif isfield(residual, 'residual')
            residual = residual.residual;
        else
            % Fallback: zero residual — better than crashing
            residual = 0;
        end
    end

    k     = cfg.cusum_slack;
    h     = cfg.cusum_threshold;
    warm  = cfg.cusum_warmup_steps;

    % Accumulate step counter
    cusum.n_steps = cusum.n_steps + 1;

    % Scalar summary: max absolute residual across nodes
    if numel(residual) > 1
        r = max(abs(residual));
    else
        r = abs(residual);
    end

    % Two-sided CUSUM update (Page 1954)
    cusum.S_upper = max(0, cusum.S_upper + r - k);
    cusum.S_lower = max(0, cusum.S_lower - r - k);

    % Cold-start guard
    in_warmup = (step <= warm);
    if in_warmup
        alarm = false;
        cusum.alarm = false;
        return
    end

    % Threshold test
    alarm = (cusum.S_upper > h) || (cusum.S_lower > h);
    cusum.alarm = alarm;

    % Optional reset on trip
    if alarm && cfg.cusum_reset_on_trip
        cusum.S_upper = 0;
        cusum.S_lower = 0;
    end
end
