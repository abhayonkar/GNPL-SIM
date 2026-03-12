function closeLogger(dt, N)
% closeLogger  Write a session-end footer and flush / close the log file.
%
%   closeLogger(dt, N)

    logEvent('INFO', 'closeLogger', ...
             sprintf('Simulation complete. Total steps run: %d  (%.1f s simulated)', ...
                     N, N*dt), N, dt);

    % Retrieve the file handle stored in logEvent and close it.
    % We signal this with the sentinel value -1.
    logEvent(-1);   % logEvent will close fid when it receives -1
end
