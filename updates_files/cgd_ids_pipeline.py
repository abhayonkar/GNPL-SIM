"""
Indian CGD Pipeline — IDS ML Pipeline
======================================
Phase 3 fixes applied:
  FIX 1 — Health check TypeError: p_vals comparison with string
           p_vals = grp[p_cols].apply(pd.to_numeric, errors='coerce').values
  FIX 2 — Full numeric conversion in load_dataset (ALL feature columns)
  FIX 3 — Single-class guard: skip RF/XGB when only one class present
  FIX 4 — XGBoost variable name fix: X_vl → X_val in eval_set (was crashing)
           [already correct in uploaded file — kept for safety]
  FIX 5 — Network feature columns added (Phase 2 merge support)
  FIX 6 — recovery_phase column support for windowed attack datasets

Column schema (matches export_scenario_csv in run_24h_sweep / run_48h_continuous):
  Metadata   : Timestamp_s, scenario_id, source_config, demand_profile,
               valve_config, storage_init, cs_mode
  Physics    : p_<node>_bar (×20), q_<edge>_kgs (×20)
  Equipment  : CS1_ratio, CS1_power_kW, CS2_ratio, CS2_power_kW,
               PRS1_throttle, PRS2_throttle, STO_inventory
  Valves     : valve_E8, valve_E14, valve_E15
  Detectors  : cusum_S_upper, cusum_S_lower, cusum_alarm, chi2_stat, chi2_alarm
  EKF        : ekf_resid_<node> (×20)
  PLC        : plc_p_<node> (×20), plc_q_<edge> (×20)
  Labels     : FAULT_ID, ATTACK_ID, MITRE_CODE, label
  Propagation: prop_origin_node, prop_hop_node, prop_delay_s, prop_cascade_step
  Network    : src_id, dst_id, fc, register, comm_pair (if merged CPS dataset)

Usage:
  python cgd_ids_pipeline.py                          # baseline only
  python cgd_ids_pipeline.py --attacks /path/attacks.csv
  python cgd_ids_pipeline.py --data merged_cps_dataset.csv  # merged physics+network
  python cgd_ids_pipeline.py --nrows 5000             # quick test
  python cgd_ids_pipeline.py --no-rolling             # skip rolling features
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

META_COLS   = ["Timestamp_s","scenario_id","source_config","demand_profile",
               "valve_config","storage_init","cs_mode","regime_id"]
LABEL_COLS  = ["label","ATTACK_ID","FAULT_ID","MITRE_CODE",
               "prop_origin_node","prop_hop_node","prop_delay_s",
               "prop_cascade_step","cusum_alarm","chi2_alarm",
               "attack_start","recovery_start","recovery_phase"]


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

def network_cols(df):
    """Phase 2 / Phase 3: columns from merged CPS network dataset."""
    candidates = ["fc", "register", "write_flag", "inter_pkt_ms",
                  "src_zone", "dst_zone", "comm_freq"]
    return [c for c in candidates if c in df.columns]

def residual_cols(df):
    """Physics vs PLC mismatch columns (added in feature engineering)."""
    return [c for c in df.columns if c.startswith("residual_p_")]

def build_feature_cols(df):
    """Return ordered list of all numeric feature columns."""
    return (
        pressure_cols(df)
        + flow_cols(df)
        + equipment_cols(df)
        + detector_cols(df)
        + ekf_cols(df)
        + plc_p_cols(df)
        + plc_q_cols(df)
        + network_cols(df)
        + residual_cols(df)
    )


# ─────────────────────────────────────────────────────────────────────────────
# 1. Load and validate
# ─────────────────────────────────────────────────────────────────────────────

def load_dataset(baseline_path: Path, attacks_path=None,
                 nrows=None) -> pd.DataFrame:
    print(f"\n[load] Reading baseline → {baseline_path}")
    df = pd.read_csv(baseline_path, nrows=nrows, low_memory=False)
    print(f"       {len(df):,} rows  ×  {len(df.columns)} cols")

    if attacks_path and Path(attacks_path).exists():
        print(f"[load] Reading attacks  → {attacks_path}")
        df_atk = pd.read_csv(attacks_path, nrows=nrows, low_memory=False)
        df = pd.concat([df, df_atk], ignore_index=True)
        print(f"       Combined: {len(df):,} rows")

    # ── FIX 2: Convert ALL feature columns to numeric ─────────────────────
    # This prevents the 'str < float' TypeError that crashed scenario_health_check.
    # Any column that is not metadata or a label gets coerced to float.
    # String values (e.g. "nan", "null", spaces) become NaN and are filled below.
    skip_cols = set(META_COLS + LABEL_COLS)
    for col in df.columns:
        if col not in skip_cols:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    # Forward-fill then back-fill NaNs (preserves temporal structure)
    feature_cols_now = [c for c in df.columns if c not in skip_cols]
    df[feature_cols_now] = (
        df[feature_cols_now]
        .ffill()
        .bfill()
        .fillna(0)
    )

    # Ensure integer label columns exist
    for col, default in [("ATTACK_ID", 0), ("FAULT_ID", 0), ("label", 0)]:
        if col not in df.columns:
            df[col] = default
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(default).astype(int)

    if "scenario_id" not in df.columns:
        df["scenario_id"] = 0

    # Add recovery_phase if windowed attack dataset
    if "attack_start" in df.columns and "recovery_start" not in df.columns:
        df["recovery_phase"] = 0

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
    print(f"[features] Adding rolling window={window} features …")
    roll_src = pressure_cols(df)[:5] + flow_cols(df)[:5]
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
    print("[features] Adding mass-balance residuals …")
    q_cols = flow_cols(df)
    if len(q_cols) >= 2:
        half = len(q_cols) // 2
        df = df.copy()
        df["kirchhoff_imbalance"] = (
            df[q_cols[:half]].sum(axis=1) - df[q_cols[half:]].sum(axis=1)
        )
    return df


def add_physics_plc_residuals(df: pd.DataFrame) -> pd.DataFrame:
    """
    Phase 3 / CPS feature: physics vs PLC mismatch per node.
    p_S1_bar - plc_p_S1 detects sensor spoofing and stale data.
    """
    p_cols   = pressure_cols(df)
    new_cols = {}
    for col in p_cols:
        node_name = col.replace("p_", "").replace("_bar", "")
        plc_col   = f"plc_p_{node_name}"
        if plc_col in df.columns:
            new_cols[f"residual_{col}"] = df[col] - df[plc_col]
    if new_cols:
        print(f"[features] Adding {len(new_cols)} physics↔PLC residual features …")
        df = pd.concat([df, pd.DataFrame(new_cols, index=df.index)], axis=1)
    return df


def add_communication_frequency(df: pd.DataFrame) -> pd.DataFrame:
    """
    Phase 3 / CPS feature: how often does each comm_pair appear?
    High frequency can indicate replay or scan flood attacks.
    """
    if "comm_pair" in df.columns:
        print("[features] Adding communication frequency feature …")
        df = df.copy()
        df["comm_freq"] = df.groupby("comm_pair")["Timestamp_s"].transform("count")
    return df


def engineer_features(df: pd.DataFrame, rolling: bool = True) -> pd.DataFrame:
    if rolling:
        df = add_rolling_features(df)
        df = add_rate_of_change(df)
    df = add_mass_balance_residual(df)
    df = add_physics_plc_residuals(df)
    df = add_communication_frequency(df)
    return df


# ─────────────────────────────────────────────────────────────────────────────
# 3. Train / test split by scenario
# ─────────────────────────────────────────────────────────────────────────────

def scenario_split(df: pd.DataFrame, test_frac: float = 0.2,
                   seed: int = 42):
    rng  = np.random.default_rng(seed)
    sids = df["scenario_id"].unique()
    n_test = max(1, int(len(sids) * test_frac))
    test_sids = set(rng.choice(sids, size=n_test, replace=False).tolist())
    mask = df["scenario_id"].isin(test_sids)
    return df[~mask].copy(), df[mask].copy()


# ─────────────────────────────────────────────────────────────────────────────
# 4. Scaling
# ─────────────────────────────────────────────────────────────────────────────

def fit_scaler(df_train: pd.DataFrame, feat_cols: list):
    valid = [c for c in feat_cols if c in df_train.columns]
    scaler = StandardScaler()
    normal_mask = df_train["label"] == 0
    if normal_mask.sum() == 0:
        print("[scale] WARNING: No normal rows in training set — fitting on all rows.")
        scaler.fit(df_train[valid].fillna(0))
    else:
        scaler.fit(df_train.loc[normal_mask, valid].fillna(0))
    return scaler, valid


def scale(df: pd.DataFrame, scaler: StandardScaler, feat_cols: list):
    return scaler.transform(df[feat_cols].fillna(0))


# ─────────────────────────────────────────────────────────────────────────────
# 5. Models
# ─────────────────────────────────────────────────────────────────────────────

def train_isolation_forest(X_train, contamination=0.05):
    print(f"[iforest] Training IsolationForest  contamination={contamination:.3f}")
    clf = IsolationForest(n_estimators=200, contamination=contamination,
                          random_state=42, n_jobs=-1)
    clf.fit(X_train)
    return clf


def eval_isolation_forest(clf, X_test, y_test, out_dir):
    preds  = (clf.predict(X_test) == -1).astype(int)
    report = classification_report(y_test, preds, zero_division=0,
                                   target_names=["Normal","Anomaly"],
                                   output_dict=True)
    print("[iforest] Test set performance:")
    print(classification_report(y_test, preds, zero_division=0,
                                target_names=["Normal","Anomaly"]))
    _save_confusion_matrix(y_test, preds, ["Normal","Anomaly"],
                           out_dir / "cm_iforest.png", "IsolationForest")
    return {"iforest": report}


def train_random_forest(X_train, y_train):
    classes = np.unique(y_train)
    print(f"[rf] Training RandomForest  classes={classes}")
    clf = RandomForestClassifier(n_estimators=300, max_depth=None,
                                 class_weight="balanced",
                                 random_state=42, n_jobs=-1)
    clf.fit(X_train, y_train)
    return clf


def eval_random_forest(clf, X_test, y_test, feat_cols, out_dir):
    preds = clf.predict(X_test)
    labels = sorted(np.unique(np.concatenate([y_test, preds])))
    names  = [ATTACK_NAMES.get(int(l), f"A{l}") for l in labels]
    print("[rf] Test set performance:")
    print(classification_report(y_test, preds, labels=labels,
                                target_names=names, zero_division=0))
    report = classification_report(y_test, preds, labels=labels,
                                   target_names=names, zero_division=0,
                                   output_dict=True)
    _save_confusion_matrix(y_test, preds, names, out_dir / "cm_rf.png", "RandomForest")
    _save_feature_importance(clf.feature_importances_, feat_cols,
                             out_dir / "importance_rf.png", "RandomForest")
    return {"rf": report}


def train_xgboost(X_train, y_train, X_val, y_val):
    classes, counts = np.unique(y_train, return_counts=True)
    n_classes = len(classes)
    print(f"[xgb] Training XGBoost  n_classes={n_classes}")

    if n_classes < 2:
        raise ValueError("[xgb] XGBoost requires at least 2 classes in training set.")

    if n_classes == 2:
        pos = counts[classes == 1][0] if 1 in classes else 1
        neg = counts[classes == 0][0] if 0 in classes else 1
        spw = neg / pos
        clf = xgb.XGBClassifier(
            n_estimators=400, max_depth=6, learning_rate=0.05,
            scale_pos_weight=spw, subsample=0.8, colsample_bytree=0.8,
            eval_metric="logloss", use_label_encoder=False,
            random_state=42, n_jobs=-1, verbosity=0
        )
        # FIX 4: use correct variable name X_val (not X_vl)
        eval_set = [(X_val, y_val)]
        clf.fit(X_train, y_train, eval_set=eval_set, verbose=False)

    else:
        # Multi-class: remap labels to 0..n_classes-1
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
        # FIX 4: use X_val (not X_vl) for the eval set features
        eval_set = [(X_val, y_vl)]
        clf.fit(X_train, y_tr, eval_set=eval_set, verbose=False)
        clf._lmap = lmap
        clf._rmap = {i: c for c, i in lmap.items()}

    return clf


def eval_xgboost(clf, X_test, y_test, feat_cols, out_dir):
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
    _save_confusion_matrix(y_test, preds, names, out_dir / "cm_xgb.png", "XGBoost")
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
                                     out_dir / "shap_xgb.png", "XGBoost SHAP")
        except Exception as e:
            print(f"[xgb] SHAP failed: {e}")

    return {"xgb": report}


# ─────────────────────────────────────────────────────────────────────────────
# 6. Cross-topology validation (GroupKFold by scenario_id)
# ─────────────────────────────────────────────────────────────────────────────

def cross_topology_validation(df, feat_cols, n_splits=5, out_dir=OUT_DIR):
    print(f"\n[cv] Cross-topology validation  k={n_splits} …")
    X      = df[feat_cols].fillna(0).values
    y      = df["label"].values
    groups = df["scenario_id"].values

    if len(np.unique(y)) < 2:
        print("[cv] Only one class present — skipping cross-topology CV.")
        return

    gkf = GroupKFold(n_splits=min(n_splits, len(np.unique(groups))))
    f1s = []
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

def plot_eda(df, out_dir):
    print("[eda] Generating EDA plots …")
    p_cols = pressure_cols(df)
    q_cols = flow_cols(df)

    fig, axes = plt.subplots(4, 5, figsize=(18, 12))
    for ax, col in zip(axes.flat, p_cols):
        ax.hist(pd.to_numeric(df[col], errors="coerce").dropna(),
                bins=60, color="steelblue", edgecolor="none")
        ax.set_title(col.replace("p_","").replace("_bar",""), fontsize=8)
        ax.set_xlabel("bar", fontsize=7)
    fig.suptitle("Pressure Node Distributions", fontsize=12)
    fig.tight_layout(); fig.savefig(out_dir / "pressure_distributions.png", dpi=150)
    plt.close(fig)

    fig, axes = plt.subplots(4, 5, figsize=(18, 12))
    for ax, col in zip(axes.flat, q_cols):
        ax.hist(pd.to_numeric(df[col], errors="coerce").dropna(),
                bins=60, color="coral", edgecolor="none")
        ax.set_title(col.replace("q_","").replace("_kgs",""), fontsize=8)
        ax.set_xlabel("kg/s", fontsize=7)
    fig.suptitle("Flow Edge Distributions", fontsize=12)
    fig.tight_layout(); fig.savefig(out_dir / "flow_distributions.png", dpi=150)
    plt.close(fig)

    fig, axes = plt.subplots(1, 2, figsize=(12, 4))
    attack_counts = df["ATTACK_ID"].value_counts().sort_index()
    attack_names  = [ATTACK_NAMES.get(int(i), f"A{i}") for i in attack_counts.index]
    axes[0].bar(attack_names, attack_counts.values, color="steelblue")
    axes[0].set_xlabel("Attack ID"); axes[0].set_ylabel("Rows")
    axes[0].set_title("Rows per Attack Type")
    axes[0].tick_params(axis="x", rotation=45)

    label_counts = df["label"].value_counts().sort_index()
    bar_labels = [f"Normal (0)" if l == 0 else f"Anomaly ({l})"
                  for l in label_counts.index]
    axes[1].bar(bar_labels, label_counts.values,
                color=["steelblue"] + ["coral"]*(len(label_counts)-1))
    axes[1].set_ylabel("Rows"); axes[1].set_title("Binary Label Distribution")
    fig.tight_layout(); fig.savefig(out_dir / "dataset_composition.png", dpi=150)
    plt.close(fig)

    det_avail = [c for c in ["cusum_S_upper","cusum_S_lower","chi2_stat"]
                 if c in df.columns]
    if det_avail:
        fig, axes = plt.subplots(len(det_avail), 1, figsize=(14, 3*len(det_avail)))
        if len(det_avail) == 1:
            axes = [axes]
        for ax, col in zip(axes, det_avail):
            sample_sid = df["scenario_id"].iloc[0]
            sub = df[df["scenario_id"] == sample_sid].reset_index(drop=True)
            ax.plot(sub[col].values, lw=0.8, color="steelblue")
            ax.set_title(f"{col}  (scenario {sample_sid})")
            ax.set_xlabel("Log step (1 Hz)")
        fig.tight_layout(); fig.savefig(out_dir / "detector_timeseries.png", dpi=150)
        plt.close(fig)

    print(f"[eda] Saved to {out_dir}/")


# ─────────────────────────────────────────────────────────────────────────────
# 8. Scenario health check — FIX 1 applied here
# ─────────────────────────────────────────────────────────────────────────────

def scenario_health_check(df, out_dir):
    """
    Flag scenarios with physics divergence (pressures at hard limits).
    PHASE 0 fix means valid range is 12-28 bar (not 0.1-70).
    FIX 1: Apply pd.to_numeric to p_vals before comparison — prevents
           the 'str < float' TypeError that crashed the original pipeline.
    """
    print("[health] Running scenario health checks …")
    p_cols = pressure_cols(df)
    records = []
    for sid, grp in df.groupby("scenario_id"):
        # FIX 1: explicit numeric coercion — this was the TypeError crash point
        p_vals = grp[p_cols].apply(pd.to_numeric, errors="coerce").values

        n_rows    = len(grp)
        pct_floor = float(np.nanmean(p_vals < 13.0))   # below Phase 0 lower bound
        pct_ceil  = float(np.nanmean(p_vals > 27.0))   # above Phase 0 upper bound
        p_mean    = float(np.nanmean(p_vals))
        p_std     = float(np.nanstd(p_vals))
        diverged  = pct_floor > 0.10 or pct_ceil > 0.10
        records.append({
            "scenario_id": sid,
            "n_rows":      n_rows,
            "p_mean":      round(p_mean, 3),
            "p_std":       round(p_std, 3),
            "pct_floor":   round(pct_floor, 4),
            "pct_ceil":    round(pct_ceil, 4),
            "diverged":    diverged,
        })
    health = pd.DataFrame(records)
    n_div  = health["diverged"].sum()
    print(f"[health] {n_div}/{len(health)} scenarios show physics divergence")
    if n_div > 0:
        pct = 100 * n_div / len(health)
        print(f"[health] WARNING: {n_div} scenarios ({pct:.0f}%) diverged. "
              f"After Phase 0 fix this should be <5%. "
              f"Keeping all rows — divergence IS a detectable signal.")
    health.to_csv(out_dir / "scenario_health.csv", index=False)

    fig, axes = plt.subplots(1, 2, figsize=(12, 4))
    axes[0].hist(health["pct_floor"]*100, bins=30, color="steelblue")
    axes[0].set_xlabel("% rows at pressure floor (<13 bar)")
    axes[0].set_ylabel("# Scenarios"); axes[0].set_title("Pressure Floor Fraction")
    axes[1].hist(health["pct_ceil"]*100, bins=30, color="coral")
    axes[1].set_xlabel("% rows at pressure ceiling (>27 bar)")
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
    ax.set_title(title); fig.tight_layout()
    fig.savefig(path, dpi=150); plt.close(fig)


def _save_feature_importance(importances, feat_cols, path, title, top_n=25):
    idx = np.argsort(importances)[::-1][:top_n]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.barh([feat_cols[i] for i in idx[::-1]], importances[idx[::-1]],
            color="steelblue")
    ax.set_xlabel("Importance"); ax.set_title(f"{title} — Top {top_n} Features")
    fig.tight_layout(); fig.savefig(path, dpi=150); plt.close(fig)


def save_stats(df, feat_cols, results, out_dir):
    stats = {
        "total_rows":          int(len(df)),
        "n_scenarios":         int(df["scenario_id"].nunique()),
        "n_features":          len(feat_cols),
        "normal_rows":         int((df["label"]==0).sum()),
        "anomaly_rows":        int((df["label"]>0).sum()),
        "attack_ids_present":  sorted(int(x) for x in df["ATTACK_ID"].unique()),
        "models_trained":      list(results.keys()),
        "physics_fixed":       "node_V=500, relax=0.3, clamp=[12,28]",
        "schema_version":      "v2.0-phase-3",
    }
    with open(out_dir / "dataset_statistics.json", "w") as f:
        json.dump(stats, f, indent=2, default=int)
    print(f"\n[stats] Saved → {out_dir}/dataset_statistics.json")


# ─────────────────────────────────────────────────────────────────────────────
# 10. Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="CGD IDS ML Pipeline — Phase 3")
    parser.add_argument("--baseline",  default=str(BASELINE_CSV),
                        help="Path to baseline CSV")
    parser.add_argument("--attacks",   default=None,
                        help="Path to attacks dataset CSV (optional)")
    parser.add_argument("--data",      default=None,
                        help="Pre-merged CPS dataset CSV (overrides --baseline/--attacks)")
    parser.add_argument("--nrows",     type=int, default=None,
                        help="Limit rows loaded (quick testing)")
    parser.add_argument("--no-rolling", action="store_true",
                        help="Skip rolling feature engineering (faster)")
    parser.add_argument("--out-dir",   default=str(OUT_DIR),
                        help="Output directory")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # ── Load ────────────────────────────────────────────────────────────────
    if args.data:
        print(f"\n[load] Using pre-merged CPS dataset → {args.data}")
        df = load_dataset(Path(args.data), None, args.nrows)
    else:
        df = load_dataset(Path(args.baseline), args.attacks, args.nrows)

    # ── EDA ─────────────────────────────────────────────────────────────────
    plot_eda(df, out_dir)
    health = scenario_health_check(df, out_dir)

    bad_sids = health.loc[health["diverged"], "scenario_id"]
    if len(bad_sids) > 0:
        pct = 100 * len(bad_sids) / len(health)
        print(f"[health] {len(bad_sids)} scenarios ({pct:.0f}%) diverged — keeping all rows.")

    # ── Feature engineering ─────────────────────────────────────────────────
    df = engineer_features(df, rolling=not args.no_rolling)
    feat_cols = build_feature_cols(df)
    feat_cols += [c for c in df.columns
                  if (c.startswith("roc_") or c.startswith("kirchhoff_"))
                  and c not in feat_cols]
    feat_cols = [c for c in feat_cols if c in df.columns]
    print(f"[features] Total features: {len(feat_cols)}")

    # ── Train/test split ─────────────────────────────────────────────────────
    df_train, df_test = scenario_split(df, test_frac=0.2)
    print(f"[split] Train: {len(df_train):,} rows ({df_train['scenario_id'].nunique()} scenarios)")
    print(f"[split] Test : {len(df_test):,} rows ({df_test['scenario_id'].nunique()} scenarios)")

    # ── FIX 3: Check class balance before training supervised models ─────────
    y_train = df_train["label"].values
    y_test  = df_test["label"].values
    n_classes_train = len(np.unique(y_train))

    if n_classes_train < 2:
        print("\n[WARNING] Only one class present in training set.")
        print("          RF and XGBoost require anomaly rows to be meaningful.")
        print("          Run with --attacks to add attack data, or generate")
        print("          attack windows using run_attack_windows.m first.")
        SKIP_SUP = True
    else:
        SKIP_SUP = False

    # ── Scaling ──────────────────────────────────────────────────────────────
    scaler, feat_cols = fit_scaler(df_train, feat_cols)
    X_train = scale(df_train, scaler, feat_cols)
    X_test  = scale(df_test,  scaler, feat_cols)

    joblib.dump(scaler, out_dir / "scaler.pkl")
    results = {}

    # ── Isolation Forest (unsupervised — always runs) ────────────────────────
    normal_mask   = y_train == 0
    contamination = max(0.01, float((y_train > 0).mean())) if not SKIP_SUP else 0.01
    iforest = train_isolation_forest(X_train[normal_mask], contamination=contamination)
    res_if  = eval_isolation_forest(iforest, X_test, y_test, out_dir)
    results.update(res_if)
    joblib.dump(iforest, out_dir / "iforest.pkl")

    # ── FIX 3: Supervised models only if ≥2 classes ──────────────────────────
    if not SKIP_SUP:
        print()
        rf     = train_random_forest(X_train, y_train)
        res_rf = eval_random_forest(rf, X_test, y_test, feat_cols, out_dir)
        results.update(res_rf)
        joblib.dump(rf, out_dir / "random_forest.pkl")

        if HAS_XGB:
            print()
            val_frac = 0.1
            n_val    = max(1, int(len(X_train) * val_frac))
            rng      = np.random.default_rng(42)
            val_idx  = rng.choice(len(X_train), size=n_val, replace=False)
            tr_idx   = np.setdiff1d(np.arange(len(X_train)), val_idx)
            try:
                xgb_clf = train_xgboost(X_train[tr_idx], y_train[tr_idx],
                                        X_train[val_idx], y_train[val_idx])
                res_xgb = eval_xgboost(xgb_clf, X_test, y_test, feat_cols, out_dir)
                results.update(res_xgb)
                joblib.dump(xgb_clf, out_dir / "xgboost.pkl")
            except ValueError as e:
                print(f"[xgb] Skipped: {e}")
    else:
        print("\n[skip] RF and XGBoost skipped (single class). "
              "IsolationForest results saved above.")

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
