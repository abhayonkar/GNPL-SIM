function [sensor_p_out, sensor_q_out] = applySensorSpoof( ...
        aid, k, dt, schedule, sensor_p, sensor_q, cfg, ekf, replay_buf)
% applySensorSpoof  Apply post-measurement sensor manipulation attacks.
%
%   [sensor_p_out, sensor_q_out] = applySensorSpoof(
%       aid, k, dt, schedule, sensor_p, sensor_q, cfg, ekf, replay_buf)
%
%   Called AFTER sensor noise is added, BEFORE ADC quantisation.
%   Routes each attack to its specific implementation:
%
%   A5 — PressureSensorSpoofing:
%        Additive bias on target pressure node. Simple but detectable by EKF.
%
%   A6 — FlowMeterSpoofing:
%        Multiplicative scaling on target flow edges. Creates mass imbalance
%        detectable by Darcy-Weisbach cross-validation.
%
%   A9 — Stealthy FDI (Liu-Ning-Reiter):
%        a = H*c with H=I. Zero EKF residual by construction.
%        Implemented in computeFDIVector.m.
%        Requires ekf argument.
%
%   A10 — Replay Attack (Mo & Sinopoli):
%        Replace all sensor channels with pre-recorded buffer content.
%        Implemented in applyReplayAttack.m.
%        Requires replay_buf argument.
%
%   IMPORTANT: A9 and A10 are applied to sensor readings BEFORE ADC
%   quantisation in runSimulation.m — this is the correct order because
%   real attackers inject into the communication layer after the ADC.

    sensor_p_out = sensor_p;
    sensor_q_out = sensor_q;

    switch aid

        case 5   % A5: Pressure sensor bias on target node
            if nargin >= 7 && isfield(cfg, 'atk5_target_node')
                k_start = find_attack_start(schedule, 5);
                frac    = min(1, (k - k_start) * dt / 30);   % 30s ramp
                sensor_p_out(cfg.atk5_target_node) = ...
                    sensor_p(cfg.atk5_target_node) + cfg.atk5_bias_bar * frac;
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
                k_local  = k - k_start;   % steps since this attack started
                [a_p, a_q, ~] = computeFDIVector(ekf, cfg, k_local, dt);
                sensor_p_out = sensor_p + a_p;
                sensor_q_out = sensor_q + a_q;
            end

        case 10  % A10: Replay attack — frozen noise realisation
            % replay_buf is managed externally in runSimulation.m
            % This case is a no-op here; replay is applied directly in
            % runSimulation via applyReplayAttack() before this function.
            % Included for completeness in the aid routing table.

    end
end

% ── helper ────────────────────────────────────────────────────────────────

function k_start = find_attack_start(schedule, target_aid)
% Return the physics step at which the given attack ID starts.
    idx = find(schedule.ids == target_aid, 1);
    if isempty(idx)
        k_start = 0;
    else
        k_start = max(1, find(schedule.label_id == target_aid, 1));
    end
end