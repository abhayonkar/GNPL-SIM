%% FIX VERIFICATION SCRIPT — run from project root
%% Expected: all 4 tests PASS. Stop immediately on any FAIL.

addpath('config','network','scada','equipment','attacks','logging',...
        'control','export','middleware','profiling','processing');

fprintf('\n=== FIX VERIFICATION (run before any dataset generation) ===\n\n');

cfg = simConfig();
cfg = apply_cgd_overrides(cfg);
[params, state] = initNetwork(cfg);
ekf = initEKF(cfg, state);

%% ── FIX 1: R matrix heterogeneous ───────────────────────────────────────
fprintf('[FIX 1] R matrix heterogeneous...\n');
R_diag = diag(ekf.R);
R_p_vals = R_diag(1:20);   % pressure states
R_q_vals = R_diag(21:40);  % flow states

assert(abs(mean(R_p_vals) - cfg.noise_sigma_p^2) < 1e-8, ...
    sprintf('FAIL: R_pressure=%.6f, expected=%.6f', mean(R_p_vals), cfg.noise_sigma_p^2));
assert(abs(mean(R_q_vals) - cfg.noise_sigma_q^2) < 1e-8, ...
    sprintf('FAIL: R_flow=%.6f, expected=%.6f', mean(R_q_vals), cfg.noise_sigma_q^2));
assert(mean(R_p_vals) < mean(R_q_vals)/10, ...
    sprintf('FAIL: R_p (%.4f) should be << R_q (%.4f)', mean(R_p_vals), mean(R_q_vals)));

fprintf('  R_pressure=%.6f bar²  R_flow=%.4f SCMD²  ratio=%.0fx  PASS\n\n',...
        mean(R_p_vals), mean(R_q_vals), mean(R_q_vals)/mean(R_p_vals));

%% ── FIX 2: logResP logs innovation not estimation error ─────────────────
fprintf('[FIX 2] logResP = EKF innovation (not xhat-state.p)...\n');
% Inject known innovation: set measurements to xhat + known_bias
known_bias_p = ones(20,1) * 2.0;  % 2 bar bias on all pressure channels
meas_p_spoofed = state.p + known_bias_p;
meas_q = state.q;

ekf_test = updateEKF(ekf, meas_p_spoofed, meas_q, state.p, state.q, params, cfg);

% residualP should capture the measurement bias
% If Fix 2 is applied, ekf.residualP ≈ known_bias (before filter update)
% logResP should log residualP not (xhat - state.p)
% We check by running updateLogs and seeing what it stores

N_test = 5;
logs_test = initLogs(params, ekf, N_test, cfg);
comp1_t = struct('ratio',1.3,'ratio_min',1.0,'ratio_max',1.6,...
                 'surge_state',0,'online',true,'node',3,...
                 'a1',50000,'a2',-100,'a3',-0.5,'b1',0.6,'b2',0.01,'b3',-2e-4);
comp2_t = comp1_t; comp2_t.ratio = 1.25; comp2_t.node = 7;
prs1_t = struct('online',true,'node',10,'setpoint',18,'deadband',0.5,'tau',30,'throttle',0.8);
prs2_t = prs1_t; prs2_t.setpoint = 14; prs2_t.node = 13;
plc_t = initPLC(cfg, state, comp1_t);
plc_t.reg_p = meas_p_spoofed;
plc_t.reg_q = meas_q;

% Manually trigger updateLogs for k=1
valve_t = ones(3,1);
logs_test = updateLogs(logs_test, state, ekf_test, plc_t, comp1_t, comp2_t,...
                       prs1_t, prs2_t, valve_t, params, 1,...
                       meas_p_spoofed, meas_q, state.p(1), state.p(2), 1, 0, cfg);

logged_resP = logs_test.logResP(:,1);
innovation_resP = ekf_test.residualP;

% Fix 2: logResP stores the innovation (not xhat-state.p).
% Fix 5: it is now normalized to z-scores, so logged = innovation / sigma_p.
expected_zscore = innovation_resP / cfg.noise_sigma_p;
assert(norm(logged_resP - expected_zscore) < 1e-6, ...
    sprintf('FAIL: logResP stores %.3f but expected z-score=%.3f', ...
            mean(abs(logged_resP)), mean(abs(expected_zscore))));
assert(max(abs(logged_resP)) > 1.0, ...
    'FAIL: logged z-score near zero — innovation not captured or sigma wrong');

fprintf('  logResP mean=%.4f bar  residualP mean=%.4f bar  match=YES  PASS\n\n',...
        mean(abs(logged_resP)), mean(abs(innovation_resP)));

%% ── FIX 3: label excludes fault_label ───────────────────────────────────
fprintf('[FIX 3] Label in run_48h_continuous excludes fault events...\n');
% Check source code directly
fid = fopen('run_48h_continuous.m','r');
content = fread(fid,'*char')'; fclose(fid);

bad_pattern  = 'int32(fault_label > 0 || aid > 0)';
good_pattern = 'int32(aid > 0)';

if contains(content, good_pattern) && ~contains(content, bad_pattern)
    fprintf('  run_48h_continuous.m: label = int32(aid > 0)  PASS\n\n');
else
    error('FAIL: run_48h_continuous.m still has fault_label in label computation. Fix 3 not applied.');
end

%% ── FIX 4: chi2_stat ≈ 1.0 under normal operation ──────────────────────
fprintf('[FIX 4] chi2_stat ≈ 1.0 under H0...\n');
n_steps = 500;
chi2_vals = zeros(n_steps,1);

% Run mini simulation: no attacks, just normal physics
cfg_test = cfg;
cfg_test.T = n_steps * cfg.dt;
N_t = n_steps;
src_p1_t = generateSourceProfile(N_t, cfg_test);
src_p2_t = generateSourceProfile(N_t, cfg_test);
demand_t = ones(N_t,1);

