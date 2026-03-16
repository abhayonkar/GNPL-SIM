function plc = receiveFromGateway(u, plc_prev, cfg)
% receiveFromGateway  Receive PLC actuator commands from Python gateway via UDP
%
% Reads 16 float64 values (128 bytes) from gateway UDP port 6006.
% Gateway sends raw INT values — this function divides by scale.
%
% Packet layout (16 x float64 = 128 bytes):
%   [1]  cs1_ratio_cmd_raw   INT/1000 -> ratio  (e.g. 1250 -> 1.25)
%   [2]  cs2_ratio_cmd_raw   INT/1000 -> ratio
%   [3]  valve_E8_raw        INT/1000 -> 0=closed, 1=open
%   [4]  valve_E14_raw       INT/1000 -> 0=closed, 1=open
%   [5]  valve_E15_raw       INT/1000 -> 0=closed, 1=open
%   [6]  prs1_setpoint_raw   INT/100  -> bar
%   [7]  prs2_setpoint_raw   INT/100  -> bar
%   [8]  cs1_power_raw       INT/10   -> kW
%   [9]  cs2_power_raw       INT/10   -> kW
%   [10] emergency_shutdown  0 or 1   -> bool
%   [11] cs1_alarm           0 or 1
%   [12] cs2_alarm           0 or 1
%   [13] sto_inject_active   0 or 1
%   [14] sto_withdraw_active 0 or 1
%   [15] prs1_active         0 or 1
%   [16] prs2_active         0 or 1
%
% Returns plc struct. On timeout returns plc_prev unchanged.
%
% Args:
%   u        - udpport object
%   plc_prev - previous plc struct (returned unchanged on timeout)
%   cfg      - config struct

    EXPECTED_BYTES = 16 * 8;   % 128 bytes

    plc = plc_prev;   % default: keep last known values

    try
        if u.NumBytesAvailable >= EXPECTED_BYTES
            bytes = read(u, EXPECTED_BYTES, 'uint8');
            vals  = typecast(uint8(bytes), 'double');  % 16x1

            % --- actuators (raw INT / scale) ---
            plc.cs1_ratio   = vals(1)  / 1000.0;   % e.g. 1250 -> 1.25
            plc.cs2_ratio   = vals(2)  / 1000.0;
            plc.valve_E8    = vals(3)  / 1000.0;   % 1000 -> 1.0 (open)
            plc.valve_E14   = vals(4)  / 1000.0;
            plc.valve_E15   = vals(5)  / 1000.0;
            plc.prs1_sp     = vals(6)  / 100.0;    % bar
            plc.prs2_sp     = vals(7)  / 100.0;
            plc.cs1_power   = vals(8)  / 10.0;     % kW
            plc.cs2_power   = vals(9)  / 10.0;

            % --- status coils ---
            plc.emergency_shutdown  = logical(vals(10));
            plc.cs1_alarm           = logical(vals(11));
            plc.cs2_alarm           = logical(vals(12));
            plc.sto_inject          = logical(vals(13));
            plc.sto_withdraw        = logical(vals(14));
            plc.prs1_active         = logical(vals(15));
            plc.prs2_active         = logical(vals(16));

            plc.updated = true;
            plc.last_rx = now();
        else
            plc.updated = false;   % no new data this cycle — use previous
        end
    catch e
        warning('receiveFromGateway: %s', e.message);
        plc.updated = false;
    end
end