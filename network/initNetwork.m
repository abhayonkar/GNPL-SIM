function [params, state] = initNetwork(cfg)
% initNetwork  Build 20-node network topology, params, and initial state.
%
%   [params, state] = initNetwork(cfg)
%
%   Additions over 8-node version:
%     - Per-edge diameter and length vectors
%     - Node elevation for hydrostatic pressure terms
%     - Node type classification (source/junction/compressor/prs/storage/demand)
%     - Line pack mass per segment (pipe stores gas)
%     - Demand node indices for boundary conditions

    %% Topology
    params.nodeNames  = cfg.nodeNames;
    params.nodeTypes  = cfg.nodeTypes;
    params.nNodes     = numel(cfg.nodeNames);
    params.edges      = cfg.edges;
    params.edgeNames  = cfg.edgeNames;
    params.nEdges     = size(cfg.edges, 1);

    %% Incidence matrix B (nNodes x nEdges)
    %   B(i,e) = +1 if edge e leaves node i
    %   B(i,e) = -1 if edge e enters node i
    params.B = zeros(params.nNodes, params.nEdges);
    for e = 1:params.nEdges
        params.B(cfg.edges(e,1), e) =  1;
        params.B(cfg.edges(e,2), e) = -1;
    end

    %% Per-edge pipe properties
    params.D     = cfg.pipe_D_vec(:);
    params.L     = cfg.pipe_L_vec(:);
    params.rough = cfg.pipe_rough * ones(params.nEdges, 1);
    params.A     = pi/4 * params.D.^2;   % cross-sectional area (m^2)

    %% Per-node properties
    params.V   = cfg.node_V * ones(params.nNodes, 1);
    params.c   = cfg.c;
    params.gamma = cfg.gamma;

    %% Elevation (m) - used for hydrostatic pressure correction
    params.elev = cfg.nodeElevation(:);   % nNodes x 1

    %% Hydrostatic pressure correction per edge (bar)
    %   dP_hydro = rho * g * (z_from - z_to) / 1e5
    %   Positive means flow assisted by gravity (downhill)
    g = 9.81;
    rho_ref = 60.0;   % kg/m^3 at 50 bar, 285K (approx for compressed natural gas)
    params.dP_hydro = zeros(params.nEdges, 1);
    for e = 1:params.nEdges
        dz = params.elev(cfg.edges(e,1)) - params.elev(cfg.edges(e,2));
        params.dP_hydro(e) = rho_ref * g * dz / 1e5;   % bar
    end

    %% Node type index sets (used for boundary conditions)
    params.sourceNodes    = find(strcmp(cellstr(cfg.nodeTypes), 'source'));
    params.demandNodes    = find(strcmp(cellstr(cfg.nodeTypes), 'demand'));
    params.compNodes      = find(strcmp(cellstr(cfg.nodeTypes), 'compressor'));
    params.prsNodes       = find(strcmp(cellstr(cfg.nodeTypes), 'prs'));
    params.storageNodes   = find(strcmp(cellstr(cfg.nodeTypes), 'storage'));
    params.junctionNodes  = find(strcmp(cellstr(cfg.nodeTypes), 'junction'));

    %% Valve edges
    params.valveEdges = cfg.valveEdges;
    params.valveState = ones(numel(cfg.valveEdges), 1);  % 1=open

    %% Turbulence state (AR(1) per edge) -- initialised to zero
    params.turb_state = zeros(params.nEdges, 1);

    %% Initial physical state
    state.p    = cfg.p0 * ones(params.nNodes, 1);
    state.q    = zeros(params.nEdges, 1);
    state.Tgas = cfg.T0 * ones(params.nNodes, 1);

    % Real-gas density (initialised with ideal gas)
    state.rho  = cfg.rho0 * state.p ./ state.Tgas;

    % Line pack: mass stored in each pipe segment (kg)
    %   M_e = rho_avg * A_e * L_e
    rho_avg = cfg.rho0 * cfg.p0 / cfg.T0;
    state.linepack = rho_avg * params.A .* params.L;   % nEdges x 1

    % Compressor state fields
    state.W1  = 0;  state.H1  = 0;  state.eta1 = 0;
    state.W2  = 0;  state.H2  = 0;  state.eta2 = 0;

    % Storage inventory (fraction 0-1)
    state.sto_inventory = cfg.sto_inventory_init;

    % PRS throttle positions (0=closed, 1=fully open)
    state.prs1_throttle = 0.8;
    state.prs2_throttle = 0.8;
end