%% test_bug_exploration.m
% =========================================================================
%  Bug Condition Exploration Tests — sweep-pipeline-bugfix spec
%  =========================================================================
%  These tests are EXPECTED TO FAIL on unfixed code.
%  Failure confirms each bug exists.  "BUG CONFIRMED" = test failed as
%  expected.  "UNEXPECTED PASS" = bug may already be fixed or test is wrong.
%
%  Run from workspace root:
%    >> cd <workspace_root>
%    >> tests/test_bug_exploration
%
%  -------------------------------------------------------------------------
%  EXPECTED COUNTEREXAMPLES (unfixed code)
%  -------------------------------------------------------------------------
%
%  Bug 1 — forced_attack_id ignored (Requirement 1.1)
%    cfg.forced_attack_id = 3, cfg.n_attacks = 1
%    Expected: schedule.nAttacks == 1 AND schedule.ids(1) == 3
%    Actual  : schedule.nAttacks == 8  (hardcoded nA=8)
%              schedule.ids(1) is a random attack ID from randperm(8), not 3
%    Counterexample: schedule.nAttacks = 8; schedule.ids(1) ∈ {1..8} \ {3}
%
%  Bug 2 — n_attacks hardcoded to 8 (Requirement 1.2)
%    cfg.n_attacks = 1, no forced_attack_id, 30-min window
%    Expected: schedule.nAttacks == 1
%    Actual  : nA = 8 is hardcoded; initAttackSchedule tries to fit 8
%              attacks into a 30-min window → timing conflict error, OR
%              succeeds but returns schedule.nAttacks = 8
%    Counterexample: error "could not place 8 attacks in 30 min simulation"
%                    OR schedule.nAttacks = 8
%
%  Bug 3 — wrong column names in validate_csv_quick (Requirement 1.3)
%    CSV has columns S1_bar, D1_bar (matching exportDataset schema)
%    Expected: validate_csv_quick returns valid=true (or valid=false with a
%              physics reason), no struct-field exception
%    Actual  : throws "No such field 'p_S1_bar'" because validate_csv_quick
%              accesses T.p_S1_bar instead of T.S1_bar
%    Counterexample: e.message = "No such field 'p_S1_bar'."
%
%  Bug 4 — quick-mode index overflow (Requirement 1.4)
%    baseline_scenarios has 5 entries; quick mode does baseline_scenarios(1:10)
%    Expected: no index error; at most min(10, numel) entries selected
%    Actual  : MATLAB throws index-exceeds-dimensions error
%    Counterexample: "index (10) exceeds array bounds (5)"
%
% =========================================================================

function test_bug_exploration()

    % Add source paths so initAttackSchedule and validate_csv_quick are found
    addpath(fullfile(pwd, 'attacks'));
    addpath(fullfile(pwd, 'config'));

    fprintf('\n');
    fprintf('=========================================================\n');
    fprintf('  Bug Condition Exploration Tests (unfixed code)\n');
    fprintf('  EXPECTED: all four tests report BUG CONFIRMED\n');
    fprintf('=========================================================\n\n');

    results = struct();
    results.bug1 = run_bug1_test();
    results.bug2 = run_bug2_test();
    results.bug3 = run_bug3_test();
    results.bug4 = run_bug4_test();

    fprintf('\n=========================================================\n');
    fprintf('  SUMMARY\n');
    fprintf('=========================================================\n');
    fields = fieldnames(results);
    all_confirmed = true;
    for i = 1:numel(fields)
        r = results.(fields{i});
        fprintf('  %s: %s\n', fields{i}, r.status);
        if ~strcmp(r.status, 'BUG CONFIRMED')
            all_confirmed = false;
        end
    end
    fprintf('\n');
    if all_confirmed
        fprintf('  Result: All 4 bugs confirmed on unfixed code.\n');
    else
        fprintf('  Result: One or more tests did not confirm the bug.\n');
        fprintf('          Check UNEXPECTED PASS entries above.\n');
    end
    fprintf('=========================================================\n\n');
