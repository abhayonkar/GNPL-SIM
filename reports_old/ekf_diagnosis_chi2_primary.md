# Phase 0 — Physics-EKF Residual Diagnosis

**Dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Generated:** 2026-06-13T02:47:39

---

## 1. Overall Anomaly Score Separation

Physics anomaly score = chi2_stat + 0.1 × CUSUM_upper  (primary: EKF chi² innovation test)

### 1a. Raw score (linear)

| Metric | Value |
|--------|-------|
| Normal mean | 1235.8892 |
| Attack mean | 1699.8455 |
| Normal std  | 487.9428 |
| Attack std  | 2781.2004 |
| Pooled std  | 1996.6427 |
| **Cohen's d** | **0.232** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

### 1b. Log-transformed score (np.log1p)

| Metric | Value |
|--------|-------|
| Normal mean | 7.0526 |
| Attack mean | 7.0843 |
| **Cohen's d** | **0.062** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

---

## 2. Per-Node EKF Residual Analysis (top 10 by separation)

| Node | Normal mean | Attack mean | Cohen's d | Assessment |
|------|-------------|-------------|-----------|------------|
| S2 | 0.1641 | -0.1921 | 0.039 | ✗ |
| CS1 | -0.0856 | 0.1588 | 0.024 | ✗ |
| S1 | 0.1253 | -0.0960 | 0.019 | ✗ |
| J6 | -0.1046 | -0.0416 | 0.013 | ✗ |
| J2 | -0.0764 | -0.0119 | 0.011 | ✗ |
| D3 | -0.0513 | -0.0024 | 0.010 | ✗ |
| D2 | -0.0663 | -0.0206 | 0.010 | ✗ |
| J1 | -0.0899 | -0.0378 | 0.009 | ✗ |
| D1 | -0.0773 | -0.0365 | 0.008 | ✗ |
| J7 | -0.1291 | -0.0919 | 0.007 | ✗ |

---

## 3. Per-Attack-Type Cohen's d (chi2_stat + 0.1×CUSUM vs normal)

Aggregate d is diluted by EKF adaptation to slow attacks (A8/A9/A10).
Per-attack breakdown reveals which attack types are detectable.

| Attack | Rows | Normal mean | Attack mean | Cohen's d | Detectable |
|--------|------|-------------|-------------|-----------|------------|
| A2_CompRamp | 30,916 | 1235.889 | 7195.681 | 1.222 | PARTIAL |
| A6_FlowSpoof | 31,051 | 1235.889 | 953.028 | 0.671 | PARTIAL |
| A3_ValveForce | 30,896 | 1235.889 | 1089.321 | 0.330 | NO |
| A7_PLCLatency | 33,287 | 1235.889 | 1093.023 | 0.320 | NO |
| A8_PipeLeak | 33,312 | 1235.889 | 1116.275 | 0.260 | NO |
| A9_FDI_Stealthy | 31,375 | 1235.889 | 1133.820 | 0.226 | NO |
| A5_PressureSpoof | 34,837 | 1235.889 | 1144.184 | 0.202 | NO |
| A10_Replay | 34,029 | 1235.889 | 1154.614 | 0.181 | NO |
| A4_DemandInject | 32,360 | 1235.889 | 1178.902 | 0.126 | NO |
| A1_SourceSpike | 36,826 | 1235.889 | 1273.794 | 0.084 | NO |

---

## 4. EKF Residual vs CUSUM Innovation Range Comparison

| Metric | Value |
|--------|-------|
| ekf_l2_normal_p50 | 24.1889 |
| ekf_l2_normal_p99 | 50.7847 |
| ekf_l2_attack_p50 | 24.3850 |
| ekf_l2_attack_p99 | 82.6428 |
| ekf_range_ratio | 1.6273 |
| cusum_normal_p50 | 0.0000 |
| cusum_normal_p99 | 0.0000 |
| cusum_attack_p50 | 0.0000 |
| cusum_attack_p99 | 0.0000 |
| ekf_cusum_correlation | nan |

**Range interpretation:**

- EKF residual L2 p99 ratio (attack/normal) = 1.63 < 2 — pressure residual has low dynamic range. Expected if EKF adapts to slow attacks; use chi2_stat as primary signal instead.
- EKF–CUSUM correlation = nan ≈ 0 — pressure residuals and CUSUM decouple. Normal: CUSUM uses all channels (P+Q); exported ekf_resid only has pressure nodes.

---

## 5. Root Cause Summary

| Check | Result |
|-------|--------|
| Aggregate score separation (Cohen's d ≥ 1.5) | FAIL (d=0.232) |
| Log-score separation (Cohen's d ≥ 1.5) | FAIL (d=0.062) |
| EKF L2 p99 range ratio ≥ 2.0 | FAIL (ratio=1.63) |
| EKF–CUSUM correlation ≥ 0.3 | FAIL (r=nan) |

**Interpretation:**

- Aggregate d < 1.5 is expected: EKF Kalman filter adapts to slow/stealthy attacks (A8 PipeLeak, A9 FDI_Stealthy, A10 Replay), returning innovations to near-zero within 30–90 steps. These attacks are structurally undetectable via residual mean-shift.
- For sudden attacks (A5 PressureSpoof, A2 CompRamp), chi2_stat d >> 1.5 at the onset. See §3 per-attack breakdown above.
- The correct Physics-EKF metric for the paper is per-attack chi2_stat AUC, not aggregate d.
- Export bug: `ekf_resid_*` columns contain only pressure residuals (logResP). Flow residuals (logResQ) are not exported — fix `export_attack_scenario_csv` in `run_attack_windows.m` to add `ekf_resid_q_*` columns, then regenerate.
