# Phase 0 — Physics-EKF Residual Diagnosis

**Dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Generated:** 2026-06-04T11:23:48

---

## 1. Overall Anomaly Score Separation

Physics anomaly score = L2(EKF residuals) + 0.1 × CUSUM_upper + 0.05 × chi2_stat

### 1a. Raw score (linear)

| Metric | Value |
|--------|-------|
| Normal mean | 321.0077 |
| Attack mean | 128.5831 |
| Normal std  | 2183.1667 |
| Attack std  | 192.0347 |
| Pooled std  | 1549.6926 |
| **Cohen's d** | **0.124** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

### 1b. Log-transformed score (np.log1p)

| Metric | Value |
|--------|-------|
| Normal mean | 4.6532 |
| Attack mean | 4.5621 |
| **Cohen's d** | **0.148** |

**Assessment:** POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed.

---

## 2. Per-Node EKF Residual Analysis (top 10 by separation)

| Node | Normal mean | Attack mean | Cohen's d | Assessment |
|------|-------------|-------------|-----------|------------|
| PRS1 | -7.6104 | -5.7575 | 0.668 | ~ |
| J6 | 3.8437 | 1.9693 | 0.655 | ~ |
| S2 | -2.0273 | -1.7411 | 0.330 | ✗ |
| J1 | 0.5241 | -0.5711 | 0.212 | ✗ |
| D3 | 0.8116 | 1.0248 | 0.199 | ✗ |
| STO | 0.9424 | 0.5898 | 0.185 | ✗ |
| CS2 | 4.9246 | 5.4688 | 0.173 | ✗ |
| J4 | -1.5196 | -1.1827 | 0.169 | ✗ |
| D1 | -0.0350 | -0.2908 | 0.163 | ✗ |
| D6 | 0.0198 | 0.0883 | 0.157 | ✗ |

---

## 3. EKF Residual vs CUSUM Innovation Range Comparison

| Metric | Value |
|--------|-------|
| ekf_l2_normal_p50 | 16.8950 |
| ekf_l2_normal_p99 | 22.6386 |
| ekf_l2_attack_p50 | 15.8619 |
| ekf_l2_attack_p99 | 53.6570 |
| ekf_range_ratio | 2.3702 |
| cusum_normal_p50 | 0.0000 |
| cusum_normal_p99 | 79705.0994 |
| cusum_attack_p50 | 0.0000 |
| cusum_attack_p99 | 0.0000 |
| ekf_cusum_correlation | 0.0340 |

**Range interpretation:**

- EKF L2 p99 ratio (attack/normal) = 2.37 ≥ 2 — adequate dynamic range.
- EKF–CUSUM correlation = 0.034 ≈ 0 — residuals are **not** tracking the EKF innovation. Root cause: Weymouth residual is computed on wrong state (physics vs PLC bus mismatch).

---

## 4. Root Cause Summary

| Check | Result |
|-------|--------|
| Raw score separation (Cohen's d ≥ 1.5) | FAIL (d=0.124) |
| Log score separation (Cohen's d ≥ 1.5) | FAIL (d=0.148) |
| EKF range ratio ≥ 2.0 | PASS (ratio=2.37) |
| EKF–CUSUM correlation ≥ 0.3 | FAIL (r=0.034) |

**Next step:**

- If all checks PASS → threshold mis-set; re-run `train_temporal_graph.py` and check fit_threshold FPR.
- If range ratio FAIL → `computeWeymouthResiduals.m` is normalising or scaling incorrectly; check unit conversion (kPa vs bar) in `p_abs` computation.
- If correlation FAIL → residual uses wrong state variable; confirm `state.q` is the PLC bus reading (not the physics solver output) at the logging step.
