"""
merge_cps_dataset.py — Phase 3: Physics + Network Dataset Merger
=================================================================
Aligns the 1 Hz physics dataset (from run_48h_continuous / run_24h_sweep)
with the 10 Hz network dataset (from network_logger.py / gateway.py)
to produce a single merged CPS dataset with ~300 columns.

Output: automated_dataset/continuous_48h/merged_cps_dataset.csv

Usage:
  python merge_cps_dataset.py
  python merge_cps_dataset.py --physics path/to/physics_dataset.csv
                              --network path/to/pipeline_data_latest.csv
                              --out     path/to/merged_cps_dataset.csv
"""

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

# Default paths
SCRIPT_DIR = Path(__file__).parent
SIM_ROOT   = SCRIPT_DIR.parent
PHYSICS_DEFAULT = SIM_ROOT / "automated_dataset/continuous_48h/physics_dataset.csv"
NETWORK_DEFAULT = SIM_ROOT / "middleware/logs/pipeline_data_latest.csv"
OUT_DEFAULT     = SIM_ROOT / "automated_dataset/continuous_48h/merged_cps_dataset.csv"


def load_physics(path: Path, nrows=None) -> pd.DataFrame:
    print(f"[merge] Loading physics dataset → {path}")
    df = pd.read_csv(path, nrows=nrows, low_memory=False)
    print(f"        {len(df):,} rows × {len(df.columns)} cols")

    # Convert all numeric columns
    meta = ["Timestamp_s","scenario_id","regime_id","MITRE_CODE",
            "source_config","demand_profile","valve_config","storage_init","cs_mode"]
    for col in df.columns:
        if col not in meta:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    df["Timestamp_s"] = pd.to_numeric(df["Timestamp_s"], errors="coerce")
    df = df.dropna(subset=["Timestamp_s"])
    return df


def load_network(path: Path, nrows=None) -> pd.DataFrame:
    print(f"[merge] Loading network dataset → {path}")
    df = pd.read_csv(path, nrows=nrows, low_memory=False)
    print(f"        {len(df):,} rows × {len(df.columns)} cols")

    # Compute Timestamp_s from ms
    if "timestamp_ms" in df.columns:
        df["Timestamp_s"] = pd.to_numeric(df["timestamp_ms"],
                                          errors="coerce") / 1000.0
    elif "timestamp_s" in df.columns:
        df["Timestamp_s"] = pd.to_numeric(df["timestamp_s"], errors="coerce")
    else:
        raise ValueError("Network CSV must have 'timestamp_ms' or 'timestamp_s' column.")

    df = df.dropna(subset=["Timestamp_s"])
    return df


def downsample_network_to_1hz(net: pd.DataFrame) -> pd.DataFrame:
    """
    Network logger produces ~20 rows per second (one per variable per poll).
    Aggregate to 1 Hz to match the physics dataset:
      - numeric columns: mean
      - categorical: first (src_id, dst_id, comm_pair, etc.)
      - ATTACK_ID: max (non-zero if any attack in that second)
      - label: max
      - attack_start, recovery_start: max (flag if transition happened in window)
      - write_flag: sum (count of write commands in that second)
    """
    print("[merge] Downsampling network dataset to 1 Hz …")
    net["t_round"] = net["Timestamp_s"].round(0)

    agg_dict = {}
    for col in net.columns:
        if col in ("t_round", "Timestamp_s"):
            continue
        if col in ("ATTACK_ID", "label", "attack_start", "recovery_start"):
            agg_dict[col] = "max"
        elif col == "write_flag":
            agg_dict[col] = "sum"
        elif col in ("src_id", "dst_id", "src_ip", "dst_ip", "comm_pair", "unit", "variable"):
            agg_dict[col] = "first"
        else:
            try:
                net[col] = pd.to_numeric(net[col], errors="coerce")
                agg_dict[col] = "mean"
            except Exception:
                agg_dict[col] = "first"

    net_1hz = (
        net.sort_values("Timestamp_s")
        .groupby("t_round")
        .agg(agg_dict)
        .reset_index()
        .rename(columns={"t_round": "Timestamp_s"})
    )
    print(f"        Downsampled: {len(net_1hz):,} rows")
    return net_1hz


