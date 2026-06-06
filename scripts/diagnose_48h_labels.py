# scripts/diagnose_48h_labels.py
import pandas as pd

for run_id in [1, 10]:  # run_01 (attacks) + run_10 (clean reference)
    path = f'automated_dataset\continuous_48h_test\physics_dataset.csv'
    df = pd.read_csv(path, nrows=5000, low_memory=False)
    
    print(f"\n=== RUN {run_id:02d} ===")
    print(f"Columns: {df.columns.tolist()}")
    print(f"\nlabel value_counts:\n{df['label'].value_counts()}")
    print(f"ATTACK_ID value_counts:\n{df['ATTACK_ID'].value_counts().head()}")
    print(f"FAULT_ID value_counts:\n{df['FAULT_ID'].value_counts()}")
    print(f"\nFirst 10 rows [ATTACK_ID, FAULT_ID, label]:")
    print(df[['ATTACK_ID', 'FAULT_ID', 'label']].head(10))