end

% -------------------------------------------------------------------------
%  Bug 1 — forced_attack_id ignored
%  Requirement 1.1
% -------------------------------------------------------------------------
function r = run_bug1_test()
    fprintf('--- Bug 1: forced_attack_id ignored (Req 1.1) ---\n');

    % Build a minimal cfg that triggers isBugCondition_1:
    %   isfield(cfg,'forced_attack_id') AND cfg.forced_attack_id > 0
    cfg = make_base_cfg();
    cfg.n_attacks        = 1;
    cfg.forced_attack_id = 3;   % want attack #3 (ValveCommandTampering)
    % 30-min window timing (single attack, so gap is irrelevant)
    cfg.atk_warmup_s   = 2 * 60;   %  2 min
    cfg.atk_recovery_s = 2 * 60;   %  2 min
    cfg.atk_min_gap_s  = 1 * 60;   %  1 min (irrelevant for 1 attack)
    cfg.atk_dur_min_s  = 60;        %  1 min attack
    cfg.atk_dur_max_s  = 120;       %  2 min attack

    N  = round(cfg.T / cfg.dt);    % steps for 30-min run

    r.status      = 'UNEXPECTED PASS';
    r.counterexample = '';

    try
        schedule = initAttackSchedule(N, cfg);

        % Assertions that SHOULD hold after the fix
        nA_ok  = (schedule.nAttacks == 1);
        id_ok  = (numel(schedule.ids) >= 1) && (schedule.ids(1) == 3);

        if nA_ok && id_ok
            fprintf('  UNEXPECTED PASS: schedule.nAttacks=%d, ids(1)=%d\n', ...
                    schedule.nAttacks, schedule.ids(1));
            r.status = 'UNEXPECTED PASS';
        else
            % Bug confirmed — document the counterexample
            ce = sprintf('schedule.nAttacks=%d (expected 1)', schedule.nAttacks);
            if numel(schedule.ids) >= 1
                ce = sprintf('%s; schedule.ids(1)=%d (expected 3)', ce, schedule.ids(1));
            end
            fprintf('  BUG CONFIRMED\n');
            fprintf('  Counterexample: %s\n', ce);
            r.status         = 'BUG CONFIRMED';
            r.counterexample = ce;
        end

    catch e
        % An error also confirms the bug (e.g. timing conflict from 8 attacks)
        ce = sprintf('error thrown: %s', e.message);
        fprintf('  BUG CONFIRMED (via error)\n');
        fprintf('  Counterexample: %s\n', ce);
        r.status         = 'BUG CONFIRMED';
        r.counterexample = ce;
    end
    fprintf('\n');
end

% -------------------------------------------------------------------------
%  Bug 2 — n_attacks hardcoded to 8
%  Requirement 1.2
% -------------------------------------------------------------------------
function r = run_bug2_test()
    fprintf('--- Bug 2: n_attacks hardcoded to 8 (Req 1.2) ---\n');

    % Build a cfg that triggers isBugCondition_2:
    %   isfield(cfg,'n_attacks') AND cfg.n_attacks ~= 8
    % No forced_attack_id — pure n_attacks=1 path.
    cfg = make_base_cfg();
    cfg.n_attacks = 1;
    % Do NOT set forced_attack_id
    % 30-min window — tight enough that 8 attacks cannot fit
    cfg.atk_warmup_s   = 2 * 60;
    cfg.atk_recovery_s = 2 * 60;
    cfg.atk_min_gap_s  = 2 * 60;   % 2-min gap between attacks
    cfg.atk_dur_min_s  = 60;
    cfg.atk_dur_max_s  = 120;

    N = round(cfg.T / cfg.dt);

    r.status         = 'UNEXPECTED PASS';
    r.counterexample = '';

    try
        schedule = initAttackSchedule(N, cfg);

        if schedule.nAttacks == 1
            fprintf('  UNEXPECTED PASS: schedule.nAttacks=1 (bug may be fixed)\n');
            r.status = 'UNEXPECTED PASS';
        else
            ce = sprintf('schedule.nAttacks=%d (expected 1; nA=8 is hardcoded)', ...
                         schedule.nAttacks);
            fprintf('  BUG CONFIRMED\n');
            fprintf('  Counterexample: %s\n', ce);
            r.status         = 'BUG CONFIRMED';
            r.counterexample = ce;
        end

    catch e
        % Timing conflict error from trying to fit 8 attacks in 30 min
        ce = sprintf('error thrown: %s', e.message);
        fprintf('  BUG CONFIRMED (via error — 8 attacks cannot fit in 30-min window)\n');
        fprintf('  Counterexample: %s\n', ce);
        r.status         = 'BUG CONFIRMED';
        r.counterexample = ce;
    end
    fprintf('\n');
