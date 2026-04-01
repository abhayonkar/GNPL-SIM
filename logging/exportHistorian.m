function exportHistorian(hist, outDir)
    if hist.row_count == 0
        fprintf('[historian] No events recorded.\n');
        return;
    end
    fname = fullfile(outDir, sprintf('historian_%s.csv', ...
                                     datestr(now,'yyyymmdd_HHMMSS')));  %#ok
    fid = fopen(fname, 'w');
    fprintf(fid, 'Timestamp_s,Tag,VarType,Value,Unit,ATTACK_ID,FAULT_ID\n');
    for i = 1:hist.row_count
        r = hist.rows{i};
        fprintf(fid, '%.4f,%s,%s,%.6f,%s,%d,%d\n', ...
                r{1}, r{2}, r{3}, r{4}, r{5}, r{6}, r{7});
    end
    fclose(fid);
    fprintf('[historian] %d events → %s\n', hist.row_count, fname);
end