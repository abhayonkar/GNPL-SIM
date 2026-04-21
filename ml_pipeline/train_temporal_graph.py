"""
train_temporal_graph.py — End-to-End Temporal + Graph IDS Training
====================================================================
BUG FIXES vs previous version:
  FIX 1 — X_node_test was NOT aligned to sequence indexing.
           X_seq_test has (N - seq_len + 1) rows (sliding windows).
           X_node_test was built with N rows → np.stack in fuse_scores
           crashed with "all arrays must be same size".
           Fixed: X_node_test = X_node_test[seq_len-1:]

  FIX 2 — n_val_seq ≠ n_val_gnn caused np.stack crash in fit_threshold.
           X_seq_normal has (N_normal - seq_len + 1) sequences.
           X_node_normal has N_normal rows.
           Fixed: compute n_val = min(n_val_seq, n_val_gnn) and use
           the same count for all three inputs.

  FIX 3 (OOM) — build_sequences called with step=1 on 1.3M-row dataset
           allocated 6.67 GiB float64 → crash on machines with <8 GB RAM.
           Fixed:
             • All sequences built as float32 (4 bytes not 8).
             • --seq-step controls stride (default 5 for train, 15 for test).
             • --max-seq-train / --max-seq-test cap sequence count.
             • build_sequences_with_labels uses shared _compute_starts()
               so windows and labels are always the same length.

Trains and evaluates all three model tiers:
  Tier 1: LSTM-AE      (temporal, unsupervised)
  Tier 2: GNN          (graph, unsupervised)
  Tier 3: Hybrid IDS   (fusion of Tier 1 + 2 + physics residual)

Usage:
  python train_temporal_graph.py
  python train_temporal_graph.py --data ../automated_dataset/attack_windows/physics_dataset_windows.csv --epochs 20
  python train_temporal_graph.py --epochs 30 --no-gnn
  # Memory-constrained machine (4 GB VRAM):
  python train_temporal_graph.py --seq-step 10 --max-seq-train 30000 --max-seq-test 10000
"""

import argparse
import json
import os
from pathlib import Path
from datetime import datetime
import numpy as np
import pandas as pd
from sklearn.metrics import (classification_report, f1_score,
                             roc_auc_score, precision_score, recall_score)
from sklearn.preprocessing import StandardScaler

import sys
sys.path.insert(0, str(Path(__file__).parent))
from models.lstm_ae   import (LSTMAEDetector, build_sequences,
                               build_sequences_with_labels, _compute_starts)
from models.gnn_ids   import (GraphAnomalyDetector, build_pipeline_adj,
                               build_node_features, DEFAULT_NODE_FEATURE_MAP)
from models.hybrid_ids import HybridIDS, physics_anomaly_score, normalise_scores

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR   = Path(__file__).parent
SIM_ROOT     = SCRIPT_DIR.parent
DEFAULT_DATA = SIM_ROOT / "automated_dataset/attack_windows/physics_dataset_windows.csv"
OUT_DIR      = SCRIPT_DIR / "ml_outputs"

ATTACK_NAMES = {
    0:"Normal", 1:"SourceSpike",  2:"CompRamp",     3:"ValveForce",
    4:"DemandInject", 5:"PressureSpoof", 6:"FlowSpoof", 7:"PLCLatency",
    8:"PipeLeak", 9:"FDI_Stealthy", 10:"ReplayAttack",
}

META_COLS  = ["Timestamp_s","scenario_id","source_config","demand_profile",
              "valve_config","storage_init","cs_mode","regime_id"]
LABEL_COLS = ["label","ATTACK_ID","FAULT_ID","MITRE_CODE",
              "prop_origin_node","prop_hop_node","prop_delay_s",
              "prop_cascade_step","cusum_alarm","chi2_alarm",
              "attack_start","recovery_start","recovery_phase"]


# ─────────────────────────────────────────────────────────────────────────────
# Data loading
# ─────────────────────────────────────────────────────────────────────────────

