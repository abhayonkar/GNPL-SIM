# Phase 0 — 48-Hour Collapse / Feature Drift Diagnosis

**Train dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Test dataset:**  `automated_dataset\continuous_48h\physics_dataset.csv`  
**Generated:** 2026-05-17T01:55:09

> Diagnostic only — no new data generated, no regime labels added.

---

## 1. Wasserstein Distance Summary

- Features analysed: **115**
- Features with W > 1.0 (drifted): **66** (57%)

### By Feature Group

| Group | Total | Drifted (W>1) | Max W | Mean W |
|-------|-------|--------------|-------|--------|
| chi2 | 2 | 1 | 124802323.330 | 62401161.665 |
| cusum | 3 | 1 | 14973.420 | 4991.146 |
| plc_flow | 20 | 18 | 3786.831 | 603.616 |
| flow | 20 | 15 | 3765.658 | 598.862 |
| other | 7 | 3 | 591.278 | 118.607 |
| plc_pressure | 20 | 10 | 36.009 | 12.040 |
| pressure | 20 | 10 | 35.999 | 12.043 |
| ekf_residual | 20 | 8 | 7.352 | 1.236 |
| valve | 3 | 0 | 0.002 | 0.002 |

---

## 2. Top 20 Drifted Features

| Rank | Feature | Group | W distance | Train mean | Test mean | Flag |
|------|---------|-------|-----------|-----------|----------|------|
| 1 | `chi2_stat` | chi2 | 124802323.330 | 1594645997.1604 | 1492145450.8485 | 🔴 DRIFT |
| 2 | `cusum_S_upper` | cusum | 14973.420 | 15131.1082 | 157.6881 | 🔴 DRIFT |
| 3 | `plc_q_E3` | plc_flow | 3786.831 | -2798.8351 | -6585.6653 | 🔴 DRIFT |
| 4 | `q_E3_kgs` | flow | 3765.658 | -2819.9851 | -6585.6394 | 🔴 DRIFT |
| 5 | `plc_q_E4` | plc_flow | 1933.749 | 1428.9984 | 3362.7475 | 🔴 DRIFT |
| 6 | `q_E4_kgs` | flow | 1923.549 | 1439.2340 | 3362.7829 | 🔴 DRIFT |
| 7 | `plc_q_E18` | plc_flow | 1779.185 | 17.6389 | -1761.5462 | 🔴 DRIFT |
| 8 | `q_E18_kgs` | flow | 1779.172 | 17.6156 | -1761.5564 | 🔴 DRIFT |
| 9 | `q_E1_kgs` | flow | 1488.885 | -144.9262 | 1316.1620 | 🔴 DRIFT |
| 10 | `plc_q_E1` | plc_flow | 1484.459 | -141.7026 | 1316.1729 | 🔴 DRIFT |
| 11 | `q_E7_kgs` | flow | 1062.920 | 1072.3554 | 9.4709 | 🔴 DRIFT |
| 12 | `plc_q_E7` | plc_flow | 1059.162 | 1068.4428 | 9.4708 | 🔴 DRIFT |
| 13 | `q_E5_kgs` | flow | 919.506 | 76.9914 | 0.0000 | 🔴 DRIFT |
| 14 | `plc_q_E5` | plc_flow | 915.017 | 80.2287 | -0.0000 | 🔴 DRIFT |
| 15 | `CS1_power_kW` | other | 591.278 | 790.5586 | 1312.7074 | 🔴 DRIFT |
| 16 | `q_E19_kgs` | flow | 589.200 | -17.1612 | 572.0389 | 🔴 DRIFT |
| 17 | `plc_q_E19` | plc_flow | 589.200 | -17.1579 | 572.0420 | 🔴 DRIFT |
| 18 | `plc_q_E17` | plc_flow | 262.155 | 267.4475 | 529.6024 | 🔴 DRIFT |
| 19 | `q_E17_kgs` | flow | 262.155 | 267.4506 | 529.6051 | 🔴 DRIFT |
| 20 | `CS2_power_kW` | other | 237.514 | 748.4336 | 985.9473 | 🔴 DRIFT |

---

## 3. Missing Feature Classes / Operating Conditions

1. **Regime diversity**: test set has 13 distinct `regime_id` values ([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]…). Training (attack_windows) does not include regime labels — regime-dependent distribution shifts are invisible to the model.

2. **Temporal span**: train covers 0.5 h, test covers 48.0 h. Diurnal and multi-hour demand cycles absent from attack_windows training windows.

3. **Pressure operating envelope**: compatible ranges (train [0.00, 1800.00] bar, test [0.10, 70.00] bar).

4. **Columns in train only** (5 cols): `cs_mode`, `demand_profile`, `source_config`, `storage_init`, `valve_config`…  Features unavailable at 48h test time — imputed as zero/NaN by scaler.

5. **Columns in test only** (4 cols): `ATTACK_START_S`, `MITRE_CODE`, `PRS1_throttle`, `PRS2_throttle`…  Test set exposes new signal channels not seen during training.


---

## 4. Root Cause Assessment

The F1 drop from 0.76 → 0.08 is explained by:

1. **66 features with W > 1.0** — the test distribution is far outside the training manifold; the scaler/threshold set on training data is invalid for 48h operation.

2. **Temporal regime shifts** — the 48h run includes diurnal demand cycles, multi-hour pressure oscillations, and compressor duty cycles that attack_windows (short windows) never exhibit.

3. **No attack labels in 48h test** — ATTACK_ID is absent, so all anomalous scores are evaluated against a threshold calibrated for a different operating point. False positives dominate, causing F1 collapse.

**Phase 2 requirement:** Generate 48h-spanning training data covering the drifted feature ranges above. Specifically, the top-drifted feature groups must be present in training.
