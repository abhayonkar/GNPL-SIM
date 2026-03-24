function plc = updatePLC(plc, sensor_p, sensor_q, k, cfg)
% updatePLC  Zone-based PLC sensor register update.
%
%   plc = updatePLC(plc, sensor_p, sensor_q, k, cfg)
%
%   UPGRADE FROM PHASE 3 (all nodes polled at z1 rate):
%   ─────────────────────────────────────────────────────
%   The previous implementation polled ALL nodes at cfg.plc_period_z1.
%   Real SCADA systems partition nodes into priority zones with different
%   poll rates. Lower-priority nodes are polled less frequently, creating
%   realistic register staleness patterns that are IDS features.
%
%   ZONE ASSIGNMENTS (from cfg, Section 9):
%     Zone 1 (cfg.plc_period_z1 = 10 steps = 1.0 s):
%       Critical nodes: sources, compressors, delivery points.
%       These are polled most frequently — operator impact is highest.
%
%     Zone 2 (cfg.plc_period_z2 = 15 steps = 1.5 s):
%       Medium-priority: junctions and PRS nodes.
%       Polled at 1.5× the base rate.
%
%     Zone 3 (cfg.plc_period_z3 = 20 steps = 2.0 s):
%       Low-priority: storage and secondary junction nodes.
%       Polled at 2× the base rate.
%
%   EFFECT ON DATASET:
%     plc.reg_p(zone3_nodes) changes at most every 2.0 s even though
%     physics advances every 0.1 s. Between polls the register holds the
%     last value (zero-order hold). This creates:
%       • Zone-dependent lag in EKF observations
%       • Characteristic "staircase" in low-priority node time series
%       • Detectable staleness signature for network-layer anomaly detectors
%
%   FLOW REGISTERS:
%     Flow registers (reg_q) use the same zone assignments as pressure.
%     In real SCADA, flow meters are often on a separate RTU scan cycle —
%     this is a simplification but consistent with the Modbus register map.

    %% Zone 1 update: critical nodes
    if mod(k, cfg.plc_period_z1) == 0
        for i = 1:numel(cfg.plc_zone1_nodes)
            n = cfg.plc_zone1_nodes(i);
            if n >= 1 && n <= numel(plc.reg_p)
                plc.reg_p(n) = sensor_p(n);
            end
        end
        % Flow edges connected to zone-1 nodes: edges 1-7, 9-11, 16-20
        z1_edges = [1,2,3,6,7,9,10,11,16,17,18,19,20];
        for ei = 1:numel(z1_edges)
            e = z1_edges(ei);
            if e >= 1 && e <= numel(plc.reg_q)
                plc.reg_q(e) = sensor_q(e);
            end
        end
    end

    %% Zone 2 update: junction + PRS nodes
    if mod(k, cfg.plc_period_z2) == 0
        for i = 1:numel(cfg.plc_zone2_nodes)
            n = cfg.plc_zone2_nodes(i);
            if n >= 1 && n <= numel(plc.reg_p)
                plc.reg_p(n) = sensor_p(n);
            end
        end
        % Flow edges in zone-2 neighbourhood: edges 4, 5, 8
        z2_edges = [4, 5, 8];
        for ei = 1:numel(z2_edges)
            e = z2_edges(ei);
            if e >= 1 && e <= numel(plc.reg_q)
                plc.reg_q(e) = sensor_q(e);
            end
        end
    end

    %% Zone 3 update: storage + secondary junction
    if mod(k, cfg.plc_period_z3) == 0
        for i = 1:numel(cfg.plc_zone3_nodes)
            n = cfg.plc_zone3_nodes(i);
            if n >= 1 && n <= numel(plc.reg_p)
                plc.reg_p(n) = sensor_p(n);
            end
        end
        % Flow edges in zone-3 neighbourhood: edges 12, 13, 14, 15
        z3_edges = [12, 13, 14, 15];
        for ei = 1:numel(z3_edges)
            e = z3_edges(ei);
            if e >= 1 && e <= numel(plc.reg_q)
                plc.reg_q(e) = sensor_q(e);
            end
        end
    end
end