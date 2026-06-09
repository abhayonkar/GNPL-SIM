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

    # Aggregate 48h sweep runs into test_48h_continuous.csv:
    python build_train_test_val_splits.py --rebuild-48h
    python build_train_test_val_splits.py --rebuild-48h \\
        --sweep-dir automated_dataset/continuous_48h \\
        --out-dir   ml_outputs/splits
"""

import argparse
import json
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
import pandas as pd

# Run IDs from run_48h_sweep.m that are clean (no attacks).
# These contribute FPR data only and are excluded from attack-based metrics.
_CLEAN_RUN_IDS = {10}

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
    try:
        df = pd.read_csv(path, usecols=[id_col], low_memory=False)
    except IndexError:
        # Pandas' chunked C parser can fail on very wide mixed-type CSVs when
        # usecols selects a single column. The Python engine is slower but more
        # tolerant, and this reads only the scenario_id column.
        df = pd.read_csv(path, usecols=[id_col], engine='python')

    numeric_ids = pd.to_numeric(df[id_col], errors='coerce')
    skipped = int(numeric_ids.isna().sum())
    if skipped:
        print(f"  WARNING: skipped {skipped:,} rows with non-numeric {id_col}")
    ids = numeric_ids.dropna().astype(int)
    return np.sort(ids.unique())


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

        print(f"  Group '{grp_name}': {n} scenarios -> "
              f"train={n - n_test - n_val}  val={n_val}  test={n_test}")

    return result


def write_window_splits(csv_path: Path, split: dict, out_dir: Path,
                        id_col: str = 'scenario_id',
                        chunksize: int = 50_000) -> dict:
    """Stream the windows dataset once and write each requested split."""
    split_names = [
        name for name in ['train', 'val', 'test', 'test_stress']
        if split.get(name)
    ]
    id_to_split = {
        int(sid): name
        for name in split_names
        for sid in split[name]
    }
    temp_paths = {
        name: out_dir / f'.windows_{name}.csv.tmp'
        for name in split_names
    }
    out_paths = {
        name: out_dir / f'windows_{name}.csv'
        for name in split_names
    }
    row_counts = {name: 0 for name in split_names}

    for path in temp_paths.values():
        path.unlink(missing_ok=True)

    try:
        for chunk_index, chunk in enumerate(
                pd.read_csv(csv_path, chunksize=chunksize, low_memory=False)):
            if id_col not in chunk.columns:
                raise ValueError(f"no '{id_col}' column in windows dataset")

            scenario_ids = pd.to_numeric(
                chunk[id_col], errors='coerce'
            ).fillna(0).astype(int)
            destinations = scenario_ids.map(id_to_split)

            for name in split_names:
                subset = chunk.loc[destinations.eq(name)]
                if subset.empty:
                    continue
                subset.to_csv(
                    temp_paths[name],
                    mode='a',
                    header=not temp_paths[name].exists(),
                    index=False,
                )
                row_counts[name] += len(subset)

            if (chunk_index + 1) % 10 == 0:
                print(f"    Processed {(chunk_index + 1) * chunksize:,} rows...")

        for name in split_names:
            temp_paths[name].replace(out_paths[name])
            print(f"  Wrote {row_counts[name]:,} rows -> {out_paths[name]}")
    except Exception:
        for path in temp_paths.values():
            path.unlink(missing_ok=True)
        raise

    return row_counts


def rebuild_48h_test(sweep_dir: Path, out_dir: Path) -> Path:
    """
    Aggregate all run_XX/physics_dataset.csv files from the 48h sweep into a
    single test_48h_continuous.csv.

    Each row gets two extra columns:
      run_id    — integer 1–10 matching run_48h_sweep.m design matrix
      clean_run — True only for run_10 (no attacks; FPR reference)

    Run_10 rows are included so that evaluate_cross_regime.py can measure FPR.
    They are tagged clean_run=True so attack-metric aggregation can exclude them.

    Returns the path to the written CSV.
    """
    print("\n" + "=" * 60)
    print("  Rebuilding 48h continuous test set from sweep runs")
    print(f"  sweep_dir : {sweep_dir}")
    print(f"  out_dir   : {out_dir}")
    print("=" * 60)

    # Load sweep manifest for metadata annotation
    manifest_path = sweep_dir / 'sweep_manifest.json'
    run_meta = {}
    if manifest_path.exists():
        try:
            with open(manifest_path) as f:
                mdata = json.load(f)
            for r in mdata.get('runs', []):
                run_meta[r['run_id']] = r
            print(f"  Loaded manifest with {len(run_meta)} run configs")
        except json.JSONDecodeError as exc:
            print(f"  WARNING: could not parse {manifest_path}: {exc}")
            print("           Continuing with empty metadata columns")
    else:
        print(f"  WARNING: sweep_manifest.json not found — metadata columns will be empty")

    run_dirs = sorted(sweep_dir.glob('run_??'))
    if not run_dirs:
        print(f"  ERROR: No run_XX directories found in {sweep_dir}")
        print("         Run run_48h_sweep() in MATLAB first.")
        return None

    frames = []
    for run_dir in run_dirs:
        run_id   = int(run_dir.name.split('_')[1])
        csv_path = run_dir / 'physics_dataset.csv'

        if not csv_path.exists():
            print(f"  [run_{run_id:02d}] physics_dataset.csv missing — skipping")
            continue

        print(f"  [run_{run_id:02d}] Loading {csv_path} ...", end=' ', flush=True)
        df = pd.read_csv(csv_path, low_memory=False)
        print(f"{len(df):,} rows")

        # Annotate from manifest when available
        meta = run_meta.get(run_id, {})
        run_cols = pd.DataFrame({
            'run_id': run_id,
            'clean_run': run_id in _CLEAN_RUN_IDS,
            'run_seed': meta.get('seed', -1),
            'run_density': meta.get('density', ''),
            'run_description': meta.get('description', ''),
        }, index=df.index)
        df = pd.concat([df, run_cols], axis=1)

        frames.append(df)

    if not frames:
        print("  ERROR: No run data loaded.")
        return None

    combined = pd.concat(frames, ignore_index=True)
    print(f"\n  Combined: {len(combined):,} rows across {len(frames)} runs")

    # Attack fraction in attack runs only
    attack_runs = combined[~combined['clean_run']]
    if len(attack_runs) > 0 and 'label' in attack_runs.columns:
        atk_frac = pd.to_numeric(attack_runs['label'], errors='coerce').mean()
        print(f"  Attack fraction (runs 01-09): {atk_frac:.3f}")

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / 'test_48h_continuous.csv'
    combined.to_csv(out_path, index=False)
    print(f"\n  Written -> {out_path}")

    # Update split manifest if it exists
    manifest_json = out_dir / 'split_manifest.json'
    if manifest_json.exists():
        with open(manifest_json) as f:
            manifest = json.load(f)
        manifest['splits']['test_48h'] = {
            'n_runs': len(frames),
            'n_rows': len(combined),
            'run_ids': [int(run_dir.name.split('_')[1]) for run_dir in run_dirs
                        if (run_dir / 'physics_dataset.csv').exists()],
            'clean_run_ids': list(_CLEAN_RUN_IDS),
        }
        with open(manifest_json, 'w') as f:
            json.dump(manifest, f, indent=2)
        print(f"  Updated split manifest -> {manifest_json}")

    return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--baseline',   default='automated_dataset/ml_dataset_baseline.csv')
    ap.add_argument('--windows',    default='automated_dataset/attack_windows/physics_dataset_windows.csv')
    ap.add_argument('--continuous', default='automated_dataset/continuous_48h/physics_dataset_features.csv')
    ap.add_argument('--health',     default='automated_dataset/attack_windows/scenario_health.csv')
    ap.add_argument('--out-dir',    default='ml_outputs/splits')
    ap.add_argument('--manifest-only', action='store_true',
                    help='Only write JSON manifests; skip large CSV writes')
    ap.add_argument('--rebuild-48h', action='store_true',
                    help='Aggregate all run_XX/physics_dataset.csv from --sweep-dir '
                         'into test_48h_continuous.csv. Runs independently of normal split.')
    ap.add_argument('--sweep-dir', default='automated_dataset/continuous_48h',
                    help='Root of 48h sweep runs for --rebuild-48h (contains run_01/ … run_10/).')
    args = ap.parse_args()

    # ── Early exit: 48h rebuild ───────────────────────────────────────────
    if args.rebuild_48h:
        out = Path(args.out_dir)
        rebuild_48h_test(Path(args.sweep_dir), out)
        return

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
        print(f"  WARNING: {windows_path} not found - using synthetic IDs 1-382")
        all_ids = np.arange(1, 383)
    else:
        all_ids = load_scenario_ids(str(windows_path))
    print(f"  Found {len(all_ids)} unique scenario IDs")

    # ── 2. Identify stress scenarios from health file ────────────────────
    health_path = Path(args.health)
    stress_ids = []
    if health_path.exists():
        sh = pd.read_csv(str(health_path), low_memory=False)
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
    existing_test_48h = None
    manifest_path = out / 'split_manifest.json'
    if manifest_path.exists():
        try:
            with open(manifest_path) as f:
                existing_manifest = json.load(f)
            existing_test_48h = existing_manifest.get('splits', {}).get('test_48h')
        except (json.JSONDecodeError, OSError):
            pass

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
    if existing_test_48h is not None:
        manifest['splits']['test_48h'] = existing_test_48h

    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)
    print(f"\n  Manifest -> {manifest_path}")

    if args.manifest_only:
        print("\nManifest-only mode. Done.")
        return

    # ── 5. Build CSV splits ──────────────────────────────────────────────
    print(f"\n[3] Building CSV splits...")

    print("  Streaming attack_windows...")
    try:
        write_window_splits(windows_path, split, out)
    except ValueError as exc:
        print(f"  ERROR: {exc}")
        return

    # Load baseline (normal-only) — add to train
    baseline_path = Path(args.baseline)
    if baseline_path.exists():
        print("\n  Loading baseline (normal-only)...")
        df_b = pd.read_csv(str(baseline_path), low_memory=False).copy()
        if 'scenario_id' not in df_b.columns:
            df_b['scenario_id'] = -1   # no scenario structure
        df_b['dataset_src'] = 'baseline'
        out_path = out / 'baseline_normal.csv'
        df_b.to_csv(out_path, index=False)
        print(f"  Baseline: {len(df_b):,} rows -> {out_path}")
    else:
        print(f"  WARNING: baseline not found at {baseline_path}")

    # Load 48h continuous as held-out test set
    cont_path = Path(args.continuous)
    if cont_path.exists():
        print("\n  Loading 48h continuous (held-out test)...")
        df_48h = pd.read_csv(str(cont_path), low_memory=False).copy()
        df_48h['dataset_src'] = '48h_continuous'
        out_path = out / 'test_48h_continuous.csv'
        df_48h.to_csv(out_path, index=False)
        print(f"  48h: {len(df_48h):,} rows -> {out_path}")

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
                df_tmp = pd.read_csv(str(csv), usecols=['label'], low_memory=False)
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
    print(f"\n  # After running run_48h_sweep() in MATLAB:")
    print(f"  python build_train_test_val_splits.py --rebuild-48h")
    print(f"  python scripts/evaluate_cross_regime.py")


if __name__ == '__main__':
    main()
