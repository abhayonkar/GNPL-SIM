%% run_48h_sweep.m
% =========================================================================
%  Indian CGD — 48-Hour Multi-Run Sweep for Cross-Regime Evaluation
% =========================================================================
%
%  PURPOSE:
%    Single 48h continuous run (n=1) gives statistically invalid cross-regime
%    metrics: one unlucky AUC=0.50 could be coincidence. This sweep produces
%    10 structurally-diverse runs so that mean±std AUC across runs is
%    reportable in Paper 2 Table IV.
%
%  DESIGN MATRIX — what varies across runs:
%  ┌─────┬──────┬─────────┬──────────────────────────┬────────────────────────┐
%  │ Run │ Seed │ Density │ Attack types              │ Regime emphasis        │
%  ├─────┼──────┼─────────┼──────────────────────────┼────────────────────────┤
%  │  01 │   42 │ normal  │ ALL (A1–A10)              │ Baseline 48h           │
%  │  02 │  137 │ high    │ Physical: A1,A2,A3,A8     │ Peak demand day        │
%  │  03 │  256 │ high    │ Sensor:   A5,A6,A9        │ Morning ramp up        │
%  │  04 │  391 │ normal  │ Cyber:    A7,A10          │ Night / low demand     │
%  │  05 │  512 │ low     │ ALL (A1–A10)              │ S1-only supply period  │
%  │  06 │  678 │ normal  │ Hybrid:   A1,A5,A9        │ Maintenance window     │
%  │  07 │  801 │ high    │ Flow:     A2,A6,A8        │ Evening cooking peak   │
%  │  08 │  943 │ low     │ Control:  A3,A7,A10       │ Day trough             │
%  │  09 │ 1024 │ normal  │ ALL (A1–A10)              │ Extended S2 interrupt  │
%  │  10 │ 1337 │ none    │ NONE (clean baseline)     │ Normal 48h (ref)       │
%  └─────┴──────┴─────────┴──────────────────────────┴────────────────────────┘
%
%  WHY THESE GROUPS?
%    Physical attacks (A1,A2,A3,A8) — change pressure/flow directly:
%      Models trained on attack_windows learn clear pressure deviations.
%      In 48h, the same pressure excursion happens during different demand
%      regimes (peak vs trough), testing whether the model recognises the
%      attack signature across regime context.
%
%    Sensor attacks (A5,A6,A9) — spoof readings without changing physics:
%      The EKF residual (physics-ML signal) should be most sensitive here.
%      Cross-regime question: does the LSTM learn sensor-physics mismatch,
%      or just the normal-period base rate?
%
%    Cyber attacks (A7,A10) — PLC latency + replay:
%      Replay attack embeds past normal data, so cross-regime shift is
%      largest here: the "replayed" buffer comes from a different operating
%      period than the injection window.
%
%    Run 10 (no attacks) — used as a normalisation reference ONLY.
%      Not mixed into attack-based evaluation. Used to verify that models
%      produce near-zero false alarm rates on purely-clean continuous data.
%
%  ML TRAINING PROTOCOL:
%    Models are trained EXCLUSIVELY on ml_outputs/splits/windows_train.csv
%    (short attack-window scenarios, attack_density='normal', 24h each).
%    These 10 runs are EVALUATION ONLY — no training data comes from here.
%    This cleanly measures cross-regime generalisation (not domain adaptation).
%
%  USAGE:
%    >> run_48h_sweep()                         % all 10 runs
%    >> run_48h_sweep('runs', [1,2,3])          % subset
%    >> run_48h_sweep('out_root', '/fast/disk') % different output location
%    >> run_48h_sweep('duration_h', 24)         % shorter runs for testing
%
%  NOTE:
%    The design matrix field "density" maps to run_48h_continuous
%    attack_density and must be one of: none, low, normal, high. It is not a
%    demand profile; operating demand regimes are generated inside each 48h
%    run.
%
% =========================================================================

