function [params, state, comp1, comp2, prs1, prs2, ekf, plc, logs] = runSimulation( ...
        cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
        N, src_p1, src_p2, demand, schedule)
% runSimulation  Phase 5 main loop — full speed, no pacing.
%
%  PHASE 5 ADDITIONS vs previous version:
%
%  1. ADC QUANTISATION (R2)
%     quantiseADC() applied to sensor_p and sensor_q after noise + spoof.
%     Platform selected by cfg.adc_platform ('codesys' or 's7_1200').
%     Effect: staircase distributions replace continuous sensor readings.
%
%  2. STEALTHY FDI A9 (R1)
%     computeFDIVector() called inside applySensorSpoof for aid==9.
%     Constructs a = H*c with H=I, guaranteeing zero EKF residual.
%     ekf struct passed into applySensorSpoof so FDI vector uses
%     current state estimate as bias anchor.
%
%  3. REPLAY ATTACK A10 (R4 / #5)
%     applyReplayAttack() manages a rolling ring buffer of T_buf_steps.
%     Pre-attack: every step writes live sensor readings into the buffer.
%     Attack active: all sensor channels replaced with buffered content.
%     k_attack counter tracks steps elapsed since attack onset.
%
%  4. SCAN-CYCLE JITTER (R3)
%     addScanJitter() generates per-platform timestamp offsets.
%     Stored in logs.logTimestamp_ms (millisecond-resolution timestamps).
%     Does not affect physics — purely a dataset realism feature.
%
%  Per-step sequence:
%    1.  Attack injection (A1–A4, A7, A8 via applyAttackEffects)
%    2.  Roughness drift AR(1)
%    3.  Flow turbulence AR(1)
%    4.  updateFlow
%    5.  A8 pipeline leak
%    6.  updateStorage
%    7.  updatePressure
%    8.  updateCompressor CS1 + CS2
%    9.  updatePRS
%   10.  updateTemperature
%   11.  updateDensity (Peng-Robinson)
%   12.  Sensor readings (multiplicative noise)
%   13.  A10 replay buffer write / channel substitution  [PHASE 5]
%   14.  applySensorSpoof (A5, A6, A9-FDI)              [PHASE 5: A9]
%   15.  quantiseADC — pressure + flow                  [PHASE 5]
%   16.  updatePLC
%   17.  updateEKF
%   18.  updateControlLogic
%   19.  detectIncidents
%   20.  [every log_every] gateway + log row + jitter   [PHASE 5: jitter]

    dt        = cfg.dt;
    log_every = max(1, cfg.log_every);
    use_gw    = isfield(cfg, 'use_gateway') && cfg.use_gateway;

    if ~exist('automated_dataset', 'dir'), mkdir('automated_dataset'); end
    exec_fid = fopen(fullfile('automated_dataset','execution_details.log'), 'w');
    fprintf(exec_fid, '[INFO] Started: %s  N=%d  log_every=%d  N_log=%d\n', ...
            datestr(now), N, log_every, floor(N/log_every));
    fprintf(exec_fid, '[INFO] ADC: %s (%s)  Jitter: %s (%s)\n', ...
            mat2str(cfg.adc_enable), cfg.adc_platform, ...
            mat2str(cfg.jitter_enable), cfg.jitter_platform);

    progress_interval = max(1, round(5*60 / dt));

    %% Persistent noise states
    turb_state     = zeros(params.nEdges, 1);
    p_acoustic     = zeros(params.nNodes, 1);
    T_turb         = zeros(params.nNodes, 1);
    rho_comp_state = 0;
    valve_states   = ones(numel(params.valveEdges), 1);

    %% Phase 5 state objects
    replay_buf  = initReplayBuffer(params.nNodes, params.nEdges, cfg);
    jitter_buf  = initJitterBuffer();
    gw_state    = initGatewayState();

    log_k = 0;
    wall_t0 = tic;

    %% Track replay attack onset per aid==10 window
    replay_k_attack = 0;   % steps elapsed since A10 onset
    prev_aid        = 0;

    logEvent('INFO','runSimulation', ...
             sprintf('Phase 5 loop: N=%d  log_every=%d  ADC=%s  Jitter=%s', ...
                     N, log_every, cfg.adc_platform, cfg.jitter_platform), 0, dt);

    %% ================================================================
    for k = 1:N

        %% 1. Attack injection (A1–A4, A7, A8)
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

        %% 11. Density (Peng-Robinson EOS)
        [state.rho, rho_comp_state] = updateDensity(state.p, state.Tgas, ...
                                                     rho_comp_state, cfg);

        %% 12. Raw sensor readings (multiplicative noise + floor)
        nf = cfg.sensor_noise_floor;
        sensor_p = state.p + max(cfg.sensor_noise * abs(state.p), nf) .* ...
                   randn(params.nNodes, 1);
        sensor_q = state.q + max(cfg.sensor_noise * abs(state.q), nf) .* ...
                   randn(params.nEdges, 1);

        %% 13. A10 REPLAY ATTACK — buffer write / channel substitution ──────
        %  Track k_attack: steps elapsed since the current A10 window started.
        %  Reset to 0 whenever we're not in A10.
        if aid == 10
            if prev_aid ~= 10
                replay_k_attack = 0;   % just entered attack window
            else
                replay_k_attack = replay_k_attack + 1;
            end
            [sensor_p, sensor_q, replay_buf] = applyReplayAttack( ...
                sensor_p, sensor_q, replay_buf, replay_k_attack, cfg);
        else
            replay_k_attack = 0;
            % Pre-attack: always keep writing to buffer so it's ready
            [~, ~, replay_buf] = applyReplayAttack( ...
                sensor_p, sensor_q, replay_buf, -1, cfg);
        end
        prev_aid = aid;

        %% 14. SENSOR SPOOFING: A5, A6, A9 (FDI) ────────────────────────────
        %  A9 uses ekf.xhatP as the bias anchor — pass ekf struct.
        [sensor_p, sensor_q] = applySensorSpoof( ...
            aid, k, dt, schedule, sensor_p, sensor_q, cfg, ekf, replay_buf);

        %% 15. ADC QUANTISATION ──────────────────────────────────────────────
        %  Applied after spoofing, before PLC register update.
        %  This matches the real signal chain: transmitter → ADC → register.
        if cfg.adc_enable
            sensor_p = quantiseADC(sensor_p, cfg.adc_p_full_scale, cfg);
            sensor_q = quantiseADC(abs(sensor_q), cfg.adc_q_full_scale, cfg) .* sign(sensor_q);
        end

        %% 16. PLC polling
        if aid == 7
            plc = updatePLCWithLatency(plc, sensor_p, sensor_q, k, ...
                                       cfg.plc_latency + cfg.atk7_extra_latency, cfg);
        else
            plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
        end

        %% 17. EKF
        ekf = updateEKF(ekf, plc.reg_p, plc.reg_q, state.p, state.q);

        %% 18. Control logic
        if aid ~= 2
            [comp1, comp2, prs1, prs2, valve_states, plc] = ...
                updateControlLogic(comp1, comp2, prs1, prs2, valve_states, ...
                                   plc, ekf.xhatP, cfg, k, dt);
        else
            plc = advanceLatencyBuffers(plc);
        end

        %% 19. Incident detection
        detectIncidents(cfg, params, state, ekf, comp1, comp2, plc, k, dt);

        %% 20. Log row + gateway — every log_every steps ───────────────────
        if mod(k, log_every) == 0

            %% Gateway exchange (1 Hz when log_every=10, dt=0.1)
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

            %% Scan-cycle jitter timestamp (R3)
            log_dt_s = cfg.dt * log_every;
            [jitter_ms, jitter_buf] = addScanJitter(log_dt_s, cfg, jitter_buf);

            %% Write dataset row
            log_k = log_k + 1;
            if log_k <= size(logs.logP, 2)
                logs = updateLogs(logs, state, ekf, plc, comp1, comp2, prs1, prs2, ...
                                  valve_states, params, log_k, sensor_p, sensor_q, ...
                                  src_p1_k, src_p2_k, demand_k, q_sto);
                logs.logAttackId(log_k)   = aid;
                logs.logAttackName(log_k) = schedule.label_name(k);
                logs.logMitreId(log_k)    = schedule.label_mitre(k);

                %% Store jitter offset (ms) — added to nominal timestamp in export
                if isfield(logs, 'logJitter_ms')
                    logs.logJitter_ms(log_k) = jitter_ms;
                end
            end
        end

        %% 21. Progress heartbeat (every 5 simulated minutes)
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
             sprintf('Done: %d steps  %d rows  %.1fs wall  %.0fx real-time', ...
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