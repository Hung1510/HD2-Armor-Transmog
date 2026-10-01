#!/usr/bin/env python3
"""
Passive Swap edition (the Nexus build): one game passive per armor, at the game's values.

    python tests/test_swap_edition.py

1. Swapping Med-Kit armor to Siege-Ready gives it exactly Siege-Ready's rows and weapon
   stats from the game's own record; "Original" puts the game's bytes back.
2. Nothing can make it stronger than the base game: no value / stacking controls in the
   panel, and a hand-edited save with stacked passives, tweaks and raw rows changes nothing
   beyond the one swap.
3. Its saves are its own (loadout-swap.ini, my-swaps.txt); the full edition's are untouched.
4. A passive not in the game's data yet leaves the armor as it is.
5. The release zip: no presets, no tools, its own README.
"""
import os
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import picker  # noqa: E402
from harness import FakeGame  # noqa: E402

F7, F9 = 0x76, 0x78
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def pid_of(name):
    return next(k for k, v in picker.CATALOG.items() if v[0].lower() == name.lower())


MEDKIT, SIEGE, FORT = pid_of("Med-Kit"), pid_of("Siege-Ready"), pid_of("Fortified")
settings, _ = picker.load_config_text("[settings]\nname = %s\n[profile: Med-Kit]\n" % picker.TITLE)
LUA = tempfile.mktemp(suffix=".lua")
with open(LUA, "w", encoding="utf-8") as f:
    f.write(picker.compile_loadout(settings, [], blank=True, swap_only=True))


def game(appdata, **kw):
    g = FakeGame(LUA, appdata=appdata, **kw)
    g.tick(420)
    return g


def open_panel(g):
    g.key(F7)
    g.tick(120)


def forge_dir(appdata):
    return os.path.join(appdata, "CowboyBingus", "Helldivers2", "ArmoryForge")


# ------------------------------------------------------------------ 1. swap and restore
appdata = tempfile.mkdtemp()
g = game(appdata)
open_panel(g)
g.click("add")
g.click("addpick:%d" % MEDKIT)
regs = g.regions()
check("swap:0" in regs and "swap:%d" % SIEGE in regs, "an armor tab lists Original and the other passives")
g.click("swap:%d" % SIEGE)
check(g.rows(MEDKIT) == g.rows(SIEGE), "Med-Kit armor now has exactly Siege-Ready's rows")
check(g.stats(MEDKIT) == g.stats(SIEGE), "... and Siege-Ready's weapon stats")
check(g.record_bytes(SIEGE) == g.pristine_record_bytes(SIEGE), "Siege-Ready's own record is untouched")
check(any("SIEGE-READY" in t for t in g.texts()) and any("Active:" in t for t in g.texts()),
      "the panel shows the swapped-in passive as active")
g.render(os.path.join(tempfile.gettempdir(), "af-swap.png"))
g.click("swap:%d" % FORT)
check(g.rows(MEDKIT) == g.rows(FORT), "picking another passive replaces the swap (no stacking)")
g.click("clear")
check(g.record_bytes(MEDKIT) == g.pristine_record_bytes(MEDKIT), "Back to original restores the game's bytes exactly")
g.click("undo")
check(g.rows(MEDKIT) == g.rows(FORT), "Undo brings the swap back")

# ------------------------------------------------------------------ 2. nothing stronger than the game
bad = [k for k in g.regions() if k.split(":")[0] in
       ("value", "inc", "inc_big", "dec", "dec_big", "reset", "reset_passive", "tick", "policy", "copy", "paste")]
check(not bad, "no value, stacking, overlap or share-code controls in the panel %s" % bad[:5])
g.click("presets")
check(not any(k.startswith("pre:builtin") for k in g.regions()), "no built-in stacking presets")
g.click("psave")
g.key(0x0D)
g.key(F7)
g.tick(200)
saved = open(os.path.join(forge_dir(appdata), "loadout-swap.ini"), encoding="utf-8").read()
check("swap = Fortified" in saved and " = on" not in saved, "loadout-swap.ini holds only the swap: %r" %
      [line for line in saved.splitlines() if line.startswith("swap")])
