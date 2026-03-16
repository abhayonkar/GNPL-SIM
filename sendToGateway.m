function sendToGateway(u, state, cfg)
% sendToGateway  Send physics state to Python gateway via UDP
%
% Packs 61 float64 values into 488 bytes and sends to gateway.
% Gateway receives on UDP port 5005, converts to INT, writes to CODESYS.
%
% Packet layout (61 x float64 = 488 bytes):
%   [0:19]  20 node pressures    bar      (gateway scales x100 -> INT)
%   [20:39] 20 edge flows        kg/s     (gateway scales x100 -> INT)
%   [40:59] 20 node temperatures K        (gateway scales x10  -> INT)
%   [60]     1 demand scalar     0-1.2    (gateway scales x1000-> INT)
%
% Args:
%   u     - udpport object (created in main_simulation.m)
%   state - simulation state struct
%   cfg   - simulation config struct

    % --- assemble payload ---
    pressures = state.p(:);          % 20x1  bar
    flows     = state.q(:);          % 20x1  kg/s
    temps     = state.T(:);          % 20x1  K

    % demand scalar: mean of normalised demand nodes relative to nominal
    % demand nodes are indices 15-20 in cfg.demandNodes
    demand_scalar = mean(state.demand_scalar);   % scalar 0-1.2

    payload = [pressures; flows; temps; demand_scalar];  % 61x1

    % --- pack as big-endian float64 and send ---
    bytes = typecast(double(payload), 'uint8');
    write(u, bytes, 'uint8');
end