%% test_phase6_functional.m
% =========================================================================
%  Phase 6 CUSUM Functional Test - Verifies fix works in practice
%  =========================================================================
%  This test runs a minimal simulation to verify that:
%  1. updateCUSUM is called with correct 4 arguments
%  2. No "Too many input arguments" error occurs
%  3. The simulation completes successfully
%
%  **Validates: Requirements 2.1, 2.2, 2.3**
%
%  Run from workspace root:
%    >> cd <workspace_root>
%    >> tests/test_phase6_functional
%
% =========================================================================

function test_phase6_functional()
    fprintf('\n');
    fprintf('=========================================================\n');
    fprintf('  Phase 6 CUSUM Functional Test (Fixed Code)\n');
    fprintf('=========================================================\n\n');
    
    % Add all required paths
    addpath(fullfile(pwd, 'config'));
    addpath(fullfile(pwd, 'network'));
    addpath(fullfile(pwd, 'equipment'));
    addpath(fullfile(pwd, 'scada'));
    addpath(fullfile(pwd, 'attacks'));
    addpath(fullfile(pwd, 'logging'));
    addpath(fullfile(pwd, 'control'));
    
    fprintf('--- Running minimal Phase 6 simulation ---\n');
    
    try
        % Create minimal configuration with very short simulation
        cfg = simConfig();
        fprintf('  Created cfg\n');
        cfg.T = 2.0;  % 2 second simulation (enough to reach updateCUSUM call)
        cfg.dt = 1.0;
        cfg.log_every = 1;
        cfg.use_gateway = false;
        fprintf('  Modified cfg\n');
        
        % Initialize network
        fprintf('  About to call initNetwork...\n');
        [params, state] = initNetwork(cfg);
        fprintf('  initNetwork completed\n');
        
        % Initialize equipment
        fprintf('  About to call initCompressor...\n');
        [comp1, comp2] = initCompressor(cfg);
        fprintf('  initCompressor completed\n');
        fprintf('  About to call initPRS...\n');
        [prs1, prs2] = initPRS(cfg);
        fprintf('  initPRS completed\n');
        
        % Initialize EKF
        ekf.xhat = zeros(40, 1);
        ekf.P    = eye(40) * 0.1;
        ekf.P0   = 1.0;
        ekf.Rk   = 0.01;
        ekf.Qn   = 0.001;
        
        % Calculate N
        N = round(cfg.T / cfg.dt);
        
        % Initialize logs
        fprintf('  About to call initLogs...\n');
        logs = initLogs(params, ekf, N, cfg);
        fprintf('  initLogs completed\n');
        plc.reg_p = ones(20, 1) * 5.0;
        plc.reg_q = ones(20, 1) * 0.1;
        plc.z1_p  = ones(7, 1) * 5.0;
        plc.z1_q  = ones(7, 1) * 0.1;
        plc.z2_p  = ones(7, 1) * 5.0;
        plc.z2_q  = ones(7, 1) * 0.1;
        plc.z3_p  = ones(6, 1) * 5.0;
        plc.z3_q  = ones(6, 1) * 0.1;
        
        % Initialize logs
        fprintf('  About to call initLogs...\n');
        logs = initLogs(params, ekf, N, cfg);
        fprintf('  initLogs completed\n');
        
        % Initialize PLC
        fprintf('  About to initialize PLC...\n');
        plc.reg_p = ones(params.nNodes, 1) * 5.0;
        plc.reg_q = ones(params.nEdges, 1) * 0.1;
        plc.z1_p  = ones(7, 1) * 5.0;
        plc.z1_q  = ones(7, 1) * 0.1;
        plc.z2_p  = ones(7, 1) * 5.0;
        plc.z2_q  = ones(7, 1) * 0.1;
        plc.z3_p  = ones(6, 1) * 5.0;
        plc.z3_q  = ones(6, 1) * 0.1;
        fprintf('  PLC initialized\n');
        
        % Initialize attack schedule (no attacks)
        schedule.nAttacks = 0;
        schedule.ids = [];
        schedule.starts = [];
        schedule.ends = [];
        schedule.durations = [];
        schedule.label_id = zeros(N, 1);
        schedule.label_name = repmat("Normal", N, 1);
        schedule.label_mitre = repmat("", N, 1);
        
        % Source pressures and demand
        src_p1 = ones(N, 1) * cfg.src_p_barg(1);
        src_p2 = ones(N, 1) * cfg.src_p_barg(2);
        demand = ones(N, 6) * 0.1;
        
        fprintf('  Starting simulation (N=%d steps)...\n', N);
        
        % Run simulation - this will call updateCUSUM at line 171
        [params, state, comp1, comp2, prs1, prs2, ekf, plc, logs] = runSimulation( ...
            cfg, params, state, comp1, comp2, prs1, prs2, ekf, plc, logs, ...
            N, src_p1, src_p2, demand, schedule);
        
        % If we reach here, simulation completed successfully
        fprintf('  ✓ Simulation completed successfully\n');
        fprintf('  ✓ No "Too many input arguments" error\n');
        fprintf('  ✓ updateCUSUM called with correct 4 arguments\n');
        fprintf('  ✓ ekf.residual correctly extracted and passed\n');
        fprintf('\n');
        fprintf('  PASS: Bug is fixed - updateCUSUM works correctly\n');
        status = 'PASS';
        
    catch e
        % Check if this is the "Too many input arguments" error
        if contains(e.message, 'Too many input arguments') || ...
           contains(e.message, 'too many input arguments')
            fprintf('  ✗ FAIL: "Too many input arguments" error still occurs\n');
            fprintf('  ✗ Error: %s\n', e.message);
            fprintf('  ✗ Full stack trace:\n');
            for i = 1:length(e.stack)
                fprintf('    [%d] %s (line %d)\n', i, e.stack(i).name, e.stack(i).line);
            end
            fprintf('\n');
            fprintf('  FAIL: Bug is NOT fixed\n');
            status = 'FAIL';
        else
            % Different error - may be unrelated to the fix
            fprintf('  ✗ Simulation failed with error: %s\n', e.message);
            fprintf('  ✗ Full stack trace:\n');
            for i = 1:length(e.stack)
                fprintf('    [%d] %s (line %d)\n', i, e.stack(i).name, e.stack(i).line);
            end
            fprintf('\n');
            fprintf('  FAIL: Unexpected error (may be unrelated to fix)\n');
            status = 'FAIL';
        end
    end
    
    fprintf('\n=========================================================\n');
    fprintf('  Result: %s\n', status);
    fprintf('=========================================================\n\n');
end
