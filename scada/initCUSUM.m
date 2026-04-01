function cusum = initCUSUM(cfg)
    cusum.S_upper       = 0;
    cusum.S_lower       = 0;
    cusum.alarm         = false;
    cusum.alarm_count   = 0;
    cusum.nx            = 40;
    H_LEN = 100;
    cusum.z_history       = zeros(1, H_LEN);
    cusum.S_upper_history = zeros(1, H_LEN);
    cusum.S_lower_history = zeros(1, H_LEN);
end