function ekf = initEKF(cfg, state)
% initEKF  Build the Extended Kalman Filter struct from cfg and initial state.
%
%   ekf = initEKF(cfg, state)
%
%   The state vector is [p; q] (pressures stacked above flows).
%   The observation model is identity (C = I) - every state is directly
%   observed through the PLC sensor bus.

    nX      = numel(state.p) + numel(state.q);
    ekf.nx  = nX;
    ekf.xhat = [state.p; state.q];           % initial state estimate
    ekf.P    = eye(nX) * cfg.ekf_P0;         % initial covariance
    ekf.Qn   = eye(nX) * cfg.ekf_Qn;         % process noise covariance
    ekf.Rk   = eye(nX) * cfg.ekf_Rk;         % measurement noise covariance
    ekf.C    = eye(nX);                       % observation matrix (identity)
    ekf.xhatP  = [state.p; state.q];          % full estimated state [pressures; flows]
    ekf.xhatQ  = state.q;                    % estimated flows
    ekf.residP = zeros(numel(state.p), 1);   % pressure residuals
    ekf.residQ = zeros(numel(state.q), 1);   % flow residuals
end