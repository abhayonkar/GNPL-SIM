function schedule = initAttackSchedule(N, cfg)
% initAttackSchedule  Randomised attack schedule over the full simulation.
%
%   schedule = initAttackSchedule(N, cfg)
%
%   Rules:
%     - 8 attacks placed randomly across the simulation window
%     - No two attacks overlap (minimum gap of cfg.atk_min_gap_s seconds)
%     - First attack starts no earlier than cfg.atk_warmup_s (warmup)
%     - Last attack ends with at least cfg.atk_recovery_s seconds remaining
%     - Each attack has a randomised duration in [cfg.atk_dur_min_s, cfg.atk_dur_max_s]
%     - Attack order is shuffled so A1..A8 do not always appear in sequence
%     - 85% normal / 15% attack target is met by capping total attack time

    dt          = cfg.dt;
    T_total     = N * dt;               % total simulation seconds
    nA          = 8;                    % fixed number of attacks

    warmup_s    = cfg.atk_warmup_s;     % earliest possible first attack start
    recovery_s  = cfg.atk_recovery_s;  % seconds to keep clear at end
    min_gap_s   = cfg.atk_min_gap_s;   % minimum gap between attacks
    dur_min     = cfg.atk_dur_min_s;
    dur_max     = cfg.atk_dur_max_s;

    usable_end  = T_total - recovery_s;

    %% Shuffle attack IDs so order is randomised each run
    attack_ids = randperm(nA);   % e.g. [3 7 1 5 2 8 4 6]

    %% Randomly place attacks with gap enforcement -------------------------
    % Strategy: draw random durations, then place start times sequentially
    % with random gaps between them.  Retry up to 1000 times if window is
    % too tight (should never happen for sensible cfg values).

    max_tries = 1000;
    placed    = false;

    for attempt = 1:max_tries
        durs   = dur_min + (dur_max - dur_min) * rand(1, nA);   % random durations
        starts = zeros(1, nA);
        ok     = true;

        % First attack: uniform random in [warmup_s, usable_end - sum(durs) - (nA-1)*min_gap_s]
        latest_first = usable_end - sum(durs) - (nA - 1) * min_gap_s;
        if latest_first < warmup_s
            continue;   % window too tight, retry (increase T or reduce durations)
        end
        starts(1) = warmup_s + (latest_first - warmup_s) * rand();

        % Subsequent attacks: start after previous end + random gap
        for i = 2:nA
            prev_end      = starts(i-1) + durs(i-1);
            latest_start  = usable_end - sum(durs(i:end)) - (nA - i) * min_gap_s;
            earliest_start = prev_end + min_gap_s;
            if earliest_start > latest_start
                ok = false;
                break;
            end
            starts(i) = earliest_start + (latest_start - earliest_start) * rand();
        end

        if ok
            placed = true;
            break;
        end
    end

    if ~placed
        error(['initAttackSchedule: could not place %d attacks in %.0f min simulation. ' ...
               'Increase cfg.T or reduce atk_dur_max_s / atk_min_gap_s.'], nA, T_total/60);
    end

    %% Build per-step label arrays -----------------------------------------
    schedule.label_id    = zeros(N, 1, 'int32');
    schedule.label_name  = repmat("Normal", N, 1);
    schedule.label_mitre = repmat("None",   N, 1);

    schedule.nAttacks = nA;
    schedule.ids      = zeros(1, nA);
    schedule.start_s  = zeros(1, nA);
    schedule.end_s    = zeros(1, nA);
    schedule.dur_s    = zeros(1, nA);
    schedule.params   = cell(1, nA);

    %% Attack catalogue (name / mitre / param strings keyed by attack ID) ---
    names  = ["SrcPressureManipulation","CompressorRatioSpoofing", ...
              "ValveCommandTampering","DemandNodeManipulation", ...
              "PressureSensorSpoofing","FlowMeterSpoofing", ...
              "PLCLatencyAttack","PipelineLeak"];
    mitres = ["T0831","T0838","T0855","T0829","T0831","T0827","T0814","T0829"];
    pstrs  = ["spike_amp=1.30", "target_ratio=1.85,ramp=120s", ...
              "forced_cmd=0",   "scale=2.5,ramp=90s", ...
              "node=J2,bias=-1.2bar", "edges=E2+E3,scale=0.40", ...
              "extra_latency=50steps", "edge=E3,frac=0.45,ramp=60s"];

    for i = 1:nA
        aid     = attack_ids(i);
        s_s     = starts(i);
        dur     = durs(i);

        k_start = max(1, round(s_s       / dt));
        k_end   = min(N, round((s_s+dur) / dt));

        schedule.label_id(k_start:k_end)    = int32(aid);
        schedule.label_name(k_start:k_end)  = names(aid);
        schedule.label_mitre(k_start:k_end) = mitres(aid);

        schedule.ids(i)     = aid;
        schedule.start_s(i) = s_s;
        schedule.end_s(i)   = s_s + dur;
        schedule.dur_s(i)   = dur;
        schedule.params{i}  = char(pstrs(aid));
    end

    %% Console summary -----------------------------------------------------
    normal_steps = sum(schedule.label_id == 0);
    attack_steps = N - normal_steps;
    fprintf('\n[schedule] Attack schedule: %d attacks over %.0f min (RANDOMISED)\n', ...
            nA, T_total/60);
    fprintf('[schedule] Normal: %.1f min (%.0f%%)  Attack: %.1f min (%.0f%%)\n', ...
            normal_steps*dt/60, 100*normal_steps/N, ...
            attack_steps*dt/60, 100*attack_steps/N);
    % Sort by start time for readable console output
    [~, ord] = sort(schedule.start_s);
    for i = 1:nA
        j = ord(i);
        fprintf('[schedule]   A%d %-35s  @%5.1fmin  dur=%.0fs\n', ...
                schedule.ids(j), char(names(schedule.ids(j))), ...
                schedule.start_s(j)/60, schedule.dur_s(j));
    end
    fprintf('\n');
end