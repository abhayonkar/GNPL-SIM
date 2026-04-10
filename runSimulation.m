function [params, state, comp1, comp2, prs1, prs2, ekf, plc, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule)
% runSimulation  Phase 6 main loop — full CPU speed, no pacing.
%
%  NEW IN PHASE 6:
%    — Physics F Jacobian in updateEKF (params + cfg now passed)
%    — CUSUM detector running alongside EKF chi-squared test
%    — Zone-based PLC polling via standalone updatePLC.m (z1/z2/z3)
%    — Fault injection: packet loss + stuck sensor (applyFaultInjection)
%    — Deadband historian updated every step (updateHistorian)
%    — FAULT_ID column added to logs alongside ATTACK_ID
%
%  Per-step sequence:
%    1.  Attack injection (A1–A4, A7, A8)
%    2.  Roughness + turbulence AR(1)
%    3.  updateFlow
%    4.  A8 leak
%    5.  updateStorage
%    6.  updatePressure
%    7.  updateCompressor CS1+CS2
%    8.  updatePRS
%    9.  updateTemperature
%   10.  updateDensity (PR-EOS)
%   11.  Sensor readings (noise)
%   12.  A10 replay buffer
%   13.  applySensorSpoof (A5, A6, A9-FDI)
%   14.  ADC quantisation
%   15.  applyFaultInjection (packet loss / stuck)   ← Phase 6
%   16.  updatePLC  (zone-based z1/z2/z3)            ← Phase 6
%   17.  updateEKF  (physics F Jacobian)             ← Phase 6
%   18.  updateCUSUM                                 ← Phase 6
%   19.  updateControlLogic
%   20.  updateHistorian                             ← Phase 6
%   21.  detectIncidents
%   22.  [every log_every] gateway + log row + jitter

    dt        = cfg.dt;
    log_every = max(1, cfg.log_every);
    use_gw    = isfield(cfg,'use_gateway') && cfg.use_gateway;

    if ~exist('automated_dataset','dir'), mkdir('automated_dataset'); end
    exec_fid = fopen(fullfile('automated_dataset','execution_details.log'),'w');
    fprintf(exec_fid,'[INFO] Phase 6 start: %s\n', datestr(now));

    progress_interval = max(1, round(5*60/dt));

    %% State objects
    turb_state     = zeros(params.nEdges,1);
    p_acoustic     = zeros(params.nNodes,1);
    T_turb         = zeros(params.nNodes,1);
    rho_comp_state = 0;
    valve_states   = ones(numel(params.valveEdges),1);

    replay_buf = initReplayBuffer(params.nNodes, params.nEdges, cfg);
    jitter_buf = initJitterBuffer();
    gw_state   = initGatewayState();
    cusum      = initCUSUM(cfg);
    hist       = initHistorian(params, cfg);
    fault      = initFaultState(params.nNodes, params.nEdges, cfg);

    log_k           = 0;
    replay_k_attack = 0;
    prev_aid        = 0;
    wall_t0         = tic;
    demand_vec      = zeros(params.nNodes, 1);   % initialised here; updated each step at §6

    logEvent('INFO','runSimulation', ...
             sprintf('Phase 6 start: N=%d  log_every=%d  N_log=%d', ...
                     N, log_every, floor(N/log_every)), 0, dt);

    %% ================================================================
    for k = 1:N

        %% 1. Attack injection
        aid = double(schedule.label_id(k));
        [src_p1_k,src_p2_k,comp1,comp2,plc,valve_states,demand_k] = ...
            applyAttackEffects(aid,k,dt,schedule,src_p1(k),src_p2(k), ...
                               comp1,comp2,plc,valve_states,demand(k),cfg);
        state.p(params.sourceNodes(1)) = src_p1_k;
        state.p(params.sourceNodes(2)) = src_p2_k;

        %% 2. Roughness + turbulence AR(1)
        a_r = cfg.rough_corr;
        sig_r = cfg.rough_var_std * cfg.pipe_rough * sqrt(1-a_r^2);
        params.rough = max(1e-6, a_r*params.rough + sig_r*randn(params.nEdges,1));
        a_t = cfg.flow_turb_corr;
        sig_t = cfg.flow_turb_std * sqrt(1-a_t^2);
        turb_state = a_t*turb_state + sig_t*abs(state.q+1e-3).*randn(params.nEdges,1);
        params.turb_state = turb_state;

        %% 3. Flow
        [state.q, dp] = updateFlow(cfg, state.p, demand_vec);
        %% 4. A8 leak
        if aid == 8
            k_s8 = max(1, round(schedule.start_s(find(schedule.ids==8,1))/dt));
            frac_leak = min(1, (k-k_s8)*dt/cfg.atk8_ramp_time);
            state.q(cfg.atk8_edge) = state.q(cfg.atk8_edge) * (1-cfg.atk8_leak_frac*frac_leak);
        end

        %% 5. Storage
        q_sto = 0;
        [state, q_sto] = updateStorage(state, params, cfg);

        %% 6. Pressure
        demand_vec = zeros(params.nNodes,1);
        demand_vec(params.demandNodes) = demand_k;
        p_prev = state.p;
        [state.p, p_acoustic] = updatePressure(params, state.p, state.q, ...
                                               demand_vec, p_acoustic, cfg);

        %% 7. Compressors
        [state, comp1] = updateCompressor(state, comp1, k, cfg, 1);
        [state, comp2] = updateCompressor(state, comp2, k, cfg, 2);

        %% 8. PRS
        [state, prs1] = updatePRS(state, prs1, cfg);
        [state, prs2] = updatePRS(state, prs2, cfg);

        %% 9. Temperature
        [state.Tgas, T_turb] = updateTemperature(params, state.Tgas, state.q, ...
                                                  p_prev, state.p, T_turb, cfg);

        %% 10. Density (PR-EOS)
        [state.rho, rho_comp_state] = updateDensity(state.p, state.Tgas, ...
                                                     rho_comp_state, cfg);

        %% 11. Sensor readings (multiplicative noise)
        nf = cfg.sensor_noise_floor;
        sensor_p = state.p + max(cfg.sensor_noise*abs(state.p),nf).*randn(params.nNodes,1);
        sensor_q = state.q + max(cfg.sensor_noise*abs(state.q),nf).*randn(params.nEdges,1);

        %% 12. A10 replay buffer
        if aid == 10
            if prev_aid ~= 10, replay_k_attack = 0;
            else,               replay_k_attack = replay_k_attack + 1; end
            [sensor_p,sensor_q,replay_buf] = applyReplayAttack( ...
                sensor_p,sensor_q,replay_buf,replay_k_attack,cfg);
        else
            replay_k_attack = 0;
            [~,~,replay_buf] = applyReplayAttack(sensor_p,sensor_q,replay_buf,-1,cfg);
        end
        prev_aid = aid;

        %% 13. Sensor spoof (A5, A6, A9-FDI)
        [sensor_p,sensor_q] = applySensorSpoof( ...
            aid,k,dt,schedule,sensor_p,sensor_q,cfg,ekf,replay_buf);

        %% 14. ADC quantisation
        if cfg.adc_enable
            sensor_p = quantiseADC(sensor_p, cfg.adc_p_full_scale, cfg);
            sensor_q = quantiseADC(abs(sensor_q),cfg.adc_q_full_scale,cfg).*sign(sensor_q);
        end

        %% 15. Fault injection (packet loss / stuck sensor) ─────── Phase 6
        [sensor_p, sensor_q, fault, fault_label] = applyFaultInjection( ...
            sensor_p, sensor_q, fault, k, dt, cfg);

        %% 16. Zone-based PLC polling ────────────────────────────── Phase 6
        if aid == 7
            plc = updatePLCWithLatency(plc,sensor_p,sensor_q,k, ...
                                       cfg.plc_latency+cfg.atk7_extra_latency,cfg);
        else
            plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
        end

        %% 17. EKF with physics Jacobian ─────────────────────────── Phase 6
        ekf = updateEKF(ekf, plc.reg_p, plc.reg_q, state.p, state.q, params, cfg);

        %% 18. CUSUM detector ────────────────────────────────────── Phase 6
        cusum = updateCUSUM(cusum, ekf.residual, cfg, k);

        %% 19. Control logic
        if aid ~= 2
            [comp1,comp2,prs1,prs2,valve_states,plc] = ...
                updateControlLogic(comp1,comp2,prs1,prs2,valve_states, ...
                                   plc,ekf.xhatP,cfg,k,dt);
        else
            plc = advanceLatencyBuffers(plc);
        end

        %% 20. Historian ─────────────────────────────────────────── Phase 6
        hist = updateHistorian(hist, state, plc, aid, k, dt, cfg, params);

        %% 21. Incident detection
        detectIncidents(cfg, params, state, ekf, comp1, comp2, plc, k, dt);

        %% 22. Log row + gateway — every log_every steps ──────────────────
        if mod(k, log_every) == 0

            if use_gw
                gw_out.p=sensor_p; gw_out.q=sensor_q;
                gw_out.T=state.Tgas; gw_out.demand_scalar=demand_k;
                sendToGateway(cfg, gw_out);
                gw_state = receiveFromGateway(cfg, gw_state);
                if gw_state.updated
                    comp1.ratio     = max(comp1.ratio_min,min(comp1.ratio_max,gw_state.cs1_ratio));
                    comp2.ratio     = max(comp2.ratio_min,min(comp2.ratio_max,gw_state.cs2_ratio));
                    valve_states(1) = gw_state.valve_E8;
                    valve_states(2) = gw_state.valve_E14;
                    valve_states(3) = gw_state.valve_E15;
                end
            end

            log_dt_s = cfg.dt * log_every;
            [jitter_ms, jitter_buf] = addScanJitter(log_dt_s, cfg, jitter_buf);

            log_k = log_k + 1;
            if log_k <= size(logs.logP,2)
                logs = updateLogs(logs,state,ekf,plc,comp1,comp2,prs1,prs2, ...
                                  valve_states,params,log_k,sensor_p,sensor_q, ...
                                  src_p1_k,src_p2_k,demand_k,q_sto);
                logs.logAttackId(log_k)   = aid;
                logs.logAttackName(log_k) = schedule.label_name(k);
                logs.logMitreId(log_k)    = schedule.label_mitre(k);
                if isfield(logs,'logFaultId')
                    logs.logFaultId(log_k) = fault_label;
                end
                if isfield(logs,'logJitter_ms')
                    logs.logJitter_ms(log_k) = jitter_ms;
                end
                if isfield(logs,'logCUSUM_upper')
                    logs.logCUSUM_upper(log_k) = cusum.S_upper;
                    logs.logCUSUM_lower(log_k) = cusum.S_lower;
                    logs.logCUSUM_alarm(log_k) = cusum.alarm;
                end
                if isfield(logs,'logChi2')
                    logs.logChi2(log_k)      = ekf.chi2_stat;
                    logs.logChi2_alarm(log_k) = ekf.chi2_alarm;
                end
            end
        end

        %% 23. Progress heartbeat
        if mod(k, progress_interval) == 0
            sim_min = k*dt/60;
            wall_s  = toc(wall_t0);
            fprintf('  [sim %5.1f / %3.0f min]  wall %6.1fs  P_S1=%.1f  P_D1=%.1f  Atk=%d  Fault=%d  Rows=%d\n', ...
                    sim_min, N*dt/60, wall_s, state.p(1), state.p(15), aid, fault_label, log_k);
            fprintf(exec_fid,'[INFO] t=%.1fmin  wall=%.1fs  aid=%d  fault=%d  rows=%d\n', ...
                    sim_min, wall_s, aid, fault_label, log_k);
        end

    end % main loop

    wall_total = toc(wall_t0);
    fclose(exec_fid);

    %% Export historian at simulation end
    exportHistorian(hist, 'automated_dataset');

    logEvent('INFO','runSimulation', ...
             sprintf('Done: %d steps  %d rows  %.1fs wall  %.0fx real-time  historian=%d events', ...
                     N, log_k, wall_total, (N*dt)/wall_total, hist.row_count), N, dt);
end

%% ===== LOCAL HELPERS =====================================================

function plc = updatePLCWithLatency(plc, sensor_p, sensor_q, k, latency, cfg)
    plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
    pad = max(0, latency - length(plc.compRatio1Buf));
    if pad > 0
        plc.compRatio1Buf = [plc.compRatio1Buf, repmat(plc.act_comp1_ratio,1,pad)];
        plc.compRatio2Buf = [plc.compRatio2Buf, repmat(plc.act_comp2_ratio,1,pad)];
        plc.valveCmdBuf   = [plc.valveCmdBuf,   repmat(plc.act_valve_cmds,1,pad)];
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