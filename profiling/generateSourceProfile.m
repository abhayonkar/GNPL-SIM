function [src_p, demand] = generateSourceProfile(N, cfg)
% generateSourceProfile  Realistic time-varying source pressure and demand.
%
%   [src_p, demand] = generateSourceProfile(N, cfg)
%
%   All amplitude, period, and bound values come from cfg (simConfig).
%   This keeps the profile shape tunable without touching this function.

    dt = cfg.dt;
    t  = (0:N-1)' * dt;   % time vector (s)

    %% Source pressure --------------------------------------------------------
    slow_osc   = cfg.src_slow_amp * sin(2*pi*t / (22*60));
    med_osc    = cfg.src_med_amp  * sin(2*pi*t / (6*60) + 0.7);
    fast_pulse = cfg.src_fast_amp * sin(2*pi*t / 75     + 1.5);
    slow_trend = cfg.src_trend    * (t / t(end));

    % Correlated AR(1) random walk
    alpha = cfg.src_ar1_alpha;
    rw    = zeros(N, 1);
    for i = 2:N
        rw(i) = alpha * rw(i-1) + sqrt(1 - alpha^2) * randn();
    end
    sig_rw = std(rw);
    if sig_rw > 1e-9
        rw = cfg.src_rw_amp * rw / sig_rw;
    end

    src_p = cfg.p0 + slow_osc + med_osc + fast_pulse + slow_trend + rw;
    src_p = max(cfg.src_p_min, min(src_p, cfg.src_p_max));

    %% Demand profile ---------------------------------------------------------
    slow_dem = cfg.dem_slow_amp * sin(2*pi*t / (18*60) + 1.0);
    fast_dem = cfg.dem_fast_amp * sin(2*pi*t / (3*60)  + 0.3);

    % Discrete demand steps (large industrial consumers switching on/off)
    steps_def = [
         7*60,  0.025;
        19*60, -0.018;
        31*60,  0.031;
        44*60, -0.022;
        57*60,  0.019;
    ];
    step_sig = zeros(N, 1);
    for i = 1:size(steps_def, 1)
        k0 = max(1, min(N, round(steps_def(i,1) / dt)));
        step_sig(k0:end) = step_sig(k0:end) + steps_def(i,2);
    end

    dem_noise = cfg.dem_noise_std * randn(N, 1);
    demand    = cfg.dem_base + slow_dem + fast_dem + step_sig + dem_noise;
    demand    = max(cfg.dem_min, min(demand, cfg.dem_max));
end
