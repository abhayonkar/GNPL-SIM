%% run_attack_windows.m
% =========================================================================
%  Indian CGD Gas Pipeline — Windowed Attack Dataset Generator
% =========================================================================
%
%  DATASET DESIGN RATIONALE:
%  ─────────────────────────
%  A continuous 48h attack dataset is ML-poor because the pipeline
%  stabilises between attacks and the classifier learns steady-state
%  not disruption. This script generates datasets with EXPLICIT
%  Normal → Attack → Recovery windows per scenario, providing:
%
%    1. Clear attack ONSET transients (most discriminating signal)
%    2. Physical RESPONSE dynamics (pressure cascade, EKF residual spike)
%    3. Natural RECOVERY (compressors compensate, PRS adjusts)
%    4. Correct LABELS including recovery_phase column
%
%  Each scenario follows the pattern:
%
%    [NORMAL 2-4h] → [ATTACK 5-20min] → [RECOVERY 1-2h]
%
%  BUGS FIXED vs previous version:
%    FIX 1: build_stub_schedule() was called INSIDE the N-step loop (twice)
%            but it itself loops over all N steps → O(N²) complexity.
%            For a 6h scenario at 10Hz: N=216,000 → 46 billion ops → hang.
%            Fixed by building schedule ONCE before the loop.
%    FIX 2: apply_cgd_overrides was defined as a local function with OLD
%            wrong values (flow_turb_std=0.005 instead of 5.0, etc.).
%            Local functions shadow the external corrected file.
%            Fixed by removing the local definition entirely — the
%            standalone config/apply_cgd_overrides.m is used instead.
%    FIX 3: A7 latency if/else block did the same thing in both branches.
%            Fixed to call updatePLCWithLatency for A7, updatePLC otherwise.
%
%  USAGE:
%    >> run_attack_windows()                       % 5 scenarios × 10 attacks
%    >> run_attack_windows('n_scenarios', 20)      % 20 scenarios
%    >> run_attack_windows('attack_ids', [1 5 8])  % specific attacks only
%    >> run_attack_windows('window_dur_h', 8)      % 8h per scenario window
%
%  REQUIRES on MATLAB path:
%    config/apply_cgd_overrides.m  (standalone — NOT defined locally here)
%
% =========================================================================

