"""
scripts/validate_smoke_output.py — Phase 0 CI smoke-test validator
==================================================================
Validates that main_simulation(5, false) produced a well-formed master_dataset.csv.

Checks:
  1. Output file exists at automated_dataset/master_dataset.csv
  2. At least 2000 data rows (skipping provenance/header lines)
  3. No NaN values in any numeric column

Exit codes:
  0 — all checks passed
  1 — validation failed (prints which check failed)

Usage (from repo root):
    python scripts/validate_smoke_output.py
    python scripts/validate_smoke_output.py --csv path/to/master_dataset.csv
"""

import argparse
import sys
from pathlib import Path

import pandas as pd


MIN_ROWS = 2000


def load_csv(path: Path) -> pd.DataFrame:
    """Load CSV, skipping comment/provenance lines (lines starting with #)."""
    return pd.read_csv(path, comment="#", low_memory=False)


def validate(csv_path: Path) -> list[str]:
    """
    Run all checks. Returns list of failure messages (empty = all passed).
    """
    failures = []

    # ── Check 1: file exists ─────────────────────────────────────────────────
    if not csv_path.exists():
        failures.append(
            f"FAIL [check 1] Output CSV not found: {csv_path}\n"
            "  main_simulation(5, false) must write to automated_dataset/master_dataset.csv"
        )
        return failures   # cannot continue without the file

    # ── Load ─────────────────────────────────────────────────────────────────
    try:
        df = load_csv(csv_path)
    except Exception as e:
        failures.append(f"FAIL [load] Could not parse CSV: {e}")
        return failures

    n_rows = len(df)
    print(f"[smoke] Loaded {csv_path} → {n_rows} rows × {len(df.columns)} cols")

    # ── Check 2: minimum row count ───────────────────────────────────────────
    if n_rows < MIN_ROWS:
        failures.append(
            f"FAIL [check 2] Only {n_rows} rows — expected ≥ {MIN_ROWS}.\n"
            "  A 5-minute simulation at 1 Hz logging produces ~300 rows;\n"
            "  ensure log_every is not set too high or the simulation is not terminating early."
        )
    else:
        print(f"[smoke] check 2 PASS — {n_rows} rows ≥ {MIN_ROWS}")

    # ── Check 3: no NaN in numeric columns ──────────────────────────────────
    non_label_cols = [
        c for c in df.columns
        if c not in ("ATTACK_NAME", "MITRE_ID")
        and df[c].dtype.kind in ("f", "i", "u")
    ]
    nan_counts = df[non_label_cols].isna().sum()
    bad_cols   = nan_counts[nan_counts > 0]
    if not bad_cols.empty:
        summary = ", ".join(f"{c}={v}" for c, v in bad_cols.items())
        failures.append(
            f"FAIL [check 3] NaN values found in {len(bad_cols)} column(s): {summary}"
        )
    else:
        print(f"[smoke] check 3 PASS — no NaN in {len(non_label_cols)} numeric columns")

    return failures


def main():
    parser = argparse.ArgumentParser(description="Smoke-test output validator")
    parser.add_argument(
        "--csv",
        default="automated_dataset/master_dataset.csv",
        help="Path to master_dataset.csv (default: automated_dataset/master_dataset.csv)",
    )
    args = parser.parse_args()

    csv_path = Path(args.csv)
    failures = validate(csv_path)

    if failures:
        print("\n── SMOKE TEST FAILED ──────────────────────────────────────")
        for msg in failures:
            print(msg)
        sys.exit(1)
    else:
        print("\n── SMOKE TEST PASSED ──────────────────────────────────────")
        sys.exit(0)


if __name__ == "__main__":
    main()
