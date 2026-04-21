function schedule = initAttackSchedule(N, cfg)
% initAttackSchedule  Randomised attack schedule over the full simulation.
%
%   schedule = initAttackSchedule(N, cfg)
%
%   Rules:
%     - cfg.n_attacks attacks placed randomly (default 8)
%     - cfg.forced_attack_id: [] = random, integer = force that attack only
%     - No two attacks overlap (min gap = cfg.atk_min_gap_s)
%     - First attack no earlier than cfg.atk_warmup_s
%     - Last attack ends at least cfg.atk_recovery_s before end
%     - Randomised durations in [cfg.atk_dur_min_s, cfg.atk_dur_max_s]
%     - Attack order shuffled each run

    dt          = cfg.dt;
    T_total     = N * dt;

    % ── Use cfg.n_attacks (default 8) ────────────────────────────────────
    nA = cfg.n_attacks;

    warmup_s   = cfg.atk_warmup_s;
    recovery_s = cfg.atk_recovery_s;
    min_gap_s  = cfg.atk_min_gap_s;
    dur_min    = cfg.atk_dur_min_s;
    dur_max    = cfg.atk_dur_max_s;
    usable_end = T_total - recovery_s;

    %% ── Select attack IDs ────────────────────────────────────────────────
    % forced_attack_id overrides random selection
    if isfield(cfg, 'forced_attack_id') && ~isempty(cfg.forced_attack_id)
        attack_ids = repmat(cfg.forced_attack_id, 1, nA);
        nA = 1;   % only one attack type, placed once
        attack_ids = attack_ids(1);
    else
        % Available attack IDs from cfg.attack_selection (default 1:10)
        if isfield(cfg, 'attack_selection') && ~isempty(cfg.attack_selection)
            pool = cfg.attack_selection;
        else
            pool = 1:8;
        end
        % Sample nA IDs from pool (with replacement, then shuffle)
        idx        = randi(numel(pool), 1, nA);
        attack_ids = pool(idx(randperm(numel(idx))));
    end

    %% ── Place attacks with gap enforcement ───────────────────────────────
    max_tries = 1000;
    placed    = false;

    for attempt = 1:max_tries
        durs   = dur_min + (dur_max - dur_min) * rand(1, nA);
        starts = zeros(1, nA);
        ok     = true;

        latest_first = usable_end - sum(durs) - (nA - 1) * min_gap_s;
        if latest_first < warmup_s
            continue;
        end
        starts(1) = warmup_s + (latest_first - warmup_s) * rand();

        for i = 2:nA
            prev_end       = starts(i-1) + durs(i-1);
            latest_start   = usable_end - sum(durs(i:end)) - (nA - i) * min_gap_s;
            earliest_start = prev_end + min_gap_s;
            if earliest_start > latest_start
                ok = false; break;
            end
            starts(i) = earliest_start + (latest_start - earliest_start) * rand();
        end

        if ok, placed = true; break; end
    end

    if ~placed
        error(['initAttackSchedule: could not place %d attacks in %.0f min. ' ...
               'Increase cfg.T or reduce atk_dur_max_s / atk_min_gap_s.'], nA, T_total/60);
    end

    %% ── Build per-step label arrays ──────────────────────────────────────
    schedule.label_id    = zeros(N, 1, 'int32');
    schedule.label_name  = repmat("Normal", N, 1);
    schedule.label_mitre = repmat("None",   N, 1);

    schedule.nAttacks = nA;
    schedule.ids      = zeros(1, nA);
    schedule.start_s  = zeros(1, nA);
    schedule.end_s    = zeros(1, nA);
    schedule.dur_s    = zeros(1, nA);
    schedule.params   = cell(1, nA);

    %% Attack catalogue (name / mitre / param strings)
    names  = ["SrcPressureManipulation","CompressorRatioSpoofing", ...
              "ValveCommandTampering","DemandNodeManipulation", ...
              "PressureSensorSpoofing","FlowMeterSpoofing", ...
              "PLCLatencyAttack","PipelineLeak","StealthyFDI","ReplayAttack"];
    mitres = ["T0831","T0838","T0855","T0829","T0831","T0827","T0814","T0829","T0835","T0835"];
    pstrs  = ["spike_amp=rand", "target_ratio=rand,ramp=rand", ...
              "ramp_close+cycle", "scale=rand,ramp=rand", ...
              "node=rand,bias=rand,osc", "edges=rand,scale=rand", ...
              "extra_latency=rand", "edge=rand,frac=rand,ramp=rand", ...
              "nodes=rand,bias=rand%", "buffer=rand"];

    for i = 1:nA
        aid     = attack_ids(i);
        s_s     = starts(i);
        dur     = durs(i);
        k_start = max(1, round(s_s       / dt));
        k_end   = min(N, round((s_s+dur) / dt));

        schedule.label_id(k_start:k_end)    = int32(aid);
        schedule.label_name(k_start:k_end)  = names(min(aid, numel(names)));
        schedule.label_mitre(k_start:k_end) = mitres(min(aid, numel(mitres)));

        schedule.ids(i)    = aid;
        schedule.start_s(i) = s_s;
        schedule.end_s(i)  = s_s + dur;
        schedule.dur_s(i)  = dur;
        schedule.params{i} = char(pstrs(min(aid, numel(pstrs))));
    end

    %% Console summary
    normal_steps = sum(schedule.label_id == 0);
    attack_steps = N - normal_steps;
    fprintf('\n[schedule] %d attacks over %.0f min (n_atk=%d, pool=%s)\n', ...
            nA, T_total/60, nA, mat2str(unique(attack_ids)));
    fprintf('[schedule] Normal: %.1f min (%.0f%%)  Attack: %.1f min (%.0f%%)\n', ...
            normal_steps*dt/60, 100*normal_steps/N, ...
            attack_steps*dt/60, 100*attack_steps/N);
    [~, ord] = sort(schedule.start_s);
    for i = 1:nA
        j = ord(i);
        nm = char(names(min(schedule.ids(j), numel(names))));
        fprintf('[schedule]   A%d %-35s  @%5.1fmin  dur=%.0fs\n', ...
                schedule.ids(j), nm, schedule.start_s(j)/60, schedule.dur_s(j));
    end
    fprintf('\n');
end
