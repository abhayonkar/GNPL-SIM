function cfg = apply_cgd_overrides(cfg)
% apply_cgd_overrides  Enforce Indian CGD operating envelope on cfg struct.
%
% Called ONCE after simConfig() and BEFORE runSimulation().
% Previously this was called prematurely (before Phase A stability fixes),
% causing storage loop divergence. Now safe to call after:
%   1. updateFlow.m wrapper is confirmed passing
%   2. sto_p_inject/withdraw/k_flow set correctly in simConfig.m
%
% WHAT THIS DOES
%   - Clamps source pressures to 20–26 barg
%   - Clamps compressor ratios to 1.1–1.6
%   - Asserts DRS delivery targets are ≥ 14 barg
%   - Verifies storage inject/withdraw bounds are within MAOP
%   - Logs a summary so sweeps have an auditable record
%
% Verification:
%   >> cfg = simConfig();
%   >> cfg = apply_cgd_overrides(cfg);
%   >> assert(all(cfg.src_p_barg >= 20 & cfg.src_p_barg <= 26))
%   >> assert(cfg.sto_p_inject <= cfg.pipe_MAOP_barg)

    fprintf('[CGD Override] Applying Indian CGD envelope (PNGRB T4S)...\n');

    % ----------------------------------------------------------------
    % 1. Source pressures: CGS outlet 20–26 barg
    % ----------------------------------------------------------------
    cfg.src_p_barg = clamp(cfg.src_p_barg, cfg.src_p_min, cfg.src_p_max);
    fprintf('  src_p_barg clamped to [%.1f, %.1f] barg\n', ...
        cfg.src_p_min, cfg.src_p_max);

    % ----------------------------------------------------------------
    % 2. Compressor ratios: 1.1–1.6
    % ----------------------------------------------------------------
    cfg.comp_ratio_nom = clamp(cfg.comp_ratio_nom, ...
        cfg.comp_ratio_min, cfg.comp_ratio_max);
    fprintf('  comp_ratio_nom = [%.2f, %.2f]\n', cfg.comp_ratio_nom);

    % ----------------------------------------------------------------
    % 3. DRS delivery: all targets ≥ 14 barg
    % ----------------------------------------------------------------
    floor_drs = 14.0;
    cfg.drs_p_target_barg = max(cfg.drs_p_target_barg, floor_drs);
    fprintf('  drs_p_target_barg (min=%.1f): %s\n', floor_drs, ...
        mat2str(cfg.drs_p_target_barg, 3));

    % ----------------------------------------------------------------
    % 4. Storage: inject ≤ MAOP, withdraw ≥ DRS floor
    % ----------------------------------------------------------------
    if cfg.sto_p_inject > cfg.pipe_MAOP_barg
        warning('apply_cgd_overrides:sto_inject_exceeds_MAOP', ...
            'sto_p_inject (%.1f) > MAOP (%.1f) — clamping.', ...
            cfg.sto_p_inject, cfg.pipe_MAOP_barg);
        cfg.sto_p_inject = cfg.pipe_MAOP_barg - 0.5;
    end
    if cfg.sto_p_withdraw < floor_drs
        warning('apply_cgd_overrides:sto_withdraw_below_drs', ...
            'sto_p_withdraw (%.1f) < DRS floor (%.1f) — clamping.', ...
            cfg.sto_p_withdraw, floor_drs);
        cfg.sto_p_withdraw = floor_drs + 0.5;
    end
    fprintf('  storage bounds: inject=%.1f, withdraw=%.1f barg\n', ...
        cfg.sto_p_inject, cfg.sto_p_withdraw);

    % ----------------------------------------------------------------
    % 5. CUSUM slack / warmup audit
    % ----------------------------------------------------------------
    fprintf('  cusum_slack=%.1f, warmup=%d steps\n', ...
        cfg.cusum_slack, cfg.cusum_warmup_steps);

    fprintf('[CGD Override] Done.\n');
end

% ----- local helper -----
function v = clamp(v, lo, hi)
    v = min(max(v, lo), hi);
end