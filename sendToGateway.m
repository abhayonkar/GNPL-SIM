function sendToGateway(cfg, gw_out)
% sendToGateway  Send physics state to Python gateway via Java UDP socket.
%
%   sendToGateway(cfg, gw_out)
%
%   Uses cfg.tx_sock (java.net.DatagramSocket) and cfg.tx_addr.
%   No toolbox required — Java sockets available in all MATLAB versions.
%
%   gw_out fields:
%     .p             — 20×1  node pressures    (bar)
%     .q             — 20×1  edge flows        (kg/s)
%     .T             — 20×1  node temperatures (K)
%     .demand_scalar — scalar demand multiplier
%
%   Packet layout (61 × float64 = 488 bytes):
%     [0:19]  pressures   bar   (gateway ×100  → INT)
%     [20:39] flows       kg/s  (gateway ×100  → INT)
%     [40:59] temps       K     (gateway ×10   → INT)
%     [60]    demand            (gateway ×1000 → INT)

    pressures = gw_out.p(:);
    flows     = gw_out.q(:);
    temps     = gw_out.T(:);
    d_scalar  = double(gw_out.demand_scalar(1));

    payload = [pressures; flows; temps; d_scalar];   % 61×1 double

    % Pack as little-endian bytes (MATLAB native = little-endian on x86)
    raw_bytes = typecast(double(payload(:)), 'uint8');   % 488 bytes

    % Wrap in Java byte array and send
    jbytes = typecast(raw_bytes, 'int8');   % Java uses signed bytes
    packet = java.net.DatagramPacket(jbytes, length(jbytes), cfg.tx_addr);
    cfg.tx_sock.send(packet);
end