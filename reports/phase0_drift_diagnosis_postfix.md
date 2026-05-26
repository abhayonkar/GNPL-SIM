# Phase 0 — 48-Hour Collapse / Feature Drift Diagnosis

**Train dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Test dataset:**  `automated_dataset\continuous_48h\run_01\physics_dataset.csv`  
**Generated:** 2026-05-26T14:34:12

> Diagnostic only — no new data generated, no regime labels added.

---

## 1. Wasserstein Distance Summary

- Features analysed: **115**
- Features with W > 1.0 (drifted): **72** (63%)

### By Feature Group

| Group | Total | Drifted (W>1) | Max W | Mean W |
|-------|-------|--------------|-------|--------|
| other | 7 | 3 | 2327.052 | 435.810 |
| cusum | 3 | 1 | 1327.565 | 442.524 |
| chi2 | 2 | 1 | 687.885 | 343.943 |
| flow | 20 | 20 | 325.000 | 89.653 |
| plc_flow | 20 | 20 | 324.177 | 89.899 |
| plc_pressure | 20 | 9 | 4.290 | 1.604 |
| pressure | 20 | 9 | 4.262 | 1.593 |
| ekf_residual | 20 | 9 | 4.173 | 0.932 |
| valve | 3 | 0 | 0.429 | 0.147 |

---

## 2. Top 20 Drifted Features

| Rank | Feature | Group | W distance | Train mean | Test mean | Flag |
|------|---------|-------|-----------|-----------|----------|------|
| 1 | `CS1_power_kW` | other | 2327.052 | 3036.0541 | 5363.0933 | 🔴 DRIFT |
| 2 | `cusum_S_upper` | cusum | 1327.565 | 1355.6676 | 28.1030 | 🔴 DRIFT |
| 3 | `CS2_power_kW` | other | 721.659 | 1994.7948 | 2716.4429 | 🔴 DRIFT |
| 4 | `chi2_stat` | chi2 | 687.885 | 1661.4476 | 973.5623 | 🔴 DRIFT |
| 5 | `q_E10_kgs` | flow | 325.000 | -214.6138 | 110.3861 | 🔴 DRIFT |
| 6 | `plc_q_E10` | plc_flow | 324.177 | -213.7909 | 110.3860 | 🔴 DRIFT |
| 7 | `q_E9_kgs` | flow | 215.682 | 519.3812 | 303.6997 | 🔴 DRIFT |
| 8 | `plc_q_E9` | plc_flow | 214.046 | 517.7403 | 303.6944 | 🔴 DRIFT |
| 9 | `q_E14_kgs` | flow | 207.430 | -207.2718 | 0.1583 | 🔴 DRIFT |
| 10 | `plc_q_E14` | plc_flow | 206.871 | -206.9215 | -0.0503 | 🔴 DRIFT |
| 11 | `q_E12_kgs` | flow | 137.423 | 345.8407 | 208.4181 | 🔴 DRIFT |
| 12 | `plc_q_E12` | plc_flow | 137.109 | 345.4659 | 208.4123 | 🔴 DRIFT |
| 13 | `plc_q_E15` | plc_flow | 128.303 | -120.4341 | 7.8692 | 🔴 DRIFT |
| 14 | `q_E15_kgs` | flow | 128.301 | -120.4289 | 7.8724 | 🔴 DRIFT |
| 15 | `q_E11_kgs` | flow | 118.974 | 70.2169 | 189.1909 | 🔴 DRIFT |
| 16 | `plc_q_E11` | plc_flow | 118.973 | 70.2149 | 189.1882 | 🔴 DRIFT |
| 17 | `plc_q_E3` | plc_flow | 107.214 | 19.4815 | -87.1239 | 🔴 DRIFT |
| 18 | `q_E3_kgs` | flow | 105.672 | 17.9379 | -87.1253 | 🔴 DRIFT |
| 19 | `plc_q_E2` | plc_flow | 105.028 | -154.7461 | -123.7620 | 🔴 DRIFT |
| 20 | `q_E2_kgs` | flow | 104.573 | -155.3017 | -123.7614 | 🔴 DRIFT |

---

## 3. Missing Feature Classes / Operating Conditions

1. **Regime diversity**: test set has 13 distinct `regime_id` values ([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]…). Training (attack_windows) does not include regime labels — regime-dependent distribution shifts are invisible to the model.

2. **Temporal span**: train covers 1.0 h, test covers 48.0 h. Diurnal and multi-hour demand cycles absent from attack_windows training windows.

3. **Pressure operating envelope**: compatible ranges (train [13.43, 42.38] bar, test [14.05, 25.80] bar).

4. **Columns in train only** (5 cols): `cs_mode`, `demand_profile`, `source_config`, `storage_init`, `valve_config`…  Features unavailable at 48h test time — imputed as zero/NaN by scaler.

5. **Columns in test only** (4 cols): `ATTACK_START_S`, `MITRE_CODE`, `PRS1_throttle`, `PRS2_throttle`…  Test set exposes new signal channels not seen during training.


---

## 4. Root Cause Assessment

The F1 drop from 0.76 → 0.08 is explained by:

1. **72 features with W > 1.0** — the test distribution is far outside the training manifold; the scaler/threshold set on training data is invalid for 48h operation.

2. **Temporal regime shifts** — the 48h run includes diurnal demand cycles, multi-hour pressure oscillations, and compressor duty cycles that attack_windows (short windows) never exhibit.

3. **No attack labels in 48h test** — ATTACK_ID is absent, so all anomalous scores are evaluated against a threshold calibrated for a different operating point. False positives dominate, causing F1 collapse.

**Phase 2 requirement:** Generate 48h-spanning training data covering the drifted feature ranges above. Specifically, the top-drifted feature groups must be present in training.