function run_attack_windows(varargin)

    ap = inputParser();
    addParameter(ap, 'n_scenarios',  5);
    addParameter(ap, 'attack_ids',   1:10);
    addParameter(ap, 'window_dur_h', 6);
    addParameter(ap, 'normal_h',     2.0);
    addParameter(ap, 'attack_min',   15);
    addParameter(ap, 'recovery_h',   1.5);
    addParameter(ap, 'out_dir',      'automated_dataset/attack_windows');
    addParameter(ap, 'gateway',      false);
    parse(ap, varargin{:});
    opt = ap.Results;

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling','processing');

    if ~exist(opt.out_dir, 'dir'), mkdir(opt.out_dir); end

    cfg = simConfig();
    cfg = apply_cgd_overrides(cfg);   % uses external config/apply_cgd_overrides.m

    dt        = cfg.dt;
    log_every = cfg.log_every;

    fprintf('\n=================================================================\n');
    fprintf('  Indian CGD Pipeline — Attack Window Dataset Generator\n');
    fprintf('  Attacks   : %s\n', mat2str(opt.attack_ids));
    fprintf('  Scenarios : %d per attack type (%d total)\n', ...
            opt.n_scenarios, opt.n_scenarios * numel(opt.attack_ids));
    fprintf('  Window    : %.1fh  (%.0fm normal + %dmin attack + %.1fh recovery)\n', ...
            opt.window_dur_h, opt.normal_h*60, opt.attack_min, opt.recovery_h);
    fprintf('  Output    : %s\n', opt.out_dir);
    fprintf('=================================================================\n\n');

    csv_path      = fullfile(opt.out_dir, 'physics_dataset_windows.csv');
    manifest_path = fullfile(opt.out_dir, 'scenario_manifest.csv');

    csv_fid = -1;
    man_fid = fopen(manifest_path, 'w');
    fprintf(man_fid, 'scenario_id,attack_id,attack_name,attack_start_s,attack_end_s,recovery_end_s,n_rows\n');

    scenario_id = 0;
    total_rows  = 0;

    atk_names = {'SourceSpike','CompRamp','ValveForce','DemandInject', ...
                 'PressureSpoof','FlowSpoof','PLCLatency','PipeLeak', ...
                 'FDI_Stealthy','ReplayAttack'};

    for atk = opt.attack_ids(:)'
        for rep = 1:opt.n_scenarios
            scenario_id = scenario_id + 1;

            fprintf('[scenario %d] attack=%d  rep=%d/%d\n', ...
                    scenario_id, atk, rep, opt.n_scenarios);

            % Build timing for this scenario
            normal_s   = (opt.normal_h * 3600) * (0.8 + 0.4*rand());
            attack_s   = opt.attack_min * 60;
            recovery_s = opt.recovery_h * 3600;
            total_s    = normal_s + attack_s + recovery_s;
            N          = round(total_s / dt);

            k_atk_start = round(normal_s / dt);
            k_atk_end   = k_atk_start + round(attack_s / dt);
            k_rec_end   = k_atk_end + round(recovery_s / dt);

            % Build per-step label arrays
            label_id       = zeros(N, 1, 'int32');
            label_id(k_atk_start:k_atk_end) = int32(atk);

            recovery_phase = zeros(N, 1, 'int32');
            recovery_phase(k_atk_end+1:min(k_rec_end, N)) = int32(1);

            attack_start_flag = zeros(N, 1, 'int32');
            if k_atk_start <= N, attack_start_flag(k_atk_start) = int32(1); end

            recovery_start_flag = zeros(N, 1, 'int32');
            if k_atk_end+1 <= N, recovery_start_flag(k_atk_end+1) = int32(1); end

            % ── FIX 1: Build schedule ONCE, before the loop ───────────────
            % Old code called build_stub_schedule(label_id, N, dt) INSIDE
            % the loop on every step → O(N²). This is the fix.
            schedule = build_stub_schedule(label_id, N, dt);

            % Initialise simulation state (fresh per scenario)
            [params, state] = initNetwork(cfg);
            [comp1, comp2]  = initCompressor(cfg);
            [prs1, prs2]    = initPRS(cfg);
            initValve(cfg);
            plc        = initPLC(cfg, state, comp1);
            ekf        = initEKF(cfg, state);
            cusum      = initCUSUM(cfg);
            fault      = initFaultState(params.nNodes, params.nEdges, cfg);
            replay_buf = initReplayBuffer(params.nNodes, params.nEdges, cfg);
            jitter_buf = initJitterBuffer(); %#ok<NASGU>

            valve_states   = ones(numel(params.valveEdges), 1);
            p_acoustic     = zeros(params.nNodes, 1);
            T_turb         = zeros(params.nNodes, 1);
            rho_comp_state = 0;
            turb_state     = zeros(params.nEdges, 1); %#ok<NASGU>
            demand_vec     = zeros(params.nNodes, 1);
            prev_aid       = 0;
            replay_k       = 0;
            fault_label    = 0;
            q_sto          = 0;

            src_p1 = generateSourceProfile(N, cfg);
            cfg_s2 = cfg;
            cfg_s2.p0        = 0.5*(cfg.src2_p_min + cfg.src2_p_max);
            cfg_s2.src_p_min = cfg.src2_p_min;
            cfg_s2.src_p_max = cfg.src2_p_max;
            src_p2 = generateSourceProfile(N, cfg_s2);
            demand = build_window_demand(N, dt, cfg);

            log_k = 0;
            if csv_fid < 0
                csv_fid = open_streaming_csv(csv_path, params);
            end

            % ── Main simulation loop ──────────────────────────────────────
            for k = 1:N

                t_s     = (k-1) * dt;
                aid     = double(label_id(k));
                r_phase = double(recovery_phase(k));

                % Pass pre-built schedule (no longer rebuilt each step)
                [src_p1_k, src_p2_k, comp1, comp2, plc, valve_states, demand_k] = ...
                    applyAttackEffects(aid, k, dt, schedule, ...
                                      src_p1(k), src_p2(k), comp1, comp2, plc, ...
                                      valve_states, demand(k), cfg);

                state.p(params.sourceNodes(1)) = src_p1_k;
                state.p(params.sourceNodes(2)) = src_p2_k;

                % Natural recovery: exponentially restore compressors post-attack
                if r_phase == 1
                    alpha_rec   = 0.05;
                    comp1.ratio = comp1.ratio + alpha_rec * (cfg.comp1_ratio - comp1.ratio);
                    comp2.ratio = comp2.ratio + alpha_rec * (cfg.comp2_ratio - comp2.ratio);
                end

                % Roughness AR(1)
                a_r   = cfg.rough_corr;
                sig_r = cfg.rough_var_std * cfg.pipe_rough * sqrt(1 - a_r^2);
                params.rough = max(1e-6, a_r * params.rough + ...
                                         sig_r * randn(params.nEdges, 1));

                [state.q, ~] = updateFlow(cfg, state.p, demand_vec);

                if aid == 8
                    frac = min(1, (k - k_atk_start) * dt / cfg.atk8_ramp_time);
                    state.q(cfg.atk8_edge) = state.q(cfg.atk8_edge) * ...
                                             (1 - cfg.atk8_leak_frac * frac);
                end

                [state, q_sto] = updateStorage(state, params, cfg);

                demand_vec = zeros(params.nNodes, 1);
                demand_vec(params.demandNodes) = demand_k;
                p_prev = state.p;
                [state.p, p_acoustic] = updatePressure(params, state.p, state.q, ...
                                                        demand_vec, p_acoustic, cfg);

                [state, comp1] = updateCompressor(state, comp1, k, cfg, 1);
                [state, comp2] = updateCompressor(state, comp2, k, cfg, 2);
                [state, prs1]  = updatePRS(state, prs1, cfg);
                [state, prs2]  = updatePRS(state, prs2, cfg);

                [state.Tgas, T_turb] = updateTemperature(params, state.Tgas, ...
                    state.q, p_prev, state.p, T_turb, cfg);
                [state.rho, rho_comp_state] = updateDensity(state.p, state.Tgas, ...
                    rho_comp_state, cfg);

                % Sensors
                nf       = cfg.sensor_noise_floor;
                sensor_p = state.p + max(cfg.sensor_noise * abs(state.p), nf) .* ...
                                     randn(params.nNodes, 1);
                sensor_q = state.q + max(cfg.sensor_noise * abs(state.q), nf) .* ...
                                     randn(params.nEdges, 1);

                % Replay
                if aid == 10
                    if prev_aid ~= 10, replay_k = 0; else, replay_k = replay_k + 1; end
                    [sensor_p, sensor_q, replay_buf] = applyReplayAttack( ...
                        sensor_p, sensor_q, replay_buf, replay_k, cfg);
                else
                    replay_k = 0;
                    [~, ~, replay_buf] = applyReplayAttack( ...
                        sensor_p, sensor_q, replay_buf, -1, cfg);
                end
                prev_aid = aid;

                % Pass pre-built schedule (not rebuilt each step)
                [sensor_p, sensor_q] = applySensorSpoof(aid, k, dt, schedule, ...
                    sensor_p, sensor_q, cfg, ekf, replay_buf);

                [sensor_p, sensor_q, fault, fault_label] = applyFaultInjection( ...
                    sensor_p, sensor_q, fault, k, dt, cfg);

                % ── FIX 3: A7 uses latency, all others use standard PLC update
                if aid == 7
                    plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
                    plc = advanceLatencyBuffers(plc);
                else
                    plc = updatePLC(plc, sensor_p, sensor_q, k, cfg);
                end

                ekf   = updateEKF(ekf, plc.reg_p, plc.reg_q, state.p, state.q, params, cfg);
                cusum = updateCUSUM(cusum, ekf.residual, cfg, k);

                if aid ~= 2
                    [comp1, comp2, prs1, prs2, valve_states, plc] = ...
                        updateControlLogic(comp1, comp2, prs1, prs2, valve_states, ...
                                           plc, ekf.xhatP, cfg, k, dt);
                end

                if mod(k, log_every) == 0
                    log_k = log_k + 1;
                    write_window_row(csv_fid, t_s, state, ekf, plc, ...
                                     comp1, comp2, prs1, prs2, valve_states, ...
                                     cusum, sensor_p, sensor_q, q_sto, ...
                                     aid, fault_label, r_phase, ...
                                     attack_start_flag(k), recovery_start_flag(k), ...
                                     scenario_id, params);
                end

            end % k loop

            total_rows = total_rows + log_k;

            atk_name = atk_names{min(atk, numel(atk_names))};
            fprintf(man_fid, '%d,%d,%s,%.1f,%.1f,%.1f,%d\n', ...
                    scenario_id, atk, atk_name, ...
                    normal_s, normal_s + attack_s, ...
                    min(normal_s + attack_s + recovery_s, total_s), log_k);

            fprintf('           → %d rows logged\n', log_k);
        end
    end

    if csv_fid > 0, fclose(csv_fid); end
    fclose(man_fid);

    fprintf('\n=================================================================\n');
    fprintf('  COMPLETE: %d total rows across %d scenarios\n', total_rows, scenario_id);
    fprintf('  Output: %s\n', opt.out_dir);
    fprintf('=================================================================\n\n');
    fprintf('Next step:\n');
    fprintf('  python cgd_ids_pipeline.py --baseline %s\n', ...
            fullfile(opt.out_dir, 'physics_dataset_windows.csv'));
