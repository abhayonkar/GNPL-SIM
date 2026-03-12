function plc = updatePLC(plc, sensor_p, sensor_q, k)
    if mod(k, plc.period) == 0
        plc.reg_p = sensor_p;
        plc.reg_q = sensor_q;
    end
end
