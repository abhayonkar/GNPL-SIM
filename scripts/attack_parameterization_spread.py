"""
Table comparing parameterization diversity vs SWaT/HAI.
"""
import json

# From randomize_attack_params.m analysis:
# Values are from the parameter ranges defined in the function
param_spread = {
    'A1 SourceSpike': {
        'spike_amp': '1.15–1.40 × nominal',
        'osc_freq': '0.005–0.020 Hz',
        'duration': '90–210 s',
        'fixed_in_SWaT': 'Yes (P11 single pump trip)'
    },
    'A9 FDI_Stealthy': {
        'target_nodes': 'C(10,3)=120 combinations',
        'bias_scale': '3–10% of nominal',
        'ramp_time': '30–90 s',
        'fixed_in_SWaT': 'N/A (SWaT has no FDI attacks)'
    },
    'A8 PipeLeak': {
        'target_edge': '6 main pipeline edges',
        'leak_fraction': '0.15–0.50 of flow',
        'ramp_time': '30–90 s',
        'fixed_in_HAI': 'Yes (single fixed leak point)'
    },
    'A2 CompRamp': {
        'target_ratio': '1.40–1.55',
        'ramp_time': '20–60 s',
        'fixed_in_SWaT': 'N/A (no compressor in SWaT)'
    }
}

# Compute exact unique instance count from dataset
import pandas as pd
df = pd.read_csv('automated_dataset/attack_windows/physics_dataset_windows.csv',
                 low_memory=False)

print("=== Parameterization Diversity ===\n")
print(f"{'Attack':<20} {'Unique instances':>17} {'vs SWaT/HAI':>15}")
print('-'*55)

for aid in range(1, 11):
    atk = df[df['ATTACK_ID'] == aid]
    n = atk['scenario_id'].nunique()
    comparison = 'SWaT: 1 fixed' if aid <= 6 else 'HAI: 1-2 fixed'
    if aid == 9: comparison = 'SWaT: N/A'
    name = {1:'SourceSpike',2:'CompRamp',3:'ValveForce',4:'DemandInject',
            5:'PressureSpoof',6:'FlowSpoof',7:'PLCLatency',8:'PipeLeak',
            9:'FDI_Stealthy',10:'ReplayAttack'}[aid]
    print(f"A{aid} {name:<18} {n:>17} {comparison:>15}")

total = df[df['ATTACK_ID'] > 0]['scenario_id'].nunique()
print(f"\nTotal unique attack instances: {total}")
print(f"Average per class: {total/10:.0f}")