from pathlib import Path

import pandas as pd


DATASET = Path("automated_dataset/attack_windows/physics_dataset_windows.csv")
THROTTLE_ALIASES = {
    "PRS1": ["PRS1_throttle", "PRS1_Throttle", "PRS1Throttle", "logPRS1Throttle"],
    "PRS2": ["PRS2_throttle", "PRS2_Throttle", "PRS2Throttle", "logPRS2Throttle"],
}


def main() -> None:
    if not DATASET.exists():
        raise FileNotFoundError(f"Dataset not found: {DATASET}")

    header = pd.read_csv(DATASET, nrows=0).columns.tolist()
    selected = {"ATTACK_ID": "ATTACK_ID"}
    for canonical, aliases in THROTTLE_ALIASES.items():
        match = next((c for c in aliases if c in header), None)
        if match is None:
            lower_match = next(
                (c for c in header if c.lower() in {a.lower() for a in aliases}),
                None,
            )
            match = lower_match
        if match is not None:
            selected[canonical] = match

    missing = [c for c in ["ATTACK_ID", "PRS1", "PRS2"] if c not in selected]
    if missing:
        prs_like = [c for c in header if "prs" in c.lower() or "throttle" in c.lower()]
        print(f"[prs] Missing required PRS columns: {missing}")
        print(f"[prs] Available PRS/throttle-like columns: {prs_like}")
        print("[prs] VERDICT: unavailable on this dataset; regenerate attack windows after the exporter patch.")
        return

    df = pd.read_csv(DATASET, usecols=list(selected.values()))
    df = df.rename(columns={v: k for k, v in selected.items()})

    means = df.groupby("ATTACK_ID")[["PRS1", "PRS2"]].mean().sort_index()
    print("\n[prs] Mean throttle by ATTACK_ID")
    print(means.round(4).to_string())

    gaps = means.max(axis=0) - means.min(axis=0)
    max_col = gaps.idxmax()
    max_gap = float(gaps[max_col])
    print(f"\n[prs] Max class mean gap: {max_gap:.4f} ({max_col})")

    if max_gap > 0.5:
        print("[prs] VERDICT: likely leakage; add PRS throttle columns to broken features.")
    elif max_gap > 0.1:
        print("[prs] VERDICT: meaningful regime/control signal; inspect but likely keep.")
    else:
        print("[prs] VERDICT: no large class-separating throttle signal detected.")


if __name__ == "__main__":
    main()