def load_and_prepare(data_path: Path, nrows=None):
    print(f"\n[data] Loading → {data_path}")
    df = pd.read_csv(data_path, nrows=nrows, low_memory=False)
    print(f"       {len(df):,} rows × {len(df.columns)} cols")

    skip = set(META_COLS + LABEL_COLS)
    for col in df.columns:
        if col not in skip:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    for col, default in [("ATTACK_ID", 0), ("label", 0)]:
        if col not in df.columns:
            df[col] = default
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(default).astype(int)

    if "scenario_id" not in df.columns:
        df["scenario_id"] = 0

    feat_cols = [c for c in df.columns if c not in skip and df[c].dtype != object]
    df[feat_cols] = df[feat_cols].ffill().bfill().fillna(0)

    return df, feat_cols


def scenario_split(df, test_frac=0.2, seed=42):
    rng   = np.random.default_rng(seed)
    sids  = df["scenario_id"].unique()
    n_test = max(1, int(len(sids) * test_frac))
    test_sids = set(rng.choice(sids, n_test, replace=False).tolist())
    mask  = df["scenario_id"].isin(test_sids)
    return df[~mask].copy(), df[mask].copy()


def time_split(df, test_frac=0.2):
    """Chronological split — first 80% train, last 20% test.
    Used when only one scenario exists (e.g. 48h continuous dataset)."""
    cut = int(len(df) * (1.0 - test_frac))
    return df.iloc[:cut].copy(), df.iloc[cut:].copy()


# ─────────────────────────────────────────────────────────────────────────────
# Evaluation helpers
# ─────────────────────────────────────────────────────────────────────────────

def evaluate(y_true, y_pred, scores, model_name: str) -> dict:
    n_cls = len(np.unique(y_true))
    auc   = roc_auc_score(y_true, scores) if n_cls > 1 else float('nan')
    f1    = f1_score(y_true, y_pred, zero_division=0)
    prec  = precision_score(y_true, y_pred, zero_division=0)
    rec   = recall_score(y_true, y_pred, zero_division=0)

    print(f"\n[{model_name}] F1={f1:.4f}  AUC={auc:.4f}  Prec={prec:.4f}  Rec={rec:.4f}")
    print(classification_report(y_true, y_pred,
                                target_names=["Normal","Anomaly"], zero_division=0))
    return {"model": model_name, "f1": f1, "auc": auc,
            "precision": prec, "recall": rec}


def per_attack_eval(df_test, y_pred, model_name: str) -> pd.DataFrame:
    rows = []
    for aid in sorted(df_test["ATTACK_ID"].unique()):
        mask = (df_test["ATTACK_ID"] == aid).values
        if mask.sum() == 0:
            continue
        f1 = f1_score(
            (df_test["ATTACK_ID"].values != 0).astype(int)[mask],
            y_pred[mask], zero_division=0
        )
        rows.append({"attack_id": int(aid),
                     "attack_name": ATTACK_NAMES.get(int(aid), f"A{aid}"),
                     "model": model_name, "f1": round(f1, 4),
                     "n_samples": int(mask.sum())})
    return pd.DataFrame(rows)


