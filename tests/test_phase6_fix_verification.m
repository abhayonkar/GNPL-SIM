%% test_phase6_fix_verification.m
% =========================================================================
%  Phase 6 CUSUM Fix Verification Test
%  =========================================================================
%  This test verifies that the fix from Task 3.1 is correctly implemented.
%  It checks that runSimulation.m line 171 calls updateCUSUM with 4 args.
%
%  Run from workspace root:
%    >> cd <workspace_root>
%    >> tests/test_phase6_fix_verification
%
% =========================================================================

function test_phase6_fix_verification()
    fprintf('\n');
    fprintf('=========================================================\n');
    fprintf('  Phase 6 CUSUM Fix Verification Test\n');
    fprintf('=========================================================\n\n');
    
    % Read the runSimulation.m file
    fid = fopen('runSimulation.m', 'r');
    if fid == -1
        fprintf('  FAIL: Could not open runSimulation.m\n');
        return;
    end
    
    content = fread(fid, '*char')';
    fclose(fid);
    
    % Search for the updateCUSUM call
    % The correct call should be: cusum = updateCUSUM(cusum, ekf.residual, cfg, k);
    % The buggy call was: cusum = updateCUSUM(cusum, ekf, cfg, k, dt);
    
    % Check for the correct pattern
    correct_pattern = 'updateCUSUM(cusum, ekf.residual, cfg, k)';
    buggy_pattern = 'updateCUSUM(cusum, ekf, cfg, k, dt)';
    
    has_correct = contains(content, correct_pattern);
    has_buggy = contains(content, buggy_pattern);
    
    fprintf('--- Checking runSimulation.m for updateCUSUM call ---\n');
    fprintf('  Looking for correct call: updateCUSUM(cusum, ekf.residual, cfg, k)\n');
    fprintf('  Looking for buggy call:   updateCUSUM(cusum, ekf, cfg, k, dt)\n\n');
    
    if has_correct && ~has_buggy
        fprintf('  ✓ PASS: Fix is correctly implemented\n');
        fprintf('  ✓ Found correct 4-argument call with ekf.residual\n');
        fprintf('  ✓ No buggy 5-argument call found\n');
        status = 'PASS';
    elseif has_buggy
        fprintf('  ✗ FAIL: Buggy call still present\n');
        fprintf('  ✗ Found buggy 5-argument call: updateCUSUM(cusum, ekf, cfg, k, dt)\n');
        status = 'FAIL';
    elseif ~has_correct
        fprintf('  ✗ FAIL: Correct call not found\n');
        fprintf('  ✗ Expected: updateCUSUM(cusum, ekf.residual, cfg, k)\n');
        status = 'FAIL';
    else
        fprintf('  ? UNKNOWN: Unexpected state\n');
        status = 'UNKNOWN';
    end
    
    fprintf('\n=========================================================\n');
    fprintf('  Result: %s\n', status);
    fprintf('=========================================================\n\n');
end
