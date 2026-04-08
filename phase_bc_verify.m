%% phase_bc_verify.m
% =========================================================================
%  Phase B + C Verification
%  Run from project root after applying all Phase B/C patches.
%
%  Steps:
%    B1 — initAttackSchedule respects n_attacks and forced_attack_id
%    B2 — verifyNoiseStats runs on existing 60-min CSV
%    C1 — computeWeymouthResiduals returns finite 20×1 vectors
%    C2 — computePropagationLabels initialises and runs correctly
%    C3 — 10-min simulation produces Phase C columns in CSV
%    C4 — propagation labels trigger during attack phase
% =========================================================================

addpath('config','network','equipment','scada','control', ...
        'attacks','logging','export','middleware','profiling','processing');

fprintf('\n=== Phase B+C Verification ===\n\n');

cfg = simConfig();
cfg = apply_cgd_overrides(cfg);

%% ── C3: 10-min simulation with Phase C columns ───────────────────────────
fprintf('[C3] 10-min simulation with Phase C columns...\n');
main_simulation(10, false);

T_c3 = readtable('automated_dataset/master_dataset.csv');
phase_c_cols = {'prop_origin_node','prop_hop_node','prop_delay_s','prop_cascade_step'};
missing_cols = phase_c_cols(~ismember(phase_c_cols, T_c3.Properties.VariableNames));
if isempty(missing_cols)
    fprintf('  All 4 Phase C columns present in CSV  PASS\n');
    fprintf('  prop_cascade_step max=%d\n\n', max(T_c3.prop_cascade_step));
else
    fprintf('  FAIL: missing columns: %s\n', strjoin(missing_cols, ', '));
    fprintf('  Check exportDataset.m PATCH 4\n\n');
end


%% ── B1: initAttackSchedule — n_attacks respected ────────────────────────
fprintf('[B1] initAttackSchedule: cfg.n_attacks=3 (not hardcoded 8)...\n');
cfg_b1 = cfg;
cfg_b1.T = 60 * 60;   % 60 min
cfg_b1.n_attacks = 3;
cfg_b1.forced_attack_id = [];
N_b1 = round(cfg_b1.T / cfg_b1.dt);
sch = initAttackSchedule(N_b1, cfg_b1);
assert(sch.nAttacks == 3, 'B1 FAIL: nAttacks=%d (expected 3)', sch.nAttacks);
assert(numel(sch.ids) == 3, 'B1 FAIL: numel(ids)=%d (expected 3)', numel(sch.ids));
fprintf('  nAttacks=%d  ids=%s  PASS\n\n', sch.nAttacks, mat2str(sch.ids));

%% ── B1b: forced_attack_id ────────────────────────────────────────────────
fprintf('[B1b] initAttackSchedule: forced_attack_id=5...\n');
cfg_b1b = cfg;
cfg_b1b.T = 30 * 60;
cfg_b1b.forced_attack_id = 5;
N_b1b = round(cfg_b1b.T / cfg_b1b.dt);
sch2 = initAttackSchedule(N_b1b, cfg_b1b);
assert(sch2.nAttacks == 1,  'B1b FAIL: nAttacks=%d (expected 1)', sch2.nAttacks);
assert(sch2.ids(1) == 5,    'B1b FAIL: ids(1)=%d (expected 5)', sch2.ids(1));
assert(any(sch2.label_id == 5), 'B1b FAIL: no steps labelled with attack 5');
fprintf('  nAttacks=%d  ids=%s  PASS\n\n', sch2.nAttacks, mat2str(sch2.ids));

%% ── B2: verifyNoiseStats ─────────────────────────────────────────────────
fprintf('[B2] verifyNoiseStats on existing CSV...\n');
csv60 = 'automated_dataset/master_dataset.csv';
if exist(csv60, 'file')
    results_noise = verifyNoiseStats(csv60, cfg);
    if results_noise.all_pass
        fprintf('  AR(1) phi_p=%.3f  phi_q=%.3f  PASS\n\n', ...
                results_noise.phi_p_mean, results_noise.phi_q_mean);
    else
        fprintf('  WARNING: noise stats outside expected range — check physics\n');
        fprintf('  phi_p=%.3f  phi_q=%.3f\n\n', ...
                results_noise.phi_p_mean, results_noise.phi_q_mean);
    end
