"""
Indian CGD Pipeline — IDS ML Pipeline
======================================
Trains and evaluates anomaly / attack-detection models on the 20-node
CGD simulator dataset produced by run_24h_sweep.

Column schema (matches export_scenario_csv in run_24h_sweep.m):
  Metadata   : Timestamp_s, scenario_id, source_config, demand_profile,
               valve_config, storage_init, cs_mode
  Physics    : p_<node>_bar (×20), q_<edge>_kgs (×20)
  Equipment  : CS1_ratio, CS1_power_kW, CS2_ratio, CS2_power_kW,
               PRS1_throttle, PRS2_throttle, STO_inventory
  Valves     : valve_E8, valve_E14, valve_E15
  Detectors  : cusum_S_upper, cusum_S_lower, cusum_alarm,
               chi2_stat, chi2_alarm
  EKF        : ekf_resid_<node> (×20)
  PLC        : plc_p_<node> (×20), plc_q_<edge> (×20)
  Labels     : FAULT_ID, ATTACK_ID, MITRE_CODE, label
  Propagation: prop_origin_node, prop_hop_node, prop_delay_s,
               prop_cascade_step

Usage
-----
  # Baseline only (unsupervised anomaly detection):
  python cgd_ids_pipeline.py

  # With attacks dataset for supervised classification:
  python cgd_ids_pipeline.py --attacks ../automated_dataset_attacks/ml_dataset_attacks.csv

  # Quick test on first 5000 rows:
  python cgd_ids_pipeline.py --nrows 5000
"""

import argparse
import json
import os
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from sklearn.ensemble import RandomForestClassifier, IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (
    classification_report, confusion_matrix,
    f1_score, roc_auc_score, ConfusionMatrixDisplay
)
from sklearn.model_selection import GroupKFold
import joblib

try:
    import xgboost as xgb
    HAS_XGB = True
except ImportError:
    HAS_XGB = False
    warnings.warn("xgboost not installed — XGBoost step will be skipped.")

try:
    import shap
    HAS_SHAP = True
except ImportError:
    HAS_SHAP = False

# ─────────────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR   = Path(__file__).parent
SIM_ROOT     = SCRIPT_DIR.parent
DATASET_DIR  = SIM_ROOT / "automated_dataset"
BASELINE_CSV = DATASET_DIR / "ml_dataset_baseline.csv"
OUT_DIR      = SCRIPT_DIR / "ml_outputs"

# Node / edge names matching the 20-node CGD network
NODE_NAMES = ["S1","J1","CS1","J2","J3","J4","CS2","J5","J6","PRS1",
              "J7","STO","PRS2","S2","D1","D2","D3","D4","D5","D6"]
EDGE_NAMES = [f"E{i}" for i in range(1, 21)]

ATTACK_NAMES = {
    0:  "Normal",
    1:  "SourceSpike",
    2:  "CompRamp",
    3:  "ValveForce",
    4:  "DemandInject",
    5:  "PressureSpoof",
    6:  "FlowSpoof",
    7:  "PLCLatency",
    8:  "PipeLeak",
    9:  "FDI_Stealthy",
    10: "ReplayAttack",
}


# ─────────────────────────────────────────────────────────────────────────────
# Column helpers
# ─────────────────────────────────────────────────────────────────────────────

def pressure_cols(df):
    return [c for c in df.columns if c.startswith("p_") and c.endswith("_bar")]

def flow_cols(df):
    return [c for c in df.columns if c.startswith("q_") and c.endswith("_kgs")]

def ekf_cols(df):
    return [c for c in df.columns if c.startswith("ekf_resid_")]

def plc_p_cols(df):
    return [c for c in df.columns if c.startswith("plc_p_")]

def plc_q_cols(df):
    return [c for c in df.columns if c.startswith("plc_q_")]

