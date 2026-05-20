"""
evaluate_cross_regime.py — Cross-Regime Generalisation Evaluation
==================================================================
Loads trained LSTM-AE + GNN models (trained exclusively on short attack-window
scenarios) and evaluates them on each of the 10 48h continuous sweep runs.

Cross-regime shift: models trained on 24h attack-window scenarios (normal
density, single regime) are evaluated on structurally different 48h runs
that span morning/evening peaks, maintenance windows, source interruptions.

Per-run metrics: F1, AUC, precision, recall, detection delay
Attack-family breakdown: Physical / Sensor / Cyber (see ATTACK_FAMILIES)
Aggregated: mean±std across runs 01–09; run 10 (clean) → FPR only

Paper 2 Table IV output: reports/cross_regime_summary.csv

Usage:
    python scripts/evaluate_cross_regime.py
    python scripts/evaluate_cross_regime.py \\
        --model-dir ml_outputs/attack_windows/temporal_graph/run_2/2026-05-17_02-37 \\
        --train-csv ml_outputs/splits/windows_train.csv \\
        --sweep-dir automated_dataset/continuous_48h \\
        --out       reports/cross_regime_results.csv
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import (f1_score, roc_auc_score,
                             precision_score, recall_score)
from sklearn.preprocessing import StandardScaler

SCRIPT_DIR = Path(__file__).parent
SIM_ROOT   = SCRIPT_DIR.parent
sys.path.insert(0, str(SIM_ROOT / "ml_pipeline"))

from models.lstm_ae  import (LSTMAEDetector, build_sequences,
                              build_sequences_with_labels, _compute_starts)
from models.gnn_ids  import (GraphAnomalyDetector, build_node_features,
                              DEFAULT_NODE_FEATURE_MAP)
from models.hybrid_ids import HybridIDS, physics_anomaly_score
from train_temporal_graph import (
    load_and_prepare, align_feature_columns,
    META_COLS, LABEL_COLS, ATTACK_NAMES,
)

# ── Attack family definitions ─────────────────────────────────────────────────
# Based on run_48h_sweep.m design matrix groupings.
ATTACK_FAMILIES = {
    'Physical': {1, 2, 3, 8},    # SourceSpike, CompRamp, ValveForce, PipeLeak
    'Sensor':   {5, 6, 9},       # PressureSpoof, FlowSpoof, FDI_Stealthy
    'Cyber':    {7, 10},         # PLCLatency, ReplayAttack
}


def attack_family(aid: int) -> str:
    for name, ids in ATTACK_FAMILIES.items():
        if aid in ids:
            return name
    return 'Other'


# ── Model loading ─────────────────────────────────────────────────────────────

def find_latest_model_dir(base: Path) -> Path:
    """Return the most recently created timestamped subdirectory that has lstm_ae.pt."""
    dirs = sorted(d for d in base.iterdir()
                  if d.is_dir() and (d / 'lstm_ae.pt').exists())
    if not dirs:
        raise FileNotFoundError(
            f"No model directories with lstm_ae.pt found under {base}.\n"
            "Run train_temporal_graph.py first.")
    return dirs[-1]


def load_models(model_dir: Path):
    lstm_path = model_dir / 'lstm_ae.pt'
    gnn_path  = model_dir / 'gnn.pt'
    if not lstm_path.exists():
        raise FileNotFoundError(f"lstm_ae.pt not found in {model_dir}")
    lstm_det = LSTMAEDetector.load(str(lstm_path))
    gnn_det  = GraphAnomalyDetector.load(str(gnn_path)) if gnn_path.exists() else None
    print(f"[models] LSTM-AE: seq_len={lstm_det.seq_len}  input_dim={lstm_det.input_dim}")
    if gnn_det:
        print(f"[models] GNN: n_nodes={gnn_det.n_nodes}")
    return lstm_det, gnn_det


# ── Scaler ────────────────────────────────────────────────────────────────────

def build_scaler(train_csv: Path, nrows=None):
    """
    Fit scaler and extract feat_cols from training data.
    Returns (scaler, feat_cols, df_normal) where df_normal is a subset of
    normal rows used later for hybrid normalisation references.
    """
    print(f"\n[scaler] Loading training data -> {train_csv}")
    if not train_csv.exists():
        raise FileNotFoundError(
            f"Training CSV not found: {train_csv}\n"
            "Run build_train_test_val_splits.py first.")
    df_train, feat_cols = load_and_prepare(train_csv, nrows)
    normal_mask = df_train['label'] == 0
    if not normal_mask.any():
        raise ValueError("No normal (label=0) rows found in training CSV.")
    scaler = StandardScaler()
    scaler.fit(df_train.loc[normal_mask, feat_cols].fillna(0))
    df_normal = df_train[normal_mask].reset_index(drop=True)
    print(f"[scaler] Fit on {len(df_normal):,} normal rows, {len(feat_cols)} features")
    return scaler, feat_cols, df_normal


# ── Node-feature normalisation reference ─────────────────────────────────────

def _node_norm_params(df_normal):
    """Compute per-node-feature mean/std from normal training rows."""
    X = build_node_features(df_normal, DEFAULT_NODE_FEATURE_MAP)  # (N, n_nodes, feat_dim)
    mean = X.mean(axis=0, keepdims=True)
    std  = X.std(axis=0,  keepdims=True) + 1e-8
    return mean, std


# ── Evaluation helpers ────────────────────────────────────────────────────────

def _median_delay(df_seq: pd.DataFrame, y_pred: np.ndarray) -> float | None:
    """Median steps from attack_start to first detection (1 step = 1 s at 1 Hz)."""
    if 'attack_start' not in df_seq.columns:
        return None
    starts = df_seq.index[df_seq['attack_start'] == 1].tolist()
    if not starts:
        return None
    delays = []
    for si in starts:
        if si >= len(y_pred):
            continue
        hit = np.where(y_pred[si:] == 1)[0]
        if len(hit) > 0:
            delays.append(int(hit[0]))
    return float(np.median(delays)) if delays else None


def _metrics_dict(y_true, y_pred, scores) -> dict:
    n_cls = len(np.unique(y_true))
    auc   = float(roc_auc_score(y_true, scores)) if n_cls > 1 else float('nan')
    return {
        'f1':        round(float(f1_score(y_true, y_pred, zero_division=0)), 4),
        'auc':       round(auc, 4) if not np.isnan(auc) else None,
        'precision': round(float(precision_score(y_true, y_pred, zero_division=0)), 4),
        'recall':    round(float(recall_score(y_true, y_pred, zero_division=0)), 4),
    }


def _build_rows(run_id, run_meta, model_name,
                y_all_seq, y_pred, scores, df_seq, is_clean) -> list[dict]:
    """
    Build one result row per family (Physical / Sensor / Cyber / ALL).
    If is_clean (run_10): only compute FPR; all other metrics are None.
    """
    base = {
        'run_id':      run_id,
        'seed':        run_meta.get('seed', -1),
        'density':     run_meta.get('density', ''),
        'description': run_meta.get('description', ''),
        'model':       model_name,
        'clean_run':   is_clean,
    }

    if is_clean:
        fpr = float(y_pred.mean())   # y_true is all-0 → any pred=1 is a FP
        return [{**base, 'family': 'CLEAN',
                 'fpr': round(fpr, 4),
                 'f1': None, 'auc': None,
                 'precision': None, 'recall': None,
                 'detection_delay_median_s': None}]

    rows = []

    # Overall (all attack types combined)
    m = _metrics_dict(y_all_seq, y_pred, scores)
    rows.append({**base, 'family': 'ALL', 'fpr': None,
                 **m, 'detection_delay_median_s': _median_delay(df_seq, y_pred)})

    # Per attack family
    if 'ATTACK_ID' in df_seq.columns:
        for fam, fam_ids in ATTACK_FAMILIES.items():
            atk_mask  = df_seq['ATTACK_ID'].isin(fam_ids)
            if not atk_mask.any():
                continue
            norm_mask = df_seq['ATTACK_ID'] == 0
            sel       = (atk_mask | norm_mask).values

            yt_f  = atk_mask[sel].astype(int).values
            yp_f  = y_pred[sel]
            sc_f  = scores[sel]

            m_f = _metrics_dict(yt_f, yp_f, sc_f)
            rows.append({**base, 'family': fam, 'fpr': None,
                         **m_f,
                         'detection_delay_median_s': _median_delay(
                             df_seq[sel].reset_index(drop=True), yp_f)})

    return rows


# ── Per-run evaluation ────────────────────────────────────────────────────────

def eval_run(run_dir: Path, run_id: int, run_meta: dict,
             lstm_det, gnn_det,
             scaler, feat_cols, df_train_normal,
             node_mean, node_std,
             seq_len: int, seq_step: int, max_seq: int) -> list[dict]:

    csv_path = run_dir / 'physics_dataset.csv'
    if not csv_path.exists():
        print(f"  [run_{run_id:02d}] physics_dataset.csv not found — skipping")
        return []

    print(f"\n[run_{run_id:02d}] Loading {csv_path.name}")
    df_run, run_feat_cols = load_and_prepare(csv_path)

    # Align feature set to training contract (add missing cols as 0)
    for col in feat_cols:
        if col not in df_run.columns:
            df_run[col] = 0.0
        df_run[col] = pd.to_numeric(df_run[col], errors='coerce').fillna(0.0)

    is_clean = (run_meta.get('density', '') == 'none'
                or not run_meta.get('attack_types'))

    # ── Scale + build sequences ───────────────────────────────────────────
    X_flat = scaler.transform(df_run[feat_cols].fillna(0)).astype(np.float32)
    y_all  = df_run['label'].values

    X_seq, y_seq = build_sequences_with_labels(
        X_flat, y_all, seq_len, step=seq_step, max_sequences=max_seq)
    starts  = _compute_starts(len(X_flat), seq_len, seq_step, max_seq)
    df_seq  = df_run.iloc[starts + seq_len - 1].reset_index(drop=True)
    print(f"  Sequences: {len(X_seq):,}  attack_frac={y_seq.mean():.3f}")

    # ── Node features ─────────────────────────────────────────────────────
    X_node_full = build_node_features(df_run, DEFAULT_NODE_FEATURE_MAP)
    X_node      = (X_node_full[starts + seq_len - 1] - node_mean) / node_std

    results = []

    # ── LSTM-AE ───────────────────────────────────────────────────────────
    lstm_scores = lstm_det.anomaly_score(X_seq)
    lstm_preds  = lstm_det.predict(X_seq)
    results.extend(_build_rows(run_id, run_meta, 'LSTM-AE',
                               y_seq, lstm_preds, lstm_scores, df_seq, is_clean))

    # ── GNN ───────────────────────────────────────────────────────────────
    if gnn_det is not None:
        gnn_scores = gnn_det.anomaly_score(X_node)
        gnn_preds  = gnn_det.predict(X_node)
        results.extend(_build_rows(run_id, run_meta, 'GNN',
                                   y_seq, gnn_preds, gnn_scores, df_seq, is_clean))

    # ── Physics baseline ──────────────────────────────────────────────────
    phys_ref  = physics_anomaly_score(df_train_normal)
    phys_thr  = float(np.quantile(phys_ref, 0.99))
    phys_sc   = physics_anomaly_score(df_seq)
    phys_pred = (phys_sc > phys_thr).astype(int)
    results.extend(_build_rows(run_id, run_meta, 'Physics-EKF',
                               y_seq, phys_pred, phys_sc, df_seq, is_clean))

    # ── Hybrid fusion ─────────────────────────────────────────────────────
    if gnn_det is not None:
        ids = HybridIDS(lstm_det, gnn_det, mode='equal')

        # Build normalisation reference from training normal data (capped at 500)
        n_norm = min(500, len(df_train_normal))
        X_flat_norm = scaler.transform(
            df_train_normal[feat_cols].fillna(0)).astype(np.float32)
        X_seq_norm  = build_sequences(
            X_flat_norm, seq_len, step=seq_step, max_sequences=n_norm)

        if len(X_seq_norm) > 0:
            norm_starts  = _compute_starts(len(X_flat_norm), seq_len, seq_step, n_norm)
            X_node_norm  = build_node_features(
                df_train_normal.iloc[norm_starts + seq_len - 1],
                DEFAULT_NODE_FEATURE_MAP)
            X_node_norm  = (X_node_norm - node_mean) / node_std
            df_norm_seq  = (df_train_normal
                            .iloc[norm_starts + seq_len - 1]
                            .reset_index(drop=True))

            ids.fit_normalisation(X_seq_norm, X_node_norm, df_norm_seq)
            ids.fit_threshold(X_seq_norm, X_node_norm, df_norm_seq, fpr=0.05)

            hybrid_sc   = ids.fuse_scores(X_seq, X_node, df_seq)
            hybrid_pred = ids.predict(X_seq, X_node, df_seq)
            results.extend(_build_rows(run_id, run_meta, 'Hybrid-IDS',
                                       y_seq, hybrid_pred, hybrid_sc,
                                       df_seq, is_clean))

    return results


# ── Aggregation ───────────────────────────────────────────────────────────────

def aggregate(rows: list[dict]) -> pd.DataFrame:
    """
    Mean ± std across attack runs (clean_run=False) per (model, family).
    Used for Paper 2 Table IV.
    """
    df = pd.DataFrame(rows)
    attack = df[~df['clean_run']]

    metrics = ['f1', 'auc', 'precision', 'recall', 'detection_delay_median_s']
    out_rows = []
    for (model, fam), grp in attack.groupby(['model', 'family']):
        row = {'model': model, 'family': fam, 'n_runs': len(grp)}
        for m in metrics:
            vals = pd.to_numeric(grp[m], errors='coerce').dropna()
            row[f'{m}_mean'] = round(float(vals.mean()), 4) if len(vals) else None
            row[f'{m}_std']  = round(float(vals.std()),  4) if len(vals) > 1 else None
        out_rows.append(row)
    return pd.DataFrame(out_rows)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description='Cross-regime generalisation evaluation for Paper 2 Table IV')
    ap.add_argument('--model-dir',    default=None,
                    help='Timestamped model dir with lstm_ae.pt + gnn.pt. '
                         'Auto-finds latest in run_2 if omitted.')
    ap.add_argument('--train-csv',    default='ml_outputs/splits/windows_train.csv',
                    help='Training CSV; used to re-fit scaler on normal rows.')
    ap.add_argument('--sweep-dir',    default='automated_dataset/continuous_48h',
                    help='Root of 48h sweep runs (contains run_01/ … run_10/).')
    ap.add_argument('--sweep-manifest', default=None)
    ap.add_argument('--out',          default='reports/cross_regime_results.csv')
    ap.add_argument('--seq-len',      type=int, default=30)
    ap.add_argument('--seq-step',     type=int, default=15)
    ap.add_argument('--max-seq',      type=int, default=20_000)
    ap.add_argument('--nrows-train',  type=int, default=None,
                    help='Cap training rows for fast iteration.')
    args = ap.parse_args()

    # ── Resolve model directory ───────────────────────────────────────────
    if args.model_dir:
        model_dir = Path(args.model_dir)
    else:
        run2_base = SIM_ROOT / 'ml_outputs/attack_windows/temporal_graph/run_2'
        model_dir = find_latest_model_dir(run2_base)
    print(f"\n[models] Loading from {model_dir}")
    lstm_det, gnn_det = load_models(model_dir)

    # ── Scaler + feature contract ─────────────────────────────────────────
    scaler, feat_cols, df_train_normal = build_scaler(
        SIM_ROOT / args.train_csv, args.nrows_train)

    # Pre-compute node normalisation params once (expensive on large df_normal)
    node_mean, node_std = _node_norm_params(df_train_normal)

    # ── Load sweep manifest ───────────────────────────────────────────────
    sweep_dir = SIM_ROOT / args.sweep_dir
    mpath = (Path(args.sweep_manifest) if args.sweep_manifest
             else sweep_dir / 'sweep_manifest.json')
    run_configs = {}
    if mpath.exists():
        with open(mpath) as f:
            mdata = json.load(f)
        for r in mdata.get('runs', []):
            run_configs[r['run_id']] = r
        print(f"[manifest] {len(run_configs)} run configs loaded")
    else:
        print(f"[manifest] WARNING: {mpath} not found — run metadata will be empty")

    # ── Collect run directories ───────────────────────────────────────────
    run_dirs = sorted(sweep_dir.glob('run_??'))
    if not run_dirs:
        print(f"\nERROR: No run_XX directories in {sweep_dir}")
        print("       Run run_48h_sweep() in MATLAB first.")
        sys.exit(1)
    print(f"\nFound {len(run_dirs)} run directories to evaluate\n")

    # ── Evaluate each run ─────────────────────────────────────────────────
    all_rows = []
    for run_dir in run_dirs:
        run_id = int(run_dir.name.split('_')[1])
        meta   = run_configs.get(run_id, {'seed': -1, 'density': 'unknown',
                                          'description': '', 'attack_types': []})
        print(f"{'='*60}")
        print(f"  RUN {run_id:02d}  {meta.get('description','')}")
        print(f"{'='*60}")
        rows = eval_run(
            run_dir, run_id, meta,
            lstm_det, gnn_det,
            scaler, feat_cols, df_train_normal,
            node_mean, node_std,
            seq_len=args.seq_len, seq_step=args.seq_step, max_seq=args.max_seq)
        all_rows.extend(rows)
        print(f"  -> {len(rows)} metric rows")

    if not all_rows:
        print("\nNo results. Check that physics_dataset.csv exists in each run_XX dir.")
        sys.exit(1)

    # ── Write per-run results ─────────────────────────────────────────────
    out_path = SIM_ROOT / args.out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df_all = pd.DataFrame(all_rows)
    df_all.to_csv(out_path, index=False)
    print(f"\n[results] Per-run CSV -> {out_path}  ({len(df_all):,} rows)")

    # ── Aggregate summary (Paper 2 Table IV) ─────────────────────────────
    summary = aggregate(all_rows)
    summary_path = out_path.parent / 'cross_regime_summary.csv'
    summary.to_csv(summary_path, index=False)
    print(f"[results] Summary CSV -> {summary_path}")

    all_overall = summary[summary['family'] == 'ALL'].drop(columns=['family'])
    if not all_overall.empty:
        print("\n  === Overall mean±std (ALL attacks) ===")
        print(all_overall[['model', 'n_runs', 'f1_mean', 'f1_std',
                            'auc_mean', 'auc_std']].to_string(index=False))

    # ── FPR from run_10 (clean reference) ────────────────────────────────
    clean_rows = [r for r in all_rows if r.get('clean_run')]
    if clean_rows:
        clean_df = pd.DataFrame(clean_rows)[['model', 'fpr']]
        fpr_path = out_path.parent / 'cross_regime_fpr.csv'
        clean_df.to_csv(fpr_path, index=False)
        print(f"\n  === FPR on clean run_10 ===")
        print(clean_df.to_string(index=False))
        print(f"  -> {fpr_path}")

    print(f"\n{'='*60}")
    print(f"  CROSS-REGIME EVALUATION COMPLETE")
    print(f"  Per-run  -> {out_path}")
    print(f"  Summary  -> {summary_path}")
    print(f"{'='*60}\n")


if __name__ == '__main__':
    main()