function run_48h_sweep(varargin)

    ap = inputParser();
    addParameter(ap, 'runs',       1:10);
    addParameter(ap, 'out_root',   'automated_dataset/continuous_48h');
    addParameter(ap, 'duration_h', 48);
    parse(ap, varargin{:});
    opt = ap.Results;

    addpath('config','network','equipment','scada','control', ...
            'attacks','logging','export','middleware','profiling','processing');

    %% ── Design matrix ────────────────────────────────────────────────────
    %  Each row: [seed, density, attack_types_cell, description_string]
    %  attack_types = [] means use default (1:10 = all)

    M = design_matrix();

    n_total = numel(opt.runs);
    fprintf('\n');
    fprintf('======================================================\n');
    fprintf('  CGD 48h Continuous Sweep — %d runs\n', n_total);
    fprintf('  Output root: %s\n', opt.out_root);
    fprintf('======================================================\n\n');

    t_sweep = tic;
    for idx = 1:n_total
        run_id = opt.runs(idx);
        if run_id < 1 || run_id > numel(M)
            fprintf('[sweep] WARNING: run %d out of range — skipping\n', run_id);
            continue;
        end

        row     = M(run_id);
        out_dir = fullfile(opt.out_root, sprintf('run_%02d', run_id));

        fprintf('------------------------------------------------------\n');
        fprintf('  RUN %02d/%02d   seed=%-5d  density=%-6s  types=%s\n', ...
                run_id, n_total, row.seed, row.density, mat2str(row.attack_types));
        fprintf('  Desc: %s\n', row.description);
        fprintf('  Out : %s\n', out_dir);
        fprintf('------------------------------------------------------\n');

        t_run = tic;
        run_48h_continuous( ...
            'seed',           row.seed, ...
            'attack_density', row.density, ...
            'attack_types',   row.attack_types, ...
            'duration_h',     opt.duration_h, ...
            'out_dir',        out_dir, ...
            'fault_enable',   true, ...
            'jitter_enable',  true, ...
            'historian_enable', false);   % skip historian to save I/O

        elapsed_m = toc(t_run) / 60;
        fprintf('\n  [run %02d complete — %.1f min wall]\n\n', run_id, elapsed_m);
    end

    elapsed_h = toc(t_sweep) / 3600;
    fprintf('======================================================\n');
    fprintf('  SWEEP COMPLETE — %d runs in %.2f h\n', n_total, elapsed_h);
    fprintf('======================================================\n\n');

    %% ── Write sweep manifest ─────────────────────────────────────────────
    write_sweep_manifest(M, opt);

    %% ── Print next-step instructions ─────────────────────────────────────
    fprintf('Next steps:\n');
    fprintf('  1. Aggregate runs into a single test CSV:\n');
    fprintf('     python ml_pipeline/build_train_test_val_splits.py --rebuild-48h\n\n');
    fprintf('  2. Evaluate cross-regime generalisation:\n');
    fprintf('     python scripts/evaluate_cross_regime.py\n\n');
    fprintf('  3. Expected Paper 2 Table IV output:\n');
    fprintf('     reports/cross_regime_results.csv\n\n');
end


% =========================================================================
%  DESIGN MATRIX
% =========================================================================

