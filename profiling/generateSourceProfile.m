function src_p = generateSourceProfile(N, cfg)
% generateSourceProfile  Generate realistic source pressure profile for N steps.
%
%   src_p = generateSourceProfile(N, cfg)
%
%   Returns an N×1 vector of source pressure values (bar) for node S1.
%   Uses cfg fields defined in simConfig.m:
%     cfg.src_slow_amp    bar — slow oscillation amplitude (~22 min cycle)
%     cfg.src_med_amp     bar — medium oscillation amplitude (~6 min cycle)
%     cfg.src_fast_amp    bar — fast oscillation amplitude (~75 s cycle)
%     cfg.src_trend       bar — linear drift over full simulation
%     cfg.src_rw_amp      bar — AR(1) random walk amplitude
%     cfg.src_ar1_alpha       — AR(1) correlation coefficient
%     cfg.src_p_min       bar — lower clamp
%     cfg.src_p_max       bar — upper clamp
%     cfg.p0              bar — nominal/initial pressure
%     cfg.dt              s   — time step

    dt   = cfg.dt;
    t    = (0:N-1)' * dt;   % time vector (s)

    % ── Deterministic components ──────────────────────────────────────────
    % Slow oscillation (~22 min industrial demand cycle)
    slow = cfg.src_slow_amp * sin(2*pi*t / (22*60));

    % Medium oscillation (~6 min compressor surge cycle)
    med  = cfg.src_med_amp  * sin(2*pi*t / (6*60) + 0.7);

    % Fast oscillation (~75 s blade-pass / acoustic)
    fast = cfg.src_fast_amp * sin(2*pi*t / 75 + 1.3);

    % Linear trend (slow drift over full simulation)
    T_total = N * dt;
    trend   = cfg.src_trend * (t / T_total - 0.5);   % centred ±src_trend/2

    % ── Diurnal demand-driven variation ───────────────────────────────────
    % Morning peak (07:00) and evening peak (18:00) create source pressure
    % swings as demand pulls pressure down at delivery nodes
    hour_of_day = mod(t / 3600, 24);
    morning     = exp(-0.5 * ((hour_of_day - 7)  / 1.5).^2);
    evening     = exp(-0.5 * ((hour_of_day - 18) / 1.5).^2);
    diurnal     = -cfg.dem_diurnal_amp * 8 * (morning + evening);
    % (negative: high demand pulls source pressure down)

    % ── AR(1) stochastic component ────────────────────────────────────────
    rw        = zeros(N, 1);
    alpha     = cfg.src_ar1_alpha;
    sig_rw    = cfg.src_rw_amp * sqrt(1 - alpha^2);
    for k = 2:N
        rw(k) = alpha * rw(k-1) + sig_rw * randn();
    end

    % ── Compose ───────────────────────────────────────────────────────────
    src_p = cfg.p0 + slow + med + fast + trend + diurnal + rw;

    % ── Clamp to physical bounds ──────────────────────────────────────────
    src_p = max(cfg.src_p_min, min(cfg.src_p_max, src_p));
end