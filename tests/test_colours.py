#!/usr/bin/env python3
"""
6.0: what you're wearing, the Colours tab, per-armor weight.

    python tests/test_colours.py

1. The equipped armor is found (helmet, cape, armor ids back to back) and followed when
   you change it; the panel opens on its passive's tab and + Armor lists it first.
2. Colours tab: your armor is on top (WEARING); a scheme gives it another armor's colour
   textures slot by slot, all 64 bits exact; Original, Undo and Remove put them back.
3. It's saved as an [armor: id] section, loads next session, travels in share codes, and
   names work in the ini.
4. Per-armor weight (full edition) beats the passive's weight.
5. The Passive Swap edition has colours but never weight.
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
    w = g.state[b"kits"][b"worn"]
    return w


BASE = "[settings]\nname = x\n[profile: Siege-Ready]\n"

# ------------------------------------------------------------------ 1. what you're wearing
app = tempfile.mkdtemp()
g = FakeGame(build(BASE, blank=True), appdata=app)
g.wear(SR)
g.tick(420)
check(worn(g) == KID[SR], "the equipped armor is found (helmet, cape, armor ids together)")
g.wear(MK)
g.tick(70)
check(worn(g) == KID[MK], "... and followed when you equip another")
g.key(F7)                                                           # wearing Med-Kit armor, no Med-Kit stack yet
g.tick(120)
g.click("add")
first = min((k for k in g.regions() if k.startswith("addpick:")), key=lambda k: g.regions()[k][1] * -1)
check(any("MED-KIT  -  YOUR ARMOR" in t for t in g.texts()), "+ Armor marks your armor's passive")
check(first == "addpick:%d" % MK, "... and lists it first")
g.click("addcancel")
g.key(F7)
g.wear(SR)
g.tick(70)
g.key(F7)
g.tick(120)

# ------------------------------------------------------------------ 2. the Colours tab
g.click("colours")
texts = " ".join(g.texts())
check("WEARING" in texts and "carm:%d" % KID[SR] in g.regions(), "Colours: your armor is listed as WEARING")
check(g.state[b"ui"][b"csel"] == KID[SR], "... and chosen when the tab opens")
check("csrc:0" in g.regions() and "SCHEMES" in texts, "the other armors' schemes are listed, with Original")
before = g.kit_luts(KID[SR])
src = next(k for k in g.regions() if k.startswith("csrc:") and k != "csrc:0")
sid = int(src.split(":")[1])
g.click(src)
after = g.kit_luts(KID[SR])
check(after == g.kit_luts(sid) and after != before, "a scheme gives the armor the other armor's textures, slot by slot, 64 bits exact")
check(any("colours of" in t for t in g.texts()), "... and says so")
check(all(g.kit_luts(k) == [g.lut(k, s) for s in (2, 6, 3)] for k in (KID[MK], KID[FO]) if k != sid),
      "other armors are left alone")
g.click("csrc:0")
check(g.kit_luts(KID[SR]) == before, "Original puts its own textures back")
g.click(src)
g.click("undo")
check(g.kit_luts(KID[SR]) == before, "Undo too")
g.click(src)
g.key(F7)                                                          # closing saves
saved = open(forge(app, "loadout.ini"), encoding="utf-8").read()
check("[armor: 0x%08X]" % KID[SR] in saved and "colours = 0x%08X" % sid in saved and NAMES[sid] in saved,
      "saved as an [armor: id] section, names as comments")

# share code
g.key(F7)
g.tick(120)
g.click("tab:1")
g.click("copy")
code = (g.clipboard() or "").split("#ini=")[1]
text = base64.urlsafe_b64decode(code + "=" * (-len(code) % 4)).decode()
check("[armor: 0x%08X]" % KID[SR] in text and "colours=0x%08X" % sid in text, "share codes carry it")

# next session
g2 = FakeGame(build(BASE, blank=True), appdata=app)
g2.tick(420)
check(g2.kit_luts(KID[SR]) == g2.kit_luts(sid), "the saved colours apply in the next session")

# names in the ini
s, _ = picker.load_config_text(BASE + "[armor: %s]\ncolours = %s\n" % (NAMES[KID[SR]], NAMES[KID[FO]]))
check(s["armors"] == {KID[SR]: {"colours": KID[FO]}}, "the ini takes armor names too")
try:
    picker.load_config_text(BASE + "[armor: No Such Armor]\ncolours = original\n")
    check(False, "an unknown armor is refused")
except picker.ConfigError:
    check(True, "an unknown armor is refused")

# ------------------------------------------------------------------ 4. per-armor weight
app3 = tempfile.mkdtemp()
g3 = FakeGame(build("[settings]\nname = x\n[profile: Siege-Ready]\nweight = heavy\n[armor: 0x%08X]\nweight = light\n" % KID[SR]),
              appdata=app3)
g3.wear(SR)
g3.tick(420)
check(g3.kit_weights(SR)[:2] == [0, 0], "this armor's own weight beats its passive's (light over heavy)")
g3.key(F7)
g3.tick(120)
g3.click("colours")
g3.click("cw:game")
check(g3.kit_weights(SR)[:2] == [2, 2], "Weight: Game on the Colours tab falls back to the passive's (heavy)")

# ------------------------------------------------------------------ 5. Passive Swap edition
app4 = tempfile.mkdtemp()
os.makedirs(os.path.dirname(forge(app4, "x")), exist_ok=True)
with open(forge(app4, "loadout-swap.ini"), "w", encoding="utf-8") as f:
    f.write("[settings]\nname = x\n[profile: Siege-Ready]\nswap = Med-Kit\n[armor: 0x%08X]\ncolours = 0x%08X\nweight = light\n"
            % (KID[SR], KID[FO]))
sw = FakeGame(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True, swap_only=True), appdata=app4)
w0 = sw.kit_weights(SR)
sw.tick(420)
check(sw.kit_luts(KID[SR]) == sw.kit_luts(KID[FO]), "Passive Swap edition: colours work")
check(sw.kit_weights(SR) == w0, "... but weight is never changed")
sw.key(F7)
sw.tick(120)
sw.click("colours")
sw.click("carm:%d" % KID[SR])
check("cw:light" not in sw.regions() and "csrc:0" in sw.regions(), "... and its Colours tab has no weight buttons")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall colours checks passed")