def detector_cols(df):
    candidates = ["cusum_S_upper", "cusum_S_lower", "chi2_stat"]
    return [c for c in candidates if c in df.columns]

def equipment_cols(df):
    candidates = ["CS1_ratio", "CS1_power_kW", "CS2_ratio", "CS2_power_kW",
                  "PRS1_throttle", "PRS2_throttle", "STO_inventory",
                  "valve_E8", "valve_E14", "valve_E15"]
    return [c for c in candidates if c in df.columns]

def build_feature_cols(df):
    """Return ordered list of numeric feature columns (no metadata, no labels)."""
    return (
        pressure_cols(df)
        + flow_cols(df)
        + equipment_cols(df)
        + detector_cols(df)
        + ekf_cols(df)
        + plc_p_cols(df)
        + plc_q_cols(df)
    )

META_COLS   = ["Timestamp_s","scenario_id","source_config","demand_profile",
               "valve_config","storage_init","cs_mode"]
LABEL_COLS  = ["label","ATTACK_ID","FAULT_ID","MITRE_CODE",
               "prop_origin_node","prop_hop_node","prop_delay_s",
               "prop_cascade_step","cusum_alarm","chi2_alarm"]


# ─────────────────────────────────────────────────────────────────────────────
# 1. Load and validate
# ─────────────────────────────────────────────────────────────────────────────

def load_dataset(baseline_path: Path, attacks_path: Path | None = None,
                 nrows: int | None = None) -> pd.DataFrame:
    print(f"\n[load] Reading baseline → {baseline_path}")
    df = pd.read_csv(baseline_path, nrows=nrows, low_memory=False)
    print(f"       {len(df):,} rows  ×  {len(df.columns)} cols")

    if attacks_path and Path(attacks_path).exists():
        print(f"[load] Reading attacks  → {attacks_path}")
        df_atk = pd.read_csv(attacks_path, nrows=nrows, low_memory=False)
        df = pd.concat([df, df_atk], ignore_index=True)
        print(f"       Combined: {len(df):,} rows")

    # Ensure integer label columns exist
    for col, default in [("ATTACK_ID", 0), ("FAULT_ID", 0), ("label", 0)]:
        if col not in df.columns:
            df[col] = default
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(default).astype(int)

    if "scenario_id" not in df.columns:
        df["scenario_id"] = 0

    print(f"[load] Label distribution:\n"
          f"       Normal rows  : {(df['label']==0).sum():,}\n"
          f"       Anomaly rows : {(df['label']>0).sum():,}")

    atk_counts = df["ATTACK_ID"].value_counts().sort_index()
    for aid, cnt in atk_counts.items():
        name = ATTACK_NAMES.get(int(aid), f"A{aid}")
        print(f"       ATTACK_ID={aid:2d} ({name:15s}): {cnt:,}")

    return df


# ─────────────────────────────────────────────────────────────────────────────
# 2. Feature engineering
# ─────────────────────────────────────────────────────────────────────────────

def add_rolling_features(df: pd.DataFrame, window: int = 30) -> pd.DataFrame:
    """Add per-scenario rolling mean and std for key sensors."""
    print(f"[features] Adding rolling window={window} features …")
    roll_src = pressure_cols(df)[:5] + flow_cols(df)[:5]  # first 5 of each
    new_cols = {}
    for col in roll_src:
        grp = df.groupby("scenario_id")[col]
        new_cols[f"{col}_rmean"] = grp.transform(
            lambda x: x.rolling(window, min_periods=1).mean())
        new_cols[f"{col}_rstd"] = grp.transform(
            lambda x: x.rolling(window, min_periods=1).std().fillna(0))
    df = pd.concat([df, pd.DataFrame(new_cols, index=df.index)], axis=1)
    return df


