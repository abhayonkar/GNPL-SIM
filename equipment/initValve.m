function valve = initValve(cfg)
% initValve  Build the valve parameter struct for the 20-node network.
%
%   valve = initValve(cfg)
%
%   The 20-node network has 3 valve edges:
%     E8  (index 8)  : J2 → J6   upper branch isolation
%     E14 (index 14) : J7 → STO  storage inject
%     E15 (index 15) : STO → J5  storage withdraw
%
%   cfg fields used:
%     cfg.valveEdges   — [8, 14, 15] vector of valve edge indices

    valve.edges = cfg.valveEdges;              % [8, 14, 15]
    valve.nValves = length(cfg.valveEdges);

    % Default states: all open (1 = open, 0 = closed)
    valve.open = ones(1, valve.nValves);

    % For backward compatibility with runSimulation (which uses act_valve_cmd scalar)
    % act_valve_cmd = 1 means E8 is open (main control valve)
    valve.act_valve_cmd = 1;
end