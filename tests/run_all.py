#!/usr/bin/env python3
"""
Run every test suite and print one summary.

    python tests/run_all.py            # all suites
    python tests/run_all.py -v         # also print each suite's output
    python tests/run_all.py scroll     # only suites whose file name contains "scroll"

Each suite is a plain script that prints "ok    ..." / "FAIL  ..." per check and exits
non-zero on failure, so any of them can also be run on its own.
Needs: pip install lupa pillow, and Node.js for the web builder parity suite.
"""
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SUITES = [
    ("test_ingame.py", "engine + panel against a fake game (LuaJIT)"),
    ("test_panel_features.py", "presets, quick-swap, undo, share codes, units"),
    ("test_panel_layout.py", "no overlapping or clipped text, 720p to 4K"),
    ("test_panel_scale.py", "panel size, whole-pixel drawing"),
    ("test_panel_scroll_drag.py", "scrolling lists, dragging the panel"),
    ("test_panel_keys_search.py", "Keys tab, bad-key fallback, search"),
    ("test_controller.py", "controller: open, navigate, tabs, back"),
    ("test_passive_info.py", "passive info, stack summary, Remove armor"),
    ("test_report_share.py", "panel off, short share codes, problem report"),
    ("test_research.py", "research build: armor kit dump, weight experiment"),
    ("test_swap_edition.py", "Passive Swap edition (Nexus build)"),
    ("test_release.py", "release zips, blank install, old saves"),
    ("test_web_parity.js", "web builder output is byte-identical to Python"),
]
CHECK = re.compile(r"^(ok|FAIL)\s{2,}", re.M)


def run(name):
    cmd = ["node", name] if name.endswith(".js") else [sys.executable, name]
    if cmd[0] == "node" and not shutil.which("node"):
        return None, 0, 0, "node not installed; skipped", 0.0
    t0 = time.time()
    r = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
    out = r.stdout + r.stderr
    marks = CHECK.findall(out)
    return r.returncode, marks.count("ok"), marks.count("FAIL"), out, time.time() - t0


def main(argv):
    verbose = "-v" in argv
    only = [a for a in argv if not a.startswith("-")]
    suites = [s for s in SUITES if not only or any(o in s[0] for o in only)]
    total_ok = total_fail = 0
    failed = []
    print("%-28s %6s %5s %7s  %s" % ("suite", "checks", "fail", "time", "covers"))
    print("-" * 100)
    for name, what in suites:
        code, ok, fail, out, dt = run(name)
        if verbose or code not in (0, None):
            print(out)
        if code is None:
            print("%-28s %6s %5s %7s  %s" % (name, "-", "-", "-", out))
            continue
        status = "" if code == 0 else "  <- FAILED"
        total_ok, total_fail = total_ok + ok, total_fail + fail
        if code != 0:
            failed.append(name)
        print("%-28s %6d %5d %6.1fs  %s%s" % (name, ok + fail, fail, dt, what, status))
    print("-" * 100)
    print("%d checks, %d failed, %d suite(s) failed" % (total_ok + total_fail, total_fail, len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
