"""Compare retained phase RTL against the published parent at every 720p pixel.

Usage: python tests/phase_four_fx_check.py [parent_transition_fx.v]
Only the parent's module identifier is changed for parallel elaboration.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> None:
    test_dir = Path(__file__).resolve().parent
    candidate = test_dir.parent / "A_display/rtl/transition_fx.v"
    parent = Path(sys.argv[1]) if len(sys.argv) > 1 else test_dir / "reference_four_fx/transition_fx_parent.v"
    bench = test_dir / "phase_four_fx_check.v"
    parent_bytes = parent.read_bytes()
    renamed, replacements = re.subn(
        rb"\bmodule\s+transition_fx\b",
        b"module transition_fx_phase_trim_parent",
        parent_bytes,
    )
    if replacements != 1:
        raise RuntimeError("Expected exactly one parent module declaration")
    with tempfile.TemporaryDirectory(prefix="phase_four_fx_check_") as work:
        work_dir = Path(work)
        reference = work_dir / "transition_fx_parent.v"
        reference.write_bytes(renamed)
        simulation = work_dir / "phase_four_fx_check.vvp"
        subprocess.run(
            ["D:/jcs/bin/iverilog.exe", "-g2012", "-s", "phase_four_fx_check", "-o", str(simulation),
             str(candidate), str(reference), str(bench)],
            check=True,
        )
        result = subprocess.run(["D:/jcs/bin/vvp.exe", str(simulation)], check=True,
                                capture_output=True, text=True)
    if "PHASE_NO_BLINDS_PASS checks=36864000 retained=4608000 disabled=32256000" not in result.stdout:
        raise RuntimeError("Missing expected pass marker: " + result.stdout)
    report = {
        "status": "PASS",
        "scope": "Actual candidate and parent transition_fx RTL; 1280x720 pixels; all 8 mode codes",
        "spreads": [128, 0, 17, 127, 255],
        "retained_mode_parent_equal_checks": 4608000,
        "disabled_mode_zero_checks": 32256000,
        "source_hashes": [
            {"path": str(path.resolve()), "sha256": sha256(path)}
            for path in [candidate, parent, bench, Path(__file__).resolve()]
        ],
        "stdout": result.stdout,
    }
    report_path = test_dir / "phase_four_fx_check_report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(result.stdout, end="")
    print("Report:", report_path)


if __name__ == "__main__":
    main()
