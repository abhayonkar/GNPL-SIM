import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).parent.parent / "ml_pipeline"))

from cgd_ids_pipeline import engineer_features


def test_engineer_features_adds_timing_and_replay_columns():
    df = pd.DataFrame(
        {
            "Timestamp_s": [0, 1, 2, 3, 4, 5],
            "scenario_id": [1, 1, 1, 1, 1, 1],
            "source_config": ["both"] * 6,
            "demand_profile": ["peak"] * 6,
            "valve_config": ["auto"] * 6,
            "cs_mode": ["both_on"] * 6,
            "p_S1_bar": [20, 20.1, 20.2, 20.3, 20.2, 20.1],
            "q_E1_kgs": [1, 1.1, 1.2, 1.1, 1.0, 0.9],
        }
    )

    out = engineer_features(df, rolling=False)

    for col in [
        "delta_t_s",
        "time_sin",
        "time_cos",
        "regime_id_num",
        "source_config_code",
        "demand_profile_code",
        "valve_config_code",
        "cs_mode_code",
        "replay_pressure_autocorr",
        "replay_flow_autocorr",
    ]:
        assert col in out.columns

    assert out["delta_t_s"].iloc[0] == 0
