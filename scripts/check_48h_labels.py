"""
scripts/check_48h_labels.py
============================
Diagnoses attack_frac=0.000 in 48h continuous data.

Checks per-run:
  - Total rows, label distribution
  - ATTACK_ID distribution
  - regime_class distribution
  - Time range where attacks appear (if any)

Run: python scripts/check_48h_labels.py
"""

import sys
from pathlib import Path
import pandas as pd

SWEEP_DIR = Path("automated_dataset/continuous_48h")

def check_run(run_dir: Path):
    csv = run_dir / "physics_dataset.csv"
    if not csv.exists():
        print(f"  SKIP: {csv} not found")
        return

    df = pd.read_csv(csv, low_memory=False)
    n = len(df)
    print(f"\n[{run_dir.name}] {n:,} rows x {df.shape[1]} cols")

    # Label column
    if 'label' in df.columns:
        lv = pd.to_numeric(df['label'], errors='coerce')
        n_attack = (lv > 0).sum()
        print(f"  label: {n_attack} non-zero ({100*n_attack/n:.2f}%)")
    else:
        print("  WARNING: 'label' column NOT FOUND")
        print(f"  Available cols: {list(df.columns[:10])}...")

    # ATTACK_ID column
    if 'ATTACK_ID' in df.columns:
        aids = pd.to_numeric(df['ATTACK_ID'], errors='coerce')
        n_atk = (aids > 0).sum()
        print(f"  ATTACK_ID>0: {n_atk} rows ({100*n_atk/n:.2f}%)")
        if n_atk > 0:
            if 'Timestamp_s' in df.columns:
                atk_t = df.loc[aids > 0, 'Timestamp_s']
                print(f"  Attack time range: {atk_t.min():.0f}s - {atk_t.max():.0f}s "
                      f"(hours {atk_t.min()/3600:.1f}-{atk_t.max()/3600:.1f})")
            vc = aids[aids > 0].value_counts().sort_index()
            print(f"  Attack IDs present: {dict(vc)}")
        else:
            print("  NOTE: 0 attack rows -> checking Timestamp range...")
            if 'Timestamp_s' in df.columns:
                t_max = df['Timestamp_s'].max()
                print(f"  Max timestamp: {t_max:.0f}s = {t_max/3600:.1f}h")
    else:
        print("  WARNING: 'ATTACK_ID' column NOT FOUND")

    # regime_class
    if 'regime_class' in df.columns:
        print(f"  regime_class: {df['regime_class'].value_counts().to_dict()}")

def main():
    if not SWEEP_DIR.exists():
        sys.exit(f"ERROR: {SWEEP_DIR} not found")

    run_dirs = sorted(SWEEP_DIR.glob("run_??"))
    if not run_dirs:
        sys.exit(f"ERROR: No run_XX dirs in {SWEEP_DIR}")

    print(f"Checking {len(run_dirs)} runs in {SWEEP_DIR}\n")
    print("=" * 60)

    for run_dir in run_dirs:
        check_run(run_dir)

    print("\n" + "=" * 60)
    print("DIAGNOSIS:")
    print("  If ATTACK_ID>0 rows exist but label=0 -> label bug (fix in run_48h_continuous.m)")
    print("  If ATTACK_ID=0 for all rows -> attacks not placed (Fix 7 not applied or density=none)")
    print("  If 'label' column missing -> wrong CSV format/version")
    print("\nFIX OPTIONS:")
    print("  A. Re-run sweep in MATLAB: run_48h_sweep()  (Fix 7 must be applied first)")
    print("  B. If ATTACK_ID>0 but label=0: python scripts/patch_48h_labels.py --apply")
    print("     Then: python ml_pipeline/build_train_test_val_splits.py --rebuild-48h")

if __name__ == "__main__":
    main()
