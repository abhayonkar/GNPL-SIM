function [src_p1_out, src_p2_out, comp1, comp2, plc, valve_states, demand_out] = ...
        applyAttackEffects(aid, k, dt, schedule, src_p1_in, src_p2_in, ...
                           comp1, comp2, plc, valve_states, demand_in, cfg)
% applyAttackEffects  Modify actuator state / source pressures / demand
%                     according to the currently active attack ID.
%
%   [src_p1_out, src_p2_out, comp1, comp2, plc, valve_states, demand_out] =
%       applyAttackEffects(aid, k, dt, schedule,
%                          src_p1_in, src_p2_in,
%                          comp1, comp2, plc, valve_states,
%                          demand_in, cfg)
%
%   Inputs  (12):
%     aid          – active attack ID (scalar uint8, 0 = Normal)
%     k            – current step index
%     dt           – simulation time step (s)
%     schedule     – attack schedule struct
%     src_p1_in    – source node S1 pressure this step (bar)
%     src_p2_in    – source node S2 pressure this step (bar)
%     comp1        – CS1 struct
%     comp2        – CS2 struct
%     plc          – PLC / SCADA struct
%     valve_states – [3×1] valve position vector (E8, E14, E15)
%     demand_in    – demand scalar this step
%     cfg          – configuration struct
%
%   Outputs (7):
%     src_p1_out   – (possibly modified) S1 pressure
%     src_p2_out   – (possibly modified) S2 pressure
%     comp1        – (possibly modified) CS1 struct
%     comp2        – (possibly modified) CS2 struct (pass-through unless A2)
%     plc          – (possibly modified) PLC struct
%     valve_states – (possibly modified) valve position vector
%     demand_out   – (possibly modified) demand scalar
%
% -----------------------------------------------------------------------
%  Attack catalogue
%   A1 SrcPressureManipulation  T0831  – inflates S1 source pressure
%   A2 CompressorRatioSpoofing  T0838  – ramps CS1 ratio toward target
%   A3 ValveCommandTampering    T0855  – forces valve_states(1) closed
%   A4 DemandNodeManipulation   T0829  – ramps demand scalar to 2.5×
%   A5 PressureSensorSpoofing   T0831  – sensor layer, handled post-measurement
%   A6 FlowMeterSpoofing        T0827  – sensor layer, handled post-measurement
%   A7 PLCLatencyAttack         T0814  – handled in runSimulation loop
%   A8 PipelineLeak             T0829  – handled in runSimulation loop
% -----------------------------------------------------------------------

    src_p1_out = src_p1_in;
    src_p2_out = src_p2_in;
    demand_out = demand_in;

    % Helper: find step boundaries for a given attack ID
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

        % ==============================================================
        case 1   % A1: Source Pressure Manipulation (T0831) -----------
        %   Phase 1 (first 60 s): exponential spike to +30% of nominal.
        %   Phase 2 (remainder):  sinusoidal oscillation around +10%.
        %   Only S1 is manipulated; S2 is passed through unchanged.
        % ==============================================================
            [k_s, k_e] = window(1);
            if k >= k_s && k <= k_e
                elapsed = (k - k_s) * dt;
                t_spike = 60;
                if elapsed < t_spike
                    frac      = elapsed / t_spike;
                    amp       = cfg.atk1_spike_amp - 1;      % e.g. 0.30
                    src_p1_out = src_p1_in * (1 + amp * sin(pi * frac));
                else
                    osc        = 0.15 * sin(2*pi * cfg.atk1_osc_freq * elapsed);
                    src_p1_out = src_p1_in * (1.10 + osc);
                end
                src_p1_out = max(cfg.src_p_min, min(src_p1_out, cfg.src_p_max + 2));
            end

        % ==============================================================
        case 2   % A2: Compressor Ratio Spoofing (T0838) --------------
        %   Ramps CS1 ratio from nominal toward atk2_target_ratio via
        %   sigmoid. PID is bypassed in runSimulation for this attack.
        %   CS2 is left unchanged (spoofing targets CS1 only).
        % ==============================================================
            [k_s, k_e] = window(2);
            if k >= k_s && k <= k_e
                elapsed  = (k - k_s) * dt;
                frac     = min(1, elapsed / cfg.atk2_ramp_time);
                r_start  = cfg.comp1_ratio;
                r_target = cfg.atk2_target_ratio;
                sig      = 1 / (1 + exp(-10*(frac - 0.5)));
                comp1.ratio = r_start + (r_target - r_start) * sig;
                comp1.ratio = max(comp1.ratio_min, min(comp1.ratio, comp1.ratio_max));
            end

        % ==============================================================
        case 3   % A3: Valve Command Tampering (T0855) ----------------
        %   Toggles valve E8 (valve_states index 1) closed every 90 s.
        %   Intermittent cycling creates asymmetric control disruption.
        %   valve_states = [E8, E14, E15]; only index 1 is tampered.
        % ==============================================================
            [k_s, ~] = window(3);
            if k >= k_s
                elapsed = (k - k_s) * dt;
                cycle   = 90;   % on/off period (s)
                if mod(floor(elapsed / cycle), 2) == 0
                    valve_states(1) = cfg.atk3_cmd;   % force E8 closed/open
                end
            end

        % ==============================================================
        case 4   % A4: Demand Node Manipulation (T0829) ---------------
        %   Ramps demand scale factor to atk4_demand_scale (2.5×) over
        %   atk4_ramp_time seconds, then holds. Models compromised SCADA
        %   demand setpoint or fraudulent consumer load injection.
        % ==============================================================
            [k_s, k_e] = window(4);
            if k >= k_s && k <= k_e
                elapsed    = (k - k_s) * dt;
                frac       = min(1, elapsed / cfg.atk4_ramp_time);
                scale      = 1 + (cfg.atk4_demand_scale - 1) * frac;
                demand_out = demand_in * scale;
                demand_out = min(demand_out, cfg.dem_max * 3);
            end

        % ==============================================================
        case {5, 6, 7, 8}
        % Sensor / PLC / pipe-layer attacks — all outputs pass through
        % unchanged. Effects are injected in runSimulation after this
        % call returns, via applySensorSpoof / inline loop logic.
        % ==============================================================

    end
end