end


% =========================================================================
%  LATENCY BUFFER ADVANCE  (mirrors run_48h_continuous helper)
% =========================================================================
function plc = advanceLatencyBuffers(plc)
    plc.compRatio1Buf   = [plc.compRatio1Buf(2:end),  plc.act_comp1_ratio];
    plc.compRatio2Buf   = [plc.compRatio2Buf(2:end),  plc.act_comp2_ratio];
    plc.valveCmdBuf     = [plc.valveCmdBuf(:,2:end),  plc.act_valve_cmds];
    plc.act_comp1_ratio = plc.compRatio1Buf(1);
    plc.act_comp2_ratio = plc.compRatio2Buf(1);
    plc.act_valve_cmds  = plc.valveCmdBuf(:,1);
end


% =========================================================================
%  BUILD DEMAND PROFILE FOR ONE WINDOW
% =========================================================================
function demand = build_window_demand(N, dt, cfg)
    t       = (0:N-1)' * dt;
    hour    = mod(t / 3600, 24);
    morning = 0.8 * exp(-0.5 * ((hour - 7.5)  / 1.2).^2);
    evening = 1.0 * exp(-0.5 * ((hour - 19.0) / 1.5).^2);
    diurnal = 0.3 + morning + evening;
    diurnal = diurnal / max(diurnal);
    demand  = cfg.dem_base * (0.4 + 0.6 * diurnal);
    noise = zeros(N, 1);
    for k = 2:N
        noise(k) = 0.95 * noise(k-1) + cfg.dem_noise_std * randn();
    end
    demand = max(0.05, demand + noise);
