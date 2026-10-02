#!/usr/bin/env python3
"""
Panel size (panel_scale) and sharp drawing, driven like a player would.

    python tests/test_panel_scale.py

1. panel_scale in [settings]: 0.8 .. 2.0 (or 80% .. 200%), same rules in picker.py and
   the web builder; the generated Lua is identical.
2. In game: Ctrl + / Ctrl - / Ctrl 0 and the [-] [+] buttons resize the panel in 10 % steps,
   capped at 80 % and 200 %; the size is saved, survives a restart and a preset load,
   and is not an undo step.
3. Up to 150 % the panel is drawn on whole pixels and always fits the screen, at 1080p,
   1440p and 4K.
4. 6.2.1: over 150 % on a small screen (1280x720) the panel is taller than the screen so its
   text is bigger; it starts at the top and the wheel outside a list scrolls it.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import picker  # noqa: E402
from harness import FakeGame  # noqa: E402

F7, CTRL, PLUS, MINUS, ZERO, NUM_PLUS = 0x76, 0x11, 0xBB, 0xBD, 0x30, 0x6B
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def node(js):
    r = subprocess.run(["node", "-e", js], capture_output=True, text=True, cwd=ROOT)
    return r.returncode, (r.stdout + r.stderr).strip()


def build(text):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p))
    return path, s


def ctrl(g, vk):
    keys = g.L.globals()[b"KEYS"]
    keys[CTRL] = True
    g.key(vk)
    keys[CTRL] = None
    g.tick(2)


def panel_px(g):
    x, y, w, h, _ = g.regions()["panel"]
    return w, h


def saved_scale(appdata):
    import glob
    f = glob.glob(os.path.join(appdata, "**", "loadout.ini"), recursive=True)
    if not f:
        return None
    for line in open(f[0], encoding="utf-8"):
        if line.startswith("panel_scale"):
            return line.split("=")[1].strip()
    return None


sink = open(os.path.join(ROOT, "presets", "01-kitchen-sink.ini"), encoding="utf-8").read()

# ------------------------------------------------------------------ 1. the setting
for val, want in (("0.8", 0.8), ("1.5", 1.5), ("120%", 1.2), ("1.25", 1.3), ("1", 1.0), ("2", 2.0), ("160%", 1.6)):
    s, _ = picker.load_config_text(sink.replace("[settings]", "[settings]\npanel_scale = %s" % val, 1))
    rc, out = node("""const core=require('./docs/core.js'),data=require('./docs/data.json'),cat=core.makeCatalog(data);
console.log(core.loadConfigText(cat,%s).settings.panel_scale)""" % json.dumps(sink.replace("[settings]", "[settings]\npanel_scale = %s" % val, 1)))
    check(abs(s["panel_scale"] - want) < 1e-9 and abs(float(out) - want) < 1e-9,
          "panel_scale = %s -> %.1f in picker.py and the web builder" % (val, want))
for bad in ("0.5", "2.1", "big", "210%"):
    try:
        picker.load_config_text("[settings]\npanel_scale = %s\n[profile: Med-Kit]\n" % bad)
        ok = False
    except picker.ConfigError:
        ok = True
    rc, out = node("""const core=require('./docs/core.js'),data=require('./docs/data.json'),cat=core.makeCatalog(data);
