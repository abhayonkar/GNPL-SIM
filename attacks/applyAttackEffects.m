function [src_p_out, comp, plc, demand_out] = applyAttackEffects( ...
        aid, k, dt, schedule, src_p_in, comp, plc, demand_in, cfg)
% applyAttackEffects  Modify actuator state / source pressure / demand
%                     according to the currently active attack ID.
%
%   [src_p_out, comp, plc, demand_out] = applyAttackEffects(
%       aid, k, dt, schedule, src_p_in, comp, plc, demand_in, cfg)
%
% -----------------------------------------------------------------------
%  Attack catalogue
%   ID 1 - SrcPressureManipulation  (T0831)
%     Inflates source pressure: fast spike followed by sinusoidal oscillation.
%   ID 2 - CompressorRatioSpoofing  (T0838)
%     Ramps compressor ratio toward attacker target (1.85), bypasses PID.
%   ID 3 - ValveCommandTampering    (T0855)
%     Forces valve command to closed (0). PLC latency delays propagation.
%   ID 4 - DemandNodeManipulation   (T0829)
%     Ramps demand scalar up to 2.5x normal, simulating false consumer load.
%   ID 5 - PressureSensorSpoofing   (T0831) -- NOTE: sensor injection handled
%     in runSimulation (after sensor reading), so this function is a no-op.
%     Demand/comp/valve unchanged; sensor corruption is post-measurement.
%   ID 6 - FlowMeterSpoofing        (T0827) -- same note as ID 5.
%   ID 7 - PLCLatencyAttack         (T0814) -- handled in runSimulation loop.
%   ID 8 - PipelineLeak             (T0829) -- handled in runSimulation loop.
% -----------------------------------------------------------------------

    src_p_out  = src_p_in;
    demand_out = demand_in;

    % Helper: find attack window boundaries for a given ID
    function [k_s, k_e] = window(target_id)
        k_s = 1; k_e = 1;
        for ii = 1:schedule.nAttacks
            if schedule.ids(ii) == target_id
                k_s = max(1,   round(schedule.start_s(ii) / dt));
                k_e = min(numel(schedule.label_id), ...
                              round(schedule.end_s(ii)   / dt));
                return;
            end
        end
    end

    switch aid

        % ==============================================================
        case 1   % -- A1: Source Pressure Manipulation (T0831) ---------
        % Phase 1 (first 60 s): fast spike to +30% of nominal
        % Phase 2 (remainder): slow sinusoidal oscillation around +10%
        % ==============================================================
            [k_s, k_e] = window(1);
            if k >= k_s && k <= k_e
                elapsed = (k - k_s) * dt;
                t_spike = 60;   % spike phase duration (s)
                if elapsed < t_spike
                    % Exponential ramp up then partial decay
                    frac = elapsed / t_spike;
                    amp  = cfg.atk1_spike_amp - 1;          % e.g. 0.30
                    src_p_out = src_p_in * (1 + amp * sin(pi * frac));
                else
                    % Sustained oscillation at +/-15% around mean
                    osc = 0.15 * sin(2*pi * cfg.atk1_osc_freq * elapsed);
                    src_p_out = src_p_in * (1.10 + osc);
                end
                src_p_out = max(cfg.src_p_min, min(src_p_out, cfg.src_p_max + 2));
            end

        % ==============================================================
        case 2   % -- A2: Compressor Ratio Spoofing (T0838) ------------
        % Ramps ratio from current value toward atk2_target_ratio.
        % PID is bypassed for this attack in runSimulation.
        % ==============================================================
            [k_s, k_e] = window(2);
            if k >= k_s && k <= k_e
                elapsed  = (k - k_s) * dt;
                frac     = min(1, elapsed / cfg.atk2_ramp_time);
                r_start  = cfg.comp_ratio;     % nominal
                r_target = cfg.atk2_target_ratio;
                % Smooth ramp using sigmoid
                sig      = 1 / (1 + exp(-10*(frac - 0.5)));
                comp.ratio = r_start + (r_target - r_start) * sig;
                comp.ratio = max(comp.ratio_min, min(comp.ratio, comp.ratio_max));
            end

        % ==============================================================
        case 3   % -- A3: Valve Command Tampering (T0855) --------------
        % Toggles valve closed. Modelled as intermittent to simulate
        % partial control -- cycles closed/open every 90 s.
        % ==============================================================
            [k_s, ~] = window(3);
            if k >= k_s
                elapsed = (k - k_s) * dt;
                cycle   = 90;   % s -- on/off period
                if mod(floor(elapsed / cycle), 2) == 0
                    plc.act_valve_cmd = cfg.atk3_cmd;   % forced off
                % else: allow normal PLC to control -- creates asymmetry
                end
            end

        % ==============================================================
        case 4   % -- A4: Demand Node Manipulation (T0829) -------------
        % Ramps demand scale factor up to 2.5x over atk4_ramp_time,
        % then holds. Models fraudulent consumer load injection or
        % a compromised SCADA demand setpoint.
        % ==============================================================
            [k_s, k_e] = window(4);
            if k >= k_s && k <= k_e
                elapsed = (k - k_s) * dt;
                frac    = min(1, elapsed / cfg.atk4_ramp_time);
                scale   = 1 + (cfg.atk4_demand_scale - 1) * frac;
                demand_out = demand_in * scale;
                demand_out = min(demand_out, cfg.dem_max * 3);
            end

        % ==============================================================
        case {5, 6, 7, 8}
        % These attacks operate at the sensor / PLC / pipe layer.
        % Effects are injected in runSimulation after this function
        % returns, using applySensorSpoof / runSimulation logic.
        % No actuator modifications here.
        % ==============================================================

    end
end
