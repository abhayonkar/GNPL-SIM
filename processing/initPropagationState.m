function state_prop = initPropagationState(nN, cfg)
% initPropagationState  Allocate the propagation tracking state struct.
%
%   state_prop = initPropagationState(nN, cfg)
%
%   Call once at simulation start (in main_simulation or runSimulation init block),
%   before the main loop. The returned struct is passed to computePropagationLabels
%   each logged step and updated in-place.
%
%   cfg fields read:
%     cfg.prop_baseline_win  — rolling window length [log rows] (default 300)
%     cfg.prop_sigma_thresh  — detection threshold [σ multipliers] (default 3.0)

    if ~isfield(cfg, 'prop_baseline_win'),  cfg.prop_baseline_win  = 300; end
    if ~isfield(cfg, 'prop_sigma_thresh'),  cfg.prop_sigma_thresh  = 3.0; end

    win = cfg.prop_baseline_win;

    state_prop.baseline_p   = zeros(nN, win);   % circular buffer of resid_p
    state_prop.buf_idx      = 0;                % current write position
    state_prop.buf_filled   = false;            % true after first full cycle
    state_prop.triggered    = false(nN, 1);     % per-node trigger flag
    state_prop.trigger_step = zeros(nN, 1);     % log step of first trigger
    state_prop.origin_node  = 0;               % node of first trigger (0=none)
    state_prop.prev_aid     = -1;              % force state reset on first call
end