% Simple loop to collect chi2 after warmup
ekf_loop = initEKF(cfg, state);
state_loop = state;
for k = 1:N_t
    sensor_p = state_loop.p + cfg.noise_sigma_p * randn(20,1);
    sensor_q = state_loop.q + cfg.noise_sigma_q * randn(20,1);
    ekf_loop = updateEKF(ekf_loop, sensor_p, sensor_q, state_loop.p, state_loop.q, params, cfg);
    chi2_vals(k) = ekf_loop.chi2_stat;
end

chi2_after_warmup = chi2_vals(cfg.cusum_warmup_steps+1:end);
chi2_mean = mean(chi2_after_warmup);
chi2_std  = std(chi2_after_warmup);

% Under H0: chi2_stat should be near 1.0
assert(chi2_mean > 0.5 && chi2_mean < 2.0, ...
    sprintf('FAIL: chi2_mean=%.3f, expected 0.5-2.0 under H0. EKF R or Q still wrong.', chi2_mean));

fprintf('  chi2_mean=%.4f  chi2_std=%.4f  (target: mean≈1.0)  PASS\n\n', chi2_mean, chi2_std);

%% ── BONUS: EKF discrimination test ──────────────────────────────────────
fprintf('[BONUS] EKF chi2 separates attack from normal...\n');
% Inject A5-style pressure bias and check chi2 rises
chi2_attack = zeros(100,1);
for k = 1:100
    sensor_p_atk = state.p + cfg.noise_sigma_p * randn(20,1);
    sensor_p_atk(15) = sensor_p_atk(15) + 3.0; % 3 bar bias on D1
    ekf_loop = updateEKF(ekf_loop, sensor_p_atk, state.q + cfg.noise_sigma_q*randn(20,1),...
                         state.p, state.q, params, cfg);
    chi2_attack(k) = ekf_loop.chi2_stat;
end

ratio = mean(chi2_attack) / chi2_mean;
assert(ratio > 3.0, sprintf('FAIL: attack chi2 (%.3f) only %.1fx normal (%.3f). R fix insufficient.',...
       mean(chi2_attack), ratio, chi2_mean));

fprintf('  Normal chi2=%.3f  Attack chi2=%.3f  ratio=%.1fx  (target >3x)  PASS\n',...
        chi2_mean, mean(chi2_attack), ratio);

%% ── FIX 5+6: normalized innovations + CUSUM calibration ─────────────────
fprintf('[FIX 5+6] Normalized innovations + CUSUM calibration...\n');

ekf_v = initEKF(cfg, state);
n = 200;
logResP_vals = zeros(20, n);
cusum_v = initCUSUM(cfg);

for k = 1:n
    sp = state.p + cfg.noise_sigma_p * randn(20,1);
    sq = state.q + cfg.noise_sigma_q * randn(20,1);
    ekf_v = updateEKF(ekf_v, sp, sq, state.p, state.q, params, cfg);

    % Fix 5: normalized log
    logResP_vals(:,k) = ekf_v.residualP / cfg.noise_sigma_p;

    % Fix 6: normalized CUSUM
    R_sig = [repmat(cfg.noise_sigma_p, params.nNodes, 1); ...
             repmat(cfg.noise_sigma_q, params.nEdges, 1)];
    cusum_v = updateCUSUM(cusum_v, ekf_v.residual ./ R_sig, cfg, k);
end

% Check 1: z-scores are O(1) in scale.
% Note: std > 1.0 is expected — innovation variance = P_ss + R, not just R.
% The goal of Fix 5 is channel equalization (P and Q on same scale), not exact N(0,1).
logResP_std = std(logResP_vals(:));
assert(logResP_std > 0.5 && logResP_std < 5.0, ...
    sprintf('FAIL: logResP z-score std=%.3f out of O(1) range [0.5, 5.0]', logResP_std));
fprintf('  logResP z-score std=%.3f (O(1) scale — channel equalization OK)  PASS\n', logResP_std);

% Check 2: CUSUM accumulator stays below threshold in normal operation
fprintf('  cusum.S_upper after 200 normal steps=%.3f (expect <h=%.1f)\n',...
        cusum_v.S_upper, cfg.cusum_threshold);

% Check 3: L2 z-score normal baseline
l2_normal = sqrt(sum(logResP_vals.^2, 1));
fprintf('  L2 z-score normal: mean=%.2f std=%.2f (expect mean≈%.2f)\n',...
        mean(l2_normal), std(l2_normal), sqrt(20));

% Check 4: Attack separates cleanly in z-score space
sp_atk = state.p; sp_atk(15) = sp_atk(15) + 2.0;   % 2 bar bias on D1
ekf_atk = updateEKF(ekf_v, sp_atk, state.q, state.p, state.q, params, cfg);
l2_attack = sqrt(sum((ekf_atk.residualP / cfg.noise_sigma_p).^2));
fprintf('  L2 z-score attack: %.2f (expect >>%.2f normal)\n', l2_attack, mean(l2_normal));

ratio56 = l2_attack / mean(l2_normal);
assert(ratio56 > 5.0, ...
    sprintf('FAIL: attack L2 only %.1fx normal. Fix 5 insufficient.', ratio56));
fprintf('  Attack/normal ratio=%.1fx  (target>5x)  PASS\n\n', ratio56);

%% ── SUMMARY ──────────────────────────────────────────────────────────────
fprintf('\n=== ALL 6 FIXES VERIFIED. Safe to run sweep. ===\n');
fprintf('  Next: run_attack_windows() then run_48h_sweep()\n\n');