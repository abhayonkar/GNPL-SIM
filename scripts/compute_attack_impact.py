"""
compute_attack_impact.py — Attack Impact Quantification for Paper 1 Table I
=============================================================================
For each attack type (A1–A10), compute:
  - Maximum pressure deviation from normal baseline
  - Primary affected node
  - Mean flow deviation on the most impacted edge
  - Number of timesteps in the attack window

Output: reports/attack_impact_table.csv

Usage:
    python scripts/compute_attack_impact.py
    python scripts/compute_attack_impact.py --data automated_dataset/attack_windows/physics_dataset_windows.csv
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

SCRIPT_DIR = Path(__file__).parent
SIM_ROOT   = SCRIPT_DIR.parent

ATTACK_NAMES = {
    0: "Normal",       1: "SourceSpike",  2: "CompRamp",    3: "ValveForce",
    4: "DemandInject", 5: "PressureSpoof", 6: "FlowSpoof",  7: "PLCLatency",
    8: "PipeLeak",     9: "FDI_Stealthy", 10: "ReplayAttack",
}

NODE_NAMES = ["S1","J1","CS1","J2","J3","J4","CS2","J5","J6","PRS1",
              "J7","STO","PRS2","S2","D1","D2","D3","D4","D5","D6"]
EDGE_NAMES = [f"E{i}" for i in range(1, 21)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default=str(
        SIM_ROOT / "automated_dataset/attack_windows/physics_dataset_windows.csv"))
    parser.add_argument("--out",  default=str(SIM_ROOT / "reports/attack_impact_table.csv"))
    args = parser.parse_args()

    print(f"[impact] Loading {args.data}")
    df = pd.read_csv(args.data, low_memory=False)
    print(f"         {len(df):,} rows x {df.shape[1]} cols")

    if "ATTACK_ID" not in df.columns:
        sys.exit("[impact] ERROR: ATTACK_ID column not found.")

    p_cols = [c for c in df.columns if c.startswith("p_") and c.endswith("_bar")]
    q_cols = [c for c in df.columns if c.startswith("q_") and c.endswith("_kgs")]

    if not p_cols:
        sys.exit("[impact] ERROR: no pressure columns (p_*_bar) found.")

    normal = df[df["ATTACK_ID"] == 0]
    if len(normal) == 0:
        sys.exit("[impact] ERROR: no normal (ATTACK_ID=0) rows found.")

    p_normal_mean = normal[p_cols].mean()
    p_normal_std  = normal[p_cols].std().clip(lower=1e-6)
    q_normal_mean = normal[q_cols].mean() if q_cols else None

    results = []
    for aid in sorted(df["ATTACK_ID"].unique()):
        if aid == 0:
            continue
        atk = df[df["ATTACK_ID"] == aid]
        if len(atk) == 0:
            continue

        # Pressure deviation from normal mean
        p_dev = (atk[p_cols] - p_normal_mean).abs()
        max_p_dev    = float(p_dev.max().max())
        primary_node = p_dev.max().idxmax()  # column name with largest max deviation
        mean_p_dev   = float(p_dev.mean().mean())

        # Normalised deviation (sigma units)
        p_dev_norm = (atk[p_cols] - p_normal_mean) / p_normal_std
        max_sigma  = float(p_dev_norm.abs().max().max())

        # Flow deviation (if flow columns present)
        max_q_dev  = float("nan")
        primary_edge = ""
        if q_cols and q_normal_mean is not None:
            q_dev        = (atk[q_cols] - q_normal_mean).abs()
            max_q_dev    = float(q_dev.max().max())
            primary_edge = q_dev.max().idxmax()

        # Convert column names to friendly node/edge labels
        node_label = primary_node.replace("p_", "").replace("_bar", "")
        edge_label = primary_edge.replace("q_", "").replace("_kgs", "")

        results.append({
            "attack_id":            int(aid),
            "attack_name":          ATTACK_NAMES.get(int(aid), f"A{aid}"),
            "n_samples":            len(atk),
            "max_pressure_dev_bar": round(max_p_dev, 4),
            "mean_pressure_dev_bar":round(mean_p_dev, 4),
            "max_sigma":            round(max_sigma, 2),
            "primary_node":         node_label,
            "max_flow_dev_kgs":     round(max_q_dev, 4) if not np.isnan(max_q_dev) else "",
            "primary_edge":         edge_label,
        })

    out_df = pd.DataFrame(results)
    print("\n[impact] Attack impact table:")
    print(out_df.to_string(index=False))

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_df.to_csv(out_path, index=False)
    print(f"\n[impact] Saved -> {out_path}")


if __name__ == "__main__":
    main()
