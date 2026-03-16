function plc = initGatewayState()
% initPLC  Initialise PLC state struct with safe default values
%
% These values are used until the first UDP packet arrives from the gateway.
% All values match PLC_PRG VAR block init values.

    plc.cs1_ratio   = 1.25;    % compressor ratio (dimensionless)
    plc.cs2_ratio   = 1.15;
    plc.valve_E8    = 1.0;     % 1.0 = open, 0.0 = closed
    plc.valve_E14   = 1.0;
    plc.valve_E15   = 1.0;
    plc.prs1_sp     = 30.0;    % bar setpoint
    plc.prs2_sp     = 25.0;
    plc.cs1_power   = 0.0;     % kW
    plc.cs2_power   = 0.0;

    plc.emergency_shutdown  = false;
    plc.cs1_alarm           = false;
    plc.cs2_alarm           = false;
    plc.sto_inject          = false;
    plc.sto_withdraw        = false;
    plc.prs1_active         = false;
    plc.prs2_active         = false;

    plc.updated  = false;
    plc.last_rx  = NaN;
end