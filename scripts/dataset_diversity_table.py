"""
Produces Table II: Attack parameterization diversity comparison.
Run: python scripts/dataset_diversity_table.py
"""
import pandas as pd
import numpy as np
from pathlib import Path

df = pd.read_csv('automated_dataset/attack_windows/physics_dataset_windows.csv',
                 low_memory=False)

ATTACK_NAMES = {
    1:'SourceSpike', 2:'CompRamp', 3:'ValveForce', 4:'DemandInject',
    5:'PressureSpoof', 6:'FlowSpoof', 7:'PLCLatency', 8:'PipeLeak',
    9:'FDI_Stealthy', 10:'ReplayAttack'
}
p_cols = [c for c in df.columns if c.startswith('p_') and c.endswith('_bar')]
q_cols = [c for c in df.columns if c.startswith('q_') and c.endswith('_kgs')]

rows = []
normal = df[df['ATTACK_ID'] == 0]
p_norm_mean = normal[p_cols].mean()

for aid, name in ATTACK_NAMES.items():
    atk = df[df['ATTACK_ID'] == aid]
    if len(atk) == 0:
        continue
    
    # Unique parameter instantiations = unique scenario_ids
    n_unique = atk['scenario_id'].nunique()
    
    # Max pressure deviation from normal
    p_dev = (atk[p_cols] - p_norm_mean).abs()
    max_dev = p_dev.max().max()
    mean_dev = p_dev.mean().mean()
    
    # Duration range per scenario (rows per scenario_id)
    rows_per_scenario = atk.groupby('scenario_id').size()
    dur_min = rows_per_scenario.min()  # seconds at 1Hz
    dur_max = rows_per_scenario.max()
    
    rows.append({
        'ID': f'A{aid}', 'Name': name,
        'Unique instances': n_unique,
        'Duration range (s)': f'{dur_min}–{dur_max}',
        'Max ΔP (bar)': round(max_dev, 3),
        'Mean ΔP (bar)': round(mean_dev, 4),
        'Total rows': len(atk)
    })

table = pd.DataFrame(rows)
print(table.to_string(index=False))
table.to_csv('reports/dataset_diversity_table.csv', index=False)
print("\nSaved → reports/dataset_diversity_table.csv")

# Also compute vs SWaT/HAI comparison
print("\n=== Parameterization comparison ===")
print(f"This dataset: {table['Unique instances'].sum()} unique attack instances")
print(f"              {table['Unique instances'].mean():.0f} per attack class (avg)")
print(f"SWaT A1-A41:  1 instance per attack (fixed valve/pump state)")
print(f"HAI:          Fixed attack timing and magnitude per run")