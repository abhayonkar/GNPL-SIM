function hist = updateHistorian(hist, state, plc, aid, k, dt, cfg, params)
% updateHistorian  Deadband-compression SCADA historian.
%
%   hist = updateHistorian(hist, state, plc, aid, k, dt, cfg, params)
%
%   MOTIVATION:
%   ────────────
%   Real SCADA historians (OSIsoft PI, Wonderware, Ignition) do not store
%   a new value for every scan cycle. They apply a deadband filter: a new
%   row is written only when the measurement changes by more than a
%   configured threshold since the last stored value, OR when a maximum
%   time interval has elapsed (periodic heartbeat).
%
%   This produces an irregular-timestep secondary dataset that is
%   fundamentally different from the uniform-rate master_dataset.csv.
%   Models trained on uniform-rate data fail on historian data, and vice
%   versa. Providing both datasets enables research on:
%     • IDS architectures for irregular time series (e.g. event-based RNN)
%     • Deadband exploitation attacks (attacker keeps changes below deadband
%       to avoid historian logging while process state drifts significantly)
%     • Transfer learning between historian and real-time data
%
%   WHAT IS LOGGED:
%     One row per change event per variable, format:
%       Timestamp_s, Node/Edge, VarType, Value, Unit, ATTACK_ID, FAULT_ID
%
%   DEADBAND RULES (from cfg, Section 21):
%     cfg.historian_deadband_p     — bar (pressure)
%     cfg.historian_deadband_q     — kg/s (flow)
%     cfg.historian_deadband_T     — K (temperature)
%     cfg.historian_max_interval_s — heartbeat: force write every N seconds
%
%   HISTORIAN STRUCT FIELDS:
%     hist.last_p      — last stored pressure per node (20×1)
%     hist.last_q      — last stored flow per edge (20×1)
%     hist.last_T      — last stored temperature per node (20×1)
%     hist.last_write_k — step at which last heartbeat write occurred
%     hist.rows        — cell array accumulating event rows (flushed to disk
%                        at simulation end by exportHistorian)
%     hist.row_count   — number of events recorded so far

    if ~cfg.historian_enable
        return;
    end

    t_s       = k * dt;
    db_p      = cfg.historian_deadband_p;
    db_q      = cfg.historian_deadband_q;
    db_T      = cfg.historian_deadband_T;
    max_int_k = round(cfg.historian_max_interval_s / dt);

    heartbeat = (k - hist.last_write_k) >= max_int_k;

    nN = params.nNodes;
    nE = params.nEdges;

    %% ── Pressure events ──────────────────────────────────────────────────
    for n = 1:nN
        val = state.p(n);
        if abs(val - hist.last_p(n)) >= db_p || heartbeat
            hist = append_row(hist, t_s, char(params.nodeNames(n)), ...
                              'pressure', val, 'bar', aid, 0);
            hist.last_p(n) = val;
        end
    end

    %% ── Flow events ──────────────────────────────────────────────────────
    for e = 1:nE
        val = state.q(e);
        if abs(val - hist.last_q(e)) >= db_q || heartbeat
            hist = append_row(hist, t_s, char(params.edgeNames(e)), ...
                              'flow', val, 'kg/s', aid, 0);
            hist.last_q(e) = val;
        end
    end

    %% ── Temperature events ───────────────────────────────────────────────
    for n = 1:nN
        val = state.Tgas(n);
        if abs(val - hist.last_T(n)) >= db_T || heartbeat
            hist = append_row(hist, t_s, char(params.nodeNames(n)), ...
                              'temperature', val, 'K', aid, 0);
            hist.last_T(n) = val;
        end
    end

    if heartbeat
        hist.last_write_k = k;
    end
end


function hist = append_row(hist, t_s, name, vartype, value, unit, aid, fid)
    hist.row_count = hist.row_count + 1;
    hist.rows{hist.row_count} = {t_s, name, vartype, value, unit, aid, fid};
end


function hist = initHistorian(params, cfg)
% initHistorian  Allocate historian state struct.
%   hist = initHistorian(params, cfg)
%   Call once at simulation start before the main loop.

    nN = params.nNodes;
    nE = params.nEdges;

    hist.last_p      = cfg.p0 * ones(nN, 1);
    hist.last_q      = zeros(nE, 1);
    hist.last_T      = cfg.T0 * ones(nN, 1);
    hist.last_write_k = 0;

    % Pre-allocate row cell array generously
    % For 100 min at 1 Hz with ~10 changes/step average: ~600,000 events
    max_rows = 800000;
    hist.rows      = cell(max_rows, 1);
    hist.row_count = 0;
end


function exportHistorian(hist, outDir)
% exportHistorian  Write historian events to CSV.
%   Called once at simulation end (from exportDataset or main_simulation).

    if hist.row_count == 0
        fprintf('[historian] No events recorded.\n');
        return;
    end

    fname = fullfile(outDir, sprintf('historian_%s.csv', ...
                                     datestr(now,'yyyymmdd_HHMMSS')));  %#ok
    fid = fopen(fname, 'w');
    fprintf(fid, 'Timestamp_s,Tag,VarType,Value,Unit,ATTACK_ID,FAULT_ID\n');

    for i = 1:hist.row_count
        r = hist.rows{i};
        fprintf(fid, '%.4f,%s,%s,%.6f,%s,%d,%d\n', ...
                r{1}, r{2}, r{3}, r{4}, r{5}, r{6}, r{7});
    end
    fclose(fid);
    fprintf('[historian] %d events → %s\n', hist.row_count, fname);
end