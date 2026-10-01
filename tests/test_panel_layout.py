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

# the fake game's armors (ids 0x7000 + n) get long, real-looking names (the worn-armor weight row)
picker.armor_names = lambda: {0x7000 + n: "KDM-%d %s Commando" % (700 + n, v[0].split(",")[0])
                              for n, (k, v) in enumerate(picker.CATALOG.items())}
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
    H = g.res()[1]
    regs = {k: (x, H - (y + h), x + w, H - y) for k, (x, y, w, h, _) in g.regions().items()}
    probs = []
    px0, py0, px1, py1 = regs["panel"]
    sw, sh = g.res()
    if px0 < 0 or py0 < 0 or px1 > sw or py1 > sh:
        probs.append("panel does not fit the %dx%d screen" % (sw, sh))
    # sharp text: every rectangle edge, text position and font size on a whole pixel
    for c in g.draw_calls():
        nums = tuple(c[1:3]) + ((c[4], c[5]) if c[0] == b"rect" else (c[4],))
        if any(abs(v - round(v)) > 1e-6 for v in nums):
            probs.append("not on whole pixels: %s %r" % (c[0].decode(), c[5] if c[0] == b"text" else nums))
            break
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
FIRST = picker.load_config_text(sink)[1][0]["perk"]          # tab 1's passive: the test wears its armor

# (text measurement, screen, panel_scale): 1080p both ways, 1440p, 4K, smallest and
# largest panel (1.5 on 1080p is capped so the panel still fits the screen)
CONFIGS = [("measured", (1920, 1080), 1.0), ("estimated", (1920, 1080), 1.0),
           ("measured", (2560, 1440), 1.0), ("estimated", (2560, 1440), 1.2),
           ("measured", (3840, 2160), 1.5), ("measured", (1920, 1080), 0.8),
           ("measured", (1920, 1080), 1.5), ("measured", (1280, 720), 1.0)]

for measure_mode, (rw, rh), scale in CONFIGS:
    mode = "%s %dx%d %d%%" % (measure_mode, rw, rh, scale * 100)
    path = build(sink.replace("[settings]", "[settings]\npanel_scale = %.1f" % scale, 1))
    g = FakeGame(path, appdata=tempfile.mkdtemp())
    g.set_resolution(rw, rh)
    if measure_mode == "estimated":
        g.L.execute(b"stingray.Gui.text_extents = nil")
    g.wear(FIRST)
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
    g.click("tab:1")
    g.click("sel:summary")
    views.append(("stack summary", layout_problems(g)))
    g.click("sel:weight")
    g.click("weight:heavy")
    views.append(("armor weight", layout_problems(g)))
    if "aw:light" not in g.regions():
        failed.append("%s: no weight row for the worn armor" % mode)
    else:
        g.click("aw:light")
        views.append(("armor weight, the worn armor light", layout_problems(g)))
    g.click("tab:1")
    g.click("remove")
    views.append(("remove: click again", layout_problems(g)))
    g.click("add")
    views.append(("+ Armor", layout_problems(g)))
    g.reveal("addpick:6")
    x, y, w, h, _ = g.regions()["addpick:6"]
    g.move_to(x + w / 2, g.res()[1] - (y + h / 2))
    views.append(("+ Armor, pointing at Engineering Kit", layout_problems(g)))
    g.click("search")
    g.type_text("padding")
    views.append(("+ Armor, searching", layout_problems(g)))
    g.key(0x1B)
    g.click("addpick:16")
    views.append(("second stack", layout_problems(g)))
    g.click("search")
    g.type_text("qqq")
    views.append(("search, nothing found", layout_problems(g)))
    g.key(0x1B)
    g.click("settings")
    views.append(("Keys tab", layout_problems(g)))
    g.pad_connect()
    g.tick(70)
    g.pad("DOWN")
    g.pad("DOWN")
    views.append(("controller: focus box and button hints", layout_problems(g)))
    g.pad("LB")
    g.pad("LB")
    views.append(("controller: a message with the button hints", layout_problems(g)))
    g.pad_connect(False)
    g.move_to(5, 5)
    for name, probs in views:
        check(not probs, "%s / %s%s" % (mode, name, ("\n        " + "\n        ".join(probs)) if probs else ""))

# many armor stacks with long names: the tabs share the row without overlapping
many = "[settings]\nname = many\n" + "".join("[profile: %s]\nScout = on\n" % n for n in (
    "Concussive Padding, Reinforced", "Concussive Padding, Grenadier", "Kinetic Displacement Mitigation",
    "Supplemental Adrenaline", "Integrated Explosives", "Adreno-Defibrillator"))
for measure_mode, res in (("measured", (1920, 1080)), ("estimated", (1280, 720))):
    g = FakeGame(build(many), appdata=tempfile.mkdtemp())
    g.set_resolution(*res)
    if measure_mode == "estimated":
        g.L.execute(b"stingray.Gui.text_extents = nil")
    g.tick(420)
    g.key(F7)
    g.tick(120)
    probs = layout_problems(g)
    regs = g.regions()
    check(not probs and (all("tab:%d" % n in regs for n in range(1, 7)) or "tabs:next" in regs),
          "%s %dx%d / 6 armor tabs with long names: all shown, or < > to reach them%s" % (measure_mode, res[0], res[1],
                                                          ("\n        " + "\n        ".join(probs)) if probs else ""))

# Passive Swap edition (the Nexus build): its own views
swap_lua = tempfile.mktemp(suffix=".lua")
_s, _ = picker.load_config_text("[settings]\nname = x\n[profile: Med-Kit]\n")
with open(swap_lua, "w", encoding="utf-8") as f:
    f.write(picker.compile_loadout(_s, [], blank=True, swap_only=True))
medkit = next(k for k, v in picker.CATALOG.items() if v[0] == "Med-Kit")
for res in ((1920, 1080), (1280, 720)):
    mode = "swap edition %dx%d" % res
    g = FakeGame(swap_lua, appdata=tempfile.mkdtemp())
    g.set_resolution(*res)
    g.tick(420)
    g.key(F7)
    g.tick(120)
    views = [("empty", layout_problems(g))]
    g.click("add")
    views.append(("+ Armor", layout_problems(g)))
    g.click("addpick:%d" % medkit)
    views.append(("original", layout_problems(g)))
    for pid in (longest, most):
        if "swap:%d" % pid not in g.regions():
            g.click("scroll:down") if "scroll:down" in g.regions() else None
        if "swap:%d" % pid in g.regions():
            g.click("swap:%d" % pid)
            views.append(("swapped to %d" % pid, layout_problems(g)))
    g.click("presets")
    g.click("psave")
    views.append(("presets, naming", layout_problems(g)))
    for name, probs in views:
        check(not probs, "%s / %s%s" % (mode, name, ("\n        " + "\n        ".join(probs)) if probs else ""))

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall layout checks passed")
