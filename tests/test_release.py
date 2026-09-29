#!/usr/bin/env python3
"""
The release zip and the blank build it installs, run against the fake game.

    python tests/test_release.py

1. The zip: no mod-manager options, the mod files at the root, icon, sources.
2. The blank build stacks nothing, says where the panel is, and the panel starts empty
   with a way in (+ Armor, Presets).
3. Saves made before the rename (PassivePicker folder), even under another build, are
   picked up; new saves go to the ArmoryForge folder.
"""
import glob
import io
import json
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


# ------------------------------------------------------------------ 1. the zip
out = tempfile.mktemp(suffix=".zip")
check(picker.main(["release", "--zip", out]) == 0, "picker.py release builds")
z = zipfile.ZipFile(out)
names = z.namelist()
man = json.loads(z.read("manifest.json"))
check("Options" not in man, "manifest has no options (nothing to pick in the mod manager)")
check(man["Name"] == "Super Earth Armory Forge" and man.get("IconPath") == "icon.png" and "icon.png" in names,
      "manifest: name + icon")
check(man["Guid"] == "e6ba95c4-beaa-54c0-96c2-a2ab56021b87", "same GUID as before, so it updates in place")
check(picker.ARCHIVE_NAME in names and not any(n.startswith(("Builds/", "Addon/")) for n in names),
      "the patch sits at the zip root")
check(all(f in names for f in ("README.md", "CREDITS.txt", "tools/picker.py", "presets/02-tank.ini")),
      "sources and presets included")
lua_path = tempfile.mktemp(suffix=".lua")
arc = z.read(picker.ARCHIVE_NAME)
settings, _ = picker.load_config_text("[settings]\nname = %s\n[profile: Med-Kit]\n" % picker.TITLE)
full = picker.compile_loadout(settings, [], blank=True)
check(picker.archive_for(full) == arc, "the zipped patch is the blank build")
with open(lua_path, "w", encoding="utf-8") as f:
    f.write(full)

# ------------------------------------------------------------------ 2. blank build
appdata = tempfile.mkdtemp()
g = FakeGame(lua_path, appdata=appdata)
g.tick(420)
check(g.phase() == "ready", "blank build scans and gets ready")
check(all(g.record_bytes(p) == g.pristine_record_bytes(p) for p in picker.CATALOG),
      "nothing in the game's data is changed")
check(any("Press F7 to forge your armor" in t for t in g.texts()), "a one-off hint says to press F7")
g.render("/tmp/pp-hint.png", crop=False)
g.tick(400)
check(not any("forge your armor" in t for t in g.texts()), "the hint goes away")
g.key(F7)
g.tick(120)
check(any("NO ARMOR FORGED YET" in t for t in g.texts()), "the panel opens on an empty armory")
g.render("/tmp/pp-empty.png")
g.click("presets")
regs = g.regions()
check("pre:installed:0" not in regs and "pre:builtin:1" in regs,
      "Presets tab: the 6 standard presets, no empty 'Installed build'")
g.click("pre:builtin:2")
g.click("pload")
check(len(g.rows(7)) > len(picker.CATALOG[7][1]), "loading Tank stacks onto Med-Kit")
g.key(F7)
g.tick(10)
saves = glob.glob(os.path.join(appdata, "**", "loadout.ini"), recursive=True)
check(len(saves) == 1 and os.sep + "ArmoryForge" + os.sep in saves[0], "the save goes to ...\\ArmoryForge\\loadout.ini")

g2 = FakeGame(lua_path, appdata=appdata)
g2.tick(420)
check(g2.rows(7) == g.rows(7), "after a restart the blank build keeps what you made")

# ------------------------------------------------------------------ 3. saves from before the rename
old = tempfile.mkdtemp()
sink = open(os.path.join(ROOT, "presets", "01-kitchen-sink.ini"), encoding="utf-8").read()
s, p = picker.load_config_text(sink)
sink_lua = tempfile.mktemp(suffix=".lua")
with open(sink_lua, "w", encoding="utf-8") as f:
    f.write(picker.compile_loadout(s, p))
g3 = FakeGame(sink_lua, appdata=old)
g3.tick(420)
g3.key(F7)
g3.tick(120)
g3.click("sel:11")
g3.click("inc:1")                       # an edit, so there is a save
g3.key(F7)
g3.tick(10)
edited = g3.rows(7)
af = os.path.join(old, "CowboyBingus", "Helldivers2", "ArmoryForge")
pp = os.path.join(old, "CowboyBingus", "Helldivers2", "PassivePicker")
os.makedirs(pp, exist_ok=True)
os.replace(os.path.join(af, "loadout.ini"), os.path.join(pp, "loadout.ini"))   # as 4.4 left it
with open(os.path.join(pp, "my-presets.txt"), "w", encoding="utf-8") as f:
    f.write("### preset: Old Friend\n" + open(os.path.join(ROOT, "presets", "03-stealth.ini")).read() + "\n### end\n")
g4 = FakeGame(lua_path, appdata=old)
g4.tick(420)
check(g4.rows(7) == edited, "the blank release picks up a 4.4 panel save (made under Kitchen Sink)")
g4.key(F7)
g4.tick(120)
g4.click("presets")
check(any("Old Friend" in t for t in g4.texts()), "presets saved by 4.4 show up")
check(not any("forge your armor" in t for t in g4.texts()), "no F7 hint when something is already stacked")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall release checks passed")
