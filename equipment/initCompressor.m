function [comp1, comp2] = initCompressor(cfg)
% initCompressor  Initialise two compressor station structs.
%
%   [comp1, comp2] = initCompressor(cfg)
%
%   Each compressor is independent with its own:
%     - node index, ratio, head curve, efficiency curve
%     - surge state (AR(1))
%     - operational bounds

    %% Compressor Station 1 (CS1, node 3) - primary high-pressure boost
    comp1.node       = cfg.comp1_node;
    comp1.ratio      = cfg.comp1_ratio;
    comp1.ratio_min  = cfg.comp1_ratio_min;
    comp1.ratio_max  = cfg.comp1_ratio_max;
    comp1.a1 = cfg.comp1_a1; comp1.a2 = cfg.comp1_a2; comp1.a3 = cfg.comp1_a3;
    comp1.b1 = cfg.comp1_b1; comp1.b2 = cfg.comp1_b2; comp1.b3 = cfg.comp1_b3;
    comp1.surge_state = 0;
    comp1.online      = true;

    %% Compressor Station 2 (CS2, node 7) - secondary distribution boost
    comp2.node       = cfg.comp2_node;
    comp2.ratio      = cfg.comp2_ratio;
    comp2.ratio_min  = cfg.comp2_ratio_min;
    comp2.ratio_max  = cfg.comp2_ratio_max;
    comp2.a1 = cfg.comp2_a1; comp2.a2 = cfg.comp2_a2; comp2.a3 = cfg.comp2_a3;
    comp2.b1 = cfg.comp2_b1; comp2.b2 = cfg.comp2_b2; comp2.b3 = cfg.comp2_b3;
    comp2.surge_state = 0;
    comp2.online      = true;
end