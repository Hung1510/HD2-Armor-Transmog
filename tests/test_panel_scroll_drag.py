#!/usr/bin/env python3
"""
Long lists scroll and the panel can be dragged, driven like a player would.

    python tests/test_panel_scroll_drag.py

1. Every passive can be reached in the "+ Armor" list and in a stack's passive list,
   on a short screen and at a big panel size: mouse wheel, the bar's arrows and track,
   PageUp / PageDown. (Reported: True Grit could not be picked as a base armor.)
2. The top strip drags the panel; it stays on the screen, the spot is saved and comes
   back after a restart, Ctrl 0 puts it back.
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import picker  # noqa: E402
from harness import FakeGame  # noqa: E402

F7, CTRL, ZERO, PGDN, PGUP = 0x76, 0x11, 0x30, 0x22, 0x21
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def build(text):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p))
    return path


def keys_like(g, prefix):
    return {k for k in g.regions() if k.startswith(prefix)}


def open_game(text, res=(1920, 1080), appdata=None):
    g = FakeGame(build(text), appdata=appdata or tempfile.mkdtemp())
    g.set_resolution(*res)
    g.tick(420)
    g.key(F7)
    g.tick(120)
    return g


sink = open(os.path.join(ROOT, "presets", "01-kitchen-sink.ini"), encoding="utf-8").read()
blank = "[settings]\npanel_scale = %s\n[profile: Med-Kit]\n"
ALL = set(picker.CATALOG)
medkit = next(k for k, v in picker.CATALOG.items() if v[0].lower() == "med-kit")
true_grit = next(k for k, v in picker.CATALOG.items() if v[0].lower() == "true grit")

# ------------------------------------------------------------------ 1. scrolling
for res, scale in (((1280, 720), "1.0"), ((1920, 1080), "1.5"), ((3440, 1440), "1.0")):
    tag = "%dx%d at %s" % (res[0], res[1], scale)
    g = open_game(blank % scale, res)
    g.click("add")
    seen = {int(k.split(":")[1]) for k in keys_like(g, "addpick:")}
    has_bar = "scroll:down" in g.regions()
    check(has_bar == (seen != ALL - {medkit}), "%s: + Armor shows a scroll bar only when the list does not fit" % tag)
    for _ in range(40):
        if "scroll:down" not in g.regions():
            break
        g.scroll_wheel("addpick:%d" % next(iter(int(k.split(':')[1]) for k in keys_like(g, "addpick:"))), -1)
        seen |= {int(k.split(":")[1]) for k in keys_like(g, "addpick:")}
    check(seen - {picker.EVERY} == ALL - {medkit} and picker.EVERY in seen, "%s: the mouse wheel reaches every armor passive in + Armor (%d/%d, plus Every armor)" % (tag, len(seen - {picker.EVERY}), len(ALL) - 1))
    if "addpick:%d" % true_grit in g.regions():
        g.click("addpick:%d" % true_grit)
        check(any("True Grit" in t or "TRUE GRIT" in t for t in g.texts()), "%s: True Grit can be picked as a base armor" % tag)
    else:
        check(False, "%s: True Grit visible after scrolling" % tag)

# the passive list of a stack, on a short screen
g = open_game(sink, (1280, 720))
g.click("tab:1")
seen = {int(k.split(":")[1]) for k in keys_like(g, "tick:")}
check("scroll:down" in g.regions() or len(seen) == len(ALL) - 1, "720p: the passive list scrolls when it does not fit")
first_view = set(seen)
for _ in range(20):
    if "scroll:down" not in g.regions():
        break
    g.click("scroll:down")
    seen |= {int(k.split(":")[1]) for k in keys_like(g, "tick:")}
check(len(seen) == len(ALL) - 1, "720p: the down arrow reaches every passive (%d/%d)" % (len(seen), len(ALL) - 1))
for _ in range(3):
    g.key(PGUP)
check({int(k.split(":")[1]) for k in keys_like(g, "tick:")} == first_view, "PageUp goes back to the top")
g.key(PGDN)
check({int(k.split(":")[1]) for k in keys_like(g, "tick:")} != first_view, "PageDown moves down a page")
if "scroll:pgup" in g.regions():
    g.click("scroll:pgup")
check("scroll:up" in g.regions(), "the bar has an up arrow")
# ticking the last passive works after scrolling
for _ in range(20):
    if "scroll:pgdn" not in g.regions():
        break
    g.click("scroll:pgdn")
last = [c for c in picker.CATALOG if "tick:%d" % c in g.regions()]
lid = last[-1]
before = g.state[b"ui"][b"version"]
g.click("tick:%d" % lid)
check(g.state[b"ui"][b"version"] != before, "a passive at the bottom of the list can be ticked")
g.render(os.path.join(tempfile.gettempdir(), "af-scroll-720.png"))

# ------------------------------------------------------------------ 2. dragging
appdata = tempfile.mkdtemp()
g = open_game(sink, (2560, 1440), appdata)
x0, y0, w, h, _ = g.regions()["panel"]
check("drag" in g.regions(), "the top strip is a drag handle")
g.drag("drag", 600, -40)
x1, y1, _, _, _ = g.regions()["panel"]
check(abs((x1 - x0) - 600) <= 2 and abs((y1 - y0) - 40) <= 2, "dragging the strip moves the panel (%+d, %+d px)" % (x1 - x0, y1 - y0))
check(any(t == "100%" for t in g.texts()), "dragging does not change the size")
g.drag("drag", 99999, 99999)
x2, y2, w2, h2, _ = g.regions()["panel"]
check(x2 + w2 <= 2560 and y2 >= 0 and x2 >= 0, "the panel stays on the screen when dragged past the edge")
before_hist = len(g.state[b"ui"][b"history"])
g.click("drag")
check(g.regions()["panel"][:2] == (x2, y2) and len(g.state[b"ui"][b"history"]) == before_hist,
      "a click on the strip without moving does nothing")
g.drag("drag", -300, 0)
x3, y3, _, _, _ = g.regions()["panel"]
saved = open(os.path.join(appdata, "CowboyBingus", "Helldivers2", "ArmoryForge", "panel-position.txt")).read()
check("x =" in saved and "y =" in saved, "the spot is saved to panel-position.txt")
g.key(F7)
g.tick(10)
g2 = open_game(sink, (2560, 1440), appdata)
check(g2.regions()["panel"][:2] == (x3, y3), "the panel opens where you left it after a restart")
g2.render(os.path.join(tempfile.gettempdir(), "af-dragged.png"))
g3 = open_game(sink, (1920, 1080), appdata)
px, py, pw, ph, _ = g3.regions()["panel"]
check(px >= 0 and py >= 0 and px + pw <= 1920 and py + ph <= 1080, "a saved spot still fits a smaller screen")
g2.ctrl(ZERO)
check(g2.regions()["panel"][:2] == (x0, y0), "Ctrl 0 puts the panel back in place")
check(any("back in place" in t for t in g2.texts()), "a message says so")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall scroll and drag checks passed")