def merge(physics: pd.DataFrame, net_1hz: pd.DataFrame) -> pd.DataFrame:
    """
    Left-join physics onto network on Timestamp_s.
    Physics is authoritative (keep all physics rows).
    Network columns are suffixed with _net to avoid name collisions.
    """
    print("[merge] Merging on Timestamp_s …")
    merged = physics.merge(
        net_1hz,
        on="Timestamp_s",
        how="left",
        suffixes=("", "_net")
    )

    # Drop duplicate _net label columns — physics labels take priority
    dup_cols = [c for c in merged.columns
                if c.endswith("_net") and c.replace("_net","") in merged.columns]
    merged = merged.drop(columns=dup_cols, errors="ignore")

    print(f"[merge] Merged shape: {merged.shape[0]:,} rows × {merged.shape[1]} cols")
    return merged


def validate_merge(merged: pd.DataFrame):
    """Quick sanity checks on merged dataset."""
    n_total   = len(merged)
    n_matched = merged["src_id"].notna().sum() if "src_id" in merged.columns else 0
    pct       = 100 * n_matched / n_total if n_total > 0 else 0
    print(f"[validate] Physics rows: {n_total:,}")
    print(f"[validate] Network-matched rows: {n_matched:,} ({pct:.1f}%)")

    if pct < 50:
        print("[validate] WARNING: <50% of physics rows matched network rows.")
        print("           Check that both datasets cover the same time window.")

    # Label consistency check
    if "ATTACK_ID" in merged.columns and "ATTACK_ID_net" not in merged.columns:
        n_atk = (merged["ATTACK_ID"] > 0).sum()
        print(f"[validate] Attack rows in physics: {n_atk:,}")

    p_mean = merged[[c for c in merged.columns
                     if c.startswith("p_") and c.endswith("_bar")]].mean().mean()
    print(f"[validate] Mean pressure: {p_mean:.1f} bar "
          f"{'✓ REALISTIC' if 14 <= p_mean <= 26 else '✗ CHECK PHYSICS FIX'}")


def write_metadata(merged, physics_path, network_path, out_path):
    meta = {
        "n_rows": int(len(merged)),
        "n_cols": int(len(merged.columns)),
        "physics_source": str(physics_path),
        "network_source": str(network_path),
        "output": str(out_path),
        "attack_ids": sorted(int(x) for x in merged["ATTACK_ID"].dropna().unique())
        if "ATTACK_ID" in merged.columns else [],
        "columns": list(merged.columns),
    }
    meta_path = out_path.parent / "merged_metadata.json"
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"[merge] Metadata → {meta_path}")


def main():
    parser = argparse.ArgumentParser(description="Merge physics + network CPS datasets")
    parser.add_argument("--physics", default=str(PHYSICS_DEFAULT))
    parser.add_argument("--network", default=str(NETWORK_DEFAULT))
    parser.add_argument("--out",     default=str(OUT_DEFAULT))
    parser.add_argument("--nrows",   type=int, default=None,
                        help="Limit rows for testing")
    args = parser.parse_args()

    physics_path = Path(args.physics)
    network_path = Path(args.network)
    out_path     = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not physics_path.exists():
        print(f"[ERROR] Physics dataset not found: {physics_path}")
        print("        Run run_48h_continuous() or run_24h_sweep() first.")
        return

    if not network_path.exists():
        print(f"[ERROR] Network dataset not found: {network_path}")
        print("        Run gateway.py with network_logger enabled first.")
        return

    physics = load_physics(physics_path, args.nrows)
    network = load_network(network_path, args.nrows)
    net_1hz = downsample_network_to_1hz(network)
    merged  = merge(physics, net_1hz)
    validate_merge(merged)

    merged.to_csv(out_path, index=False)
    print(f"[merge] Saved → {out_path}")

    write_metadata(merged, physics_path, network_path, out_path)
    print("\n[merge] Done. Run ML pipeline with:")
    print(f"        python cgd_ids_pipeline.py --data {out_path}")


if __name__ == "__main__":
    main()
