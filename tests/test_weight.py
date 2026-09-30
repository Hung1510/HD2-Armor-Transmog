#!/usr/bin/env python3
"""
Armor weight (5.7, full edition): heavy looks with light speed, or any other mix.

    python tests/test_weight.py

1. `weight = light` in a profile: picker.py reads it, the game sets the ARMOR pieces of
   every armor with that passive to light; undergarments, helmets and other armors stay.
2. The panel's ARMOR WEIGHT row: pick Heavy / Game, undo, Remove armor all put the right
   weights back; the choice is saved and loads again; share codes carry it.
3. If the game puts a weight back, it is set again within 5 s.
4. The Passive Swap edition never touches weights, whatever its save file says.
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

F7 = 0x76
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


SR, MK = pid_of("Siege-Ready"), pid_of("Med-Kit")

# ------------------------------------------------------------------ 1. the loadout line
s, p = picker.load_config_text("[settings]\nname = x\n[profile: Siege-Ready]\nweight = light\n")
check(p[0]["weight"] == 0, "picker.py reads weight = light")
for bad in ("fast", "2"):
    try:
        picker.load_config_text("[profile: Siege-Ready]\nweight = %s\n" % bad)
        check(False, "weight = %s is refused" % bad)
    except picker.ConfigError:
        check(True, "weight = %s is refused" % bad)
check(picker.load_config_text("[profile: Siege-Ready]\nweight = game\n")[1][0]["weight"] is None, "weight = game means the armor's own")
check("weight = 0" in picker.compile_loadout(s, p) and "weight =" not in
      picker.compile_loadout(*picker.load_config_text("[profile: Siege-Ready]\nFortified = on\n")).split("default = {")[1].split("presets")[0],
      "the build carries the weight, and builds without one are unchanged")

app = tempfile.mkdtemp()
g = FakeGame(build("[settings]\nname = x\n[profile: Siege-Ready]\nweight = light\n"), appdata=app)
before = {pid: g.kit_weights(pid) for pid in g.kits if pid is not None}
g.tick(420)
sr0 = before[SR]
check(g.kit_weights(SR) == [0, 0, sr0[2]], "Siege-Ready armor pieces are light (%s -> %s)" % (sr0, g.kit_weights(SR)))
check(g.kit_weights(SR)[2] == 1, "... its undergarment piece is left alone")
check(all(g.kit_weights(pid) == w for pid, w in before.items() if pid != SR), "other armors keep their weight")
check(g.kit_weights(None) == [2], "helmets are left alone")
check(g.bytes_read < 2 * 1024 * 1024, "the scan still stops early (%.1f MB read)" % (g.bytes_read / 1048576))

# ------------------------------------------------------------------ 2. the panel
g.key(F7)
g.tick(120)
g.click("tab:1")
check("sel:weight" in g.regions() and any("ARMOR WEIGHT: LIGHT" in t for t in g.texts()), "the armor tab has an ARMOR WEIGHT row")
g.click("sel:weight")
texts = " ".join(g.texts())
check("SPEED 550" in texts and "SPEED 450" in texts and "Applies to all 1 armor(s)" in texts,
      "the weight view shows what each weight gives and how many armors it changes")
g.click("weight:heavy")
check(g.kit_weights(SR)[:2] == [2, 2], "Heavy: the armor pieces are heavy")
g.click("undo")
check(g.kit_weights(SR)[:2] == [0, 0], "Undo puts light back")
g.click("weight:game")
check(g.kit_weights(SR) == sr0, "Game puts the armor's own weights back")
g.click("weight:heavy")
g.tick(120)                                            # saved a moment later
g.click("copy")
code = (g.clipboard() or "").split("#ini=")[1]
import base64  # noqa: E402
check("weight=heavy" in base64.urlsafe_b64decode(code + "=" * (-len(code) % 4)).decode(), "share codes carry the weight")
g.key(F7)                                              # closing saves
saved = open(os.path.join(app, "CowboyBingus", "Helldivers2", "ArmoryForge", "loadout.ini"), encoding="utf-8").read()
check("weight    = heavy" in saved, "the weight is saved with the loadout")

# ------------------------------------------------------------------ 3. the game puts a weight back
# (retire = false keeps re-checking every 5 s, like the passives)
e = FakeGame(build("[settings]\nname = x\nretire = false\n[profile: Siege-Ready]\nweight = heavy\n"), appdata=tempfile.mkdtemp())
e.tick(420)
a = e.kits[SR][0][0]
e._write(a, (sr0[0]).to_bytes(4, "little"))
e.advance_wall(6)
e.tick(10)
check(e.kit_weights(SR)[0] == 2, "retire = false: a weight the game put back is set again")

# Remove armor puts the game's weight back
g.key(F7)
g.tick(120)
g.click("tab:1")
g.click("remove")
g.click("remove")
check(g.kit_weights(SR) == sr0, "Remove armor puts the game's own weight back")

# the save loads again in a fresh session (release build keeps panel saves)
app2 = tempfile.mkdtemp()
g2 = FakeGame(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True), appdata=app2)
path = os.path.join(app2, "CowboyBingus", "Helldivers2", "ArmoryForge")
os.makedirs(path, exist_ok=True)
with open(os.path.join(path, "loadout.ini"), "w", encoding="utf-8") as f:
    f.write(saved)
g2 = FakeGame(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True), appdata=app2)
g2.tick(420)
check(g2.kit_weights(SR)[:2] == [2, 2], "the saved weight applies in the next session")

# ------------------------------------------------------------------ 4. Passive Swap edition
app3 = tempfile.mkdtemp()
path = os.path.join(app3, "CowboyBingus", "Helldivers2", "ArmoryForge")
os.makedirs(path, exist_ok=True)
with open(os.path.join(path, "loadout-swap.ini"), "w", encoding="utf-8") as f:
    f.write("[settings]\nname = x\n[profile: Siege-Ready]\nswap = Med-Kit\nweight = light\n")
sw = FakeGame(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True, swap_only=True), appdata=app3)
sb = {pid: sw.kit_weights(pid) for pid in sw.kits}
sw.tick(420)
check(all(sw.kit_weights(pid) == w for pid, w in sb.items()), "Passive Swap edition: no weight is ever changed")
sw.key(F7)
sw.tick(120)
sw.click("tab:1")
check("sel:weight" not in sw.regions(), "Passive Swap edition: no weight row")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall weight checks passed")
