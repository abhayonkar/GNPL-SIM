"""
Shows GroupKFold (scenario-level) vs random split inflation.
"""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
from pathlib import Path

# CV results already in cross_topology_cv.csv
cv = pd.read_csv('ml_outputs/attack_windows/traditional_ml/run_4_clean/cross_topology_cv.csv')

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4))

# Left: CV fold bars
ax1.bar(cv['fold'], cv['f1'], color='steelblue', edgecolor='white', linewidth=0.5)
ax1.axhline(cv['f1'].mean(), color='red', linestyle='--', 
            label=f"GroupKFold mean={cv['f1'].mean():.3f}±{cv['f1'].std():.3f}")
ax1.axhline(0.88, color='orange', linestyle=':', 
            label=f"Random split ≈0.880 (+{0.88-cv['f1'].mean():.3f} inflation)")
ax1.set_ylim(0, 1.0)
ax1.set_xlabel('Fold', fontsize=11)
ax1.set_ylabel('F1 Score (RandomForest)', fontsize=11)
ax1.set_title('Evaluation Protocol Comparison\n(Scenario-Grouped vs Random Split)', fontsize=10)
ax1.legend(fontsize=8)

# Right: Model F1 honest vs inflated
models = ['LSTM-AE', 'GNN', 'RF', 'XGBoost']
f1_honest = [0.369, 0.333, 0.806, 0.806]  # GroupKFold / val-data
f1_inflated = [0.59, 0.39, 0.88, 0.88]    # random split estimate

x = np.arange(len(models))
w = 0.35
ax2.bar(x - w/2, f1_honest, w, label='Scenario-grouped (honest)', color='steelblue')
ax2.bar(x + w/2, f1_inflated, w, label='Random split (inflated)', color='salmon')
ax2.set_xticks(x)
ax2.set_xticklabels(models, fontsize=9)
ax2.set_ylabel('F1 Score', fontsize=11)
ax2.set_title('Leakage Inflation by Model', fontsize=10)
ax2.legend(fontsize=8)
ax2.set_ylim(0, 1.0)

plt.tight_layout()
Path('reports/figures').mkdir(parents=True, exist_ok=True)
plt.savefig('reports/figures/cv_comparison.pdf', dpi=300, bbox_inches='tight')
print("Saved → reports/figures/cv_comparison.pdf")