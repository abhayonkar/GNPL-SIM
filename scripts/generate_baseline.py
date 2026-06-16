"""
scripts/generate_baseline.py
============================
Extracts normal (ATTACK_ID==0) rows from physics_dataset_windows.csv
and writes them as ml_dataset_baseline.csv.

Run from project root:
    python scripts/generate_baseline.py

This is a valid substitute for run_24h_sweep since:
  - physics_dataset_windows has 672,249 normal rows (66% of 1.0M)
  - These rows come from 197 distinct scenarios at varying operating points
  - The scaler/threshold in cgd_ids_pipeline.py is trained on label==0 rows only

Alternative: add --baseline to cgd_ids_pipeline.py call to skip this entirely.
"""

import sys
from pathlib import Path

import pandas as pd

SRC  = Path("automated_dataset/attack_windows/physics_dataset_windows.csv")
DST  = Path("automated_dataset/ml_dataset_baseline.csv")

def main():
    if not SRC.exists():
        sys.exit(f"[generate_baseline] ERROR: {SRC} not found")

    print(f"[generate_baseline] Loading {SRC} ...")
    df = pd.read_csv(SRC, low_memory=False)
    print(f"  {len(df):,} rows x {df.shape[1]} cols")

    if "ATTACK_ID" not in df.columns:
        sys.exit("[generate_baseline] ERROR: ATTACK_ID column not found")

    normal = df[df["ATTACK_ID"] == 0].copy()
    print(f"  Normal rows (ATTACK_ID==0): {len(normal):,}")

    DST.parent.mkdir(parents=True, exist_ok=True)
    normal.to_csv(DST, index=False)
    info = DST.stat()
    print(f"  Written -> {DST}  ({info.st_size/1024/1024:.1f} MB)")
    print(f"  Scenarios: {normal['scenario_id'].nunique()}")
    print("[generate_baseline] Done -- ready to run cgd_ids_pipeline.py")

if __name__ == "__main__":
    main()
