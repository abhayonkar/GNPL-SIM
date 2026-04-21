function [sensor_p_out, sensor_q_out] = applySensorSpoof( ...
        aid, k, dt, schedule, sensor_p, sensor_q, cfg, ekf, replay_buf)
% applySensorSpoof  Apply post-measurement sensor manipulation attacks.
%
%   Routes each attack to its implementation:
%   A5 — PressureSensorSpoofing: bias + sinusoidal oscillation (atk5_osc_amp/freq)
%   A6 — FlowMeterSpoofing: multiplicative scaling on target edges
%   A9 — Stealthy FDI: a=H*c, zero EKF residual by construction
%   A10 — Replay: no-op here; handled in runSimulation via applyReplayAttack

    sensor_p_out = sensor_p;
    sensor_q_out = sensor_q;

    switch aid

        case 5   % A5: Pressure sensor bias + oscillation on target node
            if nargin >= 7 && isfield(cfg, 'atk5_target_node')
                k_start  = find_attack_start(schedule, 5);
                elapsed  = (k - k_start) * dt;

                % 30-second linear ramp-in
                frac    = min(1, elapsed / 30);

                % Base bias
                bias = cfg.atk5_bias_bar * frac;

                % Sinusoidal oscillation component (NEW)
                if isfield(cfg, 'atk5_osc_amp') && isfield(cfg, 'atk5_osc_freq')
                    osc = cfg.atk5_osc_amp * frac * sin(2*pi * cfg.atk5_osc_freq * elapsed);
                else
                    osc = 0;
                end

                sensor_p_out(cfg.atk5_target_node) = ...
                    sensor_p(cfg.atk5_target_node) + bias + osc;
            end

        case 6   % A6: Flow meter scaling on target edges
            if nargin >= 7 && isfield(cfg, 'atk6_edges')
                for ei = 1:numel(cfg.atk6_edges)
                    e = cfg.atk6_edges(ei);
                    if e >= 1 && e <= numel(sensor_q_out)
                        sensor_q_out(e) = sensor_q(e) * cfg.atk6_scale;
                    end
                end
            end

        case 9   % A9: Stealthy FDI — zero EKF residual
            if nargin >= 8 && ~isempty(ekf)
                k_start  = find_attack_start(schedule, 9);
                k_local  = k - k_start;
                [a_p, a_q, ~] = computeFDIVector(ekf, cfg, k_local, dt);
                sensor_p_out = sensor_p + a_p;
                sensor_q_out = sensor_q + a_q;
            end

        case 10  % A10: no-op — handled externally via applyReplayAttack

    end
end

% ── helper ────────────────────────────────────────────────────────────────

function k_start = find_attack_start(schedule, target_aid)
    idx = find(schedule.ids == target_aid, 1);
    if isempty(idx)
        k_start = 0;
    else
        k_start = max(1, find(schedule.label_id == target_aid, 1));
    end
end
