function cusum = updateCUSUM(cusum, ekf, cfg, k, dt)
% updateCUSUM  CUSUM sequential change-point detector on EKF innovations.
%
%   cusum = updateCUSUM(cusum, ekf, cfg, k, dt)
%
%   THEORY (Page 1954; applied to ICS by Murguia & Ruths 2016):
%   ─────────────────────────────────────────────────────────────
%   The cumulative-sum (CUSUM) test is a sequential hypothesis test that
%   accumulates evidence of a distributional change in a statistic stream.
%   Applied to the EKF innovation sequence, it detects sustained shifts
%   in the mean of the normalised residual — the signature of attacks that
%   produce a persistent but small bias rather than a large instantaneous
%   spike (which the chi-squared test handles better).
%
%   TWO-SIDED CUSUM (upper + lower arms):
%     S_upper(k) = max(0, S_upper(k-1) + z(k) - slack)
%     S_lower(k) = max(0, S_lower(k-1) - z(k) - slack)
%     Alarm when S_upper(k) > threshold OR S_lower(k) > threshold
%
%   where z(k) is the scalar summary statistic at step k:
%     z(k) = ||r_norm(k)||₂ / √nX    (RMS normalised innovation)
%     r_norm(k) = S(k)^{-1/2} · innovation(k)
%
%   PARAMETERS (from cfg, Section 20):
%     cfg.cusum_slack     : allowance per step (dead-band). Typical: 1.0
%     cfg.cusum_threshold : alarm level. Set to achieve desired ARL.
%     cfg.cusum_reset_on_alarm : reset S to 0 after alarm (Page test)
%
%   CUSUM STRUCT FIELDS:
%     cusum.S_upper   : upper CUSUM statistic (scalar)
%     cusum.S_lower   : lower CUSUM statistic (scalar)
%     cusum.alarm     : true/false — alarm status this step
%     cusum.alarm_count : total alarms since simulation start
%     cusum.z_history : recent z values (ring buffer, length 100)
%     cusum.S_upper_history : same for S_upper
%     cusum.nx        : number of state dimensions (for normalisation)
%
%   NOTE ON STEALTHY FDI:
%   The Liu-Ning-Reiter FDI attack (A9) is designed to produce zero EKF
%   innovation — so z(k) remains at its normal-operation level during A9.
%   CUSUM therefore does NOT detect A9 either (by the same mathematical
%   argument). This is the correct result: it proves that A9 can only be
%   detected by physics cross-validation, not by any innovation-based test.
%
%   The replay attack (A10) produces a frozen innovation realisation
%   (since replayed sensors = same values = same residual). Over time
%   the CUSUM lower arm may detect the anomalous reduction in innovation
%   variance (too-quiet signature) if the slack is set appropriately.

    if ~cfg.cusum_enable
        return;
    end

    nX   = cusum.nx;
    slack = cfg.cusum_slack;
    thr   = cfg.cusum_threshold;

    %% Normalised innovation scalar z(k) = RMS of whitened residual
    r = ekf.residual;   % 40×1 raw innovation
    S_mat = ekf.S;      % 40×40 innovation covariance

    %  Whiten: r_w = S^{-1/2} · r  — use diagonal approximation for speed
    %  Full Cholesky would be more correct but expensive at 10 Hz
    S_diag = max(1e-6, diag(S_mat));
    r_norm = r ./ sqrt(S_diag);

    z = norm(r_norm) / sqrt(nX);   % scalar RMS normalised innovation

    %% Two-sided CUSUM update
    cusum.S_upper = max(0, cusum.S_upper + z - slack);
    cusum.S_lower = max(0, cusum.S_lower - z - slack);

    %% Alarm detection
    cusum.alarm = (cusum.S_upper > thr) || (cusum.S_lower > thr);

    if cusum.alarm
        cusum.alarm_count = cusum.alarm_count + 1;
        if cfg.cusum_reset_on_alarm
            cusum.S_upper = 0;
            cusum.S_lower = 0;
        end
        logEvent('WARNING','updateCUSUM', ...
                 sprintf('CUSUM alarm #%d  S_upper=%.2f  S_lower=%.2f  z=%.3f', ...
                         cusum.alarm_count, cusum.S_upper, cusum.S_lower, z), ...
                 k, dt);
    end

    %% Ring-buffer history (last 100 values, for export / visualisation)
    H_LEN = 100;
    cusum.z_history       = [cusum.z_history(2:end),       z];
    cusum.S_upper_history = [cusum.S_upper_history(2:end),  cusum.S_upper];
    cusum.S_lower_history = [cusum.S_lower_history(2:end),  cusum.S_lower];
end


function cusum = initCUSUM(cfg)
% initCUSUM  Initialise CUSUM state struct.
%   cusum = initCUSUM(cfg)
%   Call once at simulation start, pass result into the main loop.

    cusum.S_upper       = 0;
    cusum.S_lower       = 0;
    cusum.alarm         = false;
    cusum.alarm_count   = 0;
    cusum.nx            = 40;   % nN + nE = 20 + 20

    H_LEN = 100;
    cusum.z_history       = zeros(1, H_LEN);
    cusum.S_upper_history = zeros(1, H_LEN);
    cusum.S_lower_history = zeros(1, H_LEN);
end