#!/usr/bin/env python3
"""
6.0: what you're wearing, one armor's weight, and the game's mouse behind the panel.

    python tests/test_wearing.py

1. The equipped armor is found (helmet, cape, armor ids back to back) and followed when
   you change it; the panel opens on its passive's tab and + Armor lists it first.
2. Per-armor weight (full edition): an [armor: id] section beats the passive's weight,
   the ARMOR WEIGHT view sets it for the armor you're wearing, it's saved with the
   armor's name as a comment and travels in share codes; names work in the ini.
3. The Passive Swap edition never changes weight.
4. While the cursor is on the open panel, the game's mouse reads "nothing pressed";
   the panel's own clicks still work; off the panel and after closing, the game gets
   its own mouse functions back.
"""
import base64
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import picker  # noqa: E402
from harness import FakeGame  # noqa: E402

F7 = 0x76
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def pid_of(name):
    return next(k for k, v in picker.CATALOG.items() if v[0].lower() == name.lower())


SR, MK, FO = pid_of("Siege-Ready"), pid_of("Med-Kit"), pid_of("Fortified")
PERKS = list(picker.CATALOG)
KID = {pid: 0x7000 + n for n, pid in enumerate(PERKS)}          # the harness's armor kit ids
NAMES = {KID[pid]: "TA-%d %s Plate" % (n, picker.CATALOG[pid][0].split(",")[0]) for n, pid in enumerate(PERKS)}
picker.armor_names = lambda: dict(NAMES)                           # test names instead of the game's


def build(text, **kw):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p, **kw))
    return path


def forge(app, name):
    return os.path.join(app, "CowboyBingus", "Helldivers2", "ArmoryForge", name)


def worn(g):
    return g.state[b"kits"][b"worn"]


BASE = "[settings]\nname = x\n[profile: Siege-Ready]\n"

# ------------------------------------------------------------------ 1. what you're wearing
app = tempfile.mkdtemp()
g = FakeGame(build(BASE + "[profile: Med-Kit]\n"), appdata=app)
g.wear(SR)
g.tick(420)
check(worn(g) == KID[SR], "the equipped armor is found (helmet, cape, armor ids together)")
g.wear(MK)
g.tick(70)
check(worn(g) == KID[MK], "... and followed when you equip another")
g.key(F7)
g.tick(120)
check(g.state[b"ui"][b"tab"] == 2, "the panel opens on the tab of the armor you're wearing (Med-Kit)")
g.key(F7)

g2 = FakeGame(build(BASE, blank=True), appdata=tempfile.mkdtemp())
g2.wear(MK)                                                          # no Med-Kit tab yet
g2.tick(420)
g2.key(F7)
g2.tick(120)
g2.click("add")
first = max((k for k in g2.regions() if k.startswith("addpick:")), key=lambda k: g2.regions()[k][1])
check(any("MED-KIT  -  YOUR ARMOR" in t for t in g2.texts()), "+ Armor marks your armor's passive")
check(first == "addpick:%d" % MK, "... and lists it first")

# ------------------------------------------------------------------ 2. per-armor weight
app3 = tempfile.mkdtemp()
g3 = FakeGame(build(BASE + "weight = heavy\n[armor: 0x%08X]\nweight = light\n" % KID[SR]), appdata=app3)
g3.wear(SR)
g3.tick(420)
check(g3.kit_weights(SR)[:2] == [0, 0], "this armor's own weight beats its passive's (light over heavy)")
g3.key(F7)
g3.tick(120)
g3.click("sel:weight")
check(any("only the armor you're wearing" in t.lower() for t in g3.texts()) and "aw:medium" in g3.regions(),
      "ARMOR WEIGHT has a row for the armor you're wearing")
g3.click("aw:game")
check(g3.kit_weights(SR)[:2] == [2, 2], "'As above' falls back to the passive's weight (heavy)")
g3.click("aw:medium")
check(g3.kit_weights(SR)[:2] == [1, 1], "Medium for this armor only")
g3.key(F7)                                                         # closing saves
saved = open(forge(app3, "loadout.ini"), encoding="utf-8").read()
check("[armor: 0x%08X]" % KID[SR] in saved and "weight  = medium" in saved and NAMES[KID[SR]] in saved,
      "saved as an [armor: id] section, the name as a comment")
