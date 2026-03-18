function [params, state, comp1, comp2, prs1, prs2, ekf, plc, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule)
% runSimulation  Main simulation loop — runs at full CPU speed.
%
%  TIMING MODEL:
%    Physics advances dt = 0.1 s per step regardless of wall time.
%    No pause(), no sleep(), no real-time pacing of any kind.
%    Logging fires every cfg.log_every steps (e.g. every 10 steps = 1 Hz
%    dataset rows for a 10 Hz physics simulation).
%    Gateway exchange fires at the same cadence as logging (once per row).
%    A 100-min simulation completes in ~seconds of wall time.
%
%  Per-step sequence:
%    1.  Attack injection (A1-A4)
%    2.  Roughness drift AR(1)
%    3.  Flow turbulence AR(1)
%    4.  updateFlow    (Darcy-Weisbach + elevation + line pack)
%    5.  updateStorage
%    6.  updatePressure
%    7.  updateCompressor CS1 + CS2
%    8.  updatePRS PRS1 + PRS2
%    9.  updateTemperature
%   10.  updateDensity (Peng-Robinson)
%   11.  Sensor reading
%   12.  applySensorSpoof (A5/A6)
%   13.  updatePLC
%   14.  updateEKF
%   15.  updateControlLogic
%   16.  detectIncidents
%   17.  [every log_every steps] gateway exchange + write dataset row
%   18.  Progress heartbeat (every 5 simulated minutes)

    dt        = cfg.dt;
    log_every = max(1, cfg.log_every);

    if ~exist('automated_dataset', 'dir'), mkdir('automated_dataset'); end
    exec_fid = fopen(fullfile('automated_dataset','execution_details.log'), 'w');
    fprintf(exec_fid, '[INFO] Started: %s  N=%d  log_every=%d  N_log=%d\n', ...
            datestr(now), N, log_every, floor(N/log_every));

    progress_interval = max(1, round(5*60 / dt));   % heartbeat every 5 sim-min
    use_gw   = isfield(cfg, 'use_gateway') && cfg.use_gateway;

    %% Persistent noise states
    turb_state     = zeros(params.nEdges, 1);
    p_acoustic     = zeros(params.nNodes, 1);
    T_turb         = zeros(params.nNodes, 1);
    rho_comp_state = 0;
    valve_states   = ones(numel(params.valveEdges), 1);

    gw_state = initGatewayState();
    log_k    = 0;
    wall_t0  = tic;

    logEvent('INFO', 'runSimulation', ...
             sprintf('Loop start  N=%d  log_every=%d  N_log=%d', ...
                     N, log_every, floor(N/log_every)), 0, dt);

    %% ================================================================
    for k = 1:N

        %% 1. Attack injection
        aid = double(schedule.label_id(k));
        [src_p1_k, src_p2_k, comp1, comp2, plc, valve_states, demand_k] = ...
            applyAttackEffects(aid, k, dt, schedule, src_p1(k), src_p2(k), ...
                               comp1, comp2, plc, valve_states, demand(k), cfg);
        state.p(params.sourceNodes(1)) = src_p1_k;
        state.p(params.sourceNodes(2)) = src_p2_k;

        %% 2. Roughness AR(1)
        a_r = cfg.rough_corr;
        sig_r = cfg.rough_var_std * cfg.pipe_rough * sqrt(1 - a_r^2);
        params.rough = a_r * params.rough + sig_r * randn(params.nEdges, 1);
        params.rough = max(1e-6, params.rough);

        %% 3. Flow turbulence AR(1)
        a_t = cfg.flow_turb_corr;
        sig_t = cfg.flow_turb_std * sqrt(1 - a_t^2);
        turb_state = a_t * turb_state + ...
                     sig_t * abs(state.q + 1e-3) .* randn(params.nEdges, 1);
        params.turb_state = turb_state;

        %% 4. Flow
        [state.q, state] = updateFlow(params, state, valve_states);

        %% 5. A8 pipeline leak
        if aid == 8
            k_s8 = max(1, round(schedule.start_s(find(schedule.ids==8,1)) / dt));
            frac_leak = min(1, (k - k_s8)*dt / cfg.atk8_ramp_time);
            state.q(cfg.atk8_edge) = state.q(cfg.atk8_edge) * ...
                                     (1 - cfg.atk8_leak_frac * frac_leak);
        end

        %% 6. Storage
        q_sto = 0;
        [state, q_sto] = updateStorage(state, params, cfg);

        %% 7. Pressure
        demand_vec = zeros(params.nNodes, 1);
        demand_vec(params.demandNodes) = demand_k;
        p_prev = state.p;
        [state.p, p_acoustic] = updatePressure(params, state.p, state.q, ...
                                               demand_vec, p_acoustic, cfg);

        %% 8. Compressors
        [state, comp1] = updateCompressor(state, comp1, k, cfg, 1);
        [state, comp2] = updateCompressor(state, comp2, k, cfg, 2);

        %% 9. PRS
        [state, prs1] = updatePRS(state, prs1, cfg);
        [state, prs2] = updatePRS(state, prs2, cfg);

        %% 10. Temperature
        [state.Tgas, T_turb] = updateTemperature(params, state.Tgas, state.q, ...
                                                  p_prev, state.p, T_turb, cfg);

        %% 11. Density (Peng-Robinson)
        [state.rho, rho_comp_state] = updateDensity(state.p, state.Tgas, ...
                                                     rho_comp_state, cfg);

        %% 12. Sensor readings
        nf = cfg.sensor_noise_floor;
        sensor_p = state.p + max(cfg.sensor_noise * abs(state.p), nf) .* ...
                   randn(params.nNodes, 1);
        sensor_q = state.q + max(cfg.sensor_noise * abs(state.q), nf) .* ...
                   randn(params.nEdges, 1);

        %% 13. Sensor spoof (A5/A6)
        [sensor_p, sensor_q] = applySensorSpoof(aid, k, dt, schedule, ...
                                                 sensor_p, sensor_q, cfg);

        %% 14. PLC polling
        if aid == 7
            plc = updatePLCWithLatency(plc, sensor_p, sensor_q, k, ...
                                       cfg.plc_latency + cfg.atk7_extra_latency, cfg);
        else
            plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
        end

        %% 15. EKF
        ekf = updateEKF(ekf, plc.reg_p, plc.reg_q, state.p, state.q);

        %% 16. Control logic
        if aid ~= 2
            [comp1, comp2, prs1, prs2, valve_states, plc] = ...
                updateControlLogic(comp1, comp2, prs1, prs2, valve_states, ...
                                   plc, ekf.xhatP, cfg, k, dt);
        else
            plc = advanceLatencyBuffers(plc);
        end

        %% 17. Incident detection
        detectIncidents(cfg, params, state, ekf, comp1, comp2, plc, k, dt);

        %% 18. Log row + gateway — every log_every steps only ─────────────
        if mod(k, log_every) == 0

            %% Gateway: once per logged row (not every physics step)
            if use_gw
                gw_out.p             = sensor_p;
                gw_out.q             = sensor_q;
                gw_out.T             = state.Tgas;
                gw_out.demand_scalar = demand_k;
                sendToGateway(cfg, gw_out);
                gw_state = receiveFromGateway(cfg, gw_state);
                if gw_state.updated
                    comp1.ratio     = max(comp1.ratio_min, min(comp1.ratio_max, gw_state.cs1_ratio));
                    comp2.ratio     = max(comp2.ratio_min, min(comp2.ratio_max, gw_state.cs2_ratio));
                    valve_states(1) = gw_state.valve_E8;
                    valve_states(2) = gw_state.valve_E14;
                    valve_states(3) = gw_state.valve_E15;
                end
            end

            %% Write dataset row
            log_k = log_k + 1;
            if log_k <= size(logs.logP, 2)
                logs = updateLogs(logs, state, ekf, plc, comp1, comp2, prs1, prs2, ...
                                  valve_states, params, log_k, sensor_p, sensor_q, ...
                                  src_p1_k, src_p2_k, demand_k, q_sto);
                logs.logAttackId(log_k)   = aid;
                logs.logAttackName(log_k) = schedule.label_name(k);
                logs.logMitreId(log_k)    = schedule.label_mitre(k);
            end
        end

        %% 19. Progress heartbeat (every 5 simulated minutes)
        if mod(k, progress_interval) == 0
            sim_min = k * dt / 60;
            wall_s  = toc(wall_t0);
            fprintf('  [sim %5.1f / %3.0f min]  wall %6.1fs  P_S1=%.1f  P_D1=%.1f  Atk=%d  Rows=%d\n', ...
                    sim_min, N*dt/60, wall_s, state.p(1), state.p(15), aid, log_k);
            fprintf(exec_fid, '[INFO] t=%.1fmin  wall=%.1fs  aid=%d  rows=%d\n', ...
                    sim_min, wall_s, aid, log_k);
        end

    end % main loop

    wall_total = toc(wall_t0);
    fclose(exec_fid);
    logEvent('INFO','runSimulation', ...
             sprintf('Done: %d steps  %d rows  %.1fs wall  %.0fx faster than real-time', ...
                     N, log_k, wall_total, (N*dt)/wall_total), N, dt);
end

%% ===== LOCAL HELPERS =====================================================

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
    plc.compRatio1Buf   = [plc.compRatio1Buf(2:end),  plc.act_comp1_ratio];
    plc.compRatio2Buf   = [plc.compRatio2Buf(2:end),  plc.act_comp2_ratio];
    plc.valveCmdBuf     = [plc.valveCmdBuf(:,2:end),  plc.act_valve_cmds];
    plc.act_comp1_ratio = plc.compRatio1Buf(1);
    plc.act_comp2_ratio = plc.compRatio2Buf(1);
    plc.act_valve_cmds  = plc.valveCmdBuf(:,1);
end