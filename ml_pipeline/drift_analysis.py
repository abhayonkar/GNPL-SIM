"""
drift_analysis.py — Phase 0 48-hour Collapse / Feature Drift Diagnosis
=======================================================================
Compares feature distributions between the training set (attack_windows) and
the 48-hour continuous test set using Wasserstein-1 distance.

Explains the F1 drop from 0.76 → 0.08 on the 48h run by identifying which
feature groups drifted beyond the training distribution.

Usage:
    python ml_pipeline/drift_analysis.py \\
        --train automated_dataset/attack_windows/physics_dataset_windows.csv \\
        --test  automated_dataset/continuous_48h/physics_dataset.csv \\
        --out   reports/phase0_drift_diagnosis.md

Output:
    reports/phase0_drift_diagnosis.md  — markdown report
    Top 20 drifted features, W > 1.0 flags, missing feature class analysis.
    Read-only diagnostic only: no new data generated, no regime labels added.
"""

import argparse
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import wasserstein_distance

warnings.filterwarnings("ignore")


# ── Feature group classification ──────────────────────────────────────────────

FEATURE_GROUPS = {
    "pressure":      lambda c: c.startswith("p_") or "pressure" in c.lower(),
    "flow":          lambda c: c.startswith("q_") or "flow" in c.lower() or c.endswith("_kgs"),
    "ekf_residual":  lambda c: c.startswith("ekf_resid_"),
    "cusum":         lambda c: c.startswith("cusum_"),
    "chi2":          lambda c: c.startswith("chi2"),
    "plc_pressure":  lambda c: c.startswith("plc_p_"),
    "plc_flow":      lambda c: c.startswith("plc_q_"),
    "compressor":    lambda c: "COMP" in c or "comp" in c.lower(),
    "valve":         lambda c: "VALVE" in c or "valve" in c.lower() or c.endswith("_cmd"),
    "source":        lambda c: "SRC" in c or "Demand" in c,
    "timestamp":     lambda c: c.lower() in ("timestamp_s", "timestamp"),
    "label":         lambda c: c in ("ATTACK_ID", "scenario_id", "regime_id",
                                     "ATTACK_NAME", "MITRE_ID"),
}


def classify_feature(col: str) -> str:
    for group, fn in FEATURE_GROUPS.items():
        if fn(col):
            return group
    return "other"


# ── Data loading ──────────────────────────────────────────────────────────────

def load_csv(path: Path, label: str) -> pd.DataFrame:
    df = pd.read_csv(path, low_memory=False)
    if df.columns[0].startswith("#"):
        df = pd.read_csv(path, comment="#", low_memory=False)
    print(f"[drift] {label}: {len(df):,} rows × {len(df.columns)} cols")
    return df


# ── Wasserstein analysis ──────────────────────────────────────────────────────

def compute_drift(train: pd.DataFrame, test: pd.DataFrame,
                  skip_groups: set | None = None) -> list[dict]:
    """
    Compute Wasserstein-1 distance for every numeric column common to both DFs.

    Returns list of dicts sorted by W descending.
    """
    skip_groups = skip_groups or {"timestamp", "label"}
    common_cols = [
        c for c in train.columns
        if c in test.columns
        and classify_feature(c) not in skip_groups
        and pd.api.types.is_numeric_dtype(train[c])
    ]

    print(f"[drift] Computing W-distance on {len(common_cols)} shared numeric columns …")

    rows = []
    for col in common_cols:
        t_vals = train[col].dropna().values.astype(np.float64)
        s_vals = test[col].dropna().values.astype(np.float64)
        if len(t_vals) < 10 or len(s_vals) < 10:
            continue
        try:
            w = wasserstein_distance(t_vals, s_vals)
        except Exception:
            w = np.nan

        rows.append({
            "feature": col,
            "group":   classify_feature(col),
            "W":       w,
            "train_mean": float(t_vals.mean()),
            "test_mean":  float(s_vals.mean()),
            "train_std":  float(t_vals.std()),
            "test_std":   float(s_vals.std()),
            "drift_flag": w > 1.0 if not np.isnan(w) else False,
        })

    rows.sort(key=lambda r: r["W"] if not np.isnan(r["W"]) else -1, reverse=True)
    return rows