def add_rate_of_change(df: pd.DataFrame) -> pd.DataFrame:
    """First difference of pressure/flow per scenario (Δp, Δq)."""
    print("[features] Adding rate-of-change (Δ) features …")
    roc_src = pressure_cols(df) + flow_cols(df)
    new_cols = {}
    for col in roc_src:
        new_cols[f"roc_{col}"] = (
            df.groupby("scenario_id")[col]
            .transform(lambda x: x.diff().fillna(0))
        )
    df = pd.concat([df, pd.DataFrame(new_cols, index=df.index)], axis=1)
    return df


def add_mass_balance_residual(df: pd.DataFrame) -> pd.DataFrame:
    """
    Kirchhoff-inspired: for each demand node, estimate mass imbalance.
    Uses available flow columns as proxy.  Simple but fast.
    """
    print("[features] Adding mass-balance residuals …")
    q_cols = flow_cols(df)
    if len(q_cols) >= 2:
        # Net flow proxy: sum of first half minus sum of second half
        half = len(q_cols) // 2
        df["kirchhoff_imbalance"] = (
            df[q_cols[:half]].sum(axis=1)
            - df[q_cols[half:]].sum(axis=1)
        )
    return df


def engineer_features(df: pd.DataFrame, rolling: bool = True) -> pd.DataFrame:
    if rolling:
        df = add_rolling_features(df)
        df = add_rate_of_change(df)
    df = add_mass_balance_residual(df)
    return df


# ─────────────────────────────────────────────────────────────────────────────
# 3. Train / test split by scenario
# ─────────────────────────────────────────────────────────────────────────────