end


% =========================================================================
%  STUB SCHEDULE (built once per scenario, passed into loop)
% =========================================================================
function schedule = build_stub_schedule(label_id, N, dt)
% build_stub_schedule  Construct the schedule struct expected by
%   applyAttackEffects and applySensorSpoof from a per-step label vector.
%
%   Called ONCE per scenario before the simulation loop (not inside it).

    names  = ["SrcPressureManipulation","CompressorRatioSpoofing", ...
              "ValveCommandTampering","DemandNodeManipulation", ...
              "PressureSensorSpoofing","FlowMeterSpoofing", ...
              "PLCLatencyAttack","PipelineLeak", ...
              "StealthyFDI","ReplayAttack"];
    mitres = ["T0831","T0838","T0855","T0829","T0831","T0827","T0814","T0829","T0835","T0835"];

    schedule.label_id    = label_id;
    schedule.label_name  = repmat("Normal", N, 1);
    schedule.label_mitre = repmat("None",   N, 1);

    for k = 1:N
        aid = double(label_id(k));
        if aid >= 1 && aid <= numel(names)
            schedule.label_name(k)  = names(aid);
            schedule.label_mitre(k) = mitres(aid);
        end
    end

    % Find contiguous attack windows and populate start_s / dur_s
    schedule.nAttacks = 0;
    schedule.ids      = [];
    schedule.start_s  = [];
    schedule.dur_s    = [];
    schedule.params   = {};

    changes = find(diff([0; int32(label_id); 0]) ~= 0);
    i = 1;
    while i < numel(changes)
        k_s = changes(i);
        k_e = changes(i+1) - 1;
        aid = double(label_id(min(k_s, N)));
        if aid > 0
            schedule.nAttacks           = schedule.nAttacks + 1;
            schedule.ids(end+1)         = aid;
            schedule.start_s(end+1)     = (k_s - 1) * dt;
            schedule.dur_s(end+1)       = (k_e - k_s + 1) * dt;
            schedule.params{end+1}      = struct();
        end
        i = i + 2;
    end
