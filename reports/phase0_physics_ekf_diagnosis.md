# Phase 0 — Physics-EKF Residual Diagnosis

**Dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Generated:** 2026-04-23T13:47:52

---

## 1. Overall Anomaly Score Separation

Physics anomaly score = L2(EKF residuals) + 0.1 × CUSUM_upper + 0.05 × chi2_stat

### 1a. Raw score (linear)

| Metric | Value |
|--------|-------|
| Normal mean | 259983888.0000 |
| Attack mean | 283708800.0000 |
| Normal std  | 18262772.0000 |
| Attack std  | 104030280.0000 |
| Pooled std  | 74685432.0000 |
| **Cohen's d** | **0.318** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

### 1b. Log-transformed score (np.log1p)

| Metric | Value |
|--------|-------|
| Normal mean | 19.3736 |
| Attack mean | 19.4190 |
| **Cohen's d** | **0.231** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

---

## 2. Per-Node EKF Residual Analysis (top 10 by separation)

| Node | Normal mean | Attack mean | Cohen's d | Assessment |
|------|-------------|-------------|-----------|------------|
| CS1 | 4.6672 | 7.2018 | 0.477 | ✗ |
| J7 | 2.3928 | 2.5316 | 0.473 | ✗ |
| J2 | 8.5080 | 6.4436 | 0.462 | ✗ |
| J5 | -2.6249 | -2.4101 | 0.328 | ✗ |
| D1 | -1.1721 | -0.8174 | 0.272 | ✗ |
| J3 | -1.5304 | -1.7485 | 0.258 | ✗ |
| CS2 | 13.6527 | 13.3478 | 0.248 | ✗ |
| S1 | 2.6491 | 2.5358 | 0.241 | ✗ |
| S2 | 1.1886 | 1.2620 | 0.228 | ✗ |
| PRS1 | -5.3746 | -5.5018 | 0.199 | ✗ |

---

## 3. EKF Residual vs CUSUM Innovation Range Comparison

| Metric | Value |
|--------|-------|
| ekf_l2_normal_p50 | 26.6112 |
| ekf_l2_normal_p99 | 27.7950 |
| ekf_l2_attack_p50 | 26.3739 |
| ekf_l2_attack_p99 | 36.7329 |
| ekf_range_ratio | 1.3216 |
| cusum_normal_p50 | 0.0000 |
| cusum_normal_p99 | 0.0000 |
| cusum_attack_p50 | 0.0000 |
| cusum_attack_p99 | 0.0000 |
| ekf_cusum_correlation | -0.0035 |

**Range interpretation:**

- EKF L2 p99 ratio (attack/normal) = 1.32 < 2 — residual barely changes under attack. Likely normalisation or sign-convention bug in `computeWeymouthResiduals.m`.
- EKF–CUSUM correlation = -0.004 ≈ 0 — residuals are **not** tracking the EKF innovation. Root cause: Weymouth residual is computed on wrong state (physics vs PLC bus mismatch).

---

## 4. Root Cause Summary

| Check | Result |
|-------|--------|
| Raw score separation (Cohen's d ≥ 1.5) | FAIL (d=0.318) |
| Log score separation (Cohen's d ≥ 1.5) | FAIL (d=0.231) |
| EKF range ratio ≥ 2.0 | FAIL (ratio=1.32) |
| EKF–CUSUM correlation ≥ 0.3 | FAIL (r=-0.004) |

**Next step:**

- If all checks PASS → threshold mis-set; re-run `train_temporal_graph.py` and check fit_threshold FPR.
- If range ratio FAIL → `computeWeymouthResiduals.m` is normalising or scaling incorrectly; check unit conversion (kPa vs bar) in `p_abs` computation.
- If correlation FAIL → residual uses wrong state variable; confirm `state.q` is the PLC bus reading (not the physics solver output) at the logging step.