def detection_delay(df_test, y_pred, model_name: str) -> pd.DataFrame:
    rows = []
    if "attack_start" not in df_test.columns:
        return pd.DataFrame(rows)

    df_reset = df_test.reset_index(drop=True)
    attack_starts = df_reset.index[df_reset["attack_start"] == 1].tolist()
    for start_idx in attack_starts:
        if start_idx >= len(y_pred):
            continue
        aid    = df_reset.loc[start_idx, "ATTACK_ID"]
        future = np.where(y_pred[start_idx:] == 1)[0]
        delay  = int(future[0]) if len(future) > 0 else -1
        rows.append({"attack_id": int(aid),
                     "attack_name": ATTACK_NAMES.get(int(aid), f"A{aid}"),
                     "model": model_name, "delay_steps": delay})
    return pd.DataFrame(rows)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data",          default=str(DEFAULT_DATA))
    parser.add_argument("--nrows",         type=int,   default=None)
    parser.add_argument("--seq-len",       type=int,   default=30)
    parser.add_argument("--epochs",        type=int,   default=20)
    parser.add_argument("--no-gnn",        action="store_true")
    parser.add_argument("--out-dir",       default=str(OUT_DIR))
    # ── FIX 3: memory-control args ────────────────────────────────────────
    parser.add_argument("--seq-step",      type=int,   default=5,
                        help="Stride for train sequences (default 5). "
                             "Larger = fewer sequences = less RAM.")
    parser.add_argument("--seq-step-test", type=int,   default=None,
                        help="Stride for test sequences (default 3× seq-step).")
    parser.add_argument("--max-seq-train", type=int,   default=50_000,
                        help="Max training sequences (default 50000, ~0.7 GB).")
    parser.add_argument("--max-seq-test",  type=int,   default=20_000,
                        help="Max test sequences (default 20000, ~0.24 GB).")
    args = parser.parse_args()

    # Derive test step from train step if not set explicitly
    seq_step_test = args.seq_step_test or (args.seq_step * 3)

    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M")
    out_dir = Path(args.out_dir) / timestamp
    out_dir.mkdir(parents=True, exist_ok=True)
    seq_len = args.seq_len

    print(f"\n[config] seq_len={seq_len}  "
          f"step_train={args.seq_step}  step_test={seq_step_test}  "
          f"max_train={args.max_seq_train:,}  max_test={args.max_seq_test:,}")

    # ── Load + split ──────────────────────────────────────────────────────
    df, feat_cols = load_and_prepare(Path(args.data), args.nrows)
    n_scenarios = df["scenario_id"].nunique()
    if n_scenarios <= 1:
        print(f"[split] Single scenario detected → using chronological 80/20 time split")
        df_train, df_test = time_split(df)
    else:
        df_train, df_test = scenario_split(df)

    print(f"\n[split] Train: {len(df_train):,} rows ({df_train['scenario_id'].nunique()} scenarios)")
    print(f"[split] Test : {len(df_test):,} rows ({df_test['scenario_id'].nunique()} scenarios)")

    n_classes = len(np.unique(df_train["label"].values))

    # ── Scale ─────────────────────────────────────────────────────────────
    scaler = StandardScaler()
    normal_mask_tr = df_train["label"] == 0
    scaler.fit(df_train.loc[normal_mask_tr, feat_cols].fillna(0))

    # Cast to float32 immediately to halve memory vs float64
    X_train_flat = scaler.transform(df_train[feat_cols].fillna(0)).astype(np.float32)
    X_test_flat  = scaler.transform(df_test[feat_cols].fillna(0)).astype(np.float32)
    y_train      = df_train["label"].values
    y_test       = df_test["label"].values

    all_results, all_delay, all_per_atk = [], [], []

    # ── TIER 1: LSTM-AE ───────────────────────────────────────────────────
    print("\n" + "="*60)
    print("  TIER 1 — LSTM Autoencoder (Temporal)")
    print("="*60)

    input_dim   = X_train_flat.shape[1]
    X_tr_normal = X_train_flat[y_train == 0]

    # FIX 3: use step + max_sequences to keep RAM under ~1 GB
    print(f"[lstm] Building train sequences  "
          f"(step={args.seq_step}, cap={args.max_seq_train:,}) ...")
    X_seq_normal = build_sequences(
        X_tr_normal, seq_len,
        step=args.seq_step,
        max_sequences=args.max_seq_train,
    )
    print(f"[lstm] Train sequences: {len(X_seq_normal):,}  "
          f"shape={X_seq_normal.shape}  "
          f"RAM≈{X_seq_normal.nbytes/1e9:.2f} GB")

    print(f"[lstm] Building test sequences  "
          f"(step={seq_step_test}, cap={args.max_seq_test:,}) ...")
    X_seq_test, y_seq_test = build_sequences_with_labels(
        X_test_flat, y_test, seq_len,
        step=seq_step_test,
        max_sequences=args.max_seq_test,
    )
    print(f"[lstm] Test sequences : {len(X_seq_test):,}  "
          f"shape={X_seq_test.shape}  "
          f"RAM≈{X_seq_test.nbytes/1e9:.2f} GB")

    # FIX 3 (df_test_seq alignment): when max_sequences caps the test set,
    # df_test_seq must index exactly the rows at each capped window's endpoint.
    # Old: iloc[seq_len-1:] → 264k rows but lstm_preds/gnn_preds only 17k → IndexError.
    # Fix: use same _compute_starts as build_sequences_with_labels, index by endpoint.
    _test_starts = _compute_starts(len(X_test_flat), seq_len,
                                   seq_step_test, args.max_seq_test)
    df_test_seq = df_test.iloc[_test_starts + seq_len - 1].reset_index(drop=True)

    lstm_det = LSTMAEDetector(input_dim=input_dim, hidden_dim=64, seq_len=seq_len)
    lstm_det.fit(X_seq_normal, epochs=args.epochs, verbose=True)

    n_val_seq = max(100, int(len(X_seq_normal) * 0.2))
    lstm_det.fit_threshold(X_seq_normal[-n_val_seq:], fpr=0.01)
    lstm_det.save(str(out_dir / "lstm_ae.pt"))

    lstm_scores = lstm_det.anomaly_score(X_seq_test)
    lstm_preds  = lstm_det.predict(X_seq_test)
    all_results.append(evaluate(y_seq_test, lstm_preds, lstm_scores, "LSTM-AE"))
    all_per_atk.append(per_attack_eval(df_test_seq, lstm_preds, "LSTM-AE"))
    all_delay.append(detection_delay(df_test_seq, lstm_preds, "LSTM-AE"))

    # ── TIER 2: GNN ───────────────────────────────────────────────────────
    if not args.no_gnn:
        print("\n" + "="*60)
        print("  TIER 2 — Graph Deviation Network (Topology)")
        print("="*60)

        adj = build_pipeline_adj(n_nodes=20)

        # Build node features for full train/test DataFrames
        X_node_train_full = build_node_features(df_train, DEFAULT_NODE_FEATURE_MAP)
        X_node_test_full  = build_node_features(df_test,  DEFAULT_NODE_FEATURE_MAP)

        # FIX 1: Align X_node_test to sequence indexing
        X_node_test = X_node_test_full[seq_len - 1:]

        # Normalise per node-feature dimension
        node_mean = X_node_train_full[y_train == 0].mean(axis=0, keepdims=True)
        node_std  = X_node_train_full[y_train == 0].std(axis=0, keepdims=True) + 1e-8
        X_node_train_full = (X_node_train_full - node_mean) / node_std
        X_node_test       = (X_node_test - node_mean) / node_std

        X_node_normal = X_node_train_full[y_train == 0]

        gnn_det = GraphAnomalyDetector(
            node_feat_dim=X_node_normal.shape[2], n_nodes=20,
            hidden_dim=32, adj=adj)
        gnn_det.fit(X_node_normal, epochs=args.epochs, verbose=True)

        n_val_gnn = max(50, int(len(X_node_normal) * 0.2))

        # FIX 2: Use min of n_val_seq and n_val_gnn for ALL fit_normalisation inputs
        n_val = min(n_val_seq, n_val_gnn)
        df_train_normal_tail = (df_train[normal_mask_tr]
                                .tail(n_val)
                                .reset_index(drop=True))

        gnn_det.fit_threshold(X_node_normal[-n_val:], fpr=0.01)
        gnn_det.save(str(out_dir / "gnn.pt"))

        gnn_scores = gnn_det.anomaly_score(X_node_test)
        gnn_preds  = gnn_det.predict(X_node_test)
        all_results.append(evaluate(y_seq_test, gnn_preds, gnn_scores, "GNN"))
        all_per_atk.append(per_attack_eval(df_test_seq, gnn_preds, "GNN"))
        all_delay.append(detection_delay(df_test_seq, gnn_preds, "GNN"))

    # ── Physics baseline ──────────────────────────────────────────────────
    print("\n" + "="*60)
    print("  PHYSICS RESIDUAL BASELINE (EKF + Kirchhoff)")
    print("="*60)

    phys_scores_tr = physics_anomaly_score(df_train[normal_mask_tr])
    phys_scores_te = physics_anomaly_score(df_test_seq)   # aligned slice
    phys_thresh    = float(np.quantile(phys_scores_tr, 0.99))
    phys_preds     = (phys_scores_te > phys_thresh).astype(int)
    all_results.append(evaluate(y_seq_test, phys_preds, phys_scores_te, "Physics-EKF"))

    # ── TIER 3: Hybrid Fusion ─────────────────────────────────────────────
    if not args.no_gnn:
        print("\n" + "="*60)
        print("  TIER 3 — Hybrid Fusion (LSTM + GNN + Physics)")
        print("="*60)

        ids = HybridIDS(lstm_det, gnn_det, mode='equal')

        # FIX 2: Use the same n_val for normalisation and threshold fitting
        ids.fit_normalisation(
            X_seq_normal[-n_val:],
            X_node_normal[-n_val:],
            df_train_normal_tail)           # same n_val rows

        if n_classes >= 2:
            # Non-overlapping sequences for supervised fusion training
            # FIX 3: pass step=seq_len, max_sequences cap for safety
            X_seq_tr_all, y_seq_tr_all = build_sequences_with_labels(
                X_train_flat, y_train, seq_len,
                step=seq_len,
                max_sequences=50_000,
            )
            # Align node features: take every seq_len-th row
            X_node_tr_all = X_node_train_full[::seq_len][:len(y_seq_tr_all)]
            df_tr_sampled = (df_train.iloc[::seq_len]
                             .iloc[:len(y_seq_tr_all)]
                             .reset_index(drop=True))
            ids.fit_weights(X_seq_tr_all, X_node_tr_all, df_tr_sampled, y_seq_tr_all)

        # FIX 2: fit_threshold with the same n_val everywhere
        ids.fit_threshold(
            X_seq_normal[-n_val:],
            X_node_normal[-n_val:],
            df_train_normal_tail,
            fpr=0.01)

        # Inference — all three inputs are aligned to seq indexing
        hybrid_scores = ids.fuse_scores(X_seq_test, X_node_test, df_test_seq)
        hybrid_preds  = ids.predict(X_seq_test, X_node_test, df_test_seq)

        all_results.append(evaluate(y_seq_test, hybrid_preds, hybrid_scores, "Hybrid-IDS"))
        all_per_atk.append(per_attack_eval(df_test_seq, hybrid_preds, "Hybrid-IDS"))
        all_delay.append(detection_delay(df_test_seq, hybrid_preds, "Hybrid-IDS"))

        breakdown = ids.score_breakdown(X_seq_test, X_node_test, df_test_seq)
        print(f"\n[hybrid] Score breakdown means:")
        for k, v in breakdown.items():
            if isinstance(v, np.ndarray):
                print(f"  {k:15s}: {v.mean():.4f}")

    # ── Save results ──────────────────────────────────────────────────────
    results_df = pd.DataFrame(all_results)
    results_df.to_csv(out_dir / "results_comparison.csv", index=False)
    print(f"\n[results]\n{results_df.to_string(index=False)}")

    if all_per_atk:
        pd.concat(all_per_atk, ignore_index=True).to_csv(
            out_dir / "per_attack_f1.csv", index=False)

    if all_delay:
        delay_df = pd.concat(all_delay, ignore_index=True)
        delay_df.to_csv(out_dir / "detection_delay.csv", index=False)
        print(f"\n[delay] Mean detection delay (steps @ 1 Hz):")
        print(delay_df.groupby("model")["delay_steps"].mean().round(1).to_string())

    paper_table = {"models": results_df.round(4).to_dict(orient="records"),
                   "note":   "1 step = 1 second at 1 Hz logging rate"}
    with open(out_dir / "paper_table.json", "w") as f:
        json.dump(paper_table, f, indent=2)

    print(f"\n{'='*60}")
    print(f"  Training complete.  Outputs → {out_dir}/")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()