end


% =========================================================================
%  STREAMING CSV
% =========================================================================
function fid = open_streaming_csv(fpath, params)
    fid = fopen(fpath, 'w');
    if fid < 0, error('Cannot open %s for writing.', fpath); end
    nn  = params.nodeNames;
    en  = params.edgeNames;
    hdr = 'Timestamp_s,scenario_id,ATTACK_ID';
    for i = 1:params.nNodes, hdr = [hdr sprintf(',p_%s_bar',   char(nn(i)))]; end %#ok
    for i = 1:params.nEdges, hdr = [hdr sprintf(',q_%s_kgs',   char(en(i)))]; end %#ok
    hdr = [hdr ',CS1_ratio,CS1_power_kW,CS2_ratio,CS2_power_kW'];
    hdr = [hdr ',PRS1_throttle,PRS2_throttle'];
    hdr = [hdr ',valve_E8,valve_E14,valve_E15,STO_inventory'];
    hdr = [hdr ',cusum_S_upper,cusum_S_lower,cusum_alarm,chi2_stat,chi2_alarm'];
    for i = 1:params.nNodes, hdr = [hdr sprintf(',ekf_resid_%s', char(nn(i)))]; end %#ok
    for i = 1:params.nNodes, hdr = [hdr sprintf(',plc_p_%s',     char(nn(i)))]; end %#ok
    for i = 1:params.nEdges, hdr = [hdr sprintf(',plc_q_%s',     char(en(i)))]; end %#ok
    hdr = [hdr ',FAULT_ID,label,attack_start,recovery_start,recovery_phase'];
    fprintf(fid, '%s\n', hdr);
end


function write_window_row(fid, t_s, state, ekf, plc, comp1, comp2, prs1, prs2, ...
                           valve_states, cusum, sensor_p, sensor_q, q_sto, ...
                           aid, fault_label, r_phase, atk_start, rec_start, ...
                           scenario_id, params)  %#ok<INUSL>
% Note: q_sto and sensor_p/sensor_q are recorded for completeness.
% The unused sensor_p/q arguments are kept so callers need not change.

    label = int32(fault_label > 0 || aid > 0);

    fprintf(fid, '%.3f,%d,%d', t_s, scenario_id, aid);
    fprintf(fid, ',%.4f', state.p);
    fprintf(fid, ',%.4f', state.q);
    fprintf(fid, ',%.4f,%.3f,%.4f,%.3f', ...
            comp1.ratio, state.W1/1000, comp2.ratio, state.W2/1000);
    fprintf(fid, ',%.4f,%.4f', prs1.throttle, prs2.throttle);
    fprintf(fid, ',%.3f,%.3f,%.3f', valve_states(1), valve_states(2), valve_states(3));
    fprintf(fid, ',%.4f', state.sto_inventory);
    fprintf(fid, ',%.4f,%.4f,%d,%.4f,%d', ...
            cusum.S_upper, cusum.S_lower, int32(cusum.alarm), ...
            ekf.chi2_stat,  int32(ekf.chi2_alarm));
    fprintf(fid, ',%.4f', ekf.xhat(1:params.nNodes) - state.p);
    fprintf(fid, ',%.4f', plc.reg_p);
    fprintf(fid, ',%.4f', plc.reg_q);
    fprintf(fid, ',%d,%d,%d,%d,%d\n', fault_label, label, atk_start, rec_start, r_phase);
end
