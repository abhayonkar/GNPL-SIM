function hist = initHistorian(params, cfg)
    nN = params.nNodes;
    nE = params.nEdges;
    hist.last_p       = cfg.p0 * ones(nN, 1);
    hist.last_q       = zeros(nE, 1);
    hist.last_T       = cfg.T0 * ones(nN, 1);
    hist.last_write_k = 0;
    max_rows = 800000;
    hist.rows      = cell(max_rows, 1);
    hist.row_count = 0;
end