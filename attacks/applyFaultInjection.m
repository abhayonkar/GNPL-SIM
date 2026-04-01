function [sensor_p_out, sensor_q_out, fault, fault_label] = applyFaultInjection( ...
        sensor_p, sensor_q, fault, k, dt, cfg)
% applyFaultInjection  Simulate communication faults: packet loss + stuck sensor.
%
%   [sensor_p_out, sensor_q_out, fault, fault_label] = applyFaultInjection(
%       sensor_p, sensor_q, fault, k, dt, cfg)
%
%   MOTIVATION:
%   ────────────
%   Real SCADA communication is not perfectly reliable. Two common faults
%   produce sensor reading anomalies that an IDS must distinguish from
%   cyberattacks:
%
%   1. PACKET LOSS — the sensor value fails to reach the PLC in a given
%      scan cycle. The PLC register retains its last-known value (zero-order
%      hold). Indistinguishable from a slow-changing sensor in a single
%      step but accumulates a lag signature over consecutive drops.
%      Label: FAULT_ID = 1
%
%   2. STUCK SENSOR — the field transmitter hardware freezes at its last
%      valid output. The flat-line signature is a distinctive IDS feature:
%      variance drops to zero while physics continues to evolve.
%      Duration follows an exponential distribution (memoryless hardware
%      fault model). Affects only the nodes in cfg.fault_stuck_nodes
%      (sensors more likely to fail due to high-vibration installation).
%      Label: FAULT_ID = 2
%
%   FAULT LABELS (fault_label):
%     0 — no fault
%     1 — packet loss (this step)
%     2 — stuck sensor (currently active)
%
%   FAULT STRUCT FIELDS:
%     fault.last_p         — last known good pressure values (20×1)
%     fault.last_q         — last known good flow values (20×1)
%     fault.stuck_active   — boolean (20×1): node is currently stuck
%     fault.stuck_rem      — remaining stuck steps per node (20×1)
%     fault.consec_drops   — consecutive packet drop counter per node
%
%   NOTE: Faults are applied AFTER noise and AFTER attacks (applySensorSpoof).
%   This correctly models the signal chain: physics → ADC → communication.

    sensor_p_out = sensor_p;
    sensor_q_out = sensor_q;
    fault_label  = 0;   % 0 = no fault

    if ~cfg.fault_enable
        return;
    end

    nN = numel(sensor_p);

    %% ── STUCK SENSOR ─────────────────────────────────────────────────────
    %  Check if new stuck events start this step
    for i = 1:numel(cfg.fault_stuck_nodes)
        n = cfg.fault_stuck_nodes(i);
        if n < 1 || n > nN, continue; end

        if ~fault.stuck_active(n)
            % Bernoulli trial: does this sensor get stuck this step?
            if rand() < cfg.fault_stuck_prob
                dur_steps = round(-cfg.fault_stuck_dur_s / dt * log(rand()));
                dur_steps = max(1, dur_steps);
                fault.stuck_active(n) = true;
                fault.stuck_rem(n)    = dur_steps;
                logEvent('INFO','applyFaultInjection', ...
                         sprintf('Stuck sensor: node %d  dur=%.0fs', ...
                                 n, dur_steps*dt), k, dt);
            end
        end
    end

    %  Apply stuck sensor: freeze at last valid reading
    any_stuck = false;
    for n = 1:nN
        if fault.stuck_active(n)
            sensor_p_out(n)   = fault.last_p(n);   % frozen value
            fault.stuck_rem(n) = fault.stuck_rem(n) - 1;
            any_stuck = true;
            if fault.stuck_rem(n) <= 0
                fault.stuck_active(n) = false;
                fault.stuck_rem(n)    = 0;
            end
        else
            fault.last_p(n) = sensor_p(n);   % update last-known-good
        end
    end
    for e = 1:numel(sensor_q)
        fault.last_q(e) = sensor_q(e);   % flows don't get stuck in this model
    end

    if any_stuck
        fault_label = 2;
        return;   % stuck takes priority over packet loss label
    end

    %% ── PACKET LOSS ──────────────────────────────────────────────────────
    %  Single Bernoulli trial for the entire scan cycle
    %  (models loss of a complete Modbus TCP frame, not per-register)
    if rand() < cfg.fault_loss_prob
        % Retain last-known-good values in PLC registers
        % Here we simulate by passing back last values
        sensor_p_out = fault.last_p;
        sensor_q_out = fault.last_q;
        fault_label  = 1;

        % Track consecutive drops
        fault.consec_drops = fault.consec_drops + 1;
        if fault.consec_drops >= cfg.fault_max_consec
            logEvent('WARNING','applyFaultInjection', ...
                     sprintf('Comms failure: %d consecutive packet drops', ...
                             fault.consec_drops), k, dt);
        end
    else
        fault.consec_drops = 0;
        fault.last_p = sensor_p;
        fault.last_q = sensor_q;
    end
end


function fault = initFaultState(nN, nE, cfg)
% initFaultState  Initialise fault injection state struct.
%   fault = initFaultState(nN, nE, cfg)
%   Call once at simulation start.

    fault.last_p       = cfg.p0 * ones(nN, 1);
    fault.last_q       = zeros(nE, 1);
    fault.stuck_active = false(nN, 1);
    fault.stuck_rem    = zeros(nN, 1);
    fault.consec_drops = 0;
end