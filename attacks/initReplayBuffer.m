function buf = initReplayBuffer(nN, nE, cfg)
    T_buf_steps   = max(1, round(cfg.atk10_buffer_s / cfg.dt));
    buf.p_buf     = zeros(nN, T_buf_steps);
    buf.q_buf     = zeros(nE, T_buf_steps);
    buf.write_idx = 0;
    buf.filled    = false;
    buf.read_idx  = 1;
end