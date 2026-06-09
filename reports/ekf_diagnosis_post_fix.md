# Phase 0 — Physics-EKF Residual Diagnosis

**Dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Generated:** 2026-06-09T00:33:50

---

## 1. Overall Anomaly Score Separation

Physics anomaly score = L2(EKF residuals) + 0.1 × CUSUM_upper + 0.05 × chi2_stat

### 1a. Raw score (linear)

| Metric | Value |
|--------|-------|
| Normal mean | 124.5121 |
| Attack mean | 111.0320 |
| Normal std  | 366.3987 |
| Attack std  | 141.8201 |
| Pooled std  | 277.8138 |
| **Cohen's d** | **0.049** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

### 1b. Log-transformed score (np.log1p)

| Metric | Value |
|--------|-------|
| Normal mean | 4.4937 |
| Attack mean | 4.4746 |
| **Cohen's d** | **0.038** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

---

## 2. Per-Node EKF Residual Analysis (top 10 by separation)

| Node | Normal mean | Attack mean | Cohen's d | Assessment |
|------|-------------|-------------|-----------|------------|
| S2 | 0.0629 | -0.1911 | 0.026 | ✗ |
| CS1 | -0.0808 | 0.1626 | 0.024 | ✗ |
| PRS2 | -0.0631 | 0.0913 | 0.022 | ✗ |
| J6 | -0.1415 | -0.0438 | 0.019 | ✗ |
| S1 | 0.0686 | -0.0953 | 0.014 | ✗ |
| PRS1 | 0.0745 | 0.1346 | 0.010 | ✗ |
| J2 | -0.0691 | -0.0114 | 0.010 | ✗ |
| D1 | -0.0853 | -0.0368 | 0.010 | ✗ |
| J1 | -0.0909 | -0.0371 | 0.010 | ✗ |
| D2 | -0.0628 | -0.0201 | 0.009 | ✗ |

---

## 3. EKF Residual vs CUSUM Innovation Range Comparison

| Metric | Value |
|--------|-------|
| ekf_l2_normal_p50 | 24.2960 |
| ekf_l2_normal_p99 | 51.3314 |
| ekf_l2_attack_p50 | 24.3979 |
| ekf_l2_attack_p99 | 82.9182 |
| ekf_range_ratio | 1.6153 |
| cusum_normal_p50 | 0.0000 |
| cusum_normal_p99 | 10290.7462 |
| cusum_attack_p50 | 0.0000 |
| cusum_attack_p99 | 0.0000 |
| ekf_cusum_correlation | 0.0167 |

**Range interpretation:**

- EKF L2 p99 ratio (attack/normal) = 1.62 < 2 — residual barely changes under attack. Likely normalisation or sign-convention bug in `computeWeymouthResiduals.m`.
- EKF–CUSUM correlation = 0.017 ≈ 0 — residuals are **not** tracking the EKF innovation. Root cause: Weymouth residual is computed on wrong state (physics vs PLC bus mismatch).

---

## 4. Root Cause Summary

| Check | Result |
|-------|--------|
| Raw score separation (Cohen's d ≥ 1.5) | FAIL (d=0.049) |
| Log score separation (Cohen's d ≥ 1.5) | FAIL (d=0.038) |
| EKF range ratio ≥ 2.0 | FAIL (ratio=1.62) |
| EKF–CUSUM correlation ≥ 0.3 | FAIL (r=0.017) |

**Next step:**

- If all checks PASS → threshold mis-set; re-run `train_temporal_graph.py` and check fit_threshold FPR.
- If range ratio FAIL → `computeWeymouthResiduals.m` is normalising or scaling incorrectly; check unit conversion (kPa vs bar) in `p_abs` computation.
- If correlation FAIL → residual uses wrong state variable; confirm `state.q` is the PLC bus reading (not the physics solver output) at the logging step.
