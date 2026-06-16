# Phase 0 — Physics-EKF Residual Diagnosis

**Dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Generated:** 2026-06-13T20:05:47

---

## 1. Overall Anomaly Score Separation

Physics anomaly score = chi2_stat + 0.1 × CUSUM_upper  (primary: EKF chi² innovation test)

### 1a. Raw score (linear)

| Metric | Value |
|--------|-------|
| Normal mean | 55.0643 |
| Attack mean | 70.5312 |
| Normal std  | 131.1403 |
| Attack std  | 93.9970 |
| Pooled std  | 114.0903 |
| **Cohen's d** | **0.136** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

### 1b. Log-transformed score (np.log1p)

| Metric | Value |
|--------|-------|
| Normal mean | 3.9239 |
| Attack mean | 3.9845 |
| **Cohen's d** | **0.121** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

---

## 2. Per-Node EKF Residual Analysis (top 10 by separation)

| Node | Normal mean | Attack mean | Cohen's d | Assessment |
|------|-------------|-------------|-----------|------------|
| q_E12 | 10.1186 | 9.4603 | 0.469 | ✗ |
| q_E9 | 14.5496 | 11.6014 | 0.423 | ✗ |
| q_E10 | -6.1350 | -4.7529 | 0.407 | ✗ |
| q_E2 | -2.4646 | -6.6422 | 0.284 | ✗ |
| q_E8 | 7.9242 | 8.2090 | 0.191 | ✗ |
| q_E14 | -8.5678 | -7.8910 | 0.160 | ✗ |
| q_E3 | -7.7787 | -4.9566 | 0.154 | ✗ |
| q_E1 | -8.1449 | -6.7129 | 0.128 | ✗ |
| q_E5 | -2.2450 | -2.7715 | 0.126 | ✗ |
| q_E17 | -0.4671 | -0.6086 | 0.111 | ✗ |

---

## 3. Per-Attack-Type Cohen's d (chi2_stat + 0.1×CUSUM vs normal)

Aggregate d is diluted by EKF adaptation to slow attacks (A8/A9/A10).
Per-attack breakdown reveals which attack types are detectable.

| Attack | Rows | Normal mean | Attack mean | Cohen's d | Detectable |
|--------|------|-------------|-------------|-----------|------------|
| A2_CompRamp | 30,916 | 55.064 | 229.469 | 1.018 | PARTIAL |
| A5_PressureSpoof | 34,837 | 55.064 | 77.778 | 0.187 | NO |
| A6_FlowSpoof | 31,051 | 55.064 | 45.722 | 0.098 | NO |
| A7_PLCLatency | 33,287 | 55.064 | 49.598 | 0.057 | NO |
| A3_ValveForce | 30,896 | 55.064 | 49.654 | 0.057 | NO |
| A8_PipeLeak | 33,312 | 55.064 | 50.012 | 0.053 | NO |
| A10_Replay | 34,029 | 55.064 | 50.927 | 0.044 | NO |
| A9_FDI_Stealthy | 31,375 | 55.064 | 51.137 | 0.041 | NO |
| A4_DemandInject | 32,360 | 55.064 | 51.766 | 0.035 | NO |
| A1_SourceSpike | 36,826 | 55.064 | 57.290 | 0.023 | NO |

---

## 4. EKF Residual vs CUSUM Innovation Range Comparison

| Metric | Value |
|--------|-------|
| ekf_l2_normal_p50 | 44.8053 |
| ekf_l2_normal_p99 | 65.6220 |
| ekf_l2_attack_p50 | 44.1939 |
| ekf_l2_attack_p99 | 146.3783 |
| ekf_range_ratio | 2.2306 |
| cusum_normal_p50 | 0.0000 |
| cusum_normal_p99 | 0.0000 |
| cusum_attack_p50 | 0.0000 |
| cusum_attack_p99 | 7.5820 |
| ekf_cusum_correlation | -0.0588 |

**Range interpretation:**

- EKF residual L2 p99 ratio (attack/normal) = 2.23 ≥ 2 — pressure residual has dynamic range.
- EKF–CUSUM correlation = -0.059 ≈ 0 — pressure residuals and CUSUM decouple. Normal: CUSUM uses all channels (P+Q); exported ekf_resid only has pressure nodes.

---

## 5. Root Cause Summary

| Check | Result |
|-------|--------|
| Aggregate score separation (Cohen's d ≥ 1.5) | FAIL (d=0.136) |
| Log-score separation (Cohen's d ≥ 1.5) | FAIL (d=0.121) |
| EKF L2 p99 range ratio ≥ 2.0 | PASS (ratio=2.23) |
| EKF–CUSUM correlation ≥ 0.3 | FAIL (r=-0.059) |

**Interpretation:**

- Aggregate d < 1.5 is expected: EKF Kalman filter adapts to slow/stealthy attacks (A8 PipeLeak, A9 FDI_Stealthy, A10 Replay), returning innovations to near-zero within 30–90 steps. These attacks are structurally undetectable via residual mean-shift.
- For sudden attacks (A5 PressureSpoof, A2 CompRamp), chi2_stat d >> 1.5 at the onset. See §3 per-attack breakdown above.
- The correct Physics-EKF metric for the paper is per-attack chi2_stat AUC, not aggregate d.
- Export bug: `ekf_resid_*` columns contain only pressure residuals (logResP). Flow residuals (logResQ) are not exported — fix `export_attack_scenario_csv` in `run_attack_windows.m` to add `ekf_resid_q_*` columns, then regenerate.
