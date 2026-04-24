"""
diagnostic_physics_residual.py — Phase 0 Physics-EKF Residual Diagnosis
========================================================================
Diagnoses why Physics-EKF F1 = 0.19 by comparing:
  1. EKF residual anomaly score distributions: normal vs attack
  2. Weymouth-implied score vs EKF innovation magnitude
  3. Correlation between residual series and EKF innovation

Usage:
    python ml_pipeline/diagnostic_physics_residual.py \\
        --dataset automated_dataset/attack_windows/physics_dataset_windows.csv \\
        --out reports/phase0_physics_ekf_diagnosis.md

Outputs a markdown report with histogram separation statistics and root-cause
findings. Does NOT retrain any model or introduce Phase 4+ logic.
"""

import argparse
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")


# ── Column groups ─────────────────────────────────────────────────────────────

EKF_RESID_PREFIX = "ekf_resid_"
PRESSURE_PREFIX  = "p_"
FLOW_PREFIX      = "q_"
CUSUM_COLS       = ["cusum_S_upper", "cusum_S_lower"]
CHI2_COL         = "chi2_stat"
ATTACK_COL       = "ATTACK_ID"


# ── Core functions ────────────────────────────────────────────────────────────

def load_dataset(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, low_memory=False)
    # skip provenance comment line if present
    if df.columns[0].startswith("#"):
        df = pd.read_csv(path, comment="#", low_memory=False)
    print(f"[diag] Loaded {len(df):,} rows × {len(df.columns)} cols from {path.name}")
    return df


def physics_anomaly_score(df: pd.DataFrame) -> np.ndarray:
    """
    Compute per-row physics anomaly score from EKF residuals and CUSUM stats.
    Mirrors hybrid_ids.physics_anomaly_score() but standalone.
    """
    scores = np.zeros(len(df), dtype=np.float32)

    ekf_cols = [c for c in df.columns if c.startswith(EKF_RESID_PREFIX)]
    if ekf_cols:
        scores += np.linalg.norm(df[ekf_cols].fillna(0).values, axis=1)

    if "kirchhoff_imbalance" in df.columns:
        scores += df["kirchhoff_imbalance"].fillna(0).abs().values.astype(np.float32)

    if "cusum_S_upper" in df.columns:
        scores += df["cusum_S_upper"].fillna(0).values.astype(np.float32) * 0.1

    if CHI2_COL in df.columns:
        scores += df[CHI2_COL].fillna(0).values.astype(np.float32) * 0.05

    return scores


def compute_separation(a: np.ndarray, b: np.ndarray) -> dict:
    """
    Cohen's d and standardised mean difference between two distributions.

    Returns dict with keys: mean_a, mean_b, std_a, std_b, cohens_d, pooled_std.
    """
    pooled_std = np.sqrt((a.std() ** 2 + b.std() ** 2) / 2.0)
    pooled_std = max(pooled_std, 1e-9)
    d = abs(a.mean() - b.mean()) / pooled_std
    return {
        "mean_normal": float(a.mean()),
        "mean_attack": float(b.mean()),
        "std_normal":  float(a.std()),
        "std_attack":  float(b.std()),
        "pooled_std":  float(pooled_std),
        "cohens_d":    float(d),
    }


def per_node_analysis(df_n: pd.DataFrame, df_a: pd.DataFrame) -> list[dict]:
    """Per-node EKF residual column Cohen's d."""
    ekf_cols = [c for c in df_n.columns if c.startswith(EKF_RESID_PREFIX)]
    rows = []
    for col in ekf_cols:
        a_vals = df_n[col].dropna().values
        b_vals = df_a[col].dropna().values
        if len(a_vals) < 10 or len(b_vals) < 10:
            continue
        sep = compute_separation(a_vals, b_vals)
        rows.append({"node": col.replace(EKF_RESID_PREFIX, ""), **sep})
    return sorted(rows, key=lambda r: r["cohens_d"], reverse=True)


