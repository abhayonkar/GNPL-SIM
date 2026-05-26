# Phase 0 — 48-Hour Collapse / Feature Drift Diagnosis

**Train dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Test dataset:**  `automated_dataset\continuous_48h\run_01\physics_dataset.csv`  
**Generated:** 2026-05-25T15:01:52

> Diagnostic only — no new data generated, no regime labels added.

---

## 1. Wasserstein Distance Summary

- Features analysed: **115**
- Features with W > 1.0 (drifted): **81** (70%)

### By Feature Group

| Group | Total | Drifted (W>1) | Max W | Mean W |
|-------|-------|--------------|-------|--------|
| cusum | 3 | 1 | 2692.898 | 897.638 |
| other | 7 | 3 | 1813.174 | 339.845 |
| chi2 | 2 | 1 | 1328.945 | 664.472 |
| flow | 20 | 20 | 402.970 | 135.228 |
| plc_flow | 20 | 20 | 401.007 | 134.758 |
| ekf_residual | 20 | 10 | 5.523 | 1.488 |
| plc_pressure | 20 | 13 | 4.624 | 2.098 |
| pressure | 20 | 13 | 4.623 | 2.131 |
| valve | 3 | 0 | 0.432 | 0.171 |

---

## 2. Top 20 Drifted Features

| Rank | Feature | Group | W distance | Train mean | Test mean | Flag |
|------|---------|-------|-----------|-----------|----------|------|
| 1 | `cusum_S_upper` | cusum | 2692.898 | 2721.0012 | 28.1030 | 🔴 DRIFT |
| 2 | `CS1_power_kW` | other | 1813.174 | 3549.9301 | 5363.0933 | 🔴 DRIFT |
| 3 | `chi2_stat` | chi2 | 1328.945 | 2302.5070 | 973.5623 | 🔴 DRIFT |
| 4 | `CS2_power_kW` | other | 563.909 | 2152.5443 | 2716.4429 | 🔴 DRIFT |
| 5 | `q_E10_kgs` | flow | 402.970 | -292.5840 | 110.3861 | 🔴 DRIFT |
| 6 | `plc_q_E10` | plc_flow | 401.007 | -290.6206 | 110.3860 | 🔴 DRIFT |
| 7 | `q_E9_kgs` | flow | 373.187 | 676.8869 | 303.6997 | 🔴 DRIFT |
| 8 | `plc_q_E9` | plc_flow | 368.619 | 672.3132 | 303.6944 | 🔴 DRIFT |
| 9 | `q_E14_kgs` | flow | 332.645 | -332.4864 | 0.1583 | 🔴 DRIFT |
| 10 | `plc_q_E14` | plc_flow | 331.775 | -331.8252 | -0.0503 | 🔴 DRIFT |
| 11 | `q_E1_kgs` | flow | 286.722 | -308.8212 | -35.2141 | 🔴 DRIFT |
| 12 | `plc_q_E1` | plc_flow | 284.869 | -306.9751 | -35.2130 | 🔴 DRIFT |
| 13 | `q_E12_kgs` | flow | 177.854 | 386.2718 | 208.4181 | 🔴 DRIFT |
| 14 | `plc_q_E12` | plc_flow | 177.172 | 385.4085 | 208.4123 | 🔴 DRIFT |
| 15 | `q_E15_kgs` | flow | 164.901 | -157.0288 | 7.8724 | 🔴 DRIFT |
| 16 | `plc_q_E15` | plc_flow | 164.697 | -156.8279 | 7.8692 | 🔴 DRIFT |
| 17 | `q_E3_kgs` | flow | 164.657 | -132.0266 | -87.1253 | 🔴 DRIFT |
| 18 | `plc_q_E3` | plc_flow | 159.999 | -128.8763 | -87.1239 | 🔴 DRIFT |
| 19 | `q_E11_kgs` | flow | 135.446 | 53.7497 | 189.1909 | 🔴 DRIFT |
| 20 | `plc_q_E11` | plc_flow | 135.442 | 53.7510 | 189.1882 | 🔴 DRIFT |

---

## 3. Missing Feature Classes / Operating Conditions

1. **Regime diversity**: test set has 13 distinct `regime_id` values ([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]…). Training (attack_windows) does not include regime labels — regime-dependent distribution shifts are invisible to the model.

2. **Temporal span**: train covers 0.5 h, test covers 48.0 h. Diurnal and multi-hour demand cycles absent from attack_windows training windows.

3. **Pressure operating envelope**: compatible ranges (train [0.00, 1800.00] bar, test [14.05, 25.80] bar).

4. **Columns in train only** (5 cols): `cs_mode`, `demand_profile`, `source_config`, `storage_init`, `valve_config`…  Features unavailable at 48h test time — imputed as zero/NaN by scaler.

5. **Columns in test only** (4 cols): `ATTACK_START_S`, `MITRE_CODE`, `PRS1_throttle`, `PRS2_throttle`…  Test set exposes new signal channels not seen during training.


---

## 4. Root Cause Assessment

The F1 drop from 0.76 → 0.08 is explained by:

1. **81 features with W > 1.0** — the test distribution is far outside the training manifold; the scaler/threshold set on training data is invalid for 48h operation.

2. **Temporal regime shifts** — the 48h run includes diurnal demand cycles, multi-hour pressure oscillations, and compressor duty cycles that attack_windows (short windows) never exhibit.

3. **No attack labels in 48h test** — ATTACK_ID is absent, so all anomalous scores are evaluated against a threshold calibrated for a different operating point. False positives dominate, causing F1 collapse.

**Phase 2 requirement:** Generate 48h-spanning training data covering the drifted feature ranges above. Specifically, the top-drifted feature groups must be present in training.
