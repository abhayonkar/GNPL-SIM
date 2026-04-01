function [t_jitter_ms, jitter_buf] = addScanJitter(log_dt_s, cfg, jitter_buf)
% addScanJitter  Simulate per-platform scan-cycle timing jitter.
%
%   [t_jitter_ms, jitter_buf] = addScanJitter(log_dt_s, cfg, jitter_buf)
%
%   WHY THIS MATTERS:
%   ─────────────────
%   Real SCADA polling intervals are not perfectly uniform. Each platform
%   has a characteristic jitter distribution that is an established IDS
%   feature for:
%     • Detecting man-in-the-middle injection (injected packets break the
%       periodic pattern)
%     • Hardware fingerprinting (CODESYS vs S7-1200 are distinguishable
%       by their inter-arrival time distributions)
%     • Detecting replay attacks (replayed traffic has artificially
%       uniform timing compared to genuine PLC polling)
%
%   PLATFORM PROFILES:
%   ──────────────────
%   'codesys' on Windows (soft-PLC):
%     Windows is not a real-time OS. The CODESYS runtime task scheduler
%     competes with other Windows threads. This produces a broad Gaussian
%     jitter with std ≈ 20 ms and occasional spikes to 150+ ms when the
%     OS preempts the CODESYS task. The distribution is approximately:
%       jitter ~ N(0, 20ms) with exponential tail for preemption spikes
%
%   's7_1200' (hardware PLC):
%     The S7-1200 runs a deterministic real-time kernel with hardware
%     task preemption. Jitter is very tight:
%       jitter ~ N(0, 1.5ms) with rare outliers at <10 ms
%
%   IMPLEMENTATION:
%   ───────────────
%   A truncated Gaussian is used for the base jitter, plus an occasional
%   large spike drawn from an exponential distribution (for OS preemption
%   modelling in the CODESYS case). An AR(1) process with coefficient 0.3
%   introduces mild serial correlation — consecutive polls tend to be
%   slightly fast or slow together, matching real SCADA traces.
%
%   INPUTS:
%     log_dt_s   — nominal log timestep in seconds (e.g. 1.0)
%     cfg        — simulation config (jitter parameters from Section 17)
%     jitter_buf — persistent state struct (AR1 state + spike cooldown)
%
%   OUTPUTS:
%     t_jitter_ms — jitter offset in milliseconds (can be negative)
%                   Add to nominal timestamp: t_actual = t_nominal + t_jitter_ms/1000
%     jitter_buf  — updated state struct

    if ~cfg.jitter_enable
        t_jitter_ms = 0;
        return;
    end

    %% Select platform parameters
    switch lower(cfg.jitter_platform)
        case 's7_1200'
            sigma_ms = cfg.jitter_s7_std_ms;
            max_ms   = cfg.jitter_s7_max_ms;
            spike_p  = 0.002;    % 0.2% chance of a hardware watchdog event
            spike_scale_ms = 5;
        otherwise   % 'codesys'
            sigma_ms = cfg.jitter_codesys_std_ms;
            max_ms   = cfg.jitter_codesys_max_ms;
            spike_p  = 0.01;     % 1% chance of OS preemption spike
            spike_scale_ms = 50; % exponential scale for spike magnitude
    end

    %% AR(1) base jitter (mild serial correlation)
    ar1_alpha = 0.30;
    base_noise = sigma_ms * randn();
    jitter_buf.ar1_state = ar1_alpha * jitter_buf.ar1_state + ...
                           sqrt(1 - ar1_alpha^2) * base_noise;

    %% Occasional spike (OS preemption / hardware event)
    if rand() < spike_p
        spike = -spike_scale_ms * log(rand());   % exponential tail (no toolbox)
        spike = min(spike, max_ms);
    else
        spike = 0;
    end

    %% Total jitter
    t_jitter_ms = jitter_buf.ar1_state + spike;

    %% Clamp to [-max_ms, +max_ms]
    t_jitter_ms = max(-max_ms, min(max_ms, t_jitter_ms));
end


function jitter_buf = initJitterBuffer()
% initJitterBuffer  Initialise persistent jitter state.
%   Call once at simulation start.

    jitter_buf.ar1_state = 0;
end