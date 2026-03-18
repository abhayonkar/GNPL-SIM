function exportDataset(logs, cfg, params, N, schedule)
% exportDataset  Write dataset CSVs + JSON + timeline to automated_dataset/
%
%   Timestamp column uses the effective log timestep:
%     log_dt = cfg.dt * cfg.log_every   (e.g. 0.1 * 10 = 1.0 s per row)
%   so Timestamp_s increments by 1.0 for a 1 Hz logged dataset.

    outDir = 'automated_dataset';
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    % Effective logging time step
    if isfield(cfg, 'log_every') && cfg.log_every > 1
        log_dt = cfg.dt * cfg.log_every;
    else
        log_dt = cfg.dt;
    end

    % Number of logged rows (may be less than N if simulation was interrupted)
    N_log = logs.N_log;
    if isfield(logs, 'logP') && size(logs.logP, 2) < N_log
        N_log = size(logs.logP, 2);
    end

    dt = cfg.dt;
    nn = params.nodeNames;
    en = params.edgeNames;

    %% ── Build column names ───────────────────────────────────────────────
    col_names = {'Timestamp_s'};
    for i = 1:params.nNodes
        col_names{end+1} = sprintf('%s_pressure_bar', char(nn(i)));
    end
    for i = 1:params.nEdges
        col_names{end+1} = sprintf('%s_flow_kgs', char(en(i)));
    end
    col_names = [col_names, {'COMP1_Power_W','COMP1_Ratio','COMP2_Power_W','COMP2_Ratio'}];
    col_names = [col_names, {'VALVE_E8_cmd','VALVE_E14_cmd','VALVE_E15_cmd'}];
    col_names = [col_names, {'SRC1_Pressure_bar','SRC2_Pressure_bar','Demand'}];
    for i = 1:params.nNodes
        col_names{end+1} = sprintf('%s_ekf_residual', char(nn(i)));
    end
    for i = 1:params.nNodes
        col_names{end+1} = sprintf('%s_plc_p', char(nn(i)));
    end
    for i = 1:params.nEdges
        col_names{end+1} = sprintf('%s_plc_q', char(en(i)));
    end
    col_names = [col_names, {'ATTACK_ID','ATTACK_NAME','MITRE_ID'}];

    %% ── Map log fields (handle both naming conventions) ──────────────────
    pow1   = getfield_safe(logs, 'logPow1',       'logPow',       zeros(1, N_log));
    pow2   = getfield_safe(logs, 'logPow2',        [],            zeros(1, N_log));
    ratio1 = getfield_safe(logs, 'logCompRatio1', 'logCompRatio', ones(1, N_log) * cfg.comp1_ratio);
    ratio2 = getfield_safe(logs, 'logCompRatio2',  [],            ones(1, N_log) * cfg.comp2_ratio);

    if isfield(logs, 'logValveStates') && size(logs.logValveStates,1) >= 3
        valve_E8  = logs.logValveStates(1,1:N_log)';
        valve_E14 = logs.logValveStates(2,1:N_log)';
        valve_E15 = logs.logValveStates(3,1:N_log)';
    else
        valve_E8  = ones(N_log,1);
        valve_E14 = ones(N_log,1);
        valve_E15 = ones(N_log,1);
    end

    srcP1  = getfield_safe(logs, 'logSrcP1', 'logSrcP', ones(1,N_log)*cfg.p0);
    srcP2  = getfield_safe(logs, 'logSrcP2', [],        ones(1,N_log)*cfg.p0);
    demand = getfield_safe(logs, 'logDemand', [],       ones(1,N_log));

    %% ── Timestamp vector using log_dt ────────────────────────────────────
    %  Row k corresponds to physics step k * log_every, time = (k-1)*log_dt
    t_vec = ((0:N_log-1)' * log_dt);

    %% ── Assemble numeric matrix ──────────────────────────────────────────
    num_data = [t_vec, ...
                logs.logP(:,1:N_log)', ...
                logs.logQ(:,1:N_log)', ...
                pow1(1:N_log)', ratio1(1:N_log)', ...
                pow2(1:N_log)', ratio2(1:N_log)', ...
                valve_E8(1:N_log), valve_E14(1:N_log), valve_E15(1:N_log), ...
                srcP1(1:N_log)', srcP2(1:N_log)', demand(1:N_log)', ...
                logs.logResP(:,1:N_log)', ...
                logs.logPlcP(:,1:N_log)', logs.logPlcQ(:,1:N_log)'];

    %% ── master_dataset.csv ───────────────────────────────────────────────
    fid = fopen(fullfile(outDir, 'master_dataset.csv'), 'w');
    fprintf(fid, '%s,', col_names{1:end-3});
    fprintf(fid, 'ATTACK_ID,ATTACK_NAME,MITRE_ID\n');
    for k = 1:N_log
        fprintf(fid, '%.4f,', num_data(k,:));
        fprintf(fid, '%d,%s,%s\n', logs.logAttackId(k), ...
                char(logs.logAttackName(k)), char(logs.logMitreId(k)));
    end
    fclose(fid);
    fprintf('[export] master_dataset.csv: %d rows x %d cols  (log_dt=%.2fs)\n', ...
            N_log, numel(col_names), log_dt);

    %% ── Normal / attack splits ───────────────────────────────────────────
    normal_mask = (logs.logAttackId(1:N_log) == 0);
    attack_mask = (logs.logAttackId(1:N_log)  > 0);
    writeSubset(fullfile(outDir, 'normal_only.csv'),  col_names, num_data, logs, normal_mask, N_log);
    writeSubset(fullfile(outDir, 'attacks_only.csv'), col_names, num_data, logs, attack_mask, N_log);
    fprintf('[export] normal_only.csv:  %d rows\n', sum(normal_mask));
    fprintf('[export] attacks_only.csv: %d rows\n', sum(attack_mask));

    %% ── spoof_forensics.csv ──────────────────────────────────────────────
    if isfield(logs, 'logSpoofP') && isfield(logs, 'logSpoofQ')
        spoof_names = {'Timestamp_s'};
        for i = 1:params.nNodes, spoof_names{end+1} = sprintf('%s_spoof_p',char(nn(i))); end
        for i = 1:params.nEdges, spoof_names{end+1} = sprintf('%s_spoof_q',char(en(i))); end
        spoof_names{end+1} = 'ATTACK_ID';
        spoof_data = [t_vec, logs.logSpoofP(:,1:N_log)', logs.logSpoofQ(:,1:N_log)'];
        fid = fopen(fullfile(outDir,'spoof_forensics.csv'),'w');
        fprintf(fid,'%s,',spoof_names{1:end-1}); fprintf(fid,'ATTACK_ID\n');
        for k = 1:N_log
            fprintf(fid,'%.4f,',spoof_data(k,:));
            fprintf(fid,'%d\n',logs.logAttackId(k));
        end
        fclose(fid);
        fprintf('[export] spoof_forensics.csv written\n');
    end

    %% ── attack_metadata.json ─────────────────────────────────────────────
    fid = fopen(fullfile(outDir,'attack_metadata.json'),'w');
    fprintf(fid,'{\n  "total_rows": %d,\n  "log_dt_s": %.2f,\n  "attacks": [\n', N_log, log_dt);
    for i = 1:schedule.nAttacks
        aid  = schedule.ids(i);
        k_s  = max(1, round(schedule.start_s(i)/dt));
        nm   = char(schedule.label_name(k_s));
        mitr = char(schedule.label_mitre(k_s));
        cnt  = sum(logs.logAttackId(1:N_log) == aid);
        pct  = 100 * cnt / N_log;
        sep  = ''; if i < schedule.nAttacks, sep = ','; end
        fprintf(fid,'    {"id":%d,"name":"%s","mitre":"%s",',aid,nm,mitr);
        fprintf(fid,'"start_s":%.1f,"dur_s":%.1f,',schedule.start_s(i),schedule.dur_s(i));
        fprintf(fid,'"row_count":%d,"pct_of_total":%.2f}%s\n',cnt,pct,sep);
    end
    fprintf(fid,'  ]\n}\n'); fclose(fid);
    fprintf('[export] attack_metadata.json written\n');

    %% ── attack_timeline.log ──────────────────────────────────────────────
    fid = fopen(fullfile(outDir,'attack_timeline.log'),'w');
    fprintf(fid,'Gas Pipeline CPS Simulator - Attack Timeline\n');
    fprintf(fid,'Physics: dt=%.2fs  log_every=%d  log_dt=%.2fs  N_log=%d\n\n', ...
            dt, cfg.log_every, log_dt, N_log);
    fprintf(fid,'%-5s %-38s %-8s %-8s %-8s %-8s %-8s\n', ...
            'AID','Name','Start','End','Dur(s)','Rows','Pct');
    fprintf(fid,'%s\n',repmat('-',1,80));
    for i = 1:schedule.nAttacks
        aid  = schedule.ids(i);
        k_s  = max(1, round(schedule.start_s(i)/dt));
        nm   = char(schedule.label_name(k_s));
        cnt  = sum(logs.logAttackId(1:N_log) == aid);
        fprintf(fid,'A%-4d %-38s %7.1fs %7.1fs %7.0fs %7d %6.1f%%\n', ...
                aid,nm,schedule.start_s(i),schedule.end_s(i), ...
                schedule.dur_s(i),cnt,100*cnt/N_log);
    end
    n_norm = sum(normal_mask);
    fprintf(fid,'%-5s %-38s %7s %7s %7s %7d %6.1f%%\n', ...
            '0','Normal','--','--','--',n_norm,100*n_norm/N_log);
    fclose(fid);
    fprintf('[export] attack_timeline.log written\n');
end

%% ── helpers ──────────────────────────────────────────────────────────────

function v = getfield_safe(logs, fname1, fname2, default)
    if isfield(logs, fname1)
        v = logs.(fname1);
    elseif ~isempty(fname2) && isfield(logs, fname2)
        v = logs.(fname2);
    else
        v = default;
    end
end

function writeSubset(fpath, col_names, num_data, logs, mask, N_log)
    fid = fopen(fpath,'w');
    fprintf(fid,'%s,',col_names{1:end-3});
    fprintf(fid,'ATTACK_ID,ATTACK_NAME,MITRE_ID\n');
    idx = find(mask);
    for ii = 1:numel(idx)
        k = idx(ii);
        if k > N_log, break; end
        fprintf(fid,'%.4f,',num_data(k,:));
        fprintf(fid,'%d,%s,%s\n',logs.logAttackId(k), ...
                char(logs.logAttackName(k)),char(logs.logMitreId(k)));
    end
    fclose(fid);
end