"""
recalibrate_crossregime.py
==========================
Post-hoc threshold recalibration for cross-regime evaluation.

Problem:
  train_temporal_graph.py sets the anomaly threshold at the 95th percentile
  of RECONSTRUCTION ERROR on attack_window NORMAL sequences.  In the 48h
  continuous domain, normal data has higher reconstruction error (regime
  changes, different operating point) so this threshold fires on everything.

Fix:
  1. Reload the saved lstm_ae.pt and gnn.pt from a crossregime run.
  2. Run inference on 48h NORMAL rows only (ATTACK_ID == 0).
  3. Reset threshold at q95 of those 48h-normal scores.
  4. Re-evaluate on the full 48h test set.

Usage:
  python scripts/recalibrate_crossregime.py \
    --train-data automated_dataset/attack_windows/physics_dataset_windows.csv \
    --test-data  ml_outputs/splits/test_48h_continuous.csv \
    --model-dir  ml_outputs/attack_windows/temporal_graph/run_q_recal_crossregime_v2/2026-06-14_10-49 \
    --out-dir    ml_outputs/attack_windows/temporal_graph/run_q_recal_crossregime_recal
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import (classification_report, f1_score,
                             roc_auc_score, precision_score, recall_score)
from sklearn.preprocessing import StandardScaler

# Make ml_pipeline importable from scripts/
sys.path.insert(0, str(Path(__file__).parent.parent / "ml_pipeline"))
from train_temporal_graph import (
    load_and_prepare, align_feature_columns,
    META_COLS, LABEL_COLS, LEAKAGE_FEATURES, ATTACK_NAMES,
)
from models.lstm_ae  import (LSTMAEDetector, build_sequences,
                              build_sequences_with_labels, _compute_starts)
from models.gnn_ids  import (GraphAnomalyDetector, build_pipeline_adj,
                              build_node_features, DEFAULT_NODE_FEATURE_MAP)
from models.hybrid_ids import physics_anomaly_score


def evaluate(y_true, y_pred, scores, name):
    auc  = roc_auc_score(y_true, scores) if len(np.unique(y_true)) > 1 else float("nan")
    f1   = f1_score(y_true, y_pred, zero_division=0)
    prec = precision_score(y_true, y_pred, zero_division=0)
    rec  = recall_score(y_true, y_pred, zero_division=0)
    print(f"\n[{name}] F1={f1:.4f}  AUC={auc:.4f}  Prec={prec:.4f}  Rec={rec:.4f}")
    print(classification_report(y_true, y_pred,
                                target_names=["Normal", "Anomaly"], zero_division=0))
    return {"model": name, "f1": f1, "auc": auc, "precision": prec, "recall": rec}


def per_attack_eval(df_aligned, y_pred, name):
    rows = []
    for aid in sorted(df_aligned["ATTACK_ID"].unique()):
        mask = (df_aligned["ATTACK_ID"] == aid).values
        if mask.sum() == 0:
            continue
        y_true_sub = (df_aligned["ATTACK_ID"].values != 0).astype(int)[mask]
        f1 = f1_score(y_true_sub, y_pred[mask], zero_division=0)
        rows.append({
            "attack_id":   int(aid),
            "attack_name": ATTACK_NAMES.get(int(aid), f"A{aid}"),
            "model":       name,
            "f1":          round(f1, 4),
            "n_samples":   int(mask.sum()),
        })
    return pd.DataFrame(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--train-data", required=True,
                        help="attack_windows CSV used for original training")
    parser.add_argument("--test-data",  required=True,
                        help="48h continuous CSV to evaluate on")
    parser.add_argument("--model-dir",  required=True,
                        help="Directory containing lstm_ae.pt and gnn.pt")
    parser.add_argument("--out-dir",    required=True)
    parser.add_argument("--seq-len",    type=int, default=60)
    parser.add_argument("--seq-step",   type=int, default=15)
    parser.add_argument("--max-seq",    type=int, default=20_000)
    parser.add_argument("--fpr",        type=float, default=0.05,
                        help="Target FPR for threshold (default 0.05)")
    parser.add_argument("--no-gnn",     action="store_true")
    args = parser.parse_args()

    out_dir   = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    model_dir = Path(args.model_dir)
    seq_len   = args.seq_len
    step      = args.seq_step
    max_seq   = args.max_seq

    print("=" * 60)
    print("  Cross-Regime Threshold Recalibration")
    print(f"  Model dir : {model_dir}")
    print(f"  Test data : {args.test_data}")
    print(f"  FPR target: {args.fpr}")
    print("=" * 60)

    # ── 1. Load training data and rebuild scaler (same as during training) ──
    print("\n[step 1] Rebuilding scaler from attack_windows training data ...")
    df_train, feat_cols = load_and_prepare(Path(args.train_data))

    skip = set(META_COLS + LABEL_COLS)
    feat_cols = [c for c in feat_cols if c not in LEAKAGE_FEATURES]

    scaler = StandardScaler()
    normal_mask_tr = df_train["label"] == 0
    scaler.fit(df_train.loc[normal_mask_tr, feat_cols].fillna(0))
    print(f"  Scaler fitted on {normal_mask_tr.sum():,} normal training rows, "
          f"{len(feat_cols)} features")

    # ── 2. Load 48h test data ───────────────────────────────────────────────
    print("\n[step 2] Loading 48h test data ...")
    df_test, _ = load_and_prepare(Path(args.test_data))
    df_train, df_test = align_feature_columns(df_train, df_test, feat_cols)

    X_test_flat = scaler.transform(df_test[feat_cols].fillna(0)).astype(np.float32)
    y_test      = df_test["label"].values

    # Normal rows only (for recalibration)
    normal_mask_te = (df_test["ATTACK_ID"] == 0).values
    X_test_normal  = X_test_flat[normal_mask_te]
    print(f"  Test rows: {len(df_test):,}  |  Normal: {normal_mask_te.sum():,}  "
          f"|  Attack: {(~normal_mask_te).sum():,}")
    print(f"  Attack fraction: {(~normal_mask_te).mean():.3f}")

    # Build test sequences (all rows, aligned)
    starts = _compute_starts(len(X_test_flat), seq_len, step, max_seq)
    X_seq_test, y_seq_test = build_sequences_with_labels(
        X_test_flat, y_test, seq_len, step=step, max_sequences=max_seq)
    df_test_seq = df_test.iloc[starts + seq_len - 1].reset_index(drop=True)
    print(f"  Test sequences: {len(X_seq_test):,}  "
          f"(normal={( y_seq_test==0).sum():,}  attack={(y_seq_test==1).sum():,})")

    # Normal sequences for threshold calibration
    X_seq_normal_te = build_sequences(X_test_normal, seq_len, step=step,
                                      max_sequences=min(10_000, len(X_test_normal)))
    print(f"  Calibration sequences (48h normal): {len(X_seq_normal_te):,}")

    all_results, all_per_atk = [], []

    # ── 3. LSTM-AE: reload, recalibrate, evaluate ───────────────────────────
    print("\n" + "=" * 60)
    print("  LSTM-AE: reload + recalibrate")
    print("=" * 60)
    lstm_path = model_dir / "lstm_ae.pt"
    lstm_det  = LSTMAEDetector.load(str(lstm_path))
    print(f"  Loaded: {lstm_path}")
    print(f"  Old threshold (attack_window domain): {lstm_det.threshold_:.5f}")

    lstm_det.fit_threshold(X_seq_normal_te, fpr=args.fpr)   # recalibrate
    print(f"  New threshold (48h-normal domain):    {lstm_det.threshold_:.5f}")

    lstm_scores = lstm_det.anomaly_score(X_seq_test)
    lstm_preds  = lstm_det.predict(X_seq_test)
    all_results.append(evaluate(y_seq_test, lstm_preds, lstm_scores, "LSTM-AE-recal"))
    all_per_atk.append(per_attack_eval(df_test_seq, lstm_preds, "LSTM-AE-recal"))

    # ── 4. GNN: reload, recalibrate, evaluate ──────────────────────────────
    if not args.no_gnn:
        print("\n" + "=" * 60)
        print("  GNN: reload + recalibrate")
        print("=" * 60)
        gnn_path = model_dir / "gnn.pt"
        gnn_det  = GraphAnomalyDetector.load(str(gnn_path))
        print(f"  Loaded: {gnn_path}")
        print(f"  Old threshold: {gnn_det.threshold_:.5f}")

        # Node features for 48h test
        X_node_test_full = build_node_features(df_test, DEFAULT_NODE_FEATURE_MAP)

        # Recompute node normalisation from training data normals
        X_node_train_full = build_node_features(df_train, DEFAULT_NODE_FEATURE_MAP)
        node_mean = X_node_train_full[normal_mask_tr.values].mean(axis=0, keepdims=True)
        node_std  = X_node_train_full[normal_mask_tr.values].std(axis=0, keepdims=True) + 1e-8
        X_node_test_norm = (X_node_test_full - node_mean) / node_std

        # Align to same sequence endpoints
        X_node_test_seq = X_node_test_norm[starts + seq_len - 1]

        # Normal node snapshots for calibration
        normal_te_endpoints = np.where(normal_mask_te)[0]
        normal_te_endpoints = normal_te_endpoints[normal_te_endpoints >= seq_len - 1]
        X_node_normal_te = X_node_test_norm[normal_te_endpoints[:10_000]]
        print(f"  Calibration node snapshots (48h normal): {len(X_node_normal_te):,}")

        gnn_det.fit_threshold(X_node_normal_te, fpr=args.fpr)
        print(f"  New threshold: {gnn_det.threshold_:.5f}")

        gnn_scores = gnn_det.anomaly_score(X_node_test_seq)
        gnn_preds  = gnn_det.predict(X_node_test_seq)
        all_results.append(evaluate(y_seq_test, gnn_preds, gnn_scores, "GNN-recal"))
        all_per_atk.append(per_attack_eval(df_test_seq, gnn_preds, "GNN-recal"))

    # ── 5. Physics baseline (already domain-free in score, just threshold) ──
    print("\n" + "=" * 60)
    print("  Physics-EKF: recalibrate on 48h normal")
    print("=" * 60)
    phys_scores_te = physics_anomaly_score(df_test_seq)
    phys_normal_scores = physics_anomaly_score(df_test_seq.iloc[
        np.where(y_seq_test == 0)[0]])
    phys_thresh = float(np.quantile(phys_normal_scores, 1.0 - args.fpr))
    phys_preds  = (phys_scores_te > phys_thresh).astype(int)
    print(f"  Threshold (q{int((1-args.fpr)*100)} of 48h-normal chi2): {phys_thresh:.2f}")
    all_results.append(evaluate(y_seq_test, phys_preds, phys_scores_te, "Physics-EKF-recal"))

    # ── 6. Save outputs ─────────────────────────────────────────────────────
    df_res = pd.DataFrame(all_results)
    df_atk = pd.concat(all_per_atk, ignore_index=True)

    df_res.to_csv(out_dir / "results_recalibrated.csv", index=False)
    df_atk.to_csv(out_dir / "per_attack_f1_recalibrated.csv", index=False)

    print("\n" + "=" * 60)
    print("  SUMMARY — Cross-Regime (threshold recalibrated on 48h normal)")
    print("=" * 60)
    print(df_res.to_string(index=False))

    print(f"\n[done] Results -> {out_dir}/")

    # Save paper-ready JSON
    paper = {"note": "Threshold recalibrated on 48h-normal data (FPR=5%)",
             "models": df_res.round(4).to_dict(orient="records")}
    with open(out_dir / "paper_table_recal.json", "w") as f:
        json.dump(paper, f, indent=2)


if __name__ == "__main__":
    main()
