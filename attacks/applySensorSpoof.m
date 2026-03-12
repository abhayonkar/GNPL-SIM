function [sensor_p, sensor_q] = applySensorSpoof( ...
        aid, k, dt, schedule, sensor_p, sensor_q, cfg)
% applySensorSpoof  Corrupt sensor readings for A5 (pressure) and A6 (flow).
%
%   Called in runSimulation AFTER physical sensor noise is added but
%   BEFORE the PLC receives the readings.  This models a man-in-the-middle
%   attack on the field-bus / historian layer.
%
%   A5 - Pressure sensor at J2 receives a constant negative bias, making
%        the PLC believe pressure is low -> compressor increases ratio ->
%        real pressure overshoots -> EKF residuals spike.
%
%   A6 - Flow meters on E2 and E3 are scaled down, making the PLC
%        believe flow is lower than real -> valve opens wider ->
%        branch imbalance and pressure gradient forms.

    function [k_s, k_e] = window(target_id)
        k_s = 1; k_e = 1;
        for ii = 1:schedule.nAttacks
            if schedule.ids(ii) == target_id
                k_s = max(1, round(schedule.start_s(ii) / dt));
                k_e = min(numel(schedule.label_id), ...
                              round(schedule.end_s(ii) / dt));
                return;
            end
        end
    end

    switch aid

        case 5   % -- A5: Pressure Sensor Spoofing (T0831) -------
            [k_s, k_e] = window(5);
            if k >= k_s && k <= k_e
                n = cfg.atk5_target_node;   % J2 = 3
                % Linear ramp over first 30 s, then hold at full bias
                elapsed = (k - k_s) * dt;
                frac    = min(1, elapsed / 30);
                sensor_p(n) = sensor_p(n) + frac * cfg.atk5_bias_bar;
                % Floor to avoid physically impossible negative readings
                sensor_p(n) = max(0.1, sensor_p(n));
            end

        case 6   % -- A6: Flow Meter Spoofing (T0827) ------------
            [k_s, k_e] = window(6);
            if k >= k_s && k <= k_e
                for e = cfg.atk6_edges
                    elapsed = (k - k_s) * dt;
                    frac    = min(1, elapsed / 45);   % 45s ramp
                    % Interpolate between real and spoofed
                    spoof = sensor_q(e) * cfg.atk6_scale;
                    sensor_q(e) = sensor_q(e) * (1 - frac) + spoof * frac;
                end
            end
    end
end
