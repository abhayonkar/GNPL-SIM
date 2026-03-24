function gw_state = receiveFromGateway(cfg, gw_prev)
% receiveFromGateway  Block-wait for actuator reply from Python gateway.
%
%   gw_state = receiveFromGateway(cfg, gw_prev)
%
%   Uses cfg.rx_sock (java.net.DatagramSocket, timeout already set).
%   Blocks up to cfg.gateway_timeout_s (set via rx_sock.setSoTimeout).
%   Returns gw_prev unchanged on timeout (offline fallback).
%
%   Packet layout (16 × float64 = 128 bytes):
%     [1-9]   actuator raw INTs  (MATLAB divides by scale)
%     [10-16] coil bools (0.0 or 1.0)

    EXPECTED_BYTES = 16 * 8;   % 128 bytes
    gw_state = gw_prev;
    gw_state.updated = false;

    try
        % Pre-allocate receive buffer
        buf    = zeros(1, EXPECTED_BYTES, 'int8');
        jbuf   = javaArray('java.lang.Byte', EXPECTED_BYTES);   %#ok — not used directly
        packet = java.net.DatagramPacket(buf, EXPECTED_BYTES);

        cfg.rx_sock.receive(packet);   % blocks until data arrives or timeout

        % Extract received bytes
        received = packet.getData();   % int8 Java array
        nbytes   = packet.getLength();

        if nbytes < EXPECTED_BYTES
            return;   % short packet — keep previous
        end

        % Convert Java int8 array to MATLAB uint8, then to doubles
        raw_bytes = typecast(int8(received(1:EXPECTED_BYTES)), 'uint8');
        vals      = typecast(raw_bytes, 'double');   % 16×1

        % Actuators (raw INT → engineering units)
        gw_state.cs1_ratio   = vals(1)  / 1000.0;
        gw_state.cs2_ratio   = vals(2)  / 1000.0;
        gw_state.valve_E8    = vals(3)  / 1000.0;
        gw_state.valve_E14   = vals(4)  / 1000.0;
        gw_state.valve_E15   = vals(5)  / 1000.0;
        gw_state.prs1_sp     = vals(6)  / 100.0;
        gw_state.prs2_sp     = vals(7)  / 100.0;
        gw_state.cs1_power   = vals(8)  / 10.0;
        gw_state.cs2_power   = vals(9)  / 10.0;

        % Status coils
        gw_state.emergency_shutdown  = logical(vals(10));
        gw_state.cs1_alarm           = logical(vals(11));
        gw_state.cs2_alarm           = logical(vals(12));
        gw_state.sto_inject          = logical(vals(13));
        gw_state.sto_withdraw        = logical(vals(14));
        gw_state.prs1_active         = logical(vals(15));
        gw_state.prs2_active         = logical(vals(16));

        gw_state.updated = true;
        gw_state.last_rx = now();

    catch e
        % java.net.SocketTimeoutException is expected on timeout — silent
        if ~contains(e.message, 'timeout') && ~contains(e.message, 'Timeout')
            warning('receiveFromGateway: %s', e.message);
        end
        gw_state.updated = false;
    end
end