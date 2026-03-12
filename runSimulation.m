function [params, state, comp1, comp2, prs1, prs2, ekf, plc, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule)
% runSimulation  Main simulation loop for 20-node gas pipeline network.
%
%  Per-step sequence:
%    1.  Attack injection (A1-A4: actuator layer)
%    2.  Roughness drift AR(1)
%    3.  Flow turbulence AR(1)
%    4.  updateFlow    (Darcy-Weisbach + elevation + line pack)
%    5.  updateStorage (bidirectional storage)
%    6.  updatePressure (mass balance + acoustic noise)
%    7.  updateCompressor CS1 + CS2
%    8.  updatePRS PRS1 + PRS2
%    9.  updateTemperature (JT + thermal)
%   10.  updateDensity (Peng-Robinson)
%   11.  Sensor reading (multiplicative noise + floor)
%   12.  applySensorSpoof (A5/A6)
%   13.  updatePLC (zone-based polling)
%   14.  updateEKF
%   15.  updateControlLogic
%   16.  updateLogs
%   17.  detectIncidents
%   18.  Progress heartbeat

    dt = cfg.dt;

    if ~exist('automated_dataset', 'dir'), mkdir('automated_dataset'); end
    exec_fid = fopen(fullfile('automated_dataset','execution_details.log'), 'w');
    fprintf(exec_fid, '[INFO] Simulation started: %s\n', datestr(now));

    progress_interval = max(1, round(5*60 / dt));

    %% Persistent noise states
    turb_state     = zeros(params.nEdges, 1);
    p_acoustic     = zeros(params.nNodes, 1);
    T_turb         = zeros(params.nNodes, 1);
    rho_comp_state = 0;

    %% Valve states (3 valves: E8, E14, E15)
    valve_states = ones(numel(params.valveEdges), 1);

    logEvent('INFO', 'runSimulation', 'Entering main simulation loop', 0, dt);

    %% ================================================================
    for k = 1:N

        %% 1. Attack injection (A1-A4) --------------------------------
        aid = double(schedule.label_id(k));
        [src_p1_k, src_p2_k, comp1, comp2, plc, valve_states, demand_k] = ...
            applyAttackEffects(aid, k, dt, schedule, src_p1(k), src_p2(k), ...
                               comp1, comp2, plc, valve_states, demand(k), cfg);

        % Apply source pressures
        state.p(params.sourceNodes(1)) = src_p1_k;
        state.p(params.sourceNodes(2)) = src_p2_k;

        %% 2. Roughness drift AR(1) -----------------------------------
        a_r = cfg.rough_corr;
        sig_r = cfg.rough_var_std * cfg.pipe_rough * sqrt(1 - a_r^2);
        params.rough = a_r * params.rough + sig_r * randn(params.nEdges, 1);
        params.rough = max(1e-6, params.rough);

        %% 3. Flow turbulence AR(1) -----------------------------------
        a_t = cfg.flow_turb_corr;
        sig_t = cfg.flow_turb_std * sqrt(1 - a_t^2);
        turb_state = a_t * turb_state + ...
                     sig_t * abs(state.q + 1e-3) .* randn(params.nEdges, 1);
        params.turb_state = turb_state;

        %% 4. Flow update (Darcy-Weisbach + elevation + line pack) ----
        [state.q, state] = updateFlow(params, state, valve_states);

        %% 5. A8: Pipeline leak on edge ----------------------------------
        if aid == 8
            k_s8 = max(1, round(schedule.start_s(find(schedule.ids==8,1)) / dt));
            frac_leak = min(1, (k - k_s8)*dt / cfg.atk8_ramp_time);
            state.q(cfg.atk8_edge) = state.q(cfg.atk8_edge) * ...
                                     (1 - cfg.atk8_leak_frac * frac_leak);
        end

        %% 6. Storage (bidirectional) ----------------------------------
        q_sto = 0;
        [state, q_sto] = updateStorage(state, params, cfg);

        %% 7. Pressure update (mass balance + acoustic) ---------------
        demand_vec = zeros(params.nNodes, 1);
        demand_vec(params.demandNodes) = demand_k;
        p_prev = state.p;
        [state.p, p_acoustic] = updatePressure(params, state.p, state.q, ...
                                               demand_vec, p_acoustic, cfg);

        %% 8. Compressor stations CS1 and CS2 -------------------------
        [state, comp1] = updateCompressor(state, comp1, k, cfg, 1);
        [state, comp2] = updateCompressor(state, comp2, k, cfg, 2);

        %% 9. PRS1 and PRS2 -------------------------------------------
        [state, prs1] = updatePRS(state, prs1, cfg);
        [state, prs2] = updatePRS(state, prs2, cfg);

        %% 10. Temperature (JT + turbulent mixing) --------------------
        [state.Tgas, T_turb] = updateTemperature(params, state.Tgas, state.q, ...
                                                  p_prev, state.p, T_turb, cfg);

        %% 11. Density (Peng-Robinson) ---------------------------------
        [state.rho, rho_comp_state] = updateDensity(state.p, state.Tgas, ...
                                                     rho_comp_state, cfg);

        %% 12. Sensor readings (multiplicative + floor) ---------------
        nf = cfg.sensor_noise_floor;
        sensor_p = state.p + max(cfg.sensor_noise * abs(state.p), nf) .* ...
                   randn(params.nNodes, 1);
        sensor_q = state.q + max(cfg.sensor_noise * abs(state.q), nf) .* ...
                   randn(params.nEdges, 1);

        %% 13. A5/A6: Sensor spoofing (before PLC) --------------------
        [sensor_p, sensor_q] = applySensorSpoof(aid, k, dt, schedule, ...
                                                 sensor_p, sensor_q, cfg);

        %% 14. PLC polling (zone-based) -------------------------------
        if aid == 7
            plc_latency_eff = cfg.plc_latency + cfg.atk7_extra_latency;
            plc = updatePLCWithLatency(plc, sensor_p, sensor_q, k, plc_latency_eff, cfg);
        else
            plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
        end

        %% 15. EKF correction -----------------------------------------
        ekf = updateEKF(ekf, plc.reg_p, plc.reg_q, state.p, state.q);

        %% 16. Control logic ------------------------------------------
        if aid ~= 2   % bypass PID during compressor ratio spoofing
            [comp1, comp2, prs1, prs2, valve_states, plc] = ...
                updateControlLogic(comp1, comp2, prs1, prs2, valve_states, ...
                                   plc, ekf.xhatP, cfg, k, dt);
        else
            % Advance latency buffers without PID
            plc = advanceLatencyBuffers(plc);
        end

        %% 17. Log all state -----------------------------------------
        logs = updateLogs(logs, state, ekf, plc, comp1, comp2, prs1, prs2, ...
                          valve_states, params, k, sensor_p, sensor_q, ...
                          src_p1_k, src_p2_k, demand_k, q_sto);
        logs.logAttackId(k)   = aid;
        logs.logAttackName(k) = schedule.label_name(k);
        logs.logMitreId(k)    = schedule.label_mitre(k);

        %% 18. Incident detection ------------------------------------
        detectIncidents(cfg, params, state, ekf, comp1, comp2, plc, k, dt);

        %% 19. Progress heartbeat ------------------------------------
        if mod(k, progress_interval) == 0
            sim_min = k * dt / 60;
            fprintf('  [%.1f/%.0f min]  P_S1=%.1f bar  P_D1=%.1f bar  Atk=%d  Inv=%.2f\n', ...
                    sim_min, N*dt/60, state.p(1), state.p(15), aid, state.sto_inventory);
            fprintf(exec_fid, '[INFO] t=%.1fmin  aid=%d\n', sim_min, aid);
        end

    end % main loop

    fclose(exec_fid);
    logEvent('INFO','runSimulation','Main simulation loop complete', N, dt);
