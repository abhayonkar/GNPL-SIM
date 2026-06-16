"""
scripts/verify_fix_status.py
=============================
Reads actual MATLAB source files and confirms which fixes are applied.
Checks code content, not just "did I apply it" -- catches cases where
fix was described but not saved correctly.

Run from project root:
    python scripts/verify_fix_status.py
"""

from pathlib import Path

CHECKS = [
    {
        "name": "Fix 5 -- updateLogs normalizes by sigma",
        "file": "logging/updateLogs.m",
        "must_contain": ["noise_sigma_p", "noise_sigma_q"],
        "must_not_contain": [],
        "description": "logResP /= sigma_p; logResQ /= sigma_q"
    },
    {
        "name": "Fix 6a -- runSimulation CUSUM uses R_sigma",
        "file": "runSimulation.m",
        "must_contain": ["R_sigma", "ekf.residual ./ R_sigma"],
        "must_not_contain": ["updateCUSUM(cusum, ekf.residual, cfg, k)"],
        "description": "cusum = updateCUSUM(cusum, ekf.residual ./ R_sigma, cfg, k)"
    },
    {
        "name": "Fix 6b -- simConfig cusum_slack=3.5",
        "file": "config/simConfig.m",
        "must_contain": ["cusum_slack         = 3.5"],
        "must_not_contain": ["cusum_slack         = 2.5"],
        "description": "cfg.cusum_slack = 3.5 (was 2.5)"
    },
    {
        "name": "Fix 7 -- attack_plan_to_schedule populates label_id",
        "file": "run_48h_continuous.m",
        "must_contain": ["schedule.label_id(k_s:k_e)"],
        "must_not_contain": [],
        "description": "schedule.label_id set inside attack loop"
    },
    {
        "name": "Fix 3 -- run_48h_continuous label=int32(aid>0) only",
        "file": "run_48h_continuous.m",
        "must_contain": ["label = int32(aid > 0)"],
        "must_not_contain": ["fault_label > 0 || aid > 0", "fault_label>0 || aid>0"],
        "description": "label excludes fault_label"
    },
    {
        "name": "Fix 8 -- verifyNoiseStats uses p_/q_ column patterns",
        "file": "processing/verifyNoiseStats.m",
        "must_contain": ["startsWith(all_vars, 'p_')", "startsWith(all_vars, 'q_')"],
        "must_not_contain": ["contains(all_vars, 'pressure_bar')"],
        "description": "column detection uses startsWith not contains"
    },
    {
        "name": "FIXED PARAM -- simConfig ekf_P0_diag=1000",
        "file": "config/simConfig.m",
        "must_contain": ["ekf_P0_diag    = 1000.0"],
        "must_not_contain": ["ekf_P0_diag    = 0.01"],
        "description": "P0=1000 (should already be set)"
    },
    {
        "name": "Fix 1 -- initEKF uses heterogeneous R",
        "file": "scada/initEKF.m",
        "must_contain": ["noise_sigma_p^2", "noise_sigma_q^2"],
        "must_not_contain": [],
        "description": "R_p=sigma_p^2, R_q=sigma_q^2"
    },
]


def check_fix(check: dict) -> tuple:
    path = Path(check["file"])
    if not path.exists():
        return False, f"FILE NOT FOUND: {path}"

    content = path.read_text(encoding="utf-8", errors="replace")

    missing = [p for p in check["must_contain"] if p not in content]
    wrong   = [p for p in check["must_not_contain"] if p in content]

    if missing and wrong:
        return False, f"MISSING: {missing} | STILL PRESENT: {wrong}"
    elif missing:
        return False, f"MISSING pattern: {missing}"
    elif wrong:
        return False, f"WRONG pattern still present: {wrong}"
    else:
        return True, "OK"


def main():
    print("=" * 65)
    print("  FIX STATUS VERIFICATION")
    print("=" * 65)

    passed = 0
    failed = 0
    missing_files = 0

    for check in CHECKS:
        ok, detail = check_fix(check)
        if "FILE NOT FOUND" in detail:
            icon = "[FILE]"
            missing_files += 1
        elif ok:
            icon = "[PASS]"
            passed += 1
        else:
            icon = "[FAIL]"
            failed += 1

        print(f"\n  {icon} {check['name']}")
        print(f"     File: {check['file']}")
        print(f"     Expected: {check['description']}")
        if not ok:
            print(f"     Status: {detail}")

    print("\n" + "=" * 65)
    print(f"  SUMMARY: {passed} PASS  |  {failed} FAIL  |  {missing_files} FILE NOT FOUND")
    print("=" * 65)

    if failed > 0:
        print("\n  CRITICAL: Apply failing fixes before running any sweep.")
        print("  Order: Fix 5 -> Fix 6a -> Fix 6b -> test_fix.m -> Fix 7 -> run_48h_sweep()")
    if missing_files > 0:
        print(f"\n  NOTE: {missing_files} files not found -- run from project root")


if __name__ == "__main__":
    main()
