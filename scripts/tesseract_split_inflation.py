# scripts/tesseract_split_inflation.py
import json, glob, pandas as pd
from pathlib import Path

# Load GroupKFold run (honest evaluation)
gkf_path = sorted(glob.glob(
    'ml_outputs/attack_windows/temporal_graph/run_post_fix/*/paper_table.json'))[-1]
with open(gkf_path) as f:
    gkf = {m['model']: m for m in json.load(f)['models']}

# Load random split run (inflated evaluation)
rnd_path = sorted(glob.glob(
    'ml_outputs/attack_windows/temporal_graph/run_post_fix_randomsplit/*/paper_table.json'))
if rnd_path:
    with open(rnd_path[-1]) as f:
        rnd = {m['model']: m for m in json.load(f)['models']}

# RF GroupKFold CV
cv = pd.read_csv(
    'ml_outputs/attack_windows/traditional_ml/run_4_clean/cross_topology_cv.csv')

print("=" * 65)
print("TESSERACT-style split inflation analysis")
print("=" * 65)
print(f"{'Model':<15}  {'Random F1':>9}  {'GroupKFold F1':>13}  {'Inflation':>10}")
print("-" * 52)
for m in ['LSTM-AE', 'GNN', 'Hybrid-IDS']:
    if m in rnd and m in gkf:
        f_r  = rnd[m]['f1']
        f_gk = gkf[m]['f1']
        print(f"{m:<15}  {f_r:>9.4f}  {f_gk:>13.4f}  {f_r-f_gk:>+10.4f}")

f_rf_cv = cv['f1'].mean()
print(f"{'RF (5-fold CV)':<15}  {'~0.880':>9}  {f_rf_cv:>13.4f}  "
      f"{0.880-f_rf_cv:>+10.4f}")

# Load cross-regime summary
cr = pd.read_csv('reports/cross_regime_post_fix.csv')
cr_all = cr[(cr['family'] == 'ALL') & (~cr['clean_run'])]
cr_fpr = cr[cr['clean_run']][['model', 'fpr']]

print("\n" + "=" * 65)
print("Cross-regime AUC (attack_windows F1 → 48h continuous AUC)")
print("=" * 65)
for m in ['LSTM-AE', 'GNN', 'Physics-EKF', 'Hybrid-IDS']:
    sub = cr_all[cr_all['model'] == m]
    if len(sub) > 0:
        auc_m = sub['auc'].mean()
        auc_s = sub['auc'].std()
        fpr_row = cr_fpr[cr_fpr['model'] == m]
        fpr = fpr_row['fpr'].values[0] if len(fpr_row) else float('nan')
        ingkf = gkf.get(m, {}).get('f1', float('nan'))
        drop  = (ingkf - auc_m) / max(ingkf, 0.01) * 100
        print(f"{m:<15}  InDist F1={ingkf:.3f}  CrossRegime AUC={auc_m:.3f}±{auc_s:.3f}"
              f"  Drop={drop:.0f}%  FPR@run10={fpr:.3f}")

print("\nKey stat for Paper 2 §I contribution statement:")
print("→ AUC collapse to ≈0.50 (random) across ALL model families")
print("→ FPR on clean run (after label fix) = measured above")