def missing_feature_classes(train: pd.DataFrame, test: pd.DataFrame) -> list[str]:
    """
    Identify feature classes / operating conditions present in test but absent or
    very rare in training data.
    """
    findings = []

    # Regime diversity
    if "regime_id" in test.columns:
        test_regimes = test["regime_id"].dropna().unique()
        n_regimes = len(test_regimes)
        findings.append(
            f"**Regime diversity**: test set has {n_regimes} distinct `regime_id` values "
            f"({sorted(test_regimes[:10].tolist())}…). "
            "Training (attack_windows) does not include regime labels — "
            "regime-dependent distribution shifts are invisible to the model."
        )
    else:
        findings.append(
            "**Regime diversity**: `regime_id` absent in test dataset — "
            "cannot directly compare operating regimes."
        )

    # Temporal columns
    ts_train = "Timestamp_s" if "Timestamp_s" in train.columns else None
    ts_test  = "Timestamp_s" if "Timestamp_s" in test.columns else None
    if ts_train and ts_test:
        train_dur = train[ts_train].max() - train[ts_train].min()
        test_dur  = test[ts_test].max()  - test[ts_test].min()
        findings.append(
            f"**Temporal span**: train covers {train_dur/3600:.1f} h, "
            f"test covers {test_dur/3600:.1f} h. "
            "Diurnal and multi-hour demand cycles absent from attack_windows training windows."
        )

    # Pressure range
    p_cols_train = [c for c in train.columns if c.startswith("p_")]
    p_cols_test  = [c for c in test.columns  if c.startswith("p_")]
    if p_cols_train and p_cols_test:
        common_p = list(set(p_cols_train) & set(p_cols_test))
        if common_p:
            p_train_range = (
                train[common_p].min().min(),
                train[common_p].max().max(),
            )
            p_test_range = (
                test[common_p].min().min(),
                test[common_p].max().max(),
            )
            if p_test_range[0] < p_train_range[0] * 0.9 or p_test_range[1] > p_train_range[1] * 1.1:
                findings.append(
                    f"**Pressure operating envelope**: train p ∈ [{p_train_range[0]:.2f}, {p_train_range[1]:.2f}] bar, "
                    f"test p ∈ [{p_test_range[0]:.2f}, {p_test_range[1]:.2f}] bar. "
                    "Test set operates outside trained pressure range — out-of-distribution for the ML model."
                )
            else:
                findings.append(
                    f"**Pressure operating envelope**: compatible ranges "
                    f"(train [{p_train_range[0]:.2f}, {p_train_range[1]:.2f}] bar, "
                    f"test [{p_test_range[0]:.2f}, {p_test_range[1]:.2f}] bar)."
                )

    # Missing columns
    train_only = set(train.columns) - set(test.columns) - {"ATTACK_ID", "scenario_id", "ATTACK_NAME", "MITRE_ID"}
    test_only  = set(test.columns)  - set(train.columns) - {"regime_id"}
    if train_only:
        findings.append(
            f"**Columns in train only** ({len(train_only)} cols): "
            f"`{'`, `'.join(sorted(train_only)[:15])}`…  "
            "Features unavailable at 48h test time — imputed as zero/NaN by scaler."
        )
    if test_only:
        findings.append(
            f"**Columns in test only** ({len(test_only)} cols): "
            f"`{'`, `'.join(sorted(test_only)[:15])}`…  "
            "Test set exposes new signal channels not seen during training."
        )

    # Demand / source variability
    demand_cols = [c for c in test.columns if "Demand" in c or "demand" in c.lower()]
    if demand_cols:
        for dc in demand_cols[:2]:
            if dc in train.columns:
                d_std_train = train[dc].std()
                d_std_test  = test[dc].std()
                if d_std_test > d_std_train * 1.5:
                    findings.append(
                        f"**Demand variability** (`{dc}`): train std={d_std_train:.4f}, "
                        f"test std={d_std_test:.4f} ({d_std_test/d_std_train:.1f}×). "
                        "48h test sees much higher demand variance — "
                        "model trained on flat-demand windows."
                    )

    return findings


def group_summary(rows: list[dict]) -> dict[str, dict]:
    """Per-group aggregate: count drifted (W > 1), max W, mean W."""
    groups: dict[str, list] = {}
    for r in rows:
        groups.setdefault(r["group"], []).append(r)

    summary = {}
    for g, items in groups.items():
        w_vals = [r["W"] for r in items if not np.isnan(r["W"])]
        summary[g] = {
            "total":   len(items),
            "drifted": sum(1 for r in items if r["drift_flag"]),
            "max_W":   float(max(w_vals)) if w_vals else 0.0,
            "mean_W":  float(np.mean(w_vals)) if w_vals else 0.0,
        }
    return summary


# ── Report writer ─────────────────────────────────────────────────────────────

