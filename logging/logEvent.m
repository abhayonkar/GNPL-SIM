function logEvent(level, source, message, k, dt)
% logEvent  Write a structured log entry to console and to logs/sim_events.log
%
%   logEvent(level, source, message, k, dt)
%
%   level   : 'INFO' | 'WARNING' | 'ERROR' | 'CRITICAL'
%   source  : string identifying the calling function, e.g. 'runSimulation'
%   message : descriptive string
%   k       : simulation step index  (pass 0 if not inside the loop)
%   dt      : simulation time step in seconds (pass 0 if not inside the loop)
%
%   All entries are also appended to  logs/sim_events.log
%   The file handle is kept in a persistent variable so the file is only
%   opened once per MATLAB session (cleared when you call initLogger).

    persistent fid;

    %% ── allow initLogger to inject / reset the file handle ──────────────
    if nargin == 1 && isnumeric(level)
        % called as  logEvent(fid_in)  by initLogger
        fid = level;
        return;
    end

    %% ── default args ─────────────────────────────────────────────────────
    if nargin < 4 || isempty(k),  k  = 0; end
    if nargin < 5 || isempty(dt), dt = 0; end

    %% ── build strings ────────────────────────────────────────────────────
    wallclock  = datestr(now, 'yyyy-mm-dd HH:MM:SS');   %#ok<TNOW1,DATST>
    sim_time_s = k * dt;
    sim_hms    = sprintf('%02d:%02d:%06.3f', ...
                     floor(sim_time_s/3600), ...
                     floor(mod(sim_time_s,3600)/60), ...
                     mod(sim_time_s,60));

    % Pad level to fixed width for column-aligned output
    level_padded = sprintf('%-8s', level);

    entry = sprintf('[%s]  SIM %s (step %7d)  %-10s  %-12s  %s', ...
                    wallclock, sim_hms, k, level_padded, source, message);

    %% ── console: coloured prefix ─────────────────────────────────────────
    switch upper(level)
        case 'WARNING',  prefix = '⚠ ';
        case 'ERROR',    prefix = '✖ ';
        case 'CRITICAL', prefix = '‼ ';
        otherwise,       prefix = '  ';   % INFO
    end
    fprintf('%s%s\n', prefix, entry);

    %% ── file ─────────────────────────────────────────────────────────────
    if ~isempty(fid) && fid > 0
        fprintf(fid, '%s\n', entry);
    end
end