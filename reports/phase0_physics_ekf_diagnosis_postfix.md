# Phase 0 — Physics-EKF Residual Diagnosis

**Dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Generated:** 2026-05-26T14:34:30

---

## 1. Overall Anomaly Score Separation

Physics anomaly score = L2(EKF residuals) + 0.1 × CUSUM_upper + 0.05 × chi2_stat

### 1a. Raw score (linear)

| Metric | Value |
|--------|-------|
| Normal mean | 301.9832 |
| Attack mean | 127.3574 |
| Normal std  | 2188.6963 |
| Attack std  | 237.6581 |
| Pooled std  | 1556.7390 |
| **Cohen's d** | **0.112** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

### 1b. Log-transformed score (np.log1p)

| Metric | Value |
|--------|-------|
| Normal mean | 4.4554 |
| Attack mean | 4.4026 |
| **Cohen's d** | **0.081** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

---

## 2. Per-Node EKF Residual Analysis (top 10 by separation)

| Node | Normal mean | Attack mean | Cohen's d | Assessment |
|------|-------------|-------------|-----------|------------|
| J6 | 3.9540 | 2.1305 | 0.716 | ~ |
| PRS1 | -7.7448 | -6.1499 | 0.676 | ~ |
| S2 | -1.5793 | -1.3623 | 0.264 | ✗ |
| CS1 | 1.4059 | 3.4923 | 0.235 | ✗ |
| J1 | -1.2358 | -2.3463 | 0.231 | ✗ |
| J2 | 0.6604 | -0.4630 | 0.216 | ✗ |
| STO | 0.9168 | 0.5862 | 0.175 | ✗ |
| CS2 | 5.0434 | 5.5450 | 0.164 | ✗ |
| D3 | 0.6628 | 0.8234 | 0.145 | ✗ |
| D1 | 0.2173 | -0.0297 | 0.136 | ✗ |

---

## 3. EKF Residual vs CUSUM Innovation Range Comparison

| Metric | Value |
|--------|-------|
| ekf_l2_normal_p50 | 15.9902 |
| ekf_l2_normal_p99 | 20.7884 |
| ekf_l2_attack_p50 | 14.9900 |
| ekf_l2_attack_p99 | 54.6418 |
| ekf_range_ratio | 2.6285 |
| cusum_normal_p50 | 0.0000 |
| cusum_normal_p99 | 79614.0378 |
| cusum_attack_p50 | 0.0000 |
| cusum_attack_p99 | 0.0000 |
| ekf_cusum_correlation | 0.0203 |

**Range interpretation:**

- EKF L2 p99 ratio (attack/normal) = 2.63 ≥ 2 — adequate dynamic range.
- EKF–CUSUM correlation = 0.020 ≈ 0 — residuals are **not** tracking the EKF innovation. Root cause: Weymouth residual is computed on wrong state (physics vs PLC bus mismatch).

---

## 4. Root Cause Summary

| Check | Result |
|-------|--------|
| Raw score separation (Cohen's d ≥ 1.5) | FAIL (d=0.112) |
| Log score separation (Cohen's d ≥ 1.5) | FAIL (d=0.081) |
| EKF range ratio ≥ 2.0 | PASS (ratio=2.63) |
| EKF–CUSUM correlation ≥ 0.3 | FAIL (r=0.020) |

**Next step:**

- If all checks PASS → threshold mis-set; re-run `train_temporal_graph.py` and check fit_threshold FPR.
- If range ratio FAIL → `computeWeymouthResiduals.m` is normalising or scaling incorrectly; check unit conversion (kPa vs bar) in `p_abs` computation.
- If correlation FAIL → residual uses wrong state variable; confirm `state.q` is the PLC bus reading (not the physics solver output) at the logging step.
