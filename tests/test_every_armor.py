#!/usr/bin/env python3
"""
6.2.1: the Every armor stack (a setup that stays whatever armor you wear).

    python tests/test_every_armor.py

1. [profile: Every armor] applies to every armor passive with no tab of its own; a passive
   with its own tab keeps that tab. own_passive = off drops the armor's own rows.
2. Its weight reaches every armor it covers and no other.
3. The panel: + Armor offers it, the header names it, Keep it / Turn it off, and it is
   saved to loadout.ini and loads back.
4. Ticking Every armor as a passive is refused; the Passive Swap edition ignores it.
5. New stacks default to Strongest only.
"""
import glob
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
EVERY = picker.EVERY
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def pid_of(name):
    return next(k for k, v in picker.CATALOG.items() if v[0].lower() == name.lower())


SR, MK, FO = pid_of("Siege-Ready"), pid_of("Med-Kit"), pid_of("Fortified")


def build(text, **kw):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p, **kw))
    return path


def keys(rows):
    return {(m, t) for m, t, _, _ in rows}


# ------------------------------------------------------------------ 1. which armors it covers
TEXT = "[settings]\nname = x\n[profile: Every armor]\nFortified = on\n[profile: Siege-Ready]\n"
g = FakeGame(build(TEXT), appdata=tempfile.mkdtemp())
fo0, mk0, sr0 = keys(g.rows(FO)), keys(g.rows(MK)), keys(g.rows(SR))
g.tick(420)
check(fo0 <= keys(g.rows(MK)) and mk0 <= keys(g.rows(MK)),
      "Med-Kit armor (no tab of its own) gets Fortified and keeps its own passive")
check(keys(g.rows(SR)) == sr0, "Siege-Ready armor has its own tab, so the Every armor stack leaves it alone")

g = FakeGame(build(TEXT.replace("Fortified = on", "own_passive = off\nFortified = on")), appdata=tempfile.mkdtemp())
g.tick(420)
check(keys(g.rows(MK)) == fo0 and not (mk0 - fo0) & keys(g.rows(MK)),
      "own_passive = off: Med-Kit armor has only Fortified, its own passive is off")
check(keys(g.rows(SR)) == sr0, "... and a passive with its own tab still keeps its own")

# ------------------------------------------------------------------ 2. weight
g = FakeGame(build("[settings]\nname = x\n[profile: Every armor]\nweight = heavy\n[profile: Siege-Ready]\n"),
             appdata=tempfile.mkdtemp())
sr_w = g.kit_weights(SR)
g.tick(420)
check(g.kit_weights(MK)[:-1] == [2] * (len(g.kit_weights(MK)) - 1), "weight = heavy makes the covered armors heavy")
check(g.kit_weights(SR) == sr_w, "... and leaves an armor with its own tab alone")

# ------------------------------------------------------------------ 3. the panel
app = tempfile.mkdtemp()
g = FakeGame(build("[settings]\nname = x\n[profile: Siege-Ready]\n"), appdata=app)
g.wear(MK)
g.tick(420)
g.key(F7)
g.tick(120)
g.click("add")
g.tick(2)
regs = g.regions()
check("addpick:%d" % EVERY in regs, "+ Armor offers Every armor")
g.click("addpick:%d" % EVERY)
g.tick(2)
check(any("Every armor stack" in t for t in g.texts()), "the header says the Every armor stack covers what you wear")
check("own:off" in g.regions(), "the base row offers Keep it / Turn it off")
g.click("own:off")
g.tick(2)
g.click("tick:%d" % FO)
g.tick(2)
check(keys(g.rows(MK)) == fo0, "the panel's Turn it off + Fortified gives Med-Kit armor only Fortified")
g.key(F7)
g.tick(120)
saved = glob.glob(os.path.join(app, "**", "loadout.ini"), recursive=True)
text = open(saved[0], encoding="utf-8").read() if saved else ""
check("[profile: Every armor]" in text and "own_passive = off" in text and "conflicts = strongest" in text,
      "saved as [profile: Every armor] with own_passive = off and Strongest only")
s, p = picker.load_config_text(text)
ev = [x for x in p if x["perk"] == EVERY]
check(ev and ev[0]["own"] is False and "Fortified" in ev[0]["enabled"], "picker.py reads the saved stack back")
g2 = FakeGame(build("[settings]\nname = x\n[profile: Siege-Ready]\n"), appdata=app)
g2.tick(420)
check(g2.state[b"loadout_source"] == b"saved" and keys(g2.rows(MK)) == fo0, "the game loads it back next time")

# ------------------------------------------------------------------ 4. refused / ignored
try:
    picker.load_config_text("[profile: Siege-Ready]\nEvery armor = on\n")
    check(False, "ticking Every armor as a passive is refused")
except picker.ConfigError:
    check(True, "ticking Every armor as a passive is refused")

settings, _ = picker.load_config_text("[settings]\nname = x\n[profile: Med-Kit]\n")
path = tempfile.mktemp(suffix=".lua")
with open(path, "w", encoding="utf-8") as f:
    f.write(picker.compile_loadout(settings, [], blank=True, swap_only=True))
sw = tempfile.mkdtemp()
d = os.path.join(sw, "CowboyBingus", "Helldivers2", "ArmoryForge")
os.makedirs(d)
open(os.path.join(d, "loadout-swap.ini"), "w").write(TEXT)
g = FakeGame(path, appdata=sw)
g.tick(420)
check(keys(g.rows(MK)) == mk0, "the Passive Swap edition ignores an Every armor stack")

print("\n%d FAILED" % len(failed) if failed else "\nall Every armor checks passed")
sys.exit(1 if failed else 0)
