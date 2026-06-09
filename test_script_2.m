% Run in MATLAB after Phase 2a completes:
% 1. Weymouth error:
%test_weymouth_analytical()   % must print "PASS: error < 0.001 bar"

run('C:\Users\Abhay.DESKTOP-HP65TET\Documents\Sim\tests\test_weymouth_analytical.m')

% 2. Noise stats:
cfg = simConfig();
results = verifyNoiseStats('automated_dataset/attack_windows/physics_dataset_windows.csv', cfg);
fprintf('phi_p=%.3f, phi_q=%.3f, sigma_p=%.4f, sigma_q=%.4f\n', ...
        results.phi_p_mean, results.phi_q_mean, ...
        results.sigma_p_mean, results.sigma_q_mean)

% 3. Physics compliance:
% Runs automatically during scenario generation; collect from scenario_health.csv
health = readtable('ml_outputs/attack_windows/traditional_ml/run_4_clean/scenario_health.csv');
fprintf('Compliance: %d/%d scenarios (%.1f%%)\n', ...
        sum(~health.diverged), height(health), 100*mean(~health.diverged))