end

%% ===== LOCAL HELPERS =================================================

function plc = updatePLC(plc, sensor_p, sensor_q, k, cfg)
    if mod(k, cfg.plc_period_z1) == 0
        plc.reg_p = sensor_p;
        plc.reg_q = sensor_q;
    end
end

function plc = updatePLCWithLatency(plc, sensor_p, sensor_q, k, latency, cfg)
    if mod(k, cfg.plc_period_z1) == 0
        plc.reg_p = sensor_p;
        plc.reg_q = sensor_q;
    end
    pad = max(0, latency - length(plc.compRatio1Buf));
    if pad > 0
        plc.compRatio1Buf = [plc.compRatio1Buf, repmat(plc.act_comp1_ratio, 1, pad)];
        plc.compRatio2Buf = [plc.compRatio2Buf, repmat(plc.act_comp2_ratio, 1, pad)];
        plc.valveCmdBuf   = [plc.valveCmdBuf,   repmat(plc.act_valve_cmds, 1, pad)];
    end
    plc = advanceLatencyBuffers(plc);
end

function plc = advanceLatencyBuffers(plc)
    plc.compRatio1Buf  = [plc.compRatio1Buf(2:end),  plc.act_comp1_ratio];
    plc.compRatio2Buf  = [plc.compRatio2Buf(2:end),  plc.act_comp2_ratio];
    plc.valveCmdBuf    = [plc.valveCmdBuf(:,2:end),  plc.act_valve_cmds];
    plc.act_comp1_ratio = plc.compRatio1Buf(1);
    plc.act_comp2_ratio = plc.compRatio2Buf(1);
    plc.act_valve_cmds  = plc.valveCmdBuf(:,1);
end