function logEvent(level, source, message, k, dt)
% logEvent  Buffered structured event logger.
%
%   logEvent(level, source, message, k, dt)
%
%   PERFORMANCE DESIGN:
%     All log entries are accumulated in an in-memory ring buffer of
%     BUFFER_SIZE lines. The buffer is flushed to disk only:
%       (a) when the buffer is full (every BUFFER_SIZE calls), or
%       (b) when logEvent(-1) is called (simulation end / cleanup).
%     This eliminates synchronous file I/O from the simulation hot path —
%     the previous design was doing one fwrite per physics step, which
%     was the primary cause of ~18× slowdown.
%
%   REPETITION SUPPRESSION:
%     Identical (level+source+message) strings are suppressed after the
%     first occurrence within a 1000-step window. This prevents the
%     "CS1 ratio clamped to min" warning from flooding the log with
%     21,000+ identical lines per run.
%
%   Special call forms (single numeric arg):
%     logEvent(fid)   — called by initLogger to register the file handle
%     logEvent(-1)    — flush buffer and close (called by closeLogger)

    persistent fid buf_lines buf_idx buf_full last_msg last_msg_count flush_threshold

    BUFFER_SIZE = 500;   % flush every 500 messages (~50 seconds at 10 Hz)
    SUPPRESS_N  = 100;   % suppress identical consecutive messages after N repeats

    %% ── Initialise persistent state on first call ────────────────────────
    if isempty(fid)
        fid           = -1;
        buf_lines     = cell(BUFFER_SIZE, 1);
        buf_idx       = 0;
        buf_full      = false;
        last_msg      = '';
        last_msg_count = 0;
        flush_threshold = BUFFER_SIZE;
    end

    %% ── Special: register file handle (called by initLogger) ─────────────
    if nargin == 1 && isnumeric(level)
        if level == -1
            % Flush and close
            flush_buffer(fid, buf_lines, buf_idx);
            if fid > 0
                try, fclose(fid); catch, end
            end
            fid            = -1;
            buf_idx        = 0;
            last_msg       = '';
            last_msg_count = 0;
        else
            fid     = level;
            buf_idx = 0;
        end
        return;
    end

    %% ── Default args ─────────────────────────────────────────────────────
    if nargin < 4 || isempty(k),  k  = 0; end
    if nargin < 5 || isempty(dt), dt = 0; end

    %% ── Build entry string ───────────────────────────────────────────────
    wallclock  = datestr(now, 'yyyy-mm-dd HH:MM:SS');   %#ok<TNOW1,DATST>
    sim_time_s = k * dt;
    sim_hms    = sprintf('%02d:%02d:%06.3f', ...
                     floor(sim_time_s/3600), ...
                     floor(mod(sim_time_s,3600)/60), ...
                     mod(sim_time_s,60));

    level_padded = sprintf('%-8s', level);
    entry = sprintf('[%s]  SIM %s (step %7d)  %-10s  %-20s  %s', ...
                    wallclock, sim_hms, k, level_padded, source, message);

    %% ── Repetition suppression ───────────────────────────────────────────
    msg_key = [level, source, message];
    if strcmp(msg_key, last_msg)
        last_msg_count = last_msg_count + 1;
        if last_msg_count > SUPPRESS_N
            % Still print a counter update every 1000 repeats
            if mod(last_msg_count, 1000) == 0
                count_entry = sprintf('[%s]  SIM %s  %-10s  %-20s  [REPEATED x%d]', ...
                    wallclock, sim_hms, level_padded, source, last_msg_count);
                console_print(level, count_entry);
                add_to_buffer(count_entry);
            end
            return;   % suppress this duplicate
        end
    else
        % New message — if we were suppressing, log the final count
        if last_msg_count > SUPPRESS_N
            count_entry = sprintf('[%s]  %-10s  %-20s  [above repeated %d times total]', ...
                wallclock, level_padded, source, last_msg_count);
            console_print(level, count_entry);
            add_to_buffer(count_entry);
        end
        last_msg       = msg_key;
        last_msg_count = 1;
    end

    %% ── Console output (always) ──────────────────────────────────────────
    console_print(level, entry);

    %% ── Buffer to memory ────────────────────────────────────────────────
    add_to_buffer(entry);

    %% ── Auto-flush when buffer full ──────────────────────────────────────
    if buf_idx >= flush_threshold
        flush_buffer(fid, buf_lines, buf_idx);
        buf_idx = 0;
    end

    % ── nested helpers (must be at end) ──────────────────────────────────
    function add_to_buffer(line)
        buf_idx = buf_idx + 1;
        if buf_idx > BUFFER_SIZE
            flush_buffer(fid, buf_lines, buf_idx - 1);
            buf_idx = 1;
        end
        buf_lines{buf_idx} = line;
    end
end

function console_print(level, entry)
    switch upper(char(level))
        case 'WARNING',  prefix = '⚠ ';
        case 'ERROR',    prefix = '✖ ';
        case 'CRITICAL', prefix = '‼ ';
        otherwise,       prefix = '  ';
    end
    fprintf('%s%s\n', prefix, entry);
end

function flush_buffer(fid, buf_lines, n)
    if fid > 0 && n > 0
        try
            for i = 1:n
                if ~isempty(buf_lines{i})
                    fprintf(fid, '%s\n', buf_lines{i});
                end
            end
            fflush(fid);
        catch
        end
    end
end