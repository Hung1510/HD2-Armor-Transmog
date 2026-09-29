#!/usr/bin/env python3
"""
Layout check for the in-game panel: no text overlaps other text, no label runs outside
its button, nothing is drawn outside the panel. Every view is checked twice: with real
text measurement, and with measurement failing (the panel then estimates widths, which
is what happens in game if Gui.text_extents is unavailable).

    python tests/test_panel_layout.py        (needs Pillow for font metrics; skipped without)
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
try:
    from PIL import ImageFont  # noqa: F401
except ImportError:
    print("Pillow not installed; layout check skipped")
    sys.exit(0)
import picker  # noqa: E402
from harness import FakeGame  # noqa: E402

F7, ENTER = 0x76, 0x0D
failed = []
# regions that hold several texts (whole rows, the panel), not single-label buttons
CONTAINERS = ("panel", "sel:", "pre:", "addpick:", "remove")


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def layout_problems(g):
    texts = g.text_boxes()
    regs = {k: (x, 1080 - (y + h), x + w, 1080 - y) for k, (x, y, w, h, _) in g.regions().items()}
    probs = []
    px0, py0, px1, py1 = regs["panel"]
    for t, x0, x1, y0, y1 in texts:
        if x0 < px0 - 1 or x1 > px1 + 1 or y0 < py0 - 1 or y1 > py1 + 1:
            probs.append("outside the panel: %r" % t)
    for i, a in enumerate(texts):
        for b in texts[i + 1:]:
            if a[0] == b[0] and abs(a[1] - b[1]) < 1 and abs(a[3] - b[3]) < 1:
                continue
            w = min(a[2], b[2]) - max(a[1], b[1])
            h = min(a[4], b[4]) - max(a[3], b[3])
            if w > 1 and h > 1:
                probs.append("text overlaps text: %r / %r" % (a[0], b[0]))
    for key, (rx0, ry0, rx1, ry1) in regs.items():
        if key.startswith(CONTAINERS):
            continue
        for t, x0, x1, y0, y1 in texts:
            cy = (y0 + y1) / 2
            if rx0 - 1 <= x0 < rx1 and ry0 <= cy <= ry1 and x1 > rx1 + 1:
                probs.append("label runs out of %s: %r" % (key, t))
    for t, x0, x1, y0, y1 in texts:             # text spilling into a button it isn't in
        cy = (y0 + y1) / 2
        for key, (rx0, ry0, rx1, ry1) in regs.items():
            if key.startswith(CONTAINERS) or not (ry0 <= cy <= ry1):
                continue
            if x0 < rx0 - 1 and x1 > rx0 + 1 and not (rx0 <= x0 < rx1):
                probs.append("text runs into %s: %r" % (key, t))
    return sorted(set(probs))


def build(text):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p))
    return path


sink = open(os.path.join(ROOT, "presets", "01-kitchen-sink.ini"), encoding="utf-8").read()
path = build(sink)

for mode in ("measured", "estimated"):
    g = FakeGame(path, appdata=tempfile.mkdtemp())
    if mode == "estimated":
        g.L.execute(b"stingray.Gui.text_extents = nil")
    g.tick(420)
    g.key(F7)
    g.tick(120)
    views = []
    longest = max(picker.CATALOG, key=lambda k: len(picker.CATALOG[k][0]))
    most = max(picker.CATALOG, key=lambda k: len(picker.CATALOG[k][1]) + len(picker.CATALOG[k][2]))
    for pid in (11, 16, 9, 7, longest, most):    # short and long names, many values, base perk
        g.click("sel:%d" % pid)
        views.append(("passive %d" % pid, layout_problems(g)))
    g.click("inc_big:1")
    g.click("value:1")
    g.type_text("12345")
    views.append(("typing a value", layout_problems(g)))
    g.key(ENTER)
    g.click("clear")
    views.append(("confirm Turn all off", layout_problems(g)))
    g.click("presets")
    views.append(("presets, nothing chosen", layout_problems(g)))
    g.click("pre:builtin:1")
    views.append(("presets, Kitchen Sink", layout_problems(g)))
    g.click("psave")
    g.type_text("A Very Long Loadout Name 99")
    views.append(("naming a preset", layout_problems(g)))
    g.key(ENTER)
    g.click("pdel")
    views.append(("confirm delete", layout_problems(g)))
    g.click("add")
    views.append(("+ Armor", layout_problems(g)))
    g.click("addpick:16")
    views.append(("second stack", layout_problems(g)))
    for name, probs in views:
        check(not probs, "%s / %s%s" % (mode, name, ("\n        " + "\n        ".join(probs)) if probs else ""))

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall layout checks passed")
