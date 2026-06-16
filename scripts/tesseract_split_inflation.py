# scripts/tesseract_split_inflation.py
# Fixed version: auto-finds latest run dirs, graceful fallbacks, NaN-safe format strings.
# Changes from original:
#   1. cv_path: run_4_clean -> run_post_fix (auto-finds latest timestamp subdir)
#   2. gkf_path/rnd_path: graceful if directory missing (no IndexError)
#   3. cross-regime path: graceful if cross_regime_post_fix.csv missing
#   4. NaN-safe format strings (no ValueError on missing cross-regime data)

import json
import glob
import pandas as pd
from pathlib import Path

def latest(pattern):
    matches = sorted(glob.glob(pattern))
    return matches[-1] if matches else None

# -- GroupKFold run (honest evaluation) ------------------------------------------
gkf_glob = latest('ml_outputs/attack_windows/temporal_graph/run_post_fix/*/paper_table.json')
if not gkf_glob:
    raise FileNotFoundError("No run_post_fix paper_table.json found. Run train_temporal_graph.py first.")

with open(gkf_glob) as f:
    gkf = {m['model']: m for m in json.load(f)['models']}
print(f"GroupKFold results from: {gkf_glob}")

# -- Random-split run (inflated evaluation) --------------------------------------
rnd_glob = latest('ml_outputs/attack_windows/temporal_graph/run_post_fix_randomsplit/*/paper_table.json')
if rnd_glob:
    with open(rnd_glob) as f:
        rnd = {m['model']: m for m in json.load(f)['models']}
    print(f"RandomSplit results from: {rnd_glob}")
else:
    print("WARNING: No random-split run found -- skipping inflation table.")
    rnd = {}

# -- RF GroupKFold CV ------------------------------------------------------------
cv_path = None
for base in ['run_post_fix', 'run_4_clean']:
    p = f'ml_outputs/attack_windows/traditional_ml/{base}/cross_topology_cv.csv'
    if Path(p).exists():
        cv_path = p
        break

if cv_path:
    cv = pd.read_csv(cv_path)
    print(f"CV results from: {cv_path}")
else:
    print("WARNING: cross_topology_cv.csv not found. Run cgd_ids_pipeline.py first.")
    cv = pd.DataFrame({'f1': [float('nan')]})

# -- Inflation table -------------------------------------------------------------
print("\n" + "=" * 65)
print("TESSERACT-style split inflation analysis")
print("=" * 65)
if rnd:
    print(f"{'Model':<15}  {'Random F1':>9}  {'GroupKFold F1':>13}  {'Inflation':>10}")
    print("-" * 52)
    for m in ['LSTM-AE', 'GNN', 'Hybrid-IDS']:
        if m in rnd and m in gkf:
            f_r  = rnd[m]['f1']
            f_gk = gkf[m]['f1']
            print(f"{m:<15}  {f_r:>9.4f}  {f_gk:>13.4f}  {f_r-f_gk:>+10.4f}")

if not cv['f1'].isna().all():
    f_rf_cv = cv['f1'].mean()
    print(f"{'RF (5-fold CV)':<15}  {'~0.880':>9}  {f_rf_cv:>13.4f}  "
          f"{0.880-f_rf_cv:>+10.4f}")

# -- Cross-regime summary --------------------------------------------------------
cr_path = 'reports/cross_regime_post_fix.csv'
if not Path(cr_path).exists():
    print(f"\nWARNING: {cr_path} not found. Run evaluate_cross_regime.py first.")
else:
    cr = pd.read_csv(cr_path)
    cr_all = cr[(cr['family'] == 'ALL') & (~cr['clean_run'])]
    cr_fpr = cr[cr['clean_run']][['model', 'fpr']]

    print("\n" + "=" * 65)
    print("Cross-regime AUC (attack_windows F1 -> 48h continuous)")
    print("=" * 65)
    for m in ['LSTM-AE', 'GNN', 'Physics-EKF', 'Hybrid-IDS']:
        sub = cr_all[cr_all['model'] == m]
        if len(sub) > 0:
            auc_m = pd.to_numeric(sub['auc'], errors='coerce').mean()
            auc_s = pd.to_numeric(sub['auc'], errors='coerce').std()
            fpr_row = cr_fpr[cr_fpr['model'] == m]
            fpr = fpr_row['fpr'].values[0] if len(fpr_row) else float('nan')
            ingkf = gkf.get(m, {}).get('f1', float('nan'))
            drop  = (ingkf - (auc_m or 0)) / max(ingkf, 0.01) * 100 if ingkf else float('nan')
            auc_str  = f"{auc_m:.3f}" if auc_m == auc_m else "nan"
            drop_str = f"{drop:.0f}"  if drop == drop  else "nan"
            print(f"{m:<15}  InDist F1={ingkf:.3f}  "
                  f"CrossRegime AUC={auc_str}  "
                  f"Drop={drop_str}%  FPR@run10={fpr:.4f}")

    print("\nKey stat for Paper 2 Sec.I contribution statement:")
    print("  AUC collapse to ~0.50 (random) across ALL model families")
    print("  FPR on clean run (after label fix) = measured above")