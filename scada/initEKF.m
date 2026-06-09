function ekf = initEKF(cfg, state)
% initEKF  Build the Extended Kalman Filter struct from cfg and initial state.
%
%   ekf = initEKF(cfg, state)
%
%   The state vector is [p; q] (pressures stacked above flows).
%   The observation model is identity (C = I) - every state is directly
%   observed through the PLC sensor bus.

    nP      = numel(state.p);
    nQ      = numel(state.q);
    nX      = nP + nQ;
    x0      = [state.p; state.q];

    ekf.nx    = nX;
    ekf.nP    = nP;
    ekf.nQ    = nQ;
    ekf.xhat  = x0;                          % initial state estimate
    ekf.P     = eye(nX) * cfg.ekf_P0;       % initial covariance
    ekf.P0    = cfg.ekf_P0;
    ekf.Rk    = cfg.ekf_Rk;
    Q_vec = [repmat(cfg.ekf_Q_p_diag, nP, 1); repmat(cfg.ekf_Q_q_diag, nQ, 1)];
    ekf.Q     = diag(Q_vec);
    ekf.Qbase = ekf.Q;
    ekf.Qn    = ekf.Q;
    R_vec = [repmat(cfg.noise_sigma_p^2, nP, 1); ...   % 0.02^2 = 4e-4 bar²
            repmat(cfg.noise_sigma_q^2, nQ, 1)];       % 5.0^2  = 25 SCMD²
    ekf.R = diag(R_vec);
    ekf.C     = eye(nX);                    % observation matrix (identity)

    ekf.xhatP = state.p;
    ekf.xhatQ = state.q;
    ekf.xpred = x0;
    ekf.shadow_x = x0;
    ekf.shadow_pressure = state.p;
    ekf.shadow_flow = state.q;

    ekf.residual  = zeros(nX, 1);
    ekf.residualP = zeros(nP, 1);
    ekf.residualQ = zeros(nQ, 1);
    ekf.residP    = ekf.residualP;
    ekf.residQ    = ekf.residualQ;
    ekf.shadow_residual = zeros(nX, 1);
    ekf.shadow_divergence = zeros(nP, 1);

    ekf.adaptive_enable = isfield(cfg, 'ekf_adaptive_enable') && cfg.ekf_adaptive_enable;
    ekf.adaptive_lambda = get_cfg_field(cfg, 'ekf_adaptive_lambda', 0.98);
    ekf.adaptive_floor  = get_cfg_field(cfg, 'ekf_adaptive_q_floor', Q_vec);
    ekf.adaptive_cap    = get_cfg_field(cfg, 'ekf_adaptive_q_cap', max(Q_vec * 25, Q_vec));
    ekf.shadow_threshold = get_cfg_field(cfg, 'shadow_divergence_threshold', 0.75);
    ekf.S = eye(nX);
    ekf.chi2_stat = 0.0;
    ekf.chi2_alarm = false;
end

function value = get_cfg_field(cfg, field_name, default_value)
    if isfield(cfg, field_name)
        value = cfg.(field_name);
    else
        value = default_value;
    end
end
