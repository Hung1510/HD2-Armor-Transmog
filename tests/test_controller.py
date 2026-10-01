#!/usr/bin/env python3
"""
Controller support, driven with a fake Xbox-style controller only (no mouse, no keyboard).

    python tests/test_controller.py

1. Back + Start opens and closes the panel; nothing happens without a controller.
2. D-pad moves a focus box between buttons, lists scroll under it, A presses, Y ticks the
   chosen passive, X undoes, LB / RB switch tabs, B goes back and finally closes.
3. Moving the mouse hands control back to the mouse.
4. The Passive Swap edition and the Keys tab work the same way.
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

failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def pid_of(name):
    return next(k for k, v in picker.CATALOG.items() if v[0].lower() == name.lower())


def build(text, **kw):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p, **kw))
    return path


def ui(g, key):
    v = g.state[b"ui"][key.encode()]
    return v.decode() if isinstance(v, bytes) else v


def is_open(g):
    return bool(ui(g, "open"))


def focus_box(g):
    """The yellow focus outline: rects drawn at z 957."""
    return [c for c in g.draw_calls() if c[0] == b"rect" and c[3] == 957]


def steer(g, key, tries=40):
    """Press the D-pad towards `key` until it has the focus, like a player would."""
    for _ in range(tries):
        f = ui(g, "focus")
        if f == key:
            return True
        regs = g.regions()
        if f not in regs or key not in regs:
            g.pad("DOWN")
            continue
        fx, fy, fw, fh, _ = regs[f]
        tx, ty, tw, th, _ = regs[key]
        dx, dy = (tx + tw / 2) - (fx + fw / 2), (ty + th / 2) - (fy + fh / 2)
        if abs(dy) > abs(dx) and abs(dy) > 2:
            g.pad("UP" if dy > 0 else "DOWN")
        else:
            g.pad("RIGHT" if dx > 0 else "LEFT")
    return ui(g, "focus") == key


sink = open(os.path.join(ROOT, "presets", "01-kitchen-sink.ini"), encoding="utf-8").read()
g = FakeGame(build(sink), appdata=tempfile.mkdtemp())
g.tick(420)

# ------------------------------------------------------------------ 1. open / close
g.pad("BACK", "START")
check(not is_open(g), "without a controller connected, nothing happens")
g.pad_connect()
g.tick(70)                                    # the empty-slot probe runs every 60 frames
g.pad("BACK", "START")
g.tick(120)
check(is_open(g), "Back + Start opens the panel")
check(any(t == "SELECT" for t in g.texts()) and any(t == "LB/RB" for t in g.texts()),
      "the prompt bar shows the controller buttons")

# ------------------------------------------------------------------ 2. navigation
g.pad("DOWN")
f0 = ui(g, "focus")
check(f0 is not None and f0.startswith("sel:"), "the first D-pad press puts the focus on the list (%s)" % f0)
check(len(focus_box(g)) == 4, "a focus box is drawn around it")
g.pad("DOWN")
f1 = ui(g, "focus")
check(f1 != f0 and f1.startswith(("sel:", "tick:")), "D-pad down moves to the next row (%s)" % f1)
g.pad("A")
sel = ui(g, "sel")
check(f1.startswith("sel:") and str(sel) == f1.split(":")[1] or f1.startswith("tick:"),
      "A presses the focused row (selected passive %s)" % sel)
# hold down: the list scrolls under the focus until the last passive
g.pad_hold("DOWN", 6)
check("sel:%d" % pid_of("True Grit") in g.regions(), "holding down scrolls the list to the last passive")
fl = ui(g, "focus")
check(fl in ("sel:%d" % pid_of("True Grit"), "tick:%d" % pid_of("True Grit")) or (fl or "").startswith(("sel:", "tick:")),
      "the focus stays in the list while it scrolls (%s)" % fl)
g.pad("A")
before = g.state[b"ui"][b"version"]
g.pad("Y")
check(g.state[b"ui"][b"version"] != before, "Y ticks / unticks the chosen passive")
g.pad("X")
check(any("Undone" in t for t in g.texts()), "X undoes")

# tabs
g.pad("RB")
check(ui(g, "adding"), "RB goes to the next tab (+ Armor)")
g.pad("RB")
check(ui(g, "presets"), "RB again: Presets")
g.pad("RB")
check(ui(g, "settings"), "RB again: Keys")
g.pad("LB")
check(ui(g, "presets"), "LB goes back a tab")
g.pad("B")
check(not ui(g, "presets") and is_open(g), "B leaves Presets")
g.pad("B")
check(not is_open(g), "B on an armor tab closes the panel")

# ------------------------------------------------------------------ 3. the mouse takes over again
g.pad("BACK", "START")
g.tick(120)
g.pad("DOWN")
check(ui(g, "pad_mode") and len(focus_box(g)) == 4, "controller mode after a D-pad press")
g.move_to(200, 300)
g.move_to(260, 360)
check(not ui(g, "pad_mode") and len(focus_box(g)) == 0, "moving the mouse hides the focus box")
g.pad("BACK", "START")
check(not is_open(g), "Back + Start closes the panel")

# ------------------------------------------------------------------ 4. swap edition, Keys tab
g2 = FakeGame(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True, swap_only=True), appdata=tempfile.mkdtemp())
g2.tick(420)
g2.pad_connect()
g2.tick(70)
g2.pad("BACK", "START")
g2.tick(120)
g2.pad("DOWN")
for _ in range(40):                           # walk down to Siege-Ready
    if ui(g2, "focus") == "swap:%d" % pid_of("Siege-Ready"):
        break
    g2.pad("DOWN")
g2.pad("A")
check(g2.rows(pid_of("Med-Kit")) == g2.rows(pid_of("Siege-Ready")), "swap edition: D-pad + A swaps Med-Kit armor to Siege-Ready")

g2.pad("RB")
g2.pad("RB")
g2.pad("RB")                                   # + Armor, Presets, Keys
check(ui(g2, "settings"), "RB reaches the Keys tab")
check(steer(g2, "key:hotkey:F6"), "the D-pad reaches F6 in the key grid")
g2.pad("A")
check(any("opens with F6" in t for t in g2.texts()), "the panel key can be changed with the controller")

# ------------------------------------------------------------------ 5. found in review
# B closes the panel without leaving a copy of it on screen
g3 = FakeGame(build(sink), appdata=tempfile.mkdtemp())
g3.tick(420)
g3.pad_connect()
g3.tick(70)
g3.pad("BACK", "START")
g3.tick(120)
g3.pad("B")
g3.tick(60)
check(not is_open(g3) and g3.state[b"ui"][b"gui"] is None and len(g3.draw_calls()) == 0,
      "B closes the panel and nothing is left drawn")
check(g3.state[b"ui"][b"errors"] == 0, "... without a panel error")

# LB / RB reach every tab at any size (tab height in pixels grows with the screen)
for res, scale in (((3840, 2160), "1.0"), ((2560, 1440), "1.5")):
    g4 = FakeGame(build(sink.replace("[settings]", "[settings]\npanel_scale = %s" % scale, 1)), appdata=tempfile.mkdtemp())
    g4.set_resolution(*res)
    g4.tick(420)
    g4.pad_connect()
    g4.tick(70)
    g4.pad("BACK", "START")
    g4.tick(120)
    seen = []
    for _ in range(5):
        g4.pad("RB")
        st = ui(g4, "settings")
        seen.append("guide" if st == "guide" else "keys" if st else "presets" if ui(g4, "presets") else "add" if ui(g4, "adding")
                    else "armor")
    check(seen == ["add", "presets", "keys", "guide", "armor"],
          "%dx%d at %s: RB cycles + Armor, Presets, Keys, Guide, armor (%s)" % (res[0], res[1], scale, seen))

# reopening with the controller after the mouse moved keeps controller mode
g5 = FakeGame(build(sink), appdata=tempfile.mkdtemp())
g5.tick(420)
g5.pad_connect()
g5.tick(70)
g5.pad("BACK", "START")
g5.tick(120)
g5.pad("DOWN")
g5.pad("BACK", "START")
g5.move_to(700, 500)
g5.move_to(900, 700)
g5.pad("BACK", "START")
g5.tick(120)
check(ui(g5, "pad_mode") and any(t == "SELECT" for t in g5.texts()), "reopened with the controller: controller mode, controller hints")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall controller checks passed")
