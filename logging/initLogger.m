function initLogger(dt, T, N)
% initLogger  Create the log directory, open sim_events.log, write a header,
%             and register the file handle with logEvent.
%
%   initLogger(dt, T, N)
%
%   dt  – simulation time step (s)
%   T   – total simulation duration (s)
%   N   – total number of steps

    if ~exist('logs', 'dir')
        mkdir('logs');
    end

    logPath = fullfile('logs', 'sim_events.log');

    % Open in append mode so consecutive runs accumulate history.
    % Use 'w' if you prefer a fresh file every run.
    fid = fopen(logPath, 'a');
    if fid < 0
        warning('initLogger: could not open %s for writing.', logPath);
        return;
    end

    %% ── session separator & header ───────────────────────────────────────
    sep = repmat('=', 1, 100);
    fprintf(fid, '\n%s\n', sep);
    fprintf(fid, 'SESSION START  %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
    fprintf(fid, 'Config  dt=%.4f s  |  T=%g s  |  N=%d steps\n', dt, T, N);
    fprintf(fid, '%s\n', sep);
    fprintf(fid, '%-21s  %-17s  %-9s  %-8s  %-12s  %s\n', ...
            'Wall-clock', 'Sim-time (step)', 'Level', 'Source', 'Message', '');
    fprintf(fid, '%s\n', repmat('-', 1, 100));

    % Register handle with logEvent via the back-door call convention
    logEvent(fid);

    logEvent('INFO', 'initLogger', ...
             sprintf('Simulation initialised  dt=%.4f s  T=%g s  N=%d', dt, T, N), ...
             0, dt);
end
