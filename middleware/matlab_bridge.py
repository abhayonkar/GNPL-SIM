"""
matlab_bridge.py - Python wrapper for MATLAB-based simulator calls.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


class MatlabBridge:
    """
    Minimal subprocess-based MATLAB bridge for near-real-time integration.

    The bridge writes a JSON payload to a temp file and asks MATLAB to run a
    function that consumes that payload and emits a JSON result file.
    """

    def __init__(self, matlab_exe: str = "matlab", timeout_s: float = 10.0):
        self.matlab_exe = matlab_exe
        self.timeout_s = float(timeout_s)

    def available(self) -> bool:
        return shutil.which(self.matlab_exe) is not None

    def call(self, matlab_function: str, payload: dict[str, Any]) -> tuple[dict[str, Any], float]:
        if not self.available():
            raise RuntimeError(f"MATLAB executable '{self.matlab_exe}' not found on PATH.")

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            in_path = tmp / "payload.json"
            out_path = tmp / "result.json"
            in_path.write_text(json.dumps(payload), encoding="utf-8")

            matlab_cmd = (
                "try, "
                f"{matlab_function}('{in_path.as_posix()}','{out_path.as_posix()}'); "
                "catch ME, disp(getReport(ME,'extended')); exit(1); end; exit(0);"
            )

            start = time.perf_counter()
            subprocess.run(
                [self.matlab_exe, "-batch", matlab_cmd],
                check=True,
                timeout=self.timeout_s,
            )
            latency_ms = (time.perf_counter() - start) * 1000.0

            if not out_path.exists():
                raise RuntimeError(f"MATLAB function '{matlab_function}' did not produce {out_path}.")

            return json.loads(out_path.read_text(encoding="utf-8")), latency_ms
