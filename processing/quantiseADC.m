function val_q = quantiseADC(val, full_scale, cfg)
% quantiseADC  Simulate ADC quantisation for a sensor channel vector.
%
%   val_q = quantiseADC(val, full_scale, cfg)
%
%   WHY THIS MATTERS:
%   ─────────────────
%   Real PLCs convert analog sensor voltages through a fixed-resolution
%   ADC before storing them as integer register values. This produces:
%     • A staircase (stepped) value distribution — not continuous
%     • A minimum detectable change = full_scale / n_counts
%     • Platform-specific resolution: CODESYS INT16 vs S7-1200 0–27648
%
%   Without ADC quantisation the dataset has the same failure mode as the
%   MSU gas pipeline dataset: perfectly continuous sensor readings that
%   no real hardware can produce, causing distribution shift and model
%   failure when deployed on actual PLCs.
%
%   PLATFORM PROFILES:
%   ──────────────────
%   'codesys'  — CODESYS Control Win SL maps physical values to signed
%                INT16 in range [−32768, 32767]. For unipolar channels
%                (pressure ≥ 0, flow signed) we use [0, 32767] for
%                non-negative values and scale accordingly.
%                Resolution = full_scale / 32767
%
%   's7_1200'  — Siemens SM1231 AI module maps 0–10V input to
%                integer range [0, 27648] (not 0–65535, not 0–32767).
%                This is a deliberate Siemens design choice documented in
%                the S7-1200 System Manual section on analog I/O.
%                Resolution = full_scale / 27648
%                This lower resolution creates a coarser staircase that
%                is MEASURABLY DIFFERENT from CODESYS — enabling hardware
%                fingerprinting and domain adaptation research.
%
%   FORMULA:
%   ─────────
%   raw_count = floor( clamp(val, 0, full_scale) / full_scale * n_counts )
%   val_q     = raw_count / n_counts * full_scale
%
%   The output is the reconstructed engineering value after quantisation,
%   not the raw integer. This matches what the MATLAB gateway receives
%   after the PLC converts raw counts back to scaled engineering values.
%
%   INPUTS:
%     val        — N×1 vector of sensor readings in engineering units
%     full_scale — scalar full-scale physical range (e.g. 70.0 bar)
%     cfg        — simulation config struct
%                    cfg.adc_platform       : 'codesys' or 's7_1200'
%                    cfg.adc_counts_codesys : 32767
%                    cfg.adc_counts_s7      : 27648
%
%   OUTPUT:
%     val_q — N×1 quantised sensor readings in engineering units

    if ~cfg.adc_enable
        val_q = val;
        return;
    end

    %% Select ADC count limit based on platform
    switch lower(cfg.adc_platform)
        case 's7_1200'
            n_counts = cfg.adc_counts_s7;       % 27648
        otherwise   % 'codesys' or any unrecognised value
            n_counts = cfg.adc_counts_codesys;  % 32767
    end

    %% Quantise: clamp → normalise → floor → denormalise
    %  clamp to [0, full_scale] — sensors are non-negative in this model
    val_clamped  = max(0, min(full_scale, val));

    %  Convert to raw ADC counts (integer)
    raw_counts   = floor(val_clamped / full_scale * n_counts);

    %  Clamp counts to valid range (guard against floating-point edge cases)
    raw_counts   = max(0, min(n_counts, raw_counts));

    %  Reconstruct engineering value from quantised counts
    val_q        = raw_counts / n_counts * full_scale;
end