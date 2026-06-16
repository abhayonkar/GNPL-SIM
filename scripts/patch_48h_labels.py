"""
scripts/patch_48h_labels.py
============================
If check_48h_labels.py shows ATTACK_ID>0 but label=0,
this script patches label = (ATTACK_ID > 0).astype(int) in-place
for all runs and re-writes the CSVs.

Run AFTER check_48h_labels.py confirms the diagnosis.
SAFE: only changes 'label' column, all other columns untouched.

Usage:
    python scripts/patch_48h_labels.py           # dry-run (no writes)
    python scripts/patch_48h_labels.py --apply   # actually write
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

SWEEP_DIR = Path("automated_dataset/continuous_48h")


def patch_run(run_dir: Path, apply: bool):
    csv = run_dir / "physics_dataset.csv"
    if not csv.exists():
        return

    df = pd.read_csv(csv, low_memory=False)

    if "ATTACK_ID" not in df.columns:
        print(f"  [{run_dir.name}] SKIP: no ATTACK_ID column")
        return

    aids = pd.to_numeric(df["ATTACK_ID"], errors="coerce").fillna(0)
    correct_label = (aids > 0).astype(int)

    if "label" in df.columns:
        current = pd.to_numeric(df["label"], errors="coerce").fillna(0)
        diff = (current != correct_label).sum()
    else:
        diff = (correct_label > 0).sum()
        print(f"  [{run_dir.name}] WARNING: 'label' column missing, will add it")

    n_atk_after = correct_label.sum()
    print(f"  [{run_dir.name}] {diff:,} rows would change -> "
          f"{n_atk_after:,} attack rows after patch ({100*n_atk_after/len(df):.2f}%)")

    if not apply:
        return

    df["label"] = correct_label
    df.to_csv(csv, index=False)
    print(f"    WRITTEN: {csv}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="Actually write patched CSVs (default: dry-run)")
    args = ap.parse_args()

    if not SWEEP_DIR.exists():
        sys.exit(f"ERROR: {SWEEP_DIR} not found")

    run_dirs = sorted(SWEEP_DIR.glob("run_??"))
    if not run_dirs:
        sys.exit("ERROR: No run_XX dirs found")

    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"[patch_48h_labels] {mode} -- {len(run_dirs)} runs\n")

    for rd in run_dirs:
        patch_run(rd, args.apply)

    if not args.apply:
        print("\nDry-run complete. Add --apply to actually patch files.")
    else:
        print("\nPatch complete. Re-run:")
        print("  python ml_pipeline/build_train_test_val_splits.py --rebuild-48h")
        print("  python scripts/evaluate_cross_regime.py ...")


if __name__ == "__main__":
    main()
