function cfg = simConfig()
% simConfig  Master configuration for the 20-node Indian CGD simulator.
%
% All European / GasLib-24 parameters have been replaced with PNGRB
% T4S-compliant Indian CGD values (ONGC/GAIL natural gas supply).
%
% Phase changelog:
%   Phase 7  : Indian CGD parameterisation, E21/E22 resilience edges
%   Phase A  : Storage loop divergence fix (sto_p_inject/withdraw/k_flow)
%              CUSUM cold-start fix (cusum_slack, cusum_warmup_steps)
%   Phase B  : sim_duration_min, attack_selection, forced_attack_id fields
%
% Verification after edit:
%   >> cfg = simConfig();
%   >> assert(cfg.src_p_barg(1) >= 20 && cfg.src_p_barg(1) <= 26)
%   >> assert(cfg.sto_p_inject == 24.5)
%   >> assert(cfg.cusum_slack  == 2.5)

    % ================================================================
    % NETWORK TOPOLOGY
    % ================================================================
    cfg.n_nodes = 20;
    cfg.n_pipes = 22;   % 20 base + E21 + E22 resilience edges

    % Node type labels (informational; used by exportDataset and IDS)
    cfg.node_types = { ...
        'source','source',          ...  % S1, S2 (CGS outlets)
        'compressor','compressor',  ...  % CS1, CS2
        'junction','junction','junction','junction','junction','junction','junction', ... % J1-J7
        'demand','demand',          ...  % D1, D2
        'prs','prs',               ...  % PRS1, PRS2
        'storage','storage',        ...  % STO1, STO2
        'drs','drs','drs','drs'    ...  % DRS1-DRS4
    };

    % ================================================================
    % PIPE GEOMETRY  (IS 3589 / API 5L Gr.B, DN50–DN300)
    % ================================================================
    % Lengths [km] — pipes 1–20 + E21 (J4→J7, 8 km) + E22 (J3→J5, 12 km)
    cfg.pipe_L = [ ...
        5.0, 8.0, 6.0, 7.0, 5.5, 9.0, 4.0, 6.5, 8.0, 5.0, ...
        7.0, 6.0, 5.0, 4.5, 8.0, 6.5, 7.0, 5.5, 6.0, 4.0, ...
        8.0, 12.0 ...   % E21, E22
    ]';

    % Diameters [m] — DN50=0.0508 … DN300=0.3048
    cfg.pipe_D = [ ...
        0.2032, 0.3048, 0.2540, 0.2032, 0.1524, 0.3048, 0.2032, 0.1524, ...
        0.2540, 0.1524, 0.2032, 0.1524, 0.1016, 0.1524, 0.2032, 0.1524, ...
        0.1016, 0.1524, 0.1016, 0.0762, ...
        0.1016, 0.0762 ...   % E21 (DN100), E22 (DN80)
    ]';

    cfg.pipe_eff = 0.92;    % Weymouth efficiency factor

    % Pipe material: API 5L Gr.B / IS 3589 Gr.410
    % MAOP per PNGRB T4S: 26 barg (design pressure)
    cfg.pipe_MAOP_barg = 26.0;

    % ================================================================
    % GAS PROPERTIES  (ONGC/GAIL supply, IS 4693)
    % ================================================================
    cfg.gas_SG     = 0.57;          % specific gravity (air=1)
    cfg.Z_factor   = 0.95;          % compressibility at 20 bar / 35°C
    cfg.T_avg_K    = 308.15;        % 35°C → K (conservative summer avg)
    cfg.T_min_K    = 293.15;        % 20°C
    cfg.T_max_K    = 318.15;        % 45°C

    % ================================================================
    % SOURCE / CGS PRESSURES  (barg)
    % ================================================================
    % CGS outlet: 20–26 barg; DRS inlet: 14–18 barg
    cfg.src_p_barg   = [22.0, 21.0];   % S1, S2 nominal setpoints
    cfg.src_p_min    = 20.0;
    cfg.src_p_max    = 26.0;

    % PRS setpoints (barg)
    cfg.prs1_setpoint_barg = 18.0;
    cfg.prs2_setpoint_barg = 14.0;

    % DRS delivery pressure target (barg)
    cfg.drs_p_target_barg  = [16.0, 15.5, 15.0, 14.5];   % DRS1–DRS4

    % ================================================================
    % COMPRESSOR PARAMETERS
    % ================================================================
    cfg.comp_ratio_min = 1.1;
    cfg.comp_ratio_max = 1.6;
    cfg.comp_ratio_nom = [1.3, 1.25];   % CS1, CS2 nominal

    % ================================================================
    % DEMAND / FLOW  (SCMD — standard cubic metres per day, city scale)
    % ================================================================
    cfg.q_min_scmd  = 0;
    cfg.q_max_scmd  = 2000;
    cfg.q_nom_scmd  = 800;      % nominal city demand

    % Demand node daily pattern multipliers (24 values, hourly)
    cfg.demand_profile = [ ...
        0.60 0.55 0.52 0.50 0.52 0.60 ...   % 00–05 h
        0.75 0.90 1.10 1.15 1.10 1.05 ...   % 06–11 h
        1.00 0.95 0.90 0.88 0.90 1.00 ...   % 12–17 h
        1.10 1.20 1.15 1.05 0.90 0.70 ...   % 18–23 h
    ];

    % ================================================================
    % STORAGE NODE PARAMETERS  — Phase A divergence fix
    % ================================================================
    % Previously incorrect values caused J7→70 bar and J5→0.1 bar blowup.
    % Fix: tighten inject/withdraw bounds to within Indian CGD MAOP range.
    cfg.sto_p_inject   = 24.5;   % barg — max injection pressure (≤ MAOP 26)
    cfg.sto_p_withdraw = 16.5;   % barg — min withdrawal pressure (≥ DRS floor)
    cfg.sto_k_flow     = 0.2;    % flow gain coefficient [SCMD/barg]

    cfg.sto_vol_m3     = [5000, 3000];   % STO1, STO2 working volumes [m³]
    cfg.sto_soc_init   = [0.60, 0.55];   % initial state-of-charge [fraction]

    % ================================================================
    % RESILIENCE EDGES  (Phase 7)
    % ================================================================
    % E21: J4 → J7 cross-tie  (pipe index 21, DN100, 8 km)
    % E22: J3 → J5 emergency bypass (pipe index 22, DN80, 12 km)
    % Both OFF by default; PLC-activated via cs2_alarm coil
    cfg.resilience_edge_idx  = [21, 22];
    cfg.resilience_valve_idx = [21, 22];    % Modbus coil addresses 4, 5
    cfg.resilience_default   = [0, 0];      % 0 = closed

    % Isolation valve V_D1 on pipe E10 (Modbus coil 6)
    cfg.isolation_valve_pipe = 10;
    cfg.isolation_valve_coil = 6;

    % ================================================================
    % EKF PARAMETERS
    % ================================================================
    cfg.ekf_n_states   = 40;        % 20 pressures + 20 flows
    cfg.ekf_Q_diag     = 1e-4;      % process noise
    cfg.ekf_R_diag     = 1e-3;      % measurement noise
    cfg.ekf_P0_diag    = 1e-2;      % initial covariance

    % ================================================================
    % CUSUM PARAMETERS  — Phase A cold-start fix
    % ================================================================
    % Old slack=1.0 caused 816 false alarms during normal operation.
    % Raised to 2.5; warmup window skips alarm evaluation for first 300 s.
    cfg.cusum_slack         = 2.5;      % k — allowable slack (sigma units)
    cfg.cusum_threshold     = 12.0;     % h — decision threshold
    cfg.cusum_warmup_steps  = 300;      % steps at cfg.dt before alarms active
    cfg.cusum_reset_on_trip = true;     % reset accumulators after alarm

    % ================================================================
    % NOISE MODEL  (AR(1) — validated by verifyNoiseStats.m)
    % ================================================================
    cfg.noise_ar1_phi   = 0.85;         % AR(1) coefficient
    cfg.noise_sigma_p   = 0.02;         % pressure noise std [barg]
    cfg.noise_sigma_q   = 5.0;          % flow noise std [SCMD]

    % ================================================================
    % SIMULATION TIMING
    % ================================================================
    cfg.dt          = 0.1;              % physics timestep [s]
    cfg.log_every   = 10;              % log every N steps → 1 Hz dataset
    cfg.sim_duration_min = 1440;        % default 24 h in minutes (Phase B field)

    % ================================================================
    % ATTACK CONFIGURATION  (Phase B fields)
    % ================================================================
    cfg.n_attacks          = 8;         % actual number of attacks per sweep
    cfg.attack_selection   = 1:10;      % which attack IDs to include
    cfg.forced_attack_id   = [];        % [] = random; set integer to force

    % ================================================================
    % MODBUS / GATEWAY
    % ================================================================
    cfg.modbus_ip    = '127.0.0.1';
    cfg.modbus_port  = 1502;
    cfg.modbus_unit  = 1;
    cfg.udp_port     = 6006;

    % Holding register map (0-indexed Modbus addresses)
    cfg.reg_sensor_start   = 0;     % addresses 0–59: sensor inputs (×100 scaled)
    cfg.reg_actuator_start = 100;   % addresses 100–111: actuator outputs
    cfg.reg_resilience     = [109, 110, 111];  % E21 valve, E22 valve, V_D1

    % ================================================================
    % DATASET EXPORT
    % ================================================================
    cfg.dataset_dir     = 'dataset/';
    cfg.export_basename = 'cgd_sim';

    % Column schema version (bump when novel columns added in Phase C)
    cfg.schema_version  = 'v2.0-phase-c';

end