function valve = initValve(cfg)
% initValve  Build the valve parameter struct from cfg.
%
%   valve = initValve(cfg)

    valve.edge = cfg.valveEdge;
    valve.open = cfg.valve_open_default;
end
