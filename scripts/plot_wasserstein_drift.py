"""
Figure 2 for Paper 2: quantified distribution shift between training 
(attack_windows) and test (48h continuous).
Requires: drift_analysis.py already run with --out reports/phase0_drift_diagnosis.md
"""
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from scipy.stats import wasserstein_distance
from pathlib import Path

# Recompute W distances (fast, 5 min)
train = pd.read_csv('automated_dataset/attack_windows/physics_dataset_windows.csv',
                    low_memory=False, nrows=50000)
test  = pd.read_csv('automated_dataset/continuous_48h/run_01/physics_dataset.csv',
                    low_memory=False, nrows=20000)

SKIP = {'Timestamp_s','scenario_id','ATTACK_ID','FAULT_ID','label','ATTACK_NAME',
        'MITRE_ID','MITRE_CODE','prop_origin_node','prop_hop_node','prop_delay_s',
        'prop_cascade_step','regime_id','ATTACK_START_S'}

GROUPS = {
    'Pressure': lambda c: c.startswith('p_'),
    'Flow': lambda c: c.startswith('q_'),
    'EKF residual': lambda c: 'ekf_resid' in c,
    'PLC readings': lambda c: c.startswith('plc_'),
    'CUSUM/chi²': lambda c: 'cusum' in c.lower() or 'chi2' in c.lower(),
    'Equipment': lambda c: any(k in c for k in ['CS1','CS2','PRS','valve','STO']),
}

def get_group(col):
    for g, fn in GROUPS.items():
        if fn(col): return g
    return 'Other'

results = []
common = [c for c in train.columns if c in test.columns and c not in SKIP]
for col in common:
    try:
        t = pd.to_numeric(train[col], errors='coerce').dropna().values
        s = pd.to_numeric(test[col],  errors='coerce').dropna().values
        if len(t) < 100 or len(s) < 100: continue
        w = wasserstein_distance(t, s)
        results.append({'feature': col, 'W': w, 'group': get_group(col)})
    except: pass

df_w = pd.DataFrame(results).sort_values('W', ascending=False)
top40 = df_w.head(40)

# Plot
GROUP_COLORS = {
    'EKF residual': '#d62728', 'CUSUM/chi²': '#ff7f0e',
    'Equipment': '#9467bd', 'Pressure': '#1f77b4',
    'Flow': '#2ca02c', 'PLC readings': '#8c564b', 'Other': '#7f7f7f'
}

fig, ax = plt.subplots(figsize=(10, 9))
colors = [GROUP_COLORS.get(g, '#7f7f7f') for g in top40['group']]
bars = ax.barh(range(len(top40)), top40['W'].values, color=colors)
ax.set_yticks(range(len(top40)))
ax.set_yticklabels([c.replace('ekf_resid_','').replace('_bar','').replace('cusum_S_','CUSUM ')
                    for c in top40['feature']], fontsize=8)
ax.axvline(1.0, color='red', linestyle='--', lw=1.5, label='W=1.0 threshold')
ax.set_xlabel('Wasserstein Distance (W)', fontsize=11)
ax.set_title('Feature Distribution Shift:\nAttack Windows (train) vs 48h Continuous (test)', fontsize=11)

patches = [mpatches.Patch(color=c, label=g) for g, c in GROUP_COLORS.items()
           if g in top40['group'].values]
ax.legend(handles=patches + [mpatches.Patch(color='red', label='W=1.0 threshold')],
          loc='lower right', fontsize=8)

# Annotate count
n_drift = (df_w['W'] > 1.0).sum()
n_total = len(df_w)
ax.text(0.98, 0.02, f'{n_drift}/{n_total} features W>1.0',
        transform=ax.transAxes, ha='right', fontsize=9,
        bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

plt.tight_layout()
Path('reports/figures').mkdir(parents=True, exist_ok=True)
plt.savefig('reports/figures/wasserstein_drift.pdf', dpi=300, bbox_inches='tight')
plt.savefig('reports/figures/wasserstein_drift.png', dpi=150, bbox_inches='tight')
print(f"Saved → reports/figures/wasserstein_drift.pdf")
print(f"n_drift={n_drift}, n_total={n_total}, pct={100*n_drift/n_total:.1f}%")