try{core.loadConfigText(cat,%s);console.log('accepted')}catch(e){console.log('refused')}""" % json.dumps("[settings]\npanel_scale = %s\n[profile: Med-Kit]\n" % bad))
    check(ok and out == "refused", "panel_scale = %s refused by both" % bad)
text13 = sink.replace("[settings]", "[settings]\npanel_scale = 1.3", 1)
s, p = picker.load_config_text(text13)
py_lua = picker.compile_loadout(s, p)
js_lua = subprocess.run(["node", "-e", """const core=require('./docs/core.js'),data=require('./docs/data.json'),cat=core.makeCatalog(data);
const {settings,profiles}=core.loadConfigText(cat,%s);process.stdout.write(core.generateLua(data,settings,profiles))""" % json.dumps(text13)],
                        capture_output=True, text=True, cwd=ROOT).stdout
check("panel_scale = 1.3," in py_lua and js_lua == py_lua,
      "generated Lua carries panel_scale = 1.3 and matches the web builder")

# ------------------------------------------------------------------ 2. in game
path, _ = build(sink)
appdata = tempfile.mkdtemp()
g = FakeGame(path, appdata=appdata)
g.tick(420)
g.key(F7)
g.tick(120)
w100, h100 = panel_px(g)
check(any(t == "100%" for t in g.texts()), "size control shows 100%")
ctrl(g, PLUS)
w110, _ = panel_px(g)
check(abs(w110 / w100 - 1.1) < 0.02 and any(t == "110%" for t in g.texts()), "Ctrl + makes the panel 10 % bigger")
ctrl(g, NUM_PLUS)
check(any(t == "120%" for t in g.texts()), "numpad + works too")
g.click("zoom:-")
check(any(t == "110%" for t in g.texts()), "the [-] button makes it smaller")
check(any("Panel size 110%" in t for t in g.texts()), "a message says the new size")
for _ in range(12):
    ctrl(g, PLUS)
check(any(t == "200%" for t in g.texts()), "capped at 200%")
for _ in range(16):
    ctrl(g, MINUS)
check(any(t == "80%" for t in g.texts()), "capped at 80%")
ctrl(g, ZERO)
check(any(t == "100%" for t in g.texts()), "Ctrl 0 resets to 100%")
ctrl(g, PLUS)
ctrl(g, PLUS)
check(g.state[b"ui"][b"history"] is not None and len(g.state[b"ui"][b"history"]) == 0,
      "resizing is not an undo step")
g.key(F7)
g.tick(200)
check(saved_scale(appdata) == "1.2", "the size is saved to loadout.ini (panel_scale = 1.2)")
g2 = FakeGame(path, appdata=appdata)
g2.tick(420)
g2.key(F7)
g2.tick(120)
check(any(t == "120%" for t in g2.texts()), "the size survives a restart")
g2.click("presets")
g2.click("pre:builtin:2")
g2.click("pload")
check(any(t == "120%" for t in g2.texts()), "loading a preset keeps your panel size")

# ------------------------------------------------------------------ 3. whole pixels, fits the screen
for (rw, rh) in ((1920, 1080), (2560, 1440), (3840, 2160)):
    for scale in (0.8, 1.0, 1.5):
        pth, _ = build(sink.replace("[settings]", "[settings]\npanel_scale = %.1f" % scale, 1))
        gg = FakeGame(pth, appdata=tempfile.mkdtemp())
        gg.set_resolution(rw, rh)
        gg.tick(420)
        gg.key(F7)
        gg.tick(120)
        calls = gg.draw_calls()
        frac = [c for c in calls if any(abs(v - round(v)) > 1e-6 for v in
                (tuple(c[1:3]) + ((c[4], c[5]) if c[0] == b"rect" else (c[4],))))]
        x, y, w, h, _ = gg.regions()["panel"]
        fits = x >= 0 and y >= 0 and x + w <= rw and y + h <= rh
        smallest = min(c[4] for c in calls if c[0] == b"text")
        check(not frac and fits and smallest >= 7,
              "%dx%d at %d%%: whole pixels, fits the screen, text >= 7 px (panel %dx%d)" % (rw, rh, scale * 100, w, h))
# bigger screens get a bigger panel (drawn at their own resolution, not stretched)
sizes = {}
for rh in (1080, 1440, 2160):
    gg = FakeGame(path, appdata=tempfile.mkdtemp())
    gg.set_resolution(rh * 16 // 9, rh)
    gg.tick(420)
    gg.key(F7)
    gg.tick(120)
    sizes[rh] = panel_px(gg)[1]
check(sizes[1080] < sizes[1440] < sizes[2160] and abs(sizes[1440] / sizes[1080] - 4 / 3) < 0.02,
      "panel height follows the screen: %s" % sizes)

# ------------------------------------------------------------------ 4. bigger than a small screen
def at_720(scale):
    pth, _ = build(sink.replace("[settings]", "[settings]\npanel_scale = %.1f" % scale, 1))
    gg = FakeGame(pth, appdata=tempfile.mkdtemp())
    gg.set_resolution(1280, 720)
    gg.tick(420)
    gg.key(F7)
    gg.tick(120)
    return gg


g15, g20 = at_720(1.5), at_720(2.0)
x, y, w, h, _ = g15.regions()["panel"]
check(y >= 0 and y + h <= 720, "720p at 150%%: the panel still fits the screen (%dx%d)" % (w, h))
body15 = max(c[4] for c in g15.draw_calls() if c[0] == b"text")
x, y, w, h, _ = g20.regions()["panel"]
body20 = max(c[4] for c in g20.draw_calls() if c[0] == b"text")
check(h > 720 and y + h == 720 and x + w <= 1280,
      "720p at 200%%: taller than the screen (%dx%d), starts at the top, fits across" % (w, h))
check(body20 > body15 * 1.4, "... and its text is bigger (%s px vs %s px at 150%%)" % (body20, body15))
g20.scroll_wheel("drag", -20)
x, y, w, h, _ = g20.regions()["panel"]
check(y == 0, "the wheel outside a list scrolls it down to its bottom edge")
low = next(k for k, r in g20.regions().items() if k != "panel" and 0 <= r[1] and r[1] + r[3] < 120
           and k.split(":")[0] not in ("sel", "tick", "addpick", "swap", "pre", "scroll"))
g20.scroll_wheel(low, 20)
x, y, w, h, _ = g20.regions()["panel"]
check(y + h == 720, "... and back up to its top (wheel over '%s')" % low)
g20.click("settings")
check(any("Taller than the screen" in t for t in g20.texts()), "Keys tab says how to scroll it")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall panel scale checks passed")
