#!/usr/bin/env python3
"""Check completion markers as well as exit status (including async failures)."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
env = dict(os.environ, GTK_A11Y="none", GSK_RENDERER="cairo")
checks = [
    (["sqgicheck", "main.nut"], None),
    (["sqgicheck", "test/layout_tests.nut"], None),
    (["sqgi", "main.nut", "--self-test"], "[OK] all self-tests passed"),
    (["xvfb-run", "-a", "python3", "test/gtk_serial_test.py"], "GTK_SERIAL_PASS"),
    (["xvfb-run", "-a", "-s", "-screen 0 1600x1600x24", "sqgi", "test/layout_tests.nut"], "RFDTOOL_LAYOUT_PASS"),
]
for command, marker in checks:
    result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    print(result.stdout, flush=True)
    if result.returncode or (marker and marker not in result.stdout) or any(
        error in result.stdout for error in ("AN ERROR HAS OCCURRED", "RFDTOOL_LAYOUT_FAIL", "[gtk-test] error:")
    ):
        raise SystemExit(f"Check failed: {command}")
