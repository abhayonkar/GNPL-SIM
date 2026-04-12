function devices = device_registry()
% device_registry  Complete device-to-IP mapping for the 20-node CGD network.
%
%   devices = device_registry()
%
%   Returns a struct where each field is a component name and each value
%   is a device descriptor with: id, ip, type, zone, poll_interval_s, desc.
%
%   This is the Phase 1 deliverable that gives your dataset device-level
%   identity — answering "which two devices are communicating" per row.
%
%   Architecture mirrors real Indian CGD SCADA (ONGC/IGL-style):
%     Zone 1 (critical):   Sources + Compressors → PLCs, 1s poll
%     Zone 2 (transport):  Junctions → RTUs, 1.5s poll
%     Zone 3 (delivery):   PRS + Storage + Valves + Demand → mixed, 2s poll
%     SCADA:               Central HMI/historian server
%
%   Usage:
%     devs = device_registry();
%     devs.S1.ip       % → '192.168.1.10'
%     devs.CS1.type    % → 'PLC'
%     devs.SCADA.id    % → 'SCADA_01'
%
%   See also: register_map.m, network_logger.py

    devices = struct();

    % ── SCADA Layer ───────────────────────────────────────────────────────
    devices.SCADA  = dev('SCADA_01', '192.168.1.100', 'SCADA',      0, 0,    'Master SCADA server / HMI');
    devices.HIST   = dev('HIST_01',  '192.168.1.101', 'Historian',  0, 0,    'OSIsoft PI historian');
    devices.ENG_WS = dev('ENG_01',   '192.168.1.102', 'Workstation',0, 0,    'Engineering workstation');

    % ── Zone 1: Sources + Compressors (PLC, 1s poll) ─────────────────────
    devices.S1  = dev('PLC_001', '192.168.1.10', 'PLC', 1, 1.0, 'Source S1 — CGS outlet');
    devices.S2  = dev('PLC_002', '192.168.1.11', 'PLC', 1, 1.0, 'Source S2 — CGS outlet');
    devices.CS1 = dev('PLC_003', '192.168.1.12', 'PLC', 1, 1.0, 'Compressor CS1');
    devices.CS2 = dev('PLC_004', '192.168.1.13', 'PLC', 1, 1.0, 'Compressor CS2');

    % ── Zone 2: Junctions (RTU, 1.5s poll) ───────────────────────────────
    devices.J1  = dev('RTU_005', '192.168.1.20', 'RTU', 2, 1.5, 'Junction J1');
    devices.J2  = dev('RTU_006', '192.168.1.21', 'RTU', 2, 1.5, 'Junction J2');
    devices.J3  = dev('RTU_007', '192.168.1.22', 'RTU', 2, 1.5, 'Junction J3');
    devices.J4  = dev('RTU_008', '192.168.1.23', 'RTU', 2, 1.5, 'Junction J4');
    devices.J5  = dev('RTU_009', '192.168.1.24', 'RTU', 2, 1.5, 'Junction J5');
    devices.J6  = dev('RTU_010', '192.168.1.25', 'RTU', 2, 1.5, 'Junction J6');
    devices.J7  = dev('RTU_011', '192.168.1.26', 'RTU', 2, 1.5, 'Junction J7');

    % ── Zone 3: PRS + Storage + Valves + Demand (mixed, 2s poll) ─────────
    devices.PRS1     = dev('PLC_012', '192.168.1.30', 'PLC', 3, 2.0, 'PRS1 — 18 barg setpoint');
    devices.PRS2     = dev('PLC_013', '192.168.1.31', 'PLC', 3, 2.0, 'PRS2 — 14 barg setpoint');
    devices.STO      = dev('PLC_014', '192.168.1.32', 'PLC', 3, 2.0, 'Underground storage cavern');
    devices.VALVE_E8 = dev('RTU_015', '192.168.1.33', 'RTU', 3, 2.0, 'Valve E8 — main isolation');
    devices.VALVE_E14= dev('RTU_016', '192.168.1.34', 'RTU', 3, 2.0, 'Valve E14 — STO inject');
    devices.VALVE_E15= dev('RTU_017', '192.168.1.35', 'RTU', 3, 2.0, 'Valve E15 — STO withdraw');
    devices.D1       = dev('RTU_018', '192.168.1.40', 'RTU', 3, 2.0, 'Demand node D1');
    devices.D2       = dev('RTU_019', '192.168.1.41', 'RTU', 3, 2.0, 'Demand node D2');
    devices.D3       = dev('RTU_020', '192.168.1.42', 'RTU', 3, 2.0, 'Demand node D3');
    devices.D4       = dev('RTU_021', '192.168.1.43', 'RTU', 3, 2.0, 'Demand node D4');
    devices.D5       = dev('RTU_022', '192.168.1.44', 'RTU', 3, 2.0, 'Demand node D5');
    devices.D6       = dev('RTU_023', '192.168.1.45', 'RTU', 3, 2.0, 'Demand node D6');
end


function d = dev(id, ip, type, zone, poll_s, desc)
    d.id           = id;
    d.ip           = ip;
    d.type         = type;   % 'PLC' | 'RTU' | 'SCADA' | 'Historian' | 'Workstation'
    d.zone         = zone;   % 0=SCADA, 1=sources/comp, 2=transport, 3=delivery
    d.poll_interval_s = poll_s;
    d.desc         = desc;
end