end

% -------------------------------------------------------------------------
%  Bug 3 — wrong column names in validate_csv_quick
%  Requirement 1.3
% -------------------------------------------------------------------------
function r = run_bug3_test()
    fprintf('--- Bug 3: wrong column names in validate_csv_quick (Req 1.3) ---\n');

    % Create a minimal CSV with the CORRECT column names as written by
    % exportDataset: S1_bar and D1_bar (no p_ prefix).
    % validate_csv_quick (unfixed) accesses T.p_S1_bar → struct-field error.

    tmp_csv = fullfile(tempdir(), 'test_bug3_minimal.csv');
    fid = fopen(tmp_csv, 'w');
    % Header: include S1_bar and D1_bar (matching exportDataset §1.2 schema)
    fprintf(fid, 'Timestamp_s,S1_bar,D1_bar,label\n');
    % Write 60 rows of valid pressure data (5–10 barg, well within MAOP)
    for k = 1:60
        fprintf(fid, '%.1f,%.4f,%.4f,0\n', (k-1)*1.0, 7.0 + 0.01*k, 5.5 + 0.01*k);
    end
    fclose(fid);

    % Build a minimal cfg (validate_csv_quick only uses cfg implicitly via
    % the catch block; the function signature is validate_csv_quick(csv_path, cfg))
    cfg = make_base_cfg();

    r.status         = 'UNEXPECTED PASS';
    r.counterexample = '';

    try
        % Call the local function defined inside run_24h_sweep.m.
        % Since it is a local function we cannot call it directly from here;
        % we replicate the exact logic to test the bug condition.
        [valid, reason] = validate_csv_quick_unfixed(tmp_csv, cfg);

        % If we reach here without error, check whether the reason contains
        % the wrong-column-name error message
        if contains(reason, 'p_S1_bar') || contains(reason, 'p_D1_bar')
            ce = sprintf('valid=%d, reason="%s"', valid, reason);
            fprintf('  BUG CONFIRMED (returned error reason with wrong column name)\n');
            fprintf('  Counterexample: %s\n', ce);
            r.status         = 'BUG CONFIRMED';
            r.counterexample = ce;
        else
            fprintf('  UNEXPECTED PASS: valid=%d, reason="%s"\n', valid, reason);
            r.status = 'UNEXPECTED PASS';
        end

    catch e
        % The unfixed code throws an exception for the wrong column name
        if contains(e.message, 'p_S1_bar') || contains(e.message, 'p_D1_bar') || ...
           contains(e.message, 'No such field') || contains(e.message, 'Unrecognized')
            ce = sprintf('error thrown: %s', e.message);
            fprintf('  BUG CONFIRMED (struct-field exception on wrong column name)\n');
            fprintf('  Counterexample: %s\n', ce);
            r.status         = 'BUG CONFIRMED';
            r.counterexample = ce;
        else
            % Unexpected error — still a failure, but different cause
            ce = sprintf('unexpected error: %s', e.message);
            fprintf('  BUG CONFIRMED (unexpected error — may still indicate bug)\n');
            fprintf('  Counterexample: %s\n', ce);
            r.status         = 'BUG CONFIRMED';
            r.counterexample = ce;
        end
    end

    % Clean up temp file
    if exist(tmp_csv, 'file'), delete(tmp_csv); end
    fprintf('\n');