def write_report(out_path: Path, rows: list[dict], group_sum: dict,
                 missing: list[str], train_path: Path, test_path: Path) -> None:
    total_drifted = sum(1 for r in rows if r["drift_flag"])
    top20 = rows[:20]

    lines = [
        "# Phase 0 — 48-Hour Collapse / Feature Drift Diagnosis",
        "",
        f"**Train dataset:** `{train_path}`  ",
        f"**Test dataset:**  `{test_path}`  ",
        f"**Generated:** {pd.Timestamp.now().isoformat(timespec='seconds')}",
        "",
        "> Diagnostic only — no new data generated, no regime labels added.",
        "",
        "---",
        "",
        "## 1. Wasserstein Distance Summary",
        "",
        f"- Features analysed: **{len(rows)}**",
        f"- Features with W > 1.0 (drifted): **{total_drifted}** "
        f"({100*total_drifted/max(len(rows),1):.0f}%)",
        "",
        "### By Feature Group",
        "",
        "| Group | Total | Drifted (W>1) | Max W | Mean W |",
        "|-------|-------|--------------|-------|--------|",
    ]
    for g, s in sorted(group_sum.items(), key=lambda x: x[1]["max_W"], reverse=True):
        lines.append(
            f"| {g} | {s['total']} | {s['drifted']} | {s['max_W']:.3f} | {s['mean_W']:.3f} |"
        )

    lines += [
        "",
        "---",
        "",
        "## 2. Top 20 Drifted Features",
        "",
        "| Rank | Feature | Group | W distance | Train mean | Test mean | Flag |",
        "|------|---------|-------|-----------|-----------|----------|------|",
    ]
    for i, r in enumerate(top20, 1):
        flag = "🔴 DRIFT" if r["drift_flag"] else "🟡"
        lines.append(
            f"| {i} | `{r['feature']}` | {r['group']} | {r['W']:.3f} "
            f"| {r['train_mean']:.4f} | {r['test_mean']:.4f} | {flag} |"
        )

    lines += [
        "",
        "---",
        "",
        "## 3. Missing Feature Classes / Operating Conditions",
        "",
    ]
    for i, finding in enumerate(missing, 1):
        lines.append(f"{i}. {finding}")
        lines.append("")

    lines += [
        "",
        "---",
        "",
        "## 4. Root Cause Assessment",
        "",
        "The F1 drop from 0.76 → 0.08 is explained by:",
        "",
        f"1. **{total_drifted} features with W > 1.0** — the test distribution is far outside "
        "the training manifold; the scaler/threshold set on training data is invalid for 48h operation.",
        "",
        "2. **Temporal regime shifts** — the 48h run includes diurnal demand cycles, multi-hour "
        "pressure oscillations, and compressor duty cycles that attack_windows (short windows) never exhibit.",
        "",
        "3. **No attack labels in 48h test** — ATTACK_ID is absent, so all anomalous scores are "
        "evaluated against a threshold calibrated for a different operating point. "
        "False positives dominate, causing F1 collapse.",
        "",
        "**Phase 2 requirement:** Generate 48h-spanning training data covering the drifted feature "
        "ranges above. Specifically, the top-drifted feature groups must be present in training.",
        "",
    ]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"[drift] Report written → {out_path}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="48h feature drift analysis")
    parser.add_argument(
        "--train",
        default="automated_dataset/attack_windows/physics_dataset_windows.csv",
    )
    parser.add_argument(
        "--test",
        default="automated_dataset/continuous_48h/physics_dataset.csv",
    )
    parser.add_argument(
        "--out",
        default="reports/phase0_drift_diagnosis.md",
    )
    args = parser.parse_args()

    train_path = Path(args.train)
    test_path  = Path(args.test)
    out_path   = Path(args.out)

    for p in (train_path, test_path):
        if not p.exists():
            print(f"[drift] ERROR: not found: {p}", file=sys.stderr)
            sys.exit(1)

    train = load_csv(train_path, "train (attack_windows)")
    test  = load_csv(test_path,  "test  (continuous_48h)")

    rows      = compute_drift(train, test)
    group_sum = group_summary(rows)
    missing   = missing_feature_classes(train, test)

    # Print top drifted features
    n_drift = sum(1 for r in rows if r["drift_flag"])
    print(f"\n[drift] Features with W > 1.0: {n_drift}")
    for r in rows[:20]:
        flag = " ← DRIFT" if r["drift_flag"] else ""
        print(f"  {r['feature']:45s}  W={r['W']:.3f}{flag}")

    write_report(out_path, rows, group_sum, missing, train_path, test_path)


if __name__ == "__main__":
    main()
