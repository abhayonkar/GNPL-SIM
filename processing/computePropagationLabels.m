function [labels, state_prop] = computePropagationLabels(resid_p, resid_q, ...
                                                           aid, k, log_k, ...
                                                           params, cfg, state_prop)
% computePropagationLabels  Track attack propagation through the pipeline network.
%
%   [labels, state_prop] = computePropagationLabels(resid_p, resid_q,
%       aid, k, log_k, params, cfg, state_prop)
%
%   CONCEPT:
%   ────────
%   When an attack begins, the anomaly signal does not appear simultaneously
%   at all sensors. It originates at the attack injection point and propagates
%   through the network via the pipe edges, with a measurable time delay at
%   each downstream node.
%
%   This function labels each logged row with four propagation features:
%
%   prop_origin_node  — node index where the anomaly first exceeded 3σ
%                       (0 if no anomaly detected yet)
%   prop_hop_node     — current farthest node where anomaly has arrived
%                       (tracks the propagation wavefront)
%   prop_delay_s      — elapsed seconds since the origin first triggered
%   prop_cascade_step — number of unique nodes that have exceeded 3σ so far
%
%   DETECTION THRESHOLD:
%   Each node has a rolling baseline (300-row window = 5 minutes at 1 Hz)
%   of Weymouth pressure residuals. A node "triggers" when the current
%   |resid_p(i)| exceeds 3σ of its baseline.
%
%   SCIENTIFIC VALUE:
%   These labels enable research on:
%     - Physics-aware graph neural networks (propagation as edge features)
%     - Attack localisation (identifying origin node from propagation pattern)
%     - Detection delay reduction (trigger on first hop, not full propagation)
%     - Dataset diversity (each attack scenario has unique propagation signature)
%
%   STATE STRUCT (state_prop — persistent between calls):
%     state_prop.baseline_p    — [nN × win_len] circular buffer of resid_p
%     state_prop.buf_idx       — current write index in circular buffer
%     state_prop.buf_filled    — whether baseline buffer has completed one cycle
%     state_prop.triggered     — [nN×1] logical: node has exceeded threshold
%     state_prop.trigger_step  — [nN×1] log step at which node first triggered
%     state_prop.origin_node   — node index of first trigger (0 if none)
%     state_prop.prev_aid      — attack ID from previous step
%
%   INPUTS:
%     resid_p    — 20×1 Weymouth pressure residual [barg]
%     resid_q    — 20×1 Weymouth flow residual [SCMD]
%     aid        — current attack ID (0 = normal)
%     k          — current physics step
%     log_k      — current log row index
%     params     — network params (nNodes, nEdges)
%     cfg        — simConfig struct
%     state_prop — persistent state (initialised by initPropagationState)
%
%   OUTPUTS:
%     labels     — struct with fields:
%                    origin_node, hop_node, delay_s, cascade_step
%     state_prop — updated state

    nN     = params.nNodes;
    win    = cfg.prop_baseline_win;    % rolling window length (log rows)
    thresh = cfg.prop_sigma_thresh;    % detection threshold (σ multipliers)
    dt_log = cfg.dt * cfg.log_every;   % seconds per log row

    %% Reset propagation state when attack changes
    if aid ~= state_prop.prev_aid
        state_prop.triggered    = false(nN, 1);
        state_prop.trigger_step = zeros(nN, 1);
        state_prop.origin_node  = 0;
        state_prop.prev_aid     = aid;
    end

    %% Update baseline circular buffer (always, not just during attacks)
    idx = mod(state_prop.buf_idx, win) + 1;
    state_prop.baseline_p(:, idx) = resid_p;
    state_prop.buf_idx = idx;
    if idx == win
        state_prop.buf_filled = true;
    end

    %% Compute per-node detection threshold from baseline
    if state_prop.buf_filled
        baseline_std = std(state_prop.baseline_p, 0, 2);   % nN×1
    else
        baseline_std = ones(nN, 1) * 0.1;   % default before baseline fills
    end

    node_thresh = thresh * baseline_std;   % nN×1

    %% Check each node for first trigger
    for i = 1:nN
        if ~state_prop.triggered(i) && abs(resid_p(i)) > node_thresh(i)
            state_prop.triggered(i)    = true;
            state_prop.trigger_step(i) = log_k;
            if state_prop.origin_node == 0
                state_prop.origin_node = i;   % first node to trigger = origin
            end
        end
    end

    %% Propagation labels for this log row
    n_triggered = sum(state_prop.triggered);

    if n_triggered == 0 || state_prop.origin_node == 0
        % No anomaly detected yet
        labels.origin_node  = 0;
        labels.hop_node     = 0;
        labels.delay_s      = 0;
        labels.cascade_step = 0;
    else
        % Find the most recently triggered node (propagation wavefront)
        trigger_steps = state_prop.trigger_step;
        trigger_steps(~state_prop.triggered) = 0;
        [~, latest_node] = max(trigger_steps);

        origin_step = state_prop.trigger_step(state_prop.origin_node);
        delay_steps = log_k - origin_step;

        labels.origin_node  = state_prop.origin_node;
        labels.hop_node     = latest_node;
        labels.delay_s      = delay_steps * dt_log;
        labels.cascade_step = n_triggered;
    end
end


function state_prop = initPropagationState(nN, cfg)
% initPropagationState  Allocate the propagation tracking state.
%
%   state_prop = initPropagationState(nN, cfg)
%   Call once at simulation start, before the main loop.
%
%   cfg fields required:
%     cfg.prop_baseline_win   — rolling window length in log rows (default 300)
%     cfg.prop_sigma_thresh   — detection sigma multiplier (default 3.0)

    if ~isfield(cfg, 'prop_baseline_win'),  cfg.prop_baseline_win  = 300; end
    if ~isfield(cfg, 'prop_sigma_thresh'),  cfg.prop_sigma_thresh  = 3.0; end

    win = cfg.prop_baseline_win;

    state_prop.baseline_p   = zeros(nN, win);
    state_prop.buf_idx      = 0;
    state_prop.buf_filled   = false;
    state_prop.triggered    = false(nN, 1);
    state_prop.trigger_step = zeros(nN, 1);
    state_prop.origin_node  = 0;
    state_prop.prev_aid     = -1;   % force reset on first call
end