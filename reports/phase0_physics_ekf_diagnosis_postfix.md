# Phase 0 — Physics-EKF Residual Diagnosis

**Dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Generated:** 2026-05-25T15:02:34

---

## 1. Overall Anomaly Score Separation

Physics anomaly score = L2(EKF residuals) + 0.1 × CUSUM_upper + 0.05 × chi2_stat

### 1a. Raw score (linear)

| Metric | Value |
|--------|-------|
| Normal mean | 750.9650 |
| Attack mean | 148.3920 |
| Normal std  | 3696.2620 |
| Attack std  | 193.7820 |
| Pooled std  | 2617.2412 |
| **Cohen's d** | **0.230** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

### 1b. Log-transformed score (np.log1p)

| Metric | Value |
|--------|-------|
| Normal mean | 4.8749 |
| Attack mean | 4.7517 |
| **Cohen's d** | **0.156** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

---

## 2. Per-Node EKF Residual Analysis (top 10 by separation)

| Node | Normal mean | Attack mean | Cohen's d | Assessment |
|------|-------------|-------------|-----------|------------|
| J6 | 5.1948 | 4.4311 | 0.280 | ✗ |
| PRS1 | -8.6866 | -8.3310 | 0.193 | ✗ |
| PRS2 | -1.7660 | -1.8801 | 0.181 | ✗ |
| D3 | 0.6179 | 0.8147 | 0.179 | ✗ |
| CS2 | 4.4975 | 4.9544 | 0.144 | ✗ |
| J1 | 0.3998 | -0.3580 | 0.141 | ✗ |
| D2 | 1.2936 | 1.5449 | 0.139 | ✗ |
| D6 | 0.0090 | 0.0657 | 0.136 | ✗ |
| D1 | 0.2467 | 0.0455 | 0.127 | ✗ |
| S2 | -2.0763 | -1.9901 | 0.106 | ✗ |

---

## 3. EKF Residual vs CUSUM Innovation Range Comparison

| Metric | Value |
|--------|-------|
| ekf_l2_normal_p50 | 17.9124 |
| ekf_l2_normal_p99 | 22.8214 |
| ekf_l2_attack_p50 | 17.5965 |
| ekf_l2_attack_p99 | 53.8873 |
| ekf_range_ratio | 2.3613 |
| cusum_normal_p50 | 0.0000 |
| cusum_normal_p99 | 245893.2153 |
| cusum_attack_p50 | 0.0000 |
| cusum_attack_p99 | 0.0000 |
| ekf_cusum_correlation | 0.0015 |

**Range interpretation:**

- EKF L2 p99 ratio (attack/normal) = 2.36 ≥ 2 — adequate dynamic range.
- EKF–CUSUM correlation = 0.001 ≈ 0 — residuals are **not** tracking the EKF innovation. Root cause: Weymouth residual is computed on wrong state (physics vs PLC bus mismatch).

---

## 4. Root Cause Summary

| Check | Result |
|-------|--------|
| Raw score separation (Cohen's d ≥ 1.5) | FAIL (d=0.230) |
| Log score separation (Cohen's d ≥ 1.5) | FAIL (d=0.156) |
| EKF range ratio ≥ 2.0 | PASS (ratio=2.36) |
| EKF–CUSUM correlation ≥ 0.3 | FAIL (r=0.001) |

**Next step:**

- If all checks PASS → threshold mis-set; re-run `train_temporal_graph.py` and check fit_threshold FPR.
- If range ratio FAIL → `computeWeymouthResiduals.m` is normalising or scaling incorrectly; check unit conversion (kPa vs bar) in `p_abs` computation.
- If correlation FAIL → residual uses wrong state variable; confirm `state.q` is the PLC bus reading (not the physics solver output) at the logging step.
