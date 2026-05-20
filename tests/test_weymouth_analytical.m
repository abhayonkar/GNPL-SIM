function test_weymouth_analytical()
% test_weymouth_analytical  Validate Weymouth solver against closed-form solution.
%
%   Two-node single-pipe system has a closed-form Weymouth solution:
%
%     Q² = K * (P1_abs² - P2_abs²)
%
%   where:
%     Q   = volumetric flow [SCMD]
%     K   = 433.5² * E² * (Tb/Pb)² * D^(16/3) / (SG * Tf * Z * L)
%     P_abs = absolute pressure [kPa]
%
%   Parameters chosen to match a typical CGD main distribution pipe
%   (DN200, 5 km, PNGRB T4S operating conditions).
%
%   Paper 1 Table II: "Weymouth solver validated against analytical
%   solution; error < 0.1%."
%
%   Run from MATLAB:
%     >> test_weymouth_analytical()

    fprintf('\n=== Weymouth Analytical Benchmark ===\n');

    %% --- Define test pipe parameters ---
    Tb  = 288.15;   % base temperature [K]  (15 deg C)
    Pb  = 101.325;  % base pressure [kPa abs]
    E   = 0.92;     % Weymouth efficiency factor
    D   = 0.2032;   % pipe diameter [m]  (DN200)
    SG  = 0.57;     % specific gravity
    Tf  = 308.15;   % flowing temperature [K]  (35 deg C)
    Z   = 0.95;     % compressibility factor
    L   = 5.0;      % pipe length [km]

    P1_barg = 22.0;   % upstream pressure [barg]
    P2_barg = 18.0;   % downstream pressure [barg]

    %% --- Analytical Weymouth solution ---
    K = (433.5 * E * Tb / Pb)^2 * D^(16/3) / (SG * Tf * Z * L);

    % Convert to kPa abs
    P1_kPa = (P1_barg + 1.01325) * 100;
    P2_kPa = (P2_barg + 1.01325) * 100;

    Q_analytical = sqrt(K * (P1_kPa^2 - P2_kPa^2));   % SCMD

    fprintf('  Pipe: DN200, L=%g km, D=%g m\n', L, D);
    fprintf('  P1=%g barg, P2=%g barg\n', P1_barg, P2_barg);
    fprintf('  Analytical Q = %.4f SCMD\n', Q_analytical);

    %% --- Simulate using computeFlows ---
    % Build a minimal 2-node cfg + params struct
    cfg_t.n_nodes  = 2;
    cfg_t.n_pipes  = 1;
    cfg_t.pipe_eff = E;
    cfg_t.gas_SG   = SG;
    cfg_t.T_avg_K  = Tf;
    cfg_t.Z_factor = Z;
    cfg_t.q_max_scmd = 5000;
    cfg_t.edges    = [1, 2];

    params_t.L = L;
    params_t.D = D;
    % Build incidence manually: E1 leaves node 1, arrives at node 2
    params_t.B = [1; -1];   % 2x1

    pressures_t = [P1_barg; P2_barg];
    demands_t   = [0; 0];

    [Q_sim, dp_sim] = computeFlows(cfg_t, params_t, pressures_t, demands_t);

    fprintf('  Simulated  Q = %.4f SCMD  (dp=%.4f barg)\n', Q_sim(1), dp_sim(1));

    %% --- Error check ---
    rel_err = abs(Q_sim(1) - Q_analytical) / Q_analytical * 100;
    fprintf('  Relative error = %.4f%%\n', rel_err);

    assert(isfinite(Q_sim(1)),      'FAIL: Q_sim is not finite');
    assert(Q_sim(1) > 0,            'FAIL: Q_sim should be positive (P1 > P2)');
    assert(rel_err < 0.1,           sprintf('FAIL: relative error %.4f%% exceeds 0.1%% target', rel_err));

    fprintf('  PASS: Weymouth solver error = %.5f%% < 0.1%% target\n\n', rel_err);

    %% --- Additional check: zero pressure differential gives zero flow ---
    [Q_flat, ~] = computeFlows(cfg_t, params_t, [21.0; 21.0], [0; 0]);
    assert(abs(Q_flat(1)) < 1e-6, 'FAIL: zero dp should give zero flow');
    fprintf('  PASS: flat pressure -> Q = %.2e SCMD (near zero)\n', Q_flat(1));

    %% --- Check flow direction reversal ---
    [Q_rev, ~] = computeFlows(cfg_t, params_t, [P2_barg; P1_barg], [0; 0]);
    assert(Q_rev(1) < 0,           'FAIL: reversed pressure should give negative flow');
    assert(abs(abs(Q_rev(1)) - Q_analytical) / Q_analytical * 100 < 0.1, ...
           'FAIL: reversed flow magnitude should equal forward flow');
    fprintf('  PASS: reversed pressure -> Q = %.4f SCMD (sign flip OK)\n', Q_rev(1));

    fprintf('\n=== ALL TESTS PASSED ===\n\n');
end
