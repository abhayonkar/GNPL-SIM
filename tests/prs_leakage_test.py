import pandas as pd
df = pd.read_csv('automated_dataset/attack_windows/physics_dataset_windows.csv')
print(df.groupby('ATTACK_ID')[['PRS1_throttle','PRS2_throttle']].mean())
# If mean diff > 0.1 between classes → legitimate signal, keep
# If perfectly separates → LEAKAGE → add to BROKEN_FEATURES list