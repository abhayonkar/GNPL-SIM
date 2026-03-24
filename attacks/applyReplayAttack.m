function [sensor_p_out, sensor_q_out, buf] = applyReplayAttack( ...
        sensor_p, sensor_q, buf, k_attack, cfg)
% applyReplayAttack  Rolling-buffer replay attack (Mo & Sinopoli 2009).
%
%   [sensor_p_out, sensor_q_out, buf] = applyReplayAttack(
%       sensor_p, sensor_q, buf, k_attack, cfg)
%
%   THEORY (Mo & Sinopoli, Allerton 2009):
%   ────────────────────────────────────────
%   The attacker records T_buf seconds of sensor data during normal
%   operation, then replays those pre-recorded values while simultaneously
%   driving the physical process with malicious actuator commands.
%
%   ALL correlated sensor channels are replaced simultaneously.
%   Partial replacement (e.g. only some pressure nodes) is detectable via
%   cross-channel inconsistency with unaffected meters — a full-channel
%   replacement is the stealthy formulation.
%
%   DETECTION SIGNATURES (what makes this scientifically interesting):
%     1. Frozen noise realisation: the same noise vector repeats with
%        period T_buf. Detectable via sample autocorrelation at lag T_buf.
%     2. Cross-channel inconsistency: replayed pressures are inconsistent
%        with live flow meters (if flows are not replayed) — detectable
%        via physics cross-validation (Darcy-Weisbach residual).
%     3. Step discontinuities at attack start/end boundaries.
%     4. Temporal correlation anomaly in EKF innovation sequence.
%
%   BUFFER STRUCTURE:
%     buf.p_buf   — [nN × T_buf_steps] ring buffer of pressure readings
%     buf.q_buf   — [nE × T_buf_steps] ring buffer of flow readings
%     buf.write_idx — current write position in the ring (1-based)
%     buf.filled    — true once the buffer has been written at least once
%     buf.read_idx  — current replay read position (only used in attack)
%
%   MODES (cfg.atk10_inject_mode):
%     'loop'   — replay buffer cyclically for the full attack duration
%     'single' — replay buffer once then hold the last value
%
%   INPUTS:
%     sensor_p   — 20×1 current pressure sensor readings (bar)
%     sensor_q   — 20×1 current flow sensor readings (kg/s)
%     buf        — replay buffer struct (see initReplayBuffer)
%     k_attack   — steps elapsed since attack start (0 = pre-attack)
%     cfg        — simulation config (uses cfg.atk10_buffer_s, cfg.dt)
%
%   OUTPUTS:
%     sensor_p_out — 20×1 (replayed if attack active, live otherwise)
%     sensor_q_out — 20×1 (replayed if attack active, live otherwise)
%     buf          — updated buffer struct

    T_buf_steps = max(1, round(cfg.atk10_buffer_s / cfg.dt));

    if k_attack <= 0
        %% ── PRE-ATTACK: write live readings into the rolling buffer ──────
        buf.write_idx = mod(buf.write_idx, T_buf_steps) + 1;
        buf.p_buf(:, buf.write_idx) = sensor_p;
        buf.q_buf(:, buf.write_idx) = sensor_q;

        if buf.write_idx == T_buf_steps
            buf.filled = true;   % buffer has been filled at least once
        end

        sensor_p_out = sensor_p;
        sensor_q_out = sensor_q;

    else
        %% ── ATTACK ACTIVE: replay from buffer ────────────────────────────
        if ~buf.filled
            % Buffer not yet full — fall back to live readings
            % (attack started before T_buf seconds of data recorded)
            sensor_p_out = sensor_p;
            sensor_q_out = sensor_q;
            logEvent('WARNING','applyReplayAttack', ...
                     'Replay buffer not yet filled — using live readings', 0, cfg.dt);
            return;
        end

        switch lower(cfg.atk10_inject_mode)
            case 'loop'
                % Cycle through the buffer repeatedly
                % read_idx advances from the oldest entry forward
                replay_step = mod(k_attack - 1, T_buf_steps) + 1;
                % Oldest entry in the ring buffer:
                oldest_idx  = mod(buf.write_idx, T_buf_steps) + 1;
                % Index into buffer at replay_step offset from oldest
                read_idx    = mod(oldest_idx + replay_step - 2, T_buf_steps) + 1;

            case 'single'
                % Replay buffer once then hold last value
                replay_step = min(k_attack, T_buf_steps);
                oldest_idx  = mod(buf.write_idx, T_buf_steps) + 1;
                read_idx    = mod(oldest_idx + replay_step - 2, T_buf_steps) + 1;

            otherwise
                read_idx = buf.write_idx;   % fallback: hold last value
        end

        sensor_p_out = buf.p_buf(:, read_idx);
        sensor_q_out = buf.q_buf(:, read_idx);

        % Continue writing live readings to buffer (attacker keeps recording)
        buf.write_idx = mod(buf.write_idx, T_buf_steps) + 1;
        buf.p_buf(:, buf.write_idx) = sensor_p;
        buf.q_buf(:, buf.write_idx) = sensor_q;
    end
end


function buf = initReplayBuffer(nN, nE, cfg)
% initReplayBuffer  Allocate the replay buffer struct.
%
%   buf = initReplayBuffer(nN, nE, cfg)
%
%   Called once at simulation start. The buffer is pre-filled with zeros;
%   the 'filled' flag ensures replay does not start until T_buf seconds
%   of real data has been recorded.

    T_buf_steps   = max(1, round(cfg.atk10_buffer_s / cfg.dt));
    buf.p_buf     = zeros(nN, T_buf_steps);
    buf.q_buf     = zeros(nE, T_buf_steps);
    buf.write_idx = 0;
    buf.filled    = false;
    buf.read_idx  = 1;
end