"""
build_train_test_val_splits.py
==============================
Builds deterministic train/val/test splits across all three datasets.

Split strategy:
  - Split by SCENARIO_ID to prevent data leakage (correlated rows within a scenario)
  - Stratified: respects pressure group (clean vs floor-hit vs stress)
  - Produces manifest CSVs listing which scenario_ids go where
  - Produces combined train/val/test CSVs (or --manifest-only for large files)

Usage:
    # Just build manifests (fast):
    python build_train_test_val_splits.py --manifest-only

    # Build full splits (slow, large files):
    python build_train_test_val_splits.py

    # Custom paths:
    python build_train_test_val_splits.py \\
        --baseline   automated_dataset/ml_dataset_baseline.csv \\
        --windows    automated_dataset/attack_windows/physics_dataset_windows.csv \\
        --continuous automated_dataset/continuous_48h/physics_dataset_features.csv \\
        --out-dir    ml_outputs/splits
"""

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

# ── Constants ─────────────────────────────────────────────────────────────
SEED       = 42
VAL_FRAC   = 0.15
TEST_FRAC  = 0.15
TRAIN_FRAC = 1.0 - VAL_FRAC - TEST_FRAC

# Held-out sets (NEVER included in train/val):
#   STRESS scenarios — scenarios with is_stress metadata (hardest)
#   48h continuous   — temporal generalization test
HELD_OUT_TAGS = ['test_stress', 'test_48h', 'test_topology_fold2']


def scenario_group(sid: int) -> str:
    """Assign scenario to pressure group for stratified split."""
    if sid <= 120:
        return 'clean_both_source'
    elif sid <= 279:
        return 'single_source'      # some floor hits; src2_p_min issue
    else:
        return 'stress'


def load_scenario_ids(path: str, id_col: str = 'scenario_id') -> np.ndarray:
    """Read unique scenario IDs from a CSV without loading full data."""
    df = pd.read_csv(path, usecols=[id_col])
    return np.sort(df[id_col].unique())


def stratified_split(ids: np.ndarray, rng: np.random.Generator,
                     val_frac: float = VAL_FRAC,
                     test_frac: float = TEST_FRAC) -> dict:
    """
    Stratified 70/15/15 split by scenario group.
    Returns dict with keys 'train', 'val', 'test' → lists of scenario IDs.
    """
    from collections import defaultdict

    groups = defaultdict(list)
    for sid in ids:
        if isinstance(sid, (int, np.integer)):
            groups[scenario_group(int(sid))].append(sid)
        else:
            groups['other'].append(sid)   # non-numeric IDs

    result = {'train': [], 'val': [], 'test': []}

    for grp_name, grp_ids in groups.items():
        arr = np.array(sorted(grp_ids))
        rng.shuffle(arr)
        n      = len(arr)
        n_test = max(1, int(n * test_frac))
        n_val  = max(1, int(n * val_frac))

        result['test'].extend(arr[:n_test].tolist())
        result['val'].extend(arr[n_test:n_test + n_val].tolist())
        result['train'].extend(arr[n_test + n_val:].tolist())

        print(f"  Group '{grp_name}': {n} scenarios → "
              f"train={n - n_test - n_val}  val={n_val}  test={n_test}")

    return result


