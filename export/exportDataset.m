function exportDataset(logs, cfg, params, N, schedule)
% exportDataset  Write dataset CSVs + JSON + timeline to automated_dataset/
%
%   Column reduction vs v1 (80 -> 47 cols):
%   DROPPED from master_dataset (available in separate data/ CSVs):
%     - Node temperatures   (8 cols)  -> data/temperature.csv
%     - Node densities      (8 cols)  -> data/density.csv
%     - COMP_Head_Jkg, COMP_Eff (2)   -> data/compressor_power.csv
%     - Spoof columns (15 cols)       -> automated_dataset/spoof_forensics.csv
%   KEPT in master_dataset (47 cols):
%     Timestamp, 8 pressures, 7 flows, COMP_Power, COMP_Ratio,
%     VALVE_CMD, SRC_Pressure, Demand, 8 EKF residuals,
%     8 PLC pressures, 7 PLC flows, ATTACK_ID, ATTACK_NAME, MITRE_ID

    outDir = 'automated_dataset';
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    dt = cfg.dt;
    nn = params.nodeNames;
    en = params.edgeNames;

    %% ----------------------------------------------------------------
    %  Build master_dataset column names (47 cols)
    %% ----------------------------------------------------------------
    col_names = {'Timestamp_s'};

    % Physical state
    for i = 1:params.nNodes
        col_names{end+1} = sprintf('%s_pressure_bar', char(nn(i)));
    end
    for i = 1:params.nEdges
        col_names{end+1} = sprintf('%s_flow_kgs', char(en(i)));
    end

    % Compressor essentials (drop Head & Eff -> compressor_power.csv)
    col_names = [col_names, {'COMP_Power_W', 'COMP_Ratio'}];

    % Actuator / source
    col_names = [col_names, {'VALVE_CMD', 'SRC_Pressure_bar', 'Demand'}];

    % EKF residuals (key anomaly detection feature)
    for i = 1:params.nNodes
        col_names{end+1} = sprintf('%s_ekf_residual', char(nn(i)));
    end

    % PLC sensor bus (what controller sees -- critical for attack detection)
    for i = 1:params.nNodes
        col_names{end+1} = sprintf('%s_plc_p', char(nn(i)));
    end
    for i = 1:params.nEdges
        col_names{end+1} = sprintf('%s_plc_q', char(en(i)));
    end

    % Labels
    col_names = [col_names, {'ATTACK_ID', 'ATTACK_NAME', 'MITRE_ID'}];
    % 1+8+7+2+3+8+8+7+3 = 47 columns

    %% ----------------------------------------------------------------
    %  Build numeric data matrix (44 numeric cols, 3 label cols)
    %% ----------------------------------------------------------------
    t_vec = ((1:N) - 1)' * dt;

    num_data = [t_vec, ...
                logs.logP', ...
                logs.logQ', ...
                logs.logPow', logs.logCompRatio', ...
                logs.logValveCmd', logs.logSrcP', logs.logDemand', ...
                logs.logResP', ...
                logs.logPlcP', logs.logPlcQ'];

    %% ----------------------------------------------------------------
    %  master_dataset.csv  (47 cols)
    %% ----------------------------------------------------------------
    fid = fopen(fullfile(outDir, 'master_dataset.csv'), 'w');
    fprintf(fid, '%s,', col_names{1:end-3});
    fprintf(fid, 'ATTACK_ID,ATTACK_NAME,MITRE_ID\n');
    for k = 1:N
        fprintf(fid, '%.4f,', num_data(k,:));
        fprintf(fid, '%d,%s,%s\n', logs.logAttackId(k), ...
                char(logs.logAttackName(k)), char(logs.logMitreId(k)));
    end
    fclose(fid);
    fprintf('[export] master_dataset.csv written (%d rows x %d cols)\n', ...
            N, numel(col_names));

    %% ----------------------------------------------------------------
    %  Normal / attack splits
    %% ----------------------------------------------------------------
    normal_mask = logs.logAttackId == 0;
    attack_mask = logs.logAttackId  > 0;

    writeSubset(fullfile(outDir, 'normal_only.csv'), ...
                col_names, num_data, logs, normal_mask);
    writeSubset(fullfile(outDir, 'attacks_only.csv'), ...
                col_names, num_data, logs, attack_mask);
    fprintf('[export] normal_only.csv:  %d rows\n', sum(normal_mask));
    fprintf('[export] attacks_only.csv: %d rows\n', sum(attack_mask));

    %% ----------------------------------------------------------------
    %  spoof_forensics.csv  (A5/A6 analysis -- separate file)
    %% ----------------------------------------------------------------
    spoof_names = {'Timestamp_s'};
    for i = 1:params.nNodes
        spoof_names{end+1} = sprintf('%s_spoof_p', char(nn(i)));
    end
    for i = 1:params.nEdges
        spoof_names{end+1} = sprintf('%s_spoof_q', char(en(i)));
    end
    spoof_names = [spoof_names, {'ATTACK_ID'}];

    spoof_data = [t_vec, logs.logSpoofP', logs.logSpoofQ'];
    fid = fopen(fullfile(outDir, 'spoof_forensics.csv'), 'w');
    fprintf(fid, '%s,', spoof_names{1:end-1});
    fprintf(fid, 'ATTACK_ID\n');
    for k = 1:N
        fprintf(fid, '%.4f,', spoof_data(k,:));
        fprintf(fid, '%d\n', logs.logAttackId(k));
    end
    fclose(fid);
    fprintf('[export] spoof_forensics.csv written (A5/A6 sensor forensics)\n');

    %% ----------------------------------------------------------------
    %  attack_metadata.json
    %% ----------------------------------------------------------------
    fid = fopen(fullfile(outDir, 'attack_metadata.json'), 'w');
    fprintf(fid, '{\n  "total_rows": %d,\n  "attacks": [\n', N);
    for i = 1:schedule.nAttacks
        aid  = schedule.ids(i);
        k_s  = max(1, round(schedule.start_s(i)/dt));
        nm   = char(schedule.label_name(k_s));
        mitr = char(schedule.label_mitre(k_s));
        cnt  = sum(logs.logAttackId == aid);
        pct  = 100 * cnt / N;
        sep  = ''; if i < schedule.nAttacks, sep = ','; end
        fprintf(fid, '    {"id":%d,"name":"%s","mitre":"%s",', aid, nm, mitr);
        fprintf(fid, '"start_s":%.1f,"dur_s":%.1f,', schedule.start_s(i), schedule.dur_s(i));
        fprintf(fid, '"row_count":%d,"pct_of_total":%.2f}%s\n', cnt, pct, sep);
    end
    fprintf(fid, '  ]\n}\n');
    fclose(fid);
    fprintf('[export] attack_metadata.json written\n');

    %% ----------------------------------------------------------------
    %  attack_timeline.log
    %% ----------------------------------------------------------------
    fid = fopen(fullfile(outDir, 'attack_timeline.log'), 'w');
    fprintf(fid, 'Gas Pipeline CPS Simulator - Attack Timeline Report\n');
    fprintf(fid, 'Simulation: %.0f min  dt=%.2fs  N=%d\n\n', N*dt/60, dt, N);
    fprintf(fid, '%-5s %-42s %-8s %-8s %-8s %-8s %-10s\n', ...
            'AID','Name','Start','End','Dur(s)','Rows','Pct(%)');
    fprintf(fid, '%s\n', repmat('-',1,90));
    for i = 1:schedule.nAttacks
        aid  = schedule.ids(i);
        k_s  = max(1, round(schedule.start_s(i)/dt));
        nm   = char(schedule.label_name(k_s));
        cnt  = sum(logs.logAttackId == aid);
        fprintf(fid, 'A%-4d %-42s %7.1fs %7.1fs %7.0fs %7d %8.1f%%\n', ...
                aid, nm, schedule.start_s(i), schedule.end_s(i), ...
                schedule.dur_s(i), cnt, 100*cnt/N);
    end
    n_norm = sum(normal_mask);
    fprintf(fid, '%-5s %-42s %7s %7s %7s %7d %8.1f%%\n', ...
            '0','Normal','--','--','--', n_norm, 100*n_norm/N);
    fclose(fid);
    fprintf('[export] attack_timeline.log written\n');
end

function writeSubset(fpath, col_names, num_data, logs, mask)
    fid = fopen(fpath, 'w');
    fprintf(fid, '%s,', col_names{1:end-3});
    fprintf(fid, 'ATTACK_ID,ATTACK_NAME,MITRE_ID\n');
    idx = find(mask);
    for ii = 1:numel(idx)
        k = idx(ii);
        fprintf(fid, '%.4f,', num_data(k,:));
        fprintf(fid, '%d,%s,%s\n', logs.logAttackId(k), ...
                char(logs.logAttackName(k)), char(logs.logMitreId(k)));
    end
    fclose(fid);
end