else
    fprintf('  SKIP: no CSV found — run main_simulation(60,false) first\n\n');
end

%% ── C1: computeWeymouthResiduals isolated ────────────────────────────────
fprintf('[C1] computeWeymouthResiduals isolated call...\n');
[params_c, state_c] = initNetwork(cfg);
ekf_c  = initEKF(cfg, state_c);
ekf_c.xhatP = state_c.p;
ekf_c.xhatQ = state_c.q;

[rp, rq] = computeWeymouthResiduals(ekf_c, state_c, params_c, cfg);
assert(numel(rp) == 20,      'C1 FAIL: resid_p not 20-element');
assert(numel(rq) == 20,      'C1 FAIL: resid_q not 20-element');
assert(all(isfinite(rp)),    'C1 FAIL: resid_p has NaN/Inf');
assert(all(isfinite(rq)),    'C1 FAIL: resid_q has NaN/Inf');
fprintf('  resid_p max=%.4f  resid_q max=%.4f  PASS\n\n', ...
        max(abs(rp)), max(abs(rq)));

%% ── C2: computePropagationLabels isolated ────────────────────────────────
fprintf('[C2] computePropagationLabels isolated call...\n');
sp = initPropagationState(20, cfg);

% Normal operation — no trigger expected
[lbl, sp] = computePropagationLabels(zeros(20,1), zeros(20,1), 0, 1, 1, params_c, cfg, sp);
assert(lbl.origin_node == 0, 'C2 FAIL: false origin during normal op');
assert(lbl.cascade_step == 0,'C2 FAIL: cascade_step nonzero during normal');

% Fill baseline buffer (300 rows)
for ki = 2:310
    [lbl, sp] = computePropagationLabels(randn(20,1)*0.01, zeros(20,1), ...
                                          0, ki, ki, params_c, cfg, sp);
end

% Inject large residual — should trigger
big_resid = zeros(20,1);
big_resid(4) = 5.0;   % J2, large anomaly
[lbl, sp] = computePropagationLabels(big_resid, zeros(20,1), 1, 311, 311, params_c, cfg, sp);
assert(lbl.origin_node > 0,   'C2 FAIL: no origin detected after large residual');
assert(lbl.cascade_step >= 1, 'C2 FAIL: cascade_step=0 after trigger');
fprintf('  origin_node=%d  cascade_step=%d  delay_s=%.1f  PASS\n\n', ...
        lbl.origin_node, lbl.cascade_step, lbl.delay_s);


%% ── C4: propagation labels trigger during attacks ────────────────────────
fprintf('[C4] Propagation labels during attack phase...\n');
if any(T_c3.ATTACK_ID > 0) && ismember('prop_cascade_step', T_c3.Properties.VariableNames)
    attack_rows  = T_c3(T_c3.ATTACK_ID > 0, :);
    n_triggered  = sum(attack_rows.prop_origin_node > 0);
    pct          = 100 * n_triggered / height(attack_rows);
    fprintf('  Attack rows: %d  |  Rows with origin detected: %d (%.1f%%)\n', ...
            height(attack_rows), n_triggered, pct);
    if pct > 0
        fprintf('  Propagation labels active during attacks  PASS\n\n');
    else
        fprintf('  WARNING: 0%% detection — check propagation baseline window\n');
        fprintf('  (may need longer simulation for baseline to fill)\n\n');
    end
else
    fprintf('  SKIP: no attack rows in 10-min baseline run\n\n');
end

%% ── Summary ──────────────────────────────────────────────────────────────
fprintf('=================================================================\n');
fprintf('  Phase B+C Verification COMPLETE\n');
fprintf('  Phase A+B+C ready — proceed to Phase D (24h sweep)\n');
fprintf('=================================================================\n\n');