function M = design_matrix()
% design_matrix  Return struct array of 10 run configurations.
%
%  The grouping rationale:
%    Runs 01,05,09 = all-attack baselines (seed diversity only)
%    Run 10        = clean reference (no attacks)
%    Runs 02-04    = attack family isolation (physical / sensor / cyber)
%    Runs 06-08    = attack family cross pairs for transferability analysis

    M = struct('seed',{},'density',{},'attack_types',{},'description',{});

    % Run 01 — All attacks, standard density, baseline seed
    M(end+1) = mk(42,   'normal', 1:10,         'All attacks A1-A10, normal density (baseline)');

    % Run 02 — Physical attacks at high density during peak demand
    %  A1=SourceSpike, A2=CompRamp, A3=ValveForce, A8=PipeLeak
    %  Models trained on attack_windows learn these as pressure/flow changes.
    %  Cross-regime test: same attacks in peak-demand operational context.
    M(end+1) = mk(137,  'high',   [1 2 3 8],    'Physical attacks high density (A1,A2,A3,A8)');

    % Run 03 — Sensor spoofing attacks at high density
    %  A5=PressureSpoof, A6=FlowSpoof, A9=FDI_Stealthy
    %  These manipulate sensor readings without changing physics.
    %  EKF residual should be the primary signal; cross-regime shifts the
    %  normal operating point that the EKF was calibrated against.
    M(end+1) = mk(256,  'high',   [5 6 9],      'Sensor attacks high density (A5,A6,A9)');

    % Run 04 — Cyber attacks at normal density, night regime
    %  A7=PLCLatency, A10=ReplayAttack
    %  Replay inserts stale data; its detection requires knowing the CURRENT
    %  operating point. Cross-regime replay is hardest: replayed segment is
    %  from a different demand regime than the injection window.
    M(end+1) = mk(391,  'normal', [7 10],       'Cyber attacks normal density (A7,A10)');

    % Run 05 — All attacks, low density, S1-only supply context
    %  S1-only changes the pressure gradient across the network significantly.
    %  Attacks during S1-only look different from attacks during dual-supply.
    M(end+1) = mk(512,  'low',    1:10,         'All attacks low density, S1-only supply');

    % Run 06 — Hybrid: physical source + sensor spoof + stealthy FDI
    %  Tests whether a stealthy multi-vector attack (source + sensor mismatch)
    %  can be distinguished from normal operation in a 48h context.
    M(end+1) = mk(678,  'normal', [1 5 9],      'Hybrid attack mix (A1,A5,A9)');

    % Run 07 — Flow-disruption attacks at high density during evening peak
    %  A2=CompRamp, A6=FlowSpoof, A8=PipeLeak
    %  Evening peak is the highest-variance operating period; attacks here
    %  are hardest to distinguish from demand-driven flow changes.
    M(end+1) = mk(801,  'high',   [2 6 8],      'Flow disruption attacks evening peak (A2,A6,A8)');

    % Run 08 — Control-path attacks, low density, day trough
    %  A3=ValveForce, A7=PLCLatency, A10=ReplayAttack
    %  Day trough has lowest signal variance; even low-density control attacks
    %  should produce clear anomalies — tests false-negative floor.
    M(end+1) = mk(943,  'low',    [3 7 10],     'Control path attacks low density (A3,A7,A10)');

    % Run 09 — All attacks, normal density, extended S2 interruption scenario
    %  S2 interruption at hour 10 (not 34h as in baseline timeline) means
    %  attacks happen before, during, and after a major topology change.
    M(end+1) = mk(1024, 'normal', 1:10,         'All attacks, extended S2 interruption context');

    % Run 10 — No attacks (clean reference)
    %  Used to verify FPR on continuous operation: a well-calibrated model
    %  should have <5% false alarm rate across the full 48h.
    %  NEVER included in attack-based evaluation metrics.
    M(end+1) = mk(1337, 'none',   [],           'Clean continuous run, no attacks (FPR reference)');
end


function row = mk(seed, density, attack_types, description)
    row.seed         = seed;
    row.density      = density;
    row.attack_types = attack_types;
    row.description  = description;
end


% =========================================================================
%  MANIFEST
% =========================================================================

function write_sweep_manifest(M, opt)
    fid = fopen(fullfile(opt.out_root, 'sweep_manifest.json'), 'w');
    fprintf(fid, '{\n');
    fprintf(fid, '  "n_runs": %d,\n', numel(M));
    fprintf(fid, '  "duration_h": %d,\n', opt.duration_h);
    fprintf(fid, '  "runs": [\n');
    for i = 1:numel(M)
        comma = ',';
        if i == numel(M), comma = ''; end
        fprintf(fid, '    { "run_id": %d, "seed": %d, "density": "%s", ', ...
                i, M(i).seed, M(i).density);
        fprintf(fid, '"attack_types": %s, "description": "%s", ', ...
                mat2str(M(i).attack_types), M(i).description);
        fprintf(fid, '"out_dir": "run_%02d" }%s\n', i, comma);
    end
    fprintf(fid, '  ]\n}\n');
    fclose(fid);
    fprintf('[sweep] Manifest written -> %s/sweep_manifest.json\n', opt.out_root);
end
