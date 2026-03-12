% main_simulation.m
% Gas Pipeline Cyber-Physical Simulator -- v2 with 8 attack scenarios
%
% Run this file from the gas_pipeline_sim_v2 root directory:
%   >> cd gas_pipeline_sim_v2
%   >> main_simulation
%
% Output files (automated_dataset/):
%   master_dataset.csv, normal_only.csv, attacks_only.csv,
%   attack_metadata.json, attack_timeline.log, execution_details.log

clear; clc;
fprintf('=== Gas Pipeline CPS Simulator v2 ===\n');
fprintf('    8 Attack Scenarios + Continuous Physics Noise\n\n');

%% Add all module paths ------------------------------------------------
addpath('config');
addpath('network');
addpath('equipment');
addpath('scada');
addpath('control');
addpath('attacks');
addpath('profiling');
addpath('logging');
addpath('export');

%% Load configuration --------------------------------------------------
cfg = simConfig();
N   = round(cfg.T / cfg.dt);
fprintf('[init] dt=%.2fs  T=%.0fmin  N=%d steps\n', cfg.dt, cfg.T/60, N);

%% Initialize logger ---------------------------------------------------
initLogger(cfg.dt, cfg.T, N);

%% Initialize network --------------------------------------------------
[params, state] = initNetwork(cfg);
logEvent('INFO', 'main', 'Network topology initialised', 0, cfg.dt);

%% Initialize equipment ------------------------------------------------
comp  = initCompressor(cfg);
valve = initValve(cfg);
% Add surge noise state
comp.surge_state = 0;

%% Initialize SCADA ----------------------------------------------------
ekf = initEKF(cfg, state);
plc = initPLC(cfg, state, comp);

%% Initialize logs -----------------------------------------------------
logs = initLogs(params, ekf, N);

%% Generate source profile and demand ----------------------------------
fprintf('[init] Generating source pressure and demand profiles...\n');
[src_p, demand] = generateSourceProfile(N, cfg);
fprintf('[init] Source pressure: [%.3f, %.3f] bar\n', min(src_p), max(src_p));
fprintf('[init] Demand:          [%.4f, %.4f]\n', min(demand), max(demand));

%% Build attack schedule (8 attacks over 120 min) ----------------------
schedule = initAttackSchedule(N, cfg);

%% Initialize pipe roughness state (used by updateFlow noise) ----------
% Roughness starts at nominal; will drift in runSimulation
params.rough  = cfg.pipe_rough * ones(params.nEdges, 1);
params.turb_state = zeros(params.nEdges, 1);

logEvent('INFO', 'main', ...
    sprintf('Starting simulation: N=%d  attacks=%d', N, schedule.nAttacks), ...
    0, cfg.dt);

%% Run simulation ------------------------------------------------------
t_sim_start = tic;
[params, state, comp, valve, ekf, plc, logs] = runSimulation( ...
    cfg, params, state, comp, valve, ekf, plc, logs, ...
    N, src_p, demand, schedule);
t_sim_elapsed = toc(t_sim_start);
fprintf('\n[sim] Simulation complete in %.1f seconds\n', t_sim_elapsed);

%% Export dataset ------------------------------------------------------
fprintf('[export] Writing dataset files...\n');
exportDataset(logs, cfg, params, N, schedule);
exportResults(logs, params);

%% Close logger --------------------------------------------------------
closeLogger(cfg.dt, N);

fprintf('\n[done] All outputs written to automated_dataset/ and data/\n');
fprintf('[done] Attack breakdown:\n');
for i = 1:schedule.nAttacks
    aid    = schedule.ids(i);
    n_rows = sum(logs.logAttackId == aid);
    nm     = char(schedule.label_name( ...
                  max(1, round(schedule.start_s(i)/cfg.dt))));
    fprintf('       A%d %-40s  %6d rows (%.1f min)\n', ...
            aid, nm, n_rows, n_rows*cfg.dt/60);
end
n_normal = sum(logs.logAttackId == 0);
fprintf('       Normal                                     %6d rows (%.1f min)\n', ...
        n_normal, n_normal*cfg.dt/60);