g3.key(F7)
g3.tick(120)
g3.click("tab:1")
g3.click("copy")
code = (g3.clipboard() or "").split("#ini=")[1]
text = base64.urlsafe_b64decode(code + "=" * (-len(code) % 4)).decode()
check("[armor: 0x%08X]" % KID[SR] in text and "weight=medium" in text, "share codes carry it")

s, _ = picker.load_config_text(BASE + "[armor: %s]\nweight = heavy\n" % NAMES[KID[FO]])
check(s["armors"] == {KID[FO]: {"weight": 2}}, "the ini takes armor names too")
for bad in ("[armor: No Such Armor]\nweight = light\n", "[armor: 0x7000]\ncolours = 0x7001\n"):
    try:
        picker.load_config_text(BASE + bad)
        check(False, "refused: %r" % bad)
    except picker.ConfigError:
        check(True, "refused: %r" % bad.split("\n")[0 if "No Such" in bad else 1])

# ------------------------------------------------------------------ 3. Passive Swap edition
app4 = tempfile.mkdtemp()
os.makedirs(os.path.dirname(forge(app4, "x")), exist_ok=True)
with open(forge(app4, "loadout-swap.ini"), "w", encoding="utf-8") as f:
    f.write("[settings]\nname = x\n[profile: Siege-Ready]\nswap = Med-Kit\n[armor: 0x%08X]\nweight = light\n" % KID[SR])
sw = FakeGame(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True, swap_only=True), appdata=app4)
sw.wear(SR)
w0 = sw.kit_weights(SR)
sw.tick(420)
check(sw.kit_weights(SR) == w0, "Passive Swap edition: weight is never changed")
check("weight =" not in picker.compile_loadout(*picker.load_config_text(BASE + "[armor: 0x7000]\nweight = light\n"),
                                                blank=True, swap_only=True).split("type_passive")[0],
      "... and its builds carry no armor weights")
sw.key(F7)
sw.tick(120)
check(not any(k.startswith("aw:") for k in sw.regions()), "... and its panel has no weight buttons")

# ------------------------------------------------------------------ 4. the game's mouse
gm = FakeGame(build(BASE), appdata=tempfile.mkdtemp())
gm.tick(420)
gm.L.execute(b"ORIG_BUTTON = stingray.Mouse.button")


def is_orig():
    return gm.L.eval(b"stingray.Mouse.button == ORIG_BUTTON")


def game_sees_button():
    """what the game's own scripts read for the left button right now"""
    gm.L.execute(b"MOUSE_DOWN = true")
    v = gm.L.eval(b"stingray.Mouse.button(stingray.Mouse.button_id('left'))")
    gm.L.execute(b"MOUSE_DOWN = false")
    return v


check(game_sees_button() == 1, "panel closed: the game reads the mouse as usual")
gm.key(F7)
gm.tick(120)
x, y, w, h, _ = gm.regions()["panel"]
gm.move_to(x + w / 2, gm.res()[1] - (y + h / 2))
check(game_sees_button() == 0, "cursor on the panel: the game sees no button pressed")
check(gm.L.eval(b"stingray.Mouse.pressed(0)") is False, "... no click")
ax = gm.L.eval(b"stingray.Mouse.axis(stingray.Mouse.axis_id('wheel'))")
check(ax[1] == 0 and ax[2] == 0, "... and no movement or wheel")
gm.click("add")
check(gm.state[b"ui"][b"adding"], "the panel's own clicks still work while the game's are blocked")
gm.click("addcancel")
gm.move_to(5, 5)                                                    # top left: off the panel
check(game_sees_button() == 1 and is_orig(),
      "cursor off the panel: the game gets its own mouse back")
gm.move_to(x + w / 2, gm.res()[1] - (y + h / 2))
check(game_sees_button() == 0, "back on the panel: blocked again")
gm.key(F7)
gm.tick(2)
check(is_orig() and game_sees_button() == 1,
      "closing the panel gives the game its mouse back")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall wearing checks passed")
