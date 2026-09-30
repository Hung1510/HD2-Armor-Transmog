#!/usr/bin/env python3
"""
Passive info, stack summary and the Remove armor button.

    python tests/test_passive_info.py

1. tools/passives.json covers every passive (plain ASCII, the game's font may lack other
   glyphs) and TESTING.md's statuses reach the panel.
2. The panel shows what a passive does, which armors carry it, and whether each effect is
   confirmed in game.
3. Stack summary adds up additive values and multiplies multipliers.
4. Remove armor is a real button that asks for a second click.
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


def open_game(text, **kw):
    g = FakeGame(build(text, **kw), appdata=tempfile.mkdtemp())
    g.tick(420)
    g.key(F7)
    g.tick(120)
    return g


# ------------------------------------------------------------------ 1. the data
info = picker.passive_info()
names = {v[0] for v in picker.CATALOG.values()}
check(set(info) == names, "tools/passives.json has an entry for each of the %d passives" % len(names))
check(all(v["desc"] and v["armors"] for v in info.values()), "every passive has a description and at least one armor")
armors = [a for v in info.values() for a in v["armors"]]
check(len(armors) == len(set(armors)), "no armor is listed under two passives (%d armors)" % len(armors))
lua = picker.passive_info_lua()
check('["Med-Kit"] = { desc = "+2 stims' in lua and "CM-14 Physician" in lua, "the info is generated into the mod")

# TESTING.md statuses: a fake file with one confirmed and one no-effect row
real = picker.TESTING_MD
fake = tempfile.mktemp(suffix=".md")
with open(fake, "w", encoding="utf-8") as f:
    f.write("| `stims` | ✅ | Med-Kit (2) | x |\n| `stim_duration` | ❌ | Med-Kit (2) | x |\n| `limb_health` | ❔ | x | x |\n")
picker.TESTING_MD = fake
marks = picker.tested_effects()
check(marks == {"stims": "ok", "stim_duration": "no"}, "TESTING.md marks are read (confirmed / no effect; untested left out)")
g = open_game("[settings]\nname = x\n[profile: Med-Kit]\nScout = on\n")
g.click("tab:1")
g.click("sel:%d" % pid_of("Med-Kit"))
texts = g.texts()
check("CONFIRMED IN GAME" in texts and "NO EFFECT SEEN" in texts, "the value cards show the in-game status of each effect")
picker.TESTING_MD = real

# ------------------------------------------------------------------ 2. info in the views
g = open_game("[settings]\nname = x\n[profile: Med-Kit]\nScout = on\n")
g.click("tab:1")
g.click("sel:%d" % pid_of("Med-Kit"))
texts = " ".join(g.texts())
check("+2 stims" in texts and "WEAR ANY OF:" in texts and "CM-14 Physician" in texts,
      "the armor's own passive: what it does and which armors carry it")
check("UNTESTED" in g.texts(), "effects nobody has confirmed yet say UNTESTED")
g.click("add")
g.reveal("addpick:%d" % pid_of("Siege-Ready"))
x, y, w, h, _ = g.regions()["addpick:%d" % pid_of("Siege-Ready")]
g.move_to(x + w / 2, g.res()[1] - (y + h / 2))
texts = g.texts()
check("SR-24 Street Scout" in texts and any("primary reload" in t for t in texts),
      "+ Armor: pointing at a passive shows what it does and its armors")

sw = open_game("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True, swap_only=True)
sw.click("tab:1")
sw.click("swap:%d" % pid_of("Siege-Ready"))
texts = " ".join(sw.texts())
check("primary reload" in texts and "APPLIES TO:" in texts and "CM-14 Physician" in texts,
      "swap edition: the swapped-in passive's description and the armors it applies to")

# ------------------------------------------------------------------ 3. stack summary
g = open_game("[settings]\nname = x\n[profile: Extra Padding]\nFortified = on\nUnflinching = on\nInflammable = on\n"
              "Kinetic Displacement Mitigation = on\n")
g.click("tab:1")
g.click("sel:summary")
texts = g.texts()
check("Armor rating  x2" in texts, "Stack summary: Extra Padding + Unflinching armor rating shows as two sources")
check("+75" in texts, "armor ratings add up (1.0 + 0.5 in the game = +75 armor)")
check("87.5%" in texts, "resists multiply: 75% (Inflammable) and 50% (Kinetic) fire resist = 87.5%")
check(any("estimate" in t for t in texts), "the summary says it is an estimate")

# ------------------------------------------------------------------ 4. Remove armor
g.click("remove")
check("CLICK AGAIN TO REMOVE" in g.texts() and "tab:1" in g.regions(), "Remove armor asks for a second click")
g.click("remove")
check("tab:1" not in g.regions(), "... and the second click removes the armor tab")
check(g.record_bytes(pid_of("Extra Padding")) == g.pristine_record_bytes(pid_of("Extra Padding")),
      "... putting the game's own passive back")
g.click("add")
check(any("REMOVE ARMOR" in t for t in g.texts()), "+ Armor explains how to remove a wrong pick")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall passive info checks passed")
