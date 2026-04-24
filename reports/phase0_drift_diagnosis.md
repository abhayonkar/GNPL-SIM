# Phase 0 — 48-Hour Collapse / Feature Drift Diagnosis

**Train dataset:** `automated_dataset\attack_windows\physics_dataset_windows.csv`  
**Test dataset:**  `automated_dataset\continuous_48h\physics_dataset.csv`  
**Generated:** 2026-04-23T13:52:08

> Diagnostic only — no new data generated, no regime labels added.

---

## 1. Wasserstein Distance Summary

- Features analysed: **117**
- Features with W > 1.0 (drifted): **101** (86%)

### By Feature Group

| Group | Total | Drifted (W>1) | Max W | Mean W |
|-------|-------|--------------|-------|--------|
| chi2 | 2 | 1 | 2936830010.443 | 1468415005.221 |
| plc_flow | 20 | 20 | 6013.581 | 1692.228 |
| flow | 20 | 20 | 6013.539 | 1692.477 |
| other | 9 | 3 | 1312.716 | 255.623 |
| cusum | 3 | 1 | 461.086 | 153.696 |
| plc_pressure | 20 | 19 | 50.666 | 28.571 |
| pressure | 20 | 19 | 50.665 | 28.573 |
| ekf_residual | 20 | 18 | 29.496 | 8.080 |
| valve | 3 | 0 | 1.000 | 0.667 |

---

## 2. Top 20 Drifted Features

| Rank | Feature | Group | W distance | Train mean | Test mean | Flag |
|------|---------|-------|-----------|-----------|----------|------|
| 1 | `chi2_stat` | chi2 | 2936830010.443 | 5231619436.1035 | 2294789425.6609 | 🔴 DRIFT |
| 2 | `plc_q_E3` | plc_flow | 6013.581 | -571.8539 | -6585.4347 | 🔴 DRIFT |
| 3 | `q_E3_kgs` | flow | 6013.539 | -571.8542 | -6585.3928 | 🔴 DRIFT |
| 4 | `plc_q_E9` | plc_flow | 4898.076 | 805.2939 | 5703.3700 | 🔴 DRIFT |
| 5 | `q_E9_kgs` | flow | 4898.011 | 805.2908 | 5703.3016 | 🔴 DRIFT |
| 6 | `q_E15_kgs` | flow | 3182.357 | -36.8072 | 3145.5501 | 🔴 DRIFT |
| 7 | `plc_q_E15` | plc_flow | 3182.320 | -36.7901 | 3145.5294 | 🔴 DRIFT |
| 8 | `plc_q_E11` | plc_flow | 2890.846 | 471.9027 | 3362.7477 | 🔴 DRIFT |
| 9 | `q_E11_kgs` | flow | 2890.830 | 471.9009 | 3362.7296 | 🔴 DRIFT |
| 10 | `q_E14_kgs` | flow | 2020.313 | 155.7677 | -1864.5455 | 🔴 DRIFT |
| 11 | `plc_q_E14` | plc_flow | 2020.232 | 155.7267 | -1864.5057 | 🔴 DRIFT |
| 12 | `plc_q_E10` | plc_flow | 2002.274 | 154.7514 | -1847.5227 | 🔴 DRIFT |
| 13 | `q_E10_kgs` | flow | 2002.265 | 154.7521 | -1847.5127 | 🔴 DRIFT |
| 14 | `plc_q_E5` | plc_flow | 1808.875 | -47.3100 | 1761.5647 | 🔴 DRIFT |
| 15 | `q_E5_kgs` | flow | 1808.849 | -47.3170 | 1761.5319 | 🔴 DRIFT |
| 16 | `q_E8_kgs` | flow | 1785.734 | 165.3560 | -1620.3780 | 🔴 DRIFT |
| 17 | `plc_q_E8` | plc_flow | 1784.643 | 164.2896 | -1620.3538 | 🔴 DRIFT |
| 18 | `q_E18_kgs` | flow | 1761.387 | -0.1044 | -1761.4916 | 🔴 DRIFT |
| 19 | `plc_q_E18` | plc_flow | 1761.376 | -0.1046 | -1761.4811 | 🔴 DRIFT |
| 20 | `q_E16_kgs` | flow | 1620.683 | 0.3369 | -1620.3462 | 🔴 DRIFT |

---

## 3. Missing Feature Classes / Operating Conditions

1. **Regime diversity**: test set has 13 distinct `regime_id` values ([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]…). Training (attack_windows) does not include regime labels — regime-dependent distribution shifts are invisible to the model.

2. **Temporal span**: train covers 4.1 h, test covers 48.0 h. Diurnal and multi-hour demand cycles absent from attack_windows training windows.

3. **Pressure operating envelope**: train p ∈ [14.50, 30.00] bar, test p ∈ [0.10, 70.00] bar. Test set operates outside trained pressure range — out-of-distribution for the ML model.

4. **Columns in train only** (3 cols): `attack_start`, `recovery_phase`, `recovery_start`…  Features unavailable at 48h test time — imputed as zero/NaN by scaler.

5. **Columns in test only** (2 cols): `ATTACK_START_S`, `MITRE_CODE`…  Test set exposes new signal channels not seen during training.


---

## 4. Root Cause Assessment

The F1 drop from 0.76 → 0.08 is explained by:

1. **101 features with W > 1.0** — the test distribution is far outside the training manifold; the scaler/threshold set on training data is invalid for 48h operation.

2. **Temporal regime shifts** — the 48h run includes diurnal demand cycles, multi-hour pressure oscillations, and compressor duty cycles that attack_windows (short windows) never exhibit.

3. **No attack labels in 48h test** — ATTACK_ID is absent, so all anomalous scores are evaluated against a threshold calibrated for a different operating point. False positives dominate, causing F1 collapse.

**Phase 2 requirement:** Generate 48h-spanning training data covering the drifted feature ranges above. Specifically, the top-drifted feature groups must be present in training.