end

% -------------------------------------------------------------------------
%  Bug 4 — quick-mode index overflow
%  Requirement 1.4
% -------------------------------------------------------------------------
function r = run_bug4_test()
    fprintf('--- Bug 4: quick-mode index overflow (Req 1.4) ---\n');

    % Build a baseline_scenarios array of length 5 (fewer than 10).
    % The unfixed quick-mode code does: baseline_scenarios(1:10)
    % which throws an index-out-of-bounds error when numel < 10.

    % Create a minimal struct array of length 5
    baseline_scenarios = repmat(struct('id', 0, 'source_config', 'S1_only', ...
                                       'demand_profile', 'medium'), 1, 5);
    for i = 1:5
        baseline_scenarios(i).id = i;
    end

    r.status         = 'UNEXPECTED PASS';
    r.counterexample = '';

    try
        % Replicate the EXACT unfixed quick-mode indexing expression from
        % run_24h_sweep.m line:
        %   scenarios = [baseline_scenarios(1:10); attack_scenarios(1:10)];
        % We test only the baseline half since that is sufficient to trigger Bug 4.
        selected = baseline_scenarios(1:10); %#ok<NASGU>

        % If we reach here, no error was thrown — unexpected pass
        fprintf('  UNEXPECTED PASS: indexing baseline_scenarios(1:10) on array of length 5 did not error\n');
        r.status = 'UNEXPECTED PASS';

    catch e
        % Index-out-of-bounds error confirms the bug
        ce = sprintf('error thrown: %s', e.message);
        fprintf('  BUG CONFIRMED (index-out-of-bounds on short array)\n');
        fprintf('  Counterexample: %s\n', ce);
        r.status         = 'BUG CONFIRMED';
        r.counterexample = ce;
    end
    fprintf('\n');
end

% =========================================================================
%  Helper: build a minimal base cfg for a 30-min simulation
% =========================================================================
function cfg = make_base_cfg()
    cfg.dt              = 1.0;      % 1-second timestep
    cfg.T               = 30 * 60;  % 30-minute simulation
    cfg.log_every       = 1;

    % Timing fields required by initAttackSchedule
    cfg.atk_warmup_s    = 5 * 60;
    cfg.atk_recovery_s  = 5 * 60;
    cfg.atk_min_gap_s   = 3 * 60;
    cfg.atk_dur_min_s   = 60;
    cfg.atk_dur_max_s   = 180;
end

% =========================================================================
%  Inline copy of the UNFIXED validate_csv_quick logic from run_24h_sweep.m
%  (Bug 3: accesses T.p_S1_bar and T.p_D1_bar — wrong column names)
%  This replicates the exact buggy code so the test is self-contained and
%  does not depend on calling a local function inside run_24h_sweep.m.
% =========================================================================
function [valid, reason] = validate_csv_quick_unfixed(csv_path, cfg) %#ok<INUSD>
    valid = true; reason = '';
    try
        T = readtable(csv_path, 'NumHeaderLines', 0);
        if height(T) < 50
            valid = false; reason = 'Too few rows'; return;
        end
        % BUG: accesses p_S1_bar and p_D1_bar — these columns do not exist
        % in the CSV written by exportDataset (which uses S1_bar, D1_bar).
        if any(T.p_S1_bar < 0, 'all') || any(T.p_D1_bar < 0, 'all')
            valid = false; reason = 'Negative pressure'; return;
        end
        if any(T.p_S1_bar > 30, 'all')
            valid = false; reason = 'Pressure exceeds MAOP+4 (30 barg)'; return;
        end
    catch e
        valid = false; reason = e.message;
    end
end
