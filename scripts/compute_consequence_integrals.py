import pandas as pd, numpy as np
from pathlib import Path

df = pd.read_csv('automated_dataset/attack_windows/physics_dataset_windows.csv',
                 low_memory=False)

ATTACK_NAMES = {1:'SourceSpike', 2:'CompRamp', 3:'ValveForce', 4:'DemandInject',
                5:'PressureSpoof', 6:'FlowSpoof', 7:'PLCLatency', 8:'PipeLeak',
                9:'FDI_Stealthy', 10:'ReplayAttack'}

MAOP, DT = 26.0, 1.0  # bar, seconds (1 Hz logging)
CH4_GWP20 = 84        # GWP over 20 years

p_cols = [c for c in df.columns if c.startswith('p_') and c.endswith('_bar')]
q_cols = [c for c in df.columns if c.startswith('q_') and c.endswith('_kgs')]
normal = df[df['ATTACK_ID'] == 0]
p_nom = normal[p_cols].mean()
q_nom = normal[q_cols].mean()

results = []
for aid, name in ATTACK_NAMES.items():
    atk = df[df['ATTACK_ID'] == aid]
    if len(atk) == 0: continue

    # IP: time-integrated absolute pressure deviation from nominal (bar·s)
    # proxy for rupture-relevant overpressure exposure
    p_dev = (atk[p_cols] - p_nom).abs()
    IP_mean = float(p_dev.mean().mean())
    IP_max  = float(p_dev.max().max())

    # Rupture flag: fraction of rows any node exceeds MAOP
    pct_maop = float((atk[p_cols] > MAOP).values.mean() * 100)

    # LD: supply deficit at demand nodes (positive = under-delivery)
    d_cols = [c for c in q_cols if any(f'D{i}' in c for i in range(1, 7))]
    if d_cols:
        q_def = (q_nom[d_cols] - atk[d_cols].mean()).clip(lower=0)
        LD = float(q_def.mean())
    else:
        LD = 0.0

    # FCH4: fugitive methane proxy for A8 (pipe leak) — flow deficit × CH4 fraction
    # In SCMD: 1 SCMD ≈ 0.717 kg, assume 92% CH4
    if aid == 8:
        leak_flow_proxy = float(atk[q_cols].apply(
            lambda col: (q_nom[col.name] - col).clip(lower=0)).mean().mean())
        # Convert SCMD → kg CH4/day → t CO2e/day (GWP20)
        FCH4_kg_day = leak_flow_proxy * 0.717 * 0.92
        FCH4_tCO2e  = FCH4_kg_day * CH4_GWP20 / 1000
    else:
        FCH4_tCO2e = 0.0

    results.append({
        'Attack': f'A{aid}',
        'Class': name,
        'Mean IP (bar)': round(IP_mean, 4),
        'Max IP (bar)': round(IP_max, 2),
        'Rows > MAOP (%)': round(pct_maop, 3),
        'LD (SCMD)': round(LD, 3),
        'FCH4 (t CO2e/day)': round(FCH4_tCO2e, 4)
    })

table = pd.DataFrame(results)
print(table.to_string(index=False))
Path('reports').mkdir(exist_ok=True)
table.to_csv('reports/consequence_integrals.csv', index=False)