def write_split_csv(df: pd.DataFrame, ids: list, path: Path,
                    id_col: str = 'scenario_id'):
    """Filter df to matching scenario IDs and write to path."""
    subset = df[df[id_col].isin(set(ids))].reset_index(drop=True)
    subset.to_csv(path, index=False)
    print(f"  Wrote {len(subset):,} rows → {path}")
    return len(subset)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--baseline',   default='automated_dataset/ml_dataset_baseline.csv')
    ap.add_argument('--windows',    default='automated_dataset/attack_windows/physics_dataset_windows.csv')
    ap.add_argument('--continuous', default='automated_dataset/continuous_48h/physics_dataset_features.csv')
    ap.add_argument('--health',     default='automated_dataset/attack_windows/scenario_health.csv')
    ap.add_argument('--out-dir',    default='ml_outputs/splits')
    ap.add_argument('--manifest-only', action='store_true',
                    help='Only write JSON manifests; skip large CSV writes')
    args = ap.parse_args()

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    rng = np.random.default_rng(SEED)

    print("=" * 60)
    print("Building train/val/test splits")
    print("=" * 60)

    # ── 1. Identify ALL scenario IDs in attack_windows ───────────────────
    print(f"\n[1] Reading scenario IDs from windows dataset...")
    windows_path = Path(args.windows)
    if not windows_path.exists():
        print(f"  WARNING: {windows_path} not found — using synthetic IDs 1-382")
        all_ids = np.arange(1, 383)
    else:
        all_ids = load_scenario_ids(str(windows_path))
    print(f"  Found {len(all_ids)} unique scenario IDs")

    # ── 2. Identify stress scenarios from health file ────────────────────
    health_path = Path(args.health)
    stress_ids = []
    if health_path.exists():
        sh = pd.read_csv(str(health_path))
        sh_num = sh[pd.to_numeric(sh['scenario_id'], errors='coerce').notna()].copy()
        sh_num['scenario_id'] = sh_num['scenario_id'].astype(int)
        # Stress = floor hits > 0 OR p_std > 4.0
        stress_mask = (sh_num['pct_floor'] > 0.05) | (sh_num['p_std'] > 4.0)
        stress_ids  = sh_num.loc[stress_mask, 'scenario_id'].tolist()
        print(f"  Identified {len(stress_ids)} stress scenario IDs")

    # ── 3. Split non-stress scenarios ────────────────────────────────────
    non_stress = np.array([sid for sid in all_ids
                           if sid not in set(stress_ids)],
                          dtype=int)
    print(f"\n[2] Splitting {len(non_stress)} non-stress scenarios (70/15/15)...")
    split = stratified_split(non_stress, rng)

    # Stress goes to held-out test only
    split['test_stress'] = [int(s) for s in stress_ids]
    print(f"\n  Totals:")
    for k, v in split.items():
        print(f"    {k:20s}: {len(v)} scenarios")

    # ── 4. Write manifest ────────────────────────────────────────────────
    manifest = {
        'seed': SEED,
        'splits': {k: sorted(v) for k, v in split.items()},
        'notes': {
            'test_stress': 'Held-out: stress scenarios (single source, floor hits)',
            'test_48h':    'Held-out: 48h continuous dataset (temporal generalization)',
            'test_topology_fold2': 'Held-out: cross-topology fold 2 (lowest F1 in CV)',
            'val':   '15% of non-stress scenarios; used for threshold tuning',
            'test':  '15% of non-stress scenarios; final evaluation',
            'train': '70% of non-stress scenarios',
        }
    }
    manifest_path = out / 'split_manifest.json'
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)
    print(f"\n  Manifest → {manifest_path}")

    if args.manifest_only:
        print("\nManifest-only mode. Done.")
        return

    # ── 5. Build CSV splits ──────────────────────────────────────────────
    print(f"\n[3] Building CSV splits...")

    # Load windows dataset
    print("  Loading attack_windows...")
    df_w = pd.read_csv(args.windows)
    if 'scenario_id' not in df_w.columns:
        print("  ERROR: no 'scenario_id' column in windows dataset")
        return

    # Coerce scenario_id to int
    df_w['scenario_id'] = pd.to_numeric(df_w['scenario_id'], errors='coerce').fillna(0).astype(int)

    print(f"  Windows shape: {df_w.shape}")

    for split_name in ['train', 'val', 'test', 'test_stress']:
        ids = split[split_name]
        if not ids:
            continue
        out_path = out / f'windows_{split_name}.csv'
        n = write_split_csv(df_w, ids, out_path)

    # Load baseline (normal-only) — add to train
    baseline_path = Path(args.baseline)
    if baseline_path.exists():
        print("\n  Loading baseline (normal-only)...")
        df_b = pd.read_csv(str(baseline_path))
        if 'scenario_id' not in df_b.columns:
            df_b['scenario_id'] = -1   # no scenario structure
        df_b['dataset_src'] = 'baseline'
        out_path = out / 'baseline_normal.csv'
        df_b.to_csv(out_path, index=False)
        print(f"  Baseline: {len(df_b):,} rows → {out_path}")
    else:
        print(f"  WARNING: baseline not found at {baseline_path}")

    # Load 48h continuous as held-out test set
    cont_path = Path(args.continuous)
    if cont_path.exists():
        print("\n  Loading 48h continuous (held-out test)...")
        df_48h = pd.read_csv(str(cont_path))
        df_48h['dataset_src'] = '48h_continuous'
        out_path = out / 'test_48h_continuous.csv'
        df_48h.to_csv(out_path, index=False)
        print(f"  48h: {len(df_48h):,} rows → {out_path}")

        # Update manifest with 48h info
        manifest['splits']['test_48h'] = ['all_172800_rows']
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2)
    else:
        print(f"  WARNING: 48h dataset not found at {cont_path}")

    # ── 6. Summary stats ────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("SPLIT SUMMARY")
    print("=" * 60)

    for split_name in ['train', 'val', 'test', 'test_stress']:
        csv = out / f'windows_{split_name}.csv'
        if csv.exists():
            n_rows = sum(1 for _ in open(csv)) - 1
            n_scen = len(split[split_name])
            pct_attack = '?'
            try:
                df_tmp = pd.read_csv(str(csv), usecols=['label'])
                pct_attack = f"{df_tmp['label'].mean()*100:.1f}%"
            except Exception:
                pass
            print(f"  {split_name:20s}: {n_scen:3d} scenarios  "
                  f"{n_rows:>9,} rows  attack={pct_attack}")

    print(f"\nAll files in: {out.resolve()}")
    print("\nRun commands:")
    print(f"  # Traditional ML (train on train split):")
    print(f"  python cgd_ids_pipeline.py \\")
    print(f"      --attacks  {out}/windows_train.csv \\")
    print(f"      --baseline {args.baseline} \\")
    print(f"      --out-dir  ml_outputs/attack_windows/traditional_ml/run_3")
    print(f"\n  # Temporal+Graph (train on train, eval on val):")
    print(f"  python train_temporal_graph.py \\")
    print(f"      --data     {out}/windows_train.csv \\")
    print(f"      --val-data {out}/windows_val.csv \\")
    print(f"      --epochs 30 --seq-step 5 --max-seq-train 50000 --max-seq-test 20000 \\")
    print(f"      --out-dir  ml_outputs/attack_windows/temporal_graph/run3")


if __name__ == '__main__':
    main()
