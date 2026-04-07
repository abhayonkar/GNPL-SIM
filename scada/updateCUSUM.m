function [cusum, alarm] = updateCUSUM(cusum, residual, cfg, step)
% updateCUSUM  Two-sided CUSUM detector with cold-start warmup guard.
%
% INPUTS
%   cusum     : struct with fields S_pos, S_neg, n_steps (persistent state)
%   residual  : scalar or Nx1 vector of normalised residuals at current step
%   cfg       : simConfig struct (reads cusum_slack, cusum_threshold,
%               cusum_warmup_steps, cusum_reset_on_trip)
%   step      : integer simulation step counter (1-based)
%
% OUTPUTS
%   cusum     : updated struct
%   alarm     : logical scalar — true if threshold crossed AND past warmup
%
% Phase A fix:
%   Old slack=1.0 → 816 false alarms in a 24-h baseline run.
%   cfg.cusum_slack=2.5, cfg.cusum_warmup_steps=300 eliminates cold-start
%   transients without masking real attacks (onset typically step >500).
%
% Verification:
%   >> cfg = simConfig();
%   >> cs = struct('S_pos',0,'S_neg',0,'n_steps',0);
%   >> for k=1:600; r=randn(20,1)*0.5; [cs,al]=updateCUSUM(cs,r,cfg,k); end
%   >> % al should be 0 throughout (no alarm on white noise with slack=2.5)

    k     = cfg.cusum_slack;
    h     = cfg.cusum_threshold;
    warm  = cfg.cusum_warmup_steps;

    % Accumulate step counter
    cusum.n_steps = cusum.n_steps + 1;

    % Scalar summary: use max absolute residual across nodes
    if numel(residual) > 1
        r = max(abs(residual));
    else
        r = residual;
    end

    % Two-sided CUSUM update (Page 1954)
    cusum.S_pos = max(0, cusum.S_pos + r - k);
    cusum.S_neg = max(0, cusum.S_neg - r - k);

    % ----------------------------------------------------------------
    % Cold-start guard: suppress alarm evaluation during warmup window
    % ----------------------------------------------------------------
    in_warmup = (step <= warm);

    if in_warmup
        alarm = false;
        return
    end

    % Threshold test
    alarm = (cusum.S_pos > h) || (cusum.S_neg > h);

    % Optional reset on trip
    if alarm && cfg.cusum_reset_on_trip
        cusum.S_pos = 0;
        cusum.S_neg = 0;
    end
end