def weymouth_vs_ekf_range(df_n: pd.DataFrame, df_a: pd.DataFrame) -> dict:
    """
    Compare magnitude ranges of:
      - EKF residual L2 norm (physics_anomaly_score contribution from EKF cols)
      - CUSUM upper statistic (innovation proxy)
    Returns a dict describing whether they are correlated / in compatible ranges.
    """
    ekf_cols = [c for c in df_n.columns if c.startswith(EKF_RESID_PREFIX)]
    result = {}

    if ekf_cols:
        ekf_norm_n = np.linalg.norm(df_n[ekf_cols].fillna(0).values, axis=1)
        ekf_norm_a = np.linalg.norm(df_a[ekf_cols].fillna(0).values, axis=1)
        result["ekf_l2_normal_p50"]  = float(np.percentile(ekf_norm_n, 50))
        result["ekf_l2_normal_p99"]  = float(np.percentile(ekf_norm_n, 99))
        result["ekf_l2_attack_p50"]  = float(np.percentile(ekf_norm_a, 50))
        result["ekf_l2_attack_p99"]  = float(np.percentile(ekf_norm_a, 99))
        result["ekf_range_ratio"]    = (
            result["ekf_l2_attack_p99"] / max(result["ekf_l2_normal_p99"], 1e-9)
        )

    if "cusum_S_upper" in df_n.columns:
        cus_n = df_n["cusum_S_upper"].fillna(0).values
        cus_a = df_a["cusum_S_upper"].fillna(0).values
        result["cusum_normal_p50"] = float(np.percentile(cus_n, 50))
        result["cusum_normal_p99"] = float(np.percentile(cus_n, 99))
        result["cusum_attack_p50"] = float(np.percentile(cus_a, 50))
        result["cusum_attack_p99"] = float(np.percentile(cus_a, 99))

        # correlation between EKF L2 and CUSUM (on combined data)
        if ekf_cols:
            n_len = min(len(ekf_norm_n), len(cus_n))
            a_len = min(len(ekf_norm_a), len(cus_a))
            combined_ekf  = np.concatenate([ekf_norm_n[:n_len], ekf_norm_a[:a_len]])
            combined_cus  = np.concatenate([cus_n[:n_len], cus_a[:a_len]])
            result["ekf_cusum_correlation"] = float(
                np.corrcoef(combined_ekf, combined_cus)[0, 1]
            )

    return result


def diagnose_normalisation_bug(sep: dict) -> str:
    """
    Heuristic root-cause assessment based on Cohen's d.
    """
    d = sep["cohens_d"]
    if d >= 1.5:
        return "SEPARATION OK — Physics score separates classes well. Low F1 is likely a threshold, not a residual bug."
    elif d >= 0.5:
        return "MODERATE SEPARATION — Residual is partially useful but likely mis-scaled or noisy. Check normalisation."
    else:
        return "POOR SEPARATION (d < 0.5) — Residual is effectively random between classes. Calibration bug confirmed."


# ── Report writer ─────────────────────────────────────────────────────────────

def write_report(out_path: Path, sep_raw: dict, sep_log: dict,
                 per_node: list[dict], ranges: dict, dataset_path: Path) -> None:
    lines = [
        "# Phase 0 — Physics-EKF Residual Diagnosis",
        "",
        f"**Dataset:** `{dataset_path}`  ",
        f"**Generated:** {pd.Timestamp.now().isoformat(timespec='seconds')}",
        "",
        "---",
        "",
        "## 1. Overall Anomaly Score Separation",
        "",
        "Physics anomaly score = L2(EKF residuals) + 0.1 × CUSUM_upper + 0.05 × chi2_stat",
        "",
        "### 1a. Raw score (linear)",
        "",
        f"| Metric | Value |",
        f"|--------|-------|",
        f"| Normal mean | {sep_raw['mean_normal']:.4f} |",
        f"| Attack mean | {sep_raw['mean_attack']:.4f} |",
        f"| Normal std  | {sep_raw['std_normal']:.4f} |",
        f"| Attack std  | {sep_raw['std_attack']:.4f} |",
        f"| Pooled std  | {sep_raw['pooled_std']:.4f} |",
        f"| **Cohen's d** | **{sep_raw['cohens_d']:.3f}** |",
        "",
        f"**Assessment:** {diagnose_normalisation_bug(sep_raw)}",
        "",
        "### 1b. Log-transformed score (np.log1p)",
        "",
        f"| Metric | Value |",
        f"|--------|-------|",
        f"| Normal mean | {sep_log['mean_normal']:.4f} |",
        f"| Attack mean | {sep_log['mean_attack']:.4f} |",
        f"| **Cohen's d** | **{sep_log['cohens_d']:.3f}** |",
        "",
        f"**Assessment:** {diagnose_normalisation_bug(sep_log)}",
        "",
        "---",
        "",
        "## 2. Per-Node EKF Residual Analysis (top 10 by separation)",
        "",
        "| Node | Normal mean | Attack mean | Cohen's d | Assessment |",
        "|------|-------------|-------------|-----------|------------|",
    ]
    for r in per_node[:10]:
        flag = "✓" if r["cohens_d"] >= 1.5 else ("~" if r["cohens_d"] >= 0.5 else "✗")
        lines.append(
            f"| {r['node']} | {r['mean_normal']:.4f} | {r['mean_attack']:.4f} "
            f"| {r['cohens_d']:.3f} | {flag} |"
        )

    lines += [
        "",
        "---",
        "",
        "## 3. EKF Residual vs CUSUM Innovation Range Comparison",
        "",
        "| Metric | Value |",
        "|--------|-------|",
    ]
    for k, v in ranges.items():
        lines.append(f"| {k} | {v:.4f} |")

    # Interpretation
    corr = ranges.get("ekf_cusum_correlation", None)
    ratio = ranges.get("ekf_range_ratio", None)
    lines += ["", "**Range interpretation:**", ""]
    if ratio is not None:
        if ratio >= 2.0:
            lines.append(f"- EKF L2 p99 ratio (attack/normal) = {ratio:.2f} ≥ 2 — adequate dynamic range.")
        else:
            lines.append(f"- EKF L2 p99 ratio (attack/normal) = {ratio:.2f} < 2 — residual barely changes under attack. "
                         "Likely normalisation or sign-convention bug in `computeWeymouthResiduals.m`.")
    if corr is not None:
        if abs(corr) >= 0.3:
            lines.append(f"- EKF–CUSUM correlation = {corr:.3f} — residuals are correlated with innovation (expected).")
        else:
            lines.append(f"- EKF–CUSUM correlation = {corr:.3f} ≈ 0 — residuals are **not** tracking the EKF innovation. "
                         "Root cause: Weymouth residual is computed on wrong state (physics vs PLC bus mismatch).")

    lines += [
        "",
        "---",
        "",
        "## 4. Root Cause Summary",
        "",
        "| Check | Result |",
        "|-------|--------|",
    ]
    d_raw = sep_raw["cohens_d"]
    d_log = sep_log["cohens_d"]
    lines.append(f"| Raw score separation (Cohen's d ≥ 1.5) | {'PASS' if d_raw >= 1.5 else 'FAIL'} (d={d_raw:.3f}) |")
    lines.append(f"| Log score separation (Cohen's d ≥ 1.5) | {'PASS' if d_log >= 1.5 else 'FAIL'} (d={d_log:.3f}) |")
    if ratio is not None:
        lines.append(f"| EKF range ratio ≥ 2.0 | {'PASS' if ratio >= 2.0 else 'FAIL'} (ratio={ratio:.2f}) |")
    if corr is not None:
        lines.append(f"| EKF–CUSUM correlation ≥ 0.3 | {'PASS' if abs(corr) >= 0.3 else 'FAIL'} (r={corr:.3f}) |")

    lines += [
        "",
        "**Next step:**",
        "",
        "- If all checks PASS → threshold mis-set; re-run `train_temporal_graph.py` and check fit_threshold FPR.",
        "- If range ratio FAIL → `computeWeymouthResiduals.m` is normalising or scaling incorrectly; "
        "check unit conversion (kPa vs bar) in `p_abs` computation.",
        "- If correlation FAIL → residual uses wrong state variable; confirm `state.q` is the PLC bus "
        "reading (not the physics solver output) at the logging step.",
        "",
    ]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"[diag] Report written → {out_path}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Physics-EKF residual diagnosis")
    parser.add_argument(
        "--dataset",
        default="automated_dataset/attack_windows/physics_dataset_windows.csv",
        help="Path to labelled dataset CSV with ATTACK_ID column",
    )
    parser.add_argument(
        "--out",
        default="reports/phase0_physics_ekf_diagnosis.md",
        help="Output markdown report path",
    )
    args = parser.parse_args()

    dataset_path = Path(args.dataset)
    out_path     = Path(args.out)

    if not dataset_path.exists():
        print(f"[diag] ERROR: dataset not found: {dataset_path}", file=sys.stderr)
        sys.exit(1)

    df = load_dataset(dataset_path)

    if ATTACK_COL not in df.columns:
        print(f"[diag] ERROR: '{ATTACK_COL}' column not found. "
              "Use the attack_windows dataset.", file=sys.stderr)
        sys.exit(1)

    normal_mask = df[ATTACK_COL] == 0
    attack_mask = df[ATTACK_COL] > 0
    df_n = df[normal_mask].reset_index(drop=True)
    df_a = df[attack_mask].reset_index(drop=True)
    print(f"[diag] Normal rows: {len(df_n):,}  Attack rows: {len(df_a):,}")

    if len(df_n) < 100 or len(df_a) < 100:
        print("[diag] WARNING: too few rows in one class — results may be unreliable.")

    # 1. Anomaly score separation
    score_n = physics_anomaly_score(df_n)
    score_a = physics_anomaly_score(df_a)
    sep_raw = compute_separation(score_n, score_a)

    log_score_n = np.log1p(score_n)
    log_score_a = np.log1p(score_a)
    sep_log = compute_separation(log_score_n, log_score_a)

    print(f"[diag] Raw  Cohen's d = {sep_raw['cohens_d']:.3f}")
    print(f"[diag] Log1p Cohen's d = {sep_log['cohens_d']:.3f}")
    print(f"[diag] Expected: ≥1.5 for good separation; <0.5 = broken residual")

    # 2. Per-node analysis
    per_node = per_node_analysis(df_n, df_a)

    # 3. Range + correlation check
    ranges = weymouth_vs_ekf_range(df_n, df_a)

    # 4. Write report
    write_report(out_path, sep_raw, sep_log, per_node, ranges, dataset_path)

    # Exit code 1 if residual is broken (helps CI gate if used)
    if sep_raw["cohens_d"] < 0.5 and sep_log["cohens_d"] < 0.5:
        print("[diag] RESULT: Residual is broken — d < 0.5 in both raw and log space.")
        sys.exit(2)
    elif sep_raw["cohens_d"] < 1.5:
        print("[diag] RESULT: Residual has moderate separation — calibration likely needed.")
        sys.exit(0)
    else:
        print("[diag] RESULT: Residual separation is adequate — check threshold, not residual.")
        sys.exit(0)


if __name__ == "__main__":
    main()