def scenario_split(df: pd.DataFrame, test_frac: float = 0.2,
                   seed: int = 42) -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    Hold-out complete scenarios for test set (prevents data leakage from
    time-correlated rows being split within the same scenario).
    """
    rng  = np.random.default_rng(seed)
    sids = df["scenario_id"].unique()
    n_test = max(1, int(len(sids) * test_frac))
    test_sids = set(rng.choice(sids, size=n_test, replace=False).tolist())
    mask = df["scenario_id"].isin(test_sids)
    return df[~mask].copy(), df[mask].copy()


# ─────────────────────────────────────────────────────────────────────────────
# 4. Scaling
# ─────────────────────────────────────────────────────────────────────────────

def fit_scaler(df_train: pd.DataFrame,
               feat_cols: list[str]) -> tuple[StandardScaler, list[str]]:
    """Fit StandardScaler on normal (label=0) training rows only."""
    valid = [c for c in feat_cols if c in df_train.columns]
    scaler = StandardScaler()
    normal_mask = df_train["label"] == 0
    scaler.fit(df_train.loc[normal_mask, valid].fillna(0))
    return scaler, valid


def scale(df: pd.DataFrame, scaler: StandardScaler,
          feat_cols: list[str]) -> np.ndarray:
    return scaler.transform(df[feat_cols].fillna(0))


# ─────────────────────────────────────────────────────────────────────────────
# 5. Models
# ─────────────────────────────────────────────────────────────────────────────

def train_isolation_forest(X_train: np.ndarray,
                           contamination: float = 0.05) -> IsolationForest:
    print(f"[iforest] Training IsolationForest  contamination={contamination}")
    clf = IsolationForest(n_estimators=200, contamination=contamination,
                          random_state=42, n_jobs=-1)
    clf.fit(X_train)
    return clf


def eval_isolation_forest(clf: IsolationForest, X_test: np.ndarray,
                           y_test: np.ndarray, out_dir: Path) -> dict:
    scores = -clf.score_samples(X_test)   # higher = more anomalous
    preds  = (clf.predict(X_test) == -1).astype(int)
    report = classification_report(y_test, preds, zero_division=0,
                                   target_names=["Normal","Anomaly"],
                                   output_dict=True)
    print("[iforest] Test set performance:")
    print(classification_report(y_test, preds, zero_division=0,
                                target_names=["Normal","Anomaly"]))
    _save_confusion_matrix(y_test, preds, ["Normal","Anomaly"],
                           out_dir / "cm_iforest.png", "IsolationForest")
    return {"iforest": report, "scores": scores}


def train_random_forest(X_train: np.ndarray,
                        y_train: np.ndarray) -> RandomForestClassifier:
    classes = np.unique(y_train)
    print(f"[rf] Training RandomForest  classes={classes}")
    clf = RandomForestClassifier(n_estimators=300, max_depth=None,
                                 class_weight="balanced",
                                 random_state=42, n_jobs=-1)
    clf.fit(X_train, y_train)
    return clf


def eval_random_forest(clf: RandomForestClassifier, X_test: np.ndarray,
                        y_test: np.ndarray, feat_cols: list[str],
                        out_dir: Path) -> dict:
    preds = clf.predict(X_test)
    labels = sorted(np.unique(np.concatenate([y_test, preds])))
    names  = [ATTACK_NAMES.get(int(l), f"A{l}") for l in labels]
    print("[rf] Test set performance:")
    print(classification_report(y_test, preds, labels=labels,
                                target_names=names, zero_division=0))
    report = classification_report(y_test, preds, labels=labels,
                                   target_names=names, zero_division=0,
                                   output_dict=True)
    _save_confusion_matrix(y_test, preds, names,
                           out_dir / "cm_rf.png", "RandomForest")
    _save_feature_importance(clf.feature_importances_, feat_cols,
                             out_dir / "importance_rf.png", "RandomForest")
    return {"rf": report}


def train_xgboost(X_train: np.ndarray, y_train: np.ndarray,
                  X_val: np.ndarray, y_val: np.ndarray) -> "xgb.XGBClassifier":
    classes, counts = np.unique(y_train, return_counts=True)
    n_classes = len(classes)
    print(f"[xgb] Training XGBoost  n_classes={n_classes}")

    if n_classes == 2:
        pos   = counts[classes == 1][0] if 1 in classes else 1
        neg   = counts[classes == 0][0] if 0 in classes else 1
        spw   = neg / pos
        clf = xgb.XGBClassifier(
            n_estimators=400, max_depth=6, learning_rate=0.05,
            scale_pos_weight=spw, subsample=0.8, colsample_bytree=0.8,
            eval_metric="logloss", use_label_encoder=False,
            random_state=42, n_jobs=-1, verbosity=0
        )
        eval_set = [(X_val, y_val)]
        clf.fit(X_train, y_train, eval_set=eval_set, verbose=False)
    else:
        # Remap labels to 0..n_classes-1 for XGBoost multi-class
        lmap = {c: i for i, c in enumerate(classes)}
        y_tr = np.array([lmap[v] for v in y_train])
        y_vl = np.array([lmap[v] for v in y_val])
        clf = xgb.XGBClassifier(
            n_estimators=400, max_depth=6, learning_rate=0.05,
            objective="multi:softprob", num_class=n_classes,
            subsample=0.8, colsample_bytree=0.8,
            eval_metric="mlogloss", use_label_encoder=False,
            random_state=42, n_jobs=-1, verbosity=0
        )
        eval_set = [(X_vl, y_vl)]
        clf.fit(X_tr, y_tr, eval_set=eval_set, verbose=False)
        clf._lmap  = lmap
        clf._rmap  = {i: c for c, i in lmap.items()}

    return clf


def eval_xgboost(clf, X_test: np.ndarray, y_test: np.ndarray,
                 feat_cols: list[str], out_dir: Path) -> dict:
    if hasattr(clf, "_rmap"):
        y_raw = clf.predict(X_test)
        preds = np.array([clf._rmap[v] for v in y_raw])
    else:
        preds = clf.predict(X_test)
    labels = sorted(np.unique(np.concatenate([y_test, preds])))
    names  = [ATTACK_NAMES.get(int(l), f"A{l}") for l in labels]
    print("[xgb] Test set performance:")
    print(classification_report(y_test, preds, labels=labels,
                                target_names=names, zero_division=0))
    report = classification_report(y_test, preds, labels=labels,
                                   target_names=names, zero_division=0,
                                   output_dict=True)
    _save_confusion_matrix(y_test, preds, names,
                           out_dir / "cm_xgb.png", "XGBoost")
    _save_feature_importance(clf.feature_importances_, feat_cols,
                             out_dir / "importance_xgb.png", "XGBoost")

    if HAS_SHAP:
        print("[xgb] Computing SHAP values …")
        try:
            explainer = shap.TreeExplainer(clf)
            sample = X_test[:min(2000, len(X_test))]
            sv = explainer.shap_values(sample)
            if isinstance(sv, list):
                sv = np.abs(np.stack(sv)).mean(axis=0)
            shap_imp = np.abs(sv).mean(axis=0)
            _save_feature_importance(shap_imp, feat_cols,
                                     out_dir / "shap_xgb.png",
                                     "XGBoost SHAP")
        except Exception as e:
            print(f"[xgb] SHAP failed: {e}")

    return {"xgb": report}


# ─────────────────────────────────────────────────────────────────────────────
# 6. Cross-topology validation (GroupKFold by scenario_id)
# ─────────────────────────────────────────────────────────────────────────────

def cross_topology_validation(df: pd.DataFrame, feat_cols: list[str],
                               n_splits: int = 5, out_dir: Path = OUT_DIR):
    print(f"\n[cv] Cross-topology validation  k={n_splits} …")
    X      = df[feat_cols].fillna(0).values
    y      = df["label"].values
    groups = df["scenario_id"].values

    if len(np.unique(y)) < 2:
        print("[cv] Only one class present — skipping cross-topology CV.")
        return

    gkf    = GroupKFold(n_splits=min(n_splits, len(np.unique(groups))))
    f1s    = []
    for fold, (tr_idx, te_idx) in enumerate(gkf.split(X, y, groups)):
        sc = StandardScaler()
        X_tr = sc.fit_transform(X[tr_idx])
        X_te = sc.transform(X[te_idx])
        clf  = RandomForestClassifier(n_estimators=100, random_state=42,
                                      n_jobs=-1, class_weight="balanced")
        clf.fit(X_tr, y[tr_idx])
        preds = clf.predict(X_te)
        f1    = f1_score(y[te_idx], preds, average="binary", zero_division=0)
        f1s.append(f1)
        print(f"  Fold {fold+1}: F1={f1:.4f}")

    print(f"[cv] Mean F1 = {np.mean(f1s):.4f} ± {np.std(f1s):.4f}")

    # Save results
    cv_df = pd.DataFrame({"fold": range(1, len(f1s)+1), "f1": f1s})
    cv_df.to_csv(out_dir / "cross_topology_cv.csv", index=False)

    fig, ax = plt.subplots(figsize=(6, 3))
    ax.bar(cv_df["fold"], cv_df["f1"], color="steelblue")
    ax.axhline(np.mean(f1s), color="red", linestyle="--",
               label=f"Mean={np.mean(f1s):.3f}")
    ax.set_xlabel("Fold"); ax.set_ylabel("F1 Score")
    ax.set_title("Cross-Topology CV (GroupKFold by scenario_id)")
    ax.legend(); fig.tight_layout()
    fig.savefig(out_dir / "cross_topology_cv.png", dpi=150)
    plt.close(fig)


# ─────────────────────────────────────────────────────────────────────────────
# 7. EDA plots
# ─────────────────────────────────────────────────────────────────────────────

def plot_eda(df: pd.DataFrame, out_dir: Path):
    print("[eda] Generating EDA plots …")
    p_cols = pressure_cols(df)
    q_cols = flow_cols(df)

    # Pressure distributions
    fig, axes = plt.subplots(4, 5, figsize=(18, 12))
    for ax, col in zip(axes.flat, p_cols):
        ax.hist(df[col].dropna(), bins=60, color="steelblue", edgecolor="none")
        ax.set_title(col.replace("p_","").replace("_bar",""), fontsize=8)
        ax.set_xlabel("bar", fontsize=7)
    fig.suptitle("Pressure Node Distributions (all scenarios)", fontsize=12)
    fig.tight_layout()
    fig.savefig(out_dir / "pressure_distributions.png", dpi=150)
    plt.close(fig)

    # Flow distributions
    fig, axes = plt.subplots(4, 5, figsize=(18, 12))
    for ax, col in zip(axes.flat, q_cols):
        ax.hist(df[col].dropna(), bins=60, color="coral", edgecolor="none")
        ax.set_title(col.replace("q_","").replace("_kgs",""), fontsize=8)
        ax.set_xlabel("kg/s", fontsize=7)
    fig.suptitle("Flow Edge Distributions (all scenarios)", fontsize=12)
    fig.tight_layout()
    fig.savefig(out_dir / "flow_distributions.png", dpi=150)
    plt.close(fig)

    # Label / attack composition
    fig, axes = plt.subplots(1, 2, figsize=(12, 4))
    attack_counts = df["ATTACK_ID"].value_counts().sort_index()
    attack_names  = [ATTACK_NAMES.get(int(i), f"A{i}") for i in attack_counts.index]
    axes[0].bar(attack_names, attack_counts.values, color="steelblue")
    axes[0].set_xlabel("Attack ID"); axes[0].set_ylabel("Rows")
    axes[0].set_title("Rows per Attack Type"); axes[0].tick_params(axis="x", rotation=45)

    label_counts = df["label"].value_counts().sort_index()
    axes[1].bar(["Normal (0)", "Anomaly (1)"], label_counts.values,
                color=["steelblue","coral"])
    axes[1].set_ylabel("Rows"); axes[1].set_title("Binary Label Distribution")
    fig.tight_layout()
    fig.savefig(out_dir / "dataset_composition.png", dpi=150)
    plt.close(fig)

    # CUSUM / chi2 detector behaviour
    det_avail = [c for c in ["cusum_S_upper","cusum_S_lower","chi2_stat"]
                 if c in df.columns]
    if det_avail:
        fig, axes = plt.subplots(len(det_avail), 1,
                                 figsize=(14, 3*len(det_avail)))
        if len(det_avail) == 1:
            axes = [axes]
        for ax, col in zip(axes, det_avail):
            sample_sid = df["scenario_id"].iloc[0]
            sub = df[df["scenario_id"] == sample_sid].reset_index(drop=True)
            ax.plot(sub[col].values, lw=0.8, color="steelblue")
            ax.set_title(f"{col}  (scenario {sample_sid})")
            ax.set_xlabel("Log step (1 Hz)")
        fig.tight_layout()
        fig.savefig(out_dir / "detector_timeseries.png", dpi=150)
        plt.close(fig)

    print(f"[eda] Saved to {out_dir}/")


# ─────────────────────────────────────────────────────────────────────────────
# 8. Scenario health check
# ─────────────────────────────────────────────────────────────────────────────

def scenario_health_check(df: pd.DataFrame, out_dir: Path) -> pd.DataFrame:
    """
    Flag scenarios with physics divergence (pressures at hard limits).
    Indian CGD: valid range is roughly 14–26 barg (14–26 bar abs here).
    Hard clamp values in runSimulation are typically 0.1 (floor) and 70 (ceiling).
    """
    print("[health] Running scenario health checks …")
    p_cols = pressure_cols(df)
    records = []
    for sid, grp in df.groupby("scenario_id"):
        p_vals    = grp[p_cols].values
        n_rows    = len(grp)
        pct_floor = float((p_vals < 0.5).mean())   # stuck at 0.1 floor
        pct_ceil  = float((p_vals > 65.0).mean())  # stuck at 70 ceiling
        p_mean    = float(np.nanmean(p_vals))
        p_std     = float(np.nanstd(p_vals))
        diverged  = pct_floor > 0.10 or pct_ceil > 0.10
        records.append({
            "scenario_id": sid,
            "n_rows": n_rows,
            "p_mean": p_mean,
            "p_std": p_std,
            "pct_floor": pct_floor,
            "pct_ceil": pct_ceil,
            "diverged": diverged,
        })
    health = pd.DataFrame(records)
    n_div  = health["diverged"].sum()
    print(f"[health] {n_div}/{len(health)} scenarios show physics divergence "
          f"(>10% rows at pressure clamp)")
    health.to_csv(out_dir / "scenario_health.csv", index=False)

    # Plot
    fig, axes = plt.subplots(1, 2, figsize=(12, 4))
    axes[0].hist(health["pct_floor"]*100, bins=30, color="steelblue")
    axes[0].set_xlabel("% rows at pressure floor (<0.5 bar)")
    axes[0].set_ylabel("# Scenarios"); axes[0].set_title("Pressure Floor Fraction")
    axes[1].hist(health["pct_ceil"]*100, bins=30, color="coral")
    axes[1].set_xlabel("% rows at pressure ceiling (>65 bar)")
    axes[1].set_ylabel("# Scenarios"); axes[1].set_title("Pressure Ceiling Fraction")
    fig.tight_layout()
    fig.savefig(out_dir / "scenario_health.png", dpi=150)
    plt.close(fig)

    return health


# ─────────────────────────────────────────────────────────────────────────────
# 9. Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _save_confusion_matrix(y_true, y_pred, labels, path, title):
    cm  = confusion_matrix(y_true, y_pred)
    fig, ax = plt.subplots(figsize=(max(4, len(labels)), max(4, len(labels))))
    disp = ConfusionMatrixDisplay(cm, display_labels=labels)
    disp.plot(ax=ax, colorbar=False, xticks_rotation="vertical")
    ax.set_title(title)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def _save_feature_importance(importances, feat_cols, path, title, top_n=25):
    idx  = np.argsort(importances)[::-1][:top_n]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.barh([feat_cols[i] for i in idx[::-1]], importances[idx[::-1]],
            color="steelblue")
    ax.set_xlabel("Importance"); ax.set_title(f"{title} — Top {top_n} Features")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def save_stats(df: pd.DataFrame, feat_cols: list[str],
               results: dict, out_dir: Path):
    stats = {
        "total_rows":     int(len(df)),
        "n_scenarios":    int(df["scenario_id"].nunique()),
        "n_features":     len(feat_cols),
        "normal_rows":    int((df["label"]==0).sum()),
        "anomaly_rows":   int((df["label"]>0).sum()),
        "attack_ids_present": sorted(df["ATTACK_ID"].unique().tolist()),
        "models_trained": list(results.keys()),
    }
    with open(out_dir / "dataset_statistics.json", "w") as f:
        json.dump(stats, f, indent=2, default=int)
    print(f"\n[stats] Saved → {out_dir}/dataset_statistics.json")


# ─────────────────────────────────────────────────────────────────────────────
# 10. Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="CGD IDS ML Pipeline")
    parser.add_argument("--baseline", default=str(BASELINE_CSV),
                        help="Path to ml_dataset_baseline.csv")
    parser.add_argument("--attacks",  default=None,
                        help="Path to attacks dataset CSV (optional)")
    parser.add_argument("--nrows",    type=int, default=None,
                        help="Limit rows loaded (for quick testing)")
    parser.add_argument("--no-rolling", action="store_true",
                        help="Skip rolling feature engineering (faster)")
    parser.add_argument("--out-dir",  default=str(OUT_DIR),
                        help="Output directory for models and plots")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # ── Load ────────────────────────────────────────────────────────────────
    df = load_dataset(Path(args.baseline), args.attacks, args.nrows)

    # ── EDA ─────────────────────────────────────────────────────────────────
    plot_eda(df, out_dir)
    health = scenario_health_check(df, out_dir)

    # Filter out highly diverged scenarios (optional — comment out to keep all)
    bad_sids = health.loc[health["diverged"], "scenario_id"]
    if len(bad_sids) > 0:
        pct = 100 * len(bad_sids) / len(health)
        print(f"[health] WARNING: {len(bad_sids)} scenarios ({pct:.0f}%) diverged. "
              f"Keeping all rows — divergence IS a detectable signal.")

    # ── Feature engineering ─────────────────────────────────────────────────
    df = engineer_features(df, rolling=not args.no_rolling)
    feat_cols = build_feature_cols(df)
    # Also add engineered columns
    feat_cols += [c for c in df.columns
                  if (c.startswith("roc_") or c.startswith("kirchhoff_"))
                  and c not in feat_cols]
    # Remove any that don't exist
    feat_cols = [c for c in feat_cols if c in df.columns]
    print(f"[features] Total features: {len(feat_cols)}")

    # ── Train/test split ─────────────────────────────────────────────────────
    df_train, df_test = scenario_split(df, test_frac=0.2)
    print(f"[split] Train: {len(df_train):,} rows ({df_train['scenario_id'].nunique()} scenarios)")
    print(f"[split] Test : {len(df_test):,} rows ({df_test['scenario_id'].nunique()} scenarios)")

    # ── Scaling ──────────────────────────────────────────────────────────────
    scaler, feat_cols = fit_scaler(df_train, feat_cols)
    X_train = scale(df_train, scaler, feat_cols)
    X_test  = scale(df_test,  scaler, feat_cols)
    y_train = df_train["label"].values
    y_test  = df_test["label"].values

    joblib.dump(scaler, out_dir / "scaler.pkl")

    results = {}

    # ── Isolation Forest (unsupervised) ──────────────────────────────────────
    normal_mask = y_train == 0
    contamination = max(0.01, (y_train > 0).mean())
    iforest = train_isolation_forest(X_train[normal_mask],
                                     contamination=contamination)
    res_if  = eval_isolation_forest(iforest, X_test, y_test, out_dir)
    results.update(res_if)
    joblib.dump(iforest, out_dir / "iforest.pkl")

    # ── Random Forest (supervised) ───────────────────────────────────────────
    print()
    rf = train_random_forest(X_train, y_train)
    res_rf = eval_random_forest(rf, X_test, y_test, feat_cols, out_dir)
    results.update(res_rf)
    joblib.dump(rf, out_dir / "random_forest.pkl")

    # ── XGBoost (supervised) ─────────────────────────────────────────────────
    if HAS_XGB:
        print()
        # Use 10% of training set as validation
        val_frac = 0.1
        n_val    = max(1, int(len(X_train) * val_frac))
        rng      = np.random.default_rng(42)
        val_idx  = rng.choice(len(X_train), size=n_val, replace=False)
        tr_idx   = np.setdiff1d(np.arange(len(X_train)), val_idx)
        xgb_clf  = train_xgboost(X_train[tr_idx], y_train[tr_idx],
                                  X_train[val_idx], y_train[val_idx])
        res_xgb  = eval_xgboost(xgb_clf, X_test, y_test, feat_cols, out_dir)
        results.update(res_xgb)
        joblib.dump(xgb_clf, out_dir / "xgboost.pkl")

    # ── Cross-topology CV ────────────────────────────────────────────────────
    print()
    cross_topology_validation(df, feat_cols, n_splits=5, out_dir=out_dir)

    # ── Save stats ───────────────────────────────────────────────────────────
    save_stats(df, feat_cols, results, out_dir)

    print(f"\n{'='*60}")
    print(f"  Pipeline complete.  Outputs → {out_dir}/")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