check(os.path.exists(os.path.join(forge_dir(appdata), "my-swaps.txt")), "presets are saved to my-swaps.txt")

# a hand-edited save that tries to stack and boost
hostile = saved.replace("swap = Fortified", "swap = Siege-Ready\nconflicts = stack\nFortified = on\nScout = on\n"
                        "Siege-Ready.stat_reload_speed = 5\nMed-Kit.stims = 20\nraw = 0x12345678 1 99")
with open(os.path.join(forge_dir(appdata), "loadout-swap.ini"), "w", encoding="utf-8") as f:
    f.write(hostile)
g2 = game(appdata)
check(g2.rows(MEDKIT) == g2.rows(SIEGE) and g2.stats(MEDKIT) == g2.stats(SIEGE),
      "a hand-edited save with stacks, tweaks and raw rows still only swaps in Siege-Ready as the game has it")
check(g2.record_bytes(SIEGE) == g2.pristine_record_bytes(SIEGE), "... and changes nothing else")

# ------------------------------------------------------------------ 3. separate saves
appdata2 = tempfile.mkdtemp()
os.makedirs(forge_dir(appdata2))
full_save = "[settings]\nname = Mine\n\n[profile: Med-Kit]\nconflicts = stack\nFortified = on\nMed-Kit.stims = 9\n"
with open(os.path.join(forge_dir(appdata2), "loadout.ini"), "w", encoding="utf-8") as f:
    f.write(full_save)
g3 = game(appdata2)
check(g3.record_bytes(MEDKIT) == g3.pristine_record_bytes(MEDKIT), "the full edition's loadout.ini is not applied")
open_panel(g3)
g3.click("add")
g3.click("addpick:%d" % MEDKIT)
g3.click("swap:%d" % SIEGE)
g3.key(F7)
g3.tick(200)
check(open(os.path.join(forge_dir(appdata2), "loadout.ini"), encoding="utf-8").read() == full_save,
      "... and is left exactly as it was")
g4 = game(appdata2)
check(g4.rows(MEDKIT) == g4.rows(SIEGE), "the swap survives a restart")

# ------------------------------------------------------------------ 4. passive not in the game yet
appdata3 = tempfile.mkdtemp()
os.makedirs(forge_dir(appdata3))
with open(os.path.join(forge_dir(appdata3), "loadout-swap.ini"), "w", encoding="utf-8") as f:
    f.write("[settings]\nname = x\n\n[profile: Med-Kit]\nswap = Siege-Ready\n")
g5 = game(appdata3, perks=[p for p in picker.CATALOG if p != SIEGE])
check(g5.record_bytes(MEDKIT) == g5.pristine_record_bytes(MEDKIT), "a passive the game doesn't have leaves the armor alone")
open_panel(g5)
g5.click("tab:1")
check(any("Waiting for Siege-Ready" in t for t in g5.texts()), "... and the panel says it is waiting for it")

# ------------------------------------------------------------------ 5. the zip
out = tempfile.mktemp(suffix=".zip")
check(picker.main(["release", "--edition", "swap", "--zip", out]) == 0, "picker.py release --edition swap builds")
z = zipfile.ZipFile(out)
names = set(z.namelist())
check(names == {"manifest.json", "icon.png", picker.ARCHIVE_NAME, picker.ARCHIVE_NAME + ".stream",
                picker.ARCHIVE_NAME + ".gpu_resources", "CREDITS.txt", "README.txt"},
      "the zip holds only the mod, CREDITS and its README: %s" % sorted(names))
lua = z.read(picker.ARCHIVE_NAME)
check(b"swap_only = true" in lua and b"Kitchen Sink" not in lua.replace(b"['Kitchen Sink']", b""),
      "the patch is the swap edition without presets (the Chinese name table aside)")
import json  # noqa: E402
man = json.loads(z.read("manifest.json"))
check(man["Name"].endswith("(Passive Swap)") and man["Guid"] == "e6ba95c4-beaa-54c0-96c2-a2ab56021b87",
      "manifest: Passive Swap name, same GUID (one or the other is installed)")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall swap edition checks passed")
