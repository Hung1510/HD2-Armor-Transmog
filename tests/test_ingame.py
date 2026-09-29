#!/usr/bin/env python3
"""
In-game behaviour, tested offline: runs the REAL generated mod (engine + panel) in
LuaJIT against a fake game (tests/harness.py). Needs: pip install lupa

    python tests/test_ingame.py

1. For every preset / example / the default loadout: the rows the game ends up with are
   exactly what tools/picker.py says (base rows with overrides, then the added rows),
   and every other armor passive is untouched.
2. The F7 panel: opens on the left, edits values, ticks passives, switches the overlap
   rule, adds and removes an armor stack (removing restores the game's bytes exactly),
   saves loadout.ini (which picker.py reads back to the same rows), survives a restart,
   is ignored after a different build is installed, and reverts.
3. retire = false puts the stack back after the game resets its data; updates go
   through two alternating buffers.
"""
import os
import struct
import sys
import tempfile
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import picker  # noqa: E402
from harness import FakeGame  # noqa: E402

F7, ENTER = 0x76, 0x0D
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def f32(v):
    return struct.unpack("<f", struct.pack("<f", v))[0]


def build(text, name):
    settings, profiles = picker.load_config_text(text)
    path = os.path.join(tempfile.mkdtemp(), name + ".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(settings, profiles))
    return path, profiles


def expected(pid, profile):
    """What picker.py says perk `pid` should hold: (rows, stats) as tuples."""
    _, rows, stats = picker.CATALOG[pid]
    base = [(m, t, f32(v)) for m, t, v in rows]
    over = {(m, t): f32(v) for m, t, v, _ in profile["overrides"]}
    base = [(m, t, over.get((m, t), v)) for m, t, v in base]
    seen = set(base)
    out = list(base)
    for m, t, v, _ in profile["rows"]:
        r = (m % (1 << 32), t, f32(v))
        if r not in seen:
            seen.add(r)
            out.append(r)
    sbase = [(s, f32(a), f32(b)) for s, a, b in stats]
    sover = {s: (f32(a), f32(b)) for s, a, b, _ in profile["stat_overrides"]}
    sbase = [(s,) + sover.get(s, (a, b)) for s, a, b in sbase]
    sseen = set(sbase)
    sout = list(sbase)
    for s, a, b, _ in profile["stats"]:
        r = (s, f32(a), f32(b))
        if r not in sseen:
            sseen.add(r)
            sout.append(r)
    return out, sout


def live(g, pid):
    rows = [(m, t, v) for m, t, v, _ in g.rows(pid)]
    stats = [tuple(s) for s in g.stats(pid)]
    return rows, stats


def matches(g, pid, profile):
    return live(g, pid) == expected(pid, profile)


def untouched_except(g, perks):
    return all(g.record_bytes(p) == g.pristine_record_bytes(p) for p in picker.CATALOG if p not in perks)


# ------------------------------------------------------------------ 1. parity
EDGE = """
[settings]
name = Edge
retire = false
hotkey = f6
[profile: Siege-Ready]
conflicts = strongest
Fortified = on
Ballistic Padding = on
Siege-Ready.stat_ammo_capacity = 2
raw = 0xAFAE3B47 1 2.5, 0x14ECCE15 2 0.25
raw_stats = 13 0.0 1.75
[profile: 9]
Democracy Protects.death_save = 0.000015
Scout = yes
"""
cases = [(f, open(os.path.join(ROOT, f), encoding="utf-8").read())
         for f in sorted(glob.glob("presets/*.ini", root_dir=ROOT)) + sorted(glob.glob("examples/*.ini", root_dir=ROOT))
         + ["loadout.ini"]]
cases.append(("edge case", EDGE))
for label, text in cases:
    path, profiles = build(text, "case")
    g = FakeGame(path)
    g.tick(420)
    ok = g.phase() == "ready" and all(matches(g, p["perk"], p) for p in profiles)
    check(ok and untouched_except(g, [p["perk"] for p in profiles]), "runtime rows == picker.py: " + label)

# ------------------------------------------------------------------ 2. panel
tank = open(os.path.join(ROOT, "presets", "02-tank.ini"), encoding="utf-8").read()
path, profiles = build(tank, "tank")
appdata = tempfile.mkdtemp()
g = FakeGame(path, appdata=appdata)
g.tick(420)
check(g.state[b"loadout_source"] == b"built-in", "first start uses the built-in loadout")
g.key(F7)
g.tick(120)
ui = g.state[b"ui"]
check(ui[b"open"] is True and "PASSIVE PICKER" in g.texts(), "F7 opens the panel and it draws")
xs = [c[1] for c in g.draw_calls() if c[0] == b"rect"]
check(min(xs) < 100, "panel sits on the left (SHODAN Stat Editor uses the right)")
check("value:1" in g.regions(), "opens on the base perk's values")

g.click("sel:9")
g.click("inc:1")
ds = [v for m, t, v, _ in g.rows(7) if m == 0xCB814D05]
check(ds == [f32(1.55)], "+ button raises Democracy Protects death_save 1.5 -> 1.55 live")
g.click("value:1")
g.type_text("100")
g.key(ENTER)
ds = [v for m, t, v, _ in g.rows(7) if m == 0xCB814D05]
check(ds == [2.0], "typing +100 (%) + Enter sets death_save to x2.0")

g.click("sel:7")
g.click("value:1")
g.type_text("6")
g.key(ENTER)
stims = [(v, d) for m, t, v, d in g.rows(7) if m == 0x2875F44A]
check(len(stims) == 1 and stims[0][0] == 6.0 and stims[0][1] != 0,
      "base perk stims replaced (not stacked), game's text hash kept")

ptr_before = struct.unpack("<Q", g.desc(7)[:8])[0]
g.click("tick:1")
ptr_after = struct.unpack("<Q", g.desc(7)[:8])[0]
check(not any(m == 0xAFAE3B47 and v == 1.0 for m, t, v, _ in g.rows(7)), "unticking Extra Padding removes its row")
check(ptr_before != ptr_after, "each update switches to the other buffer")

armor_before = [v for m, t, v, _ in g.rows(7) if m == 0xAFAE3B47]
g.click("policy:strongest")
armor_after = [v for m, t, v, _ in g.rows(7) if m == 0xAFAE3B47]
check(len(armor_before) > 1 and len(armor_after) == 1, "Strongest only keeps one armor_rating row")

g.click("add")
g.click("addpick:16")
g.click("tick:2")
check(any(m == 0x21A7BA64 for m, t, v, _ in g.rows(16)), "+ Armor Siege-Ready, tick Scout: Scout lands on Siege-Ready")
g.click("remove")
g.click("remove")
check(g.record_bytes(16) == g.pristine_record_bytes(16), "Remove this armor restores the game's bytes exactly")

g.key(F7)
check(g.state[b"ui"][b"open"] is False, "F7 closes the panel")
g.tick(120)
saved = glob.glob(os.path.join(appdata, "**", "loadout.ini"), recursive=True)
check(len(saved) == 1, "loadout.ini saved under %LOCALAPPDATA%")
text = open(saved[0], encoding="utf-8").read()
s2, p2 = picker.load_config_text(text)
check(all(matches(g, p["perk"], p) for p in p2), "picker.py reads the saved file back to the same rows")
live7 = live(g, 7)

g2 = FakeGame(path, appdata=appdata)
g2.tick(420)
check(g2.state[b"loadout_source"] == b"saved" and live(g2, 7) == live7, "restart: the panel's save is used")

other, _ = build(open(os.path.join(ROOT, "presets", "03-stealth.ini"), encoding="utf-8").read(), "stealth")
g3 = FakeGame(other, appdata=appdata)
g3.tick(420)
check(g3.state[b"loadout_source"] == b"built-in", "a different installed build ignores the old save")

g2.key(F7)
g2.tick(120)
g2.click("presets")
g2.click("pre:installed:0")
g2.click("pload")
check(matches(g2, 7, profiles[0]), "Presets > Installed build restores the preset's rows")

# ------------------------------------------------------------------ 3. enforcement
g4 = FakeGame(path, retire=False)
g4.tick(420)
want = live(g4, 7)
rec = g4.records[7]
g4._write(rec + 16, g4.pristine_record_bytes(7)[24 + 16:24 + 32])     # the game reloads the record
g4.advance_wall(10)
g4.tick(30)
check(live(g4, 7) == want, "retire = false: stack put back after the game resets it")

# ------------------------------------------------------------------ 4. passive dump + check-dump
import subprocess  # noqa: E402

def check_dump(dump):
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "picker.py"), "check-dump", dump],
                       capture_output=True, text=True)
    return r.returncode, r.stdout


appdata = tempfile.mkdtemp()
g5 = FakeGame(path, appdata=appdata)
g5.tick(420)
dumps = glob.glob(os.path.join(appdata, "**", "passives-dump.txt"), recursive=True)
check(len(dumps) == 1, "passives-dump.txt written after the scan")
code, out = check_dump(dumps[0])
check(code == 0 and "matches the game" in out, "check-dump: unchanged game matches CATALOG")
check(g5.record_bytes(7) != g5.pristine_record_bytes(7) and "row 0x2875F44A 1 2" in open(dumps[0]).read(),
      "dump holds the game's own values, not the stacked ones")

patched = dict(picker.CATALOG)
name, rows, stats = patched[7]
patched[7] = (name, [(0x2875F44A, 1, 3.0)] + list(rows[1:]), stats)            # balance change: stims +3
patched[0] = ("none", [(0, 0, 0.0)], [])                                         # the game's empty entry
patched[42] = ("Brand New", [(0xDEADBEEF, 2, 1.25), (0x2875F44A, 1, 1.0)], [(18, 0.0, 1.1)])  # new passive
del patched[5]                                                                  # removed passive
appdata = tempfile.mkdtemp()
g6 = FakeGame(path, appdata=appdata, game=patched)
g6.tick(420)
dump = glob.glob(os.path.join(appdata, "**", "passives-dump.txt"), recursive=True)[0]
code, out = check_dump(dump)
check(code == 1, "check-dump: a patched game reports differences")
check("NEW       perk 42" in out and "(0xDEADBEEF, 2, 1.25)" in out and "(18, 0.0, 1.1)" in out,
      "check-dump: new passive printed as a ready-to-paste CATALOG line")
check("CHANGED   perk 7 Med-Kit" in out and "(0x2875F44A, 1, 3.0)" in out, "check-dump: balance change found")
check("MISSING   perk 5" in out, "check-dump: removed passive found")
check("NEW       perk 0" not in out and "perk 0 is the game's empty" in out, "check-dump: perk 0 (no passive) ignored")
check('0xDEADBEEF: ("effect_deadbeef"' in out and '18: ("stat_18"' in out, "check-dump: new effect ids listed")
check("NOT in the catalog=1" in open(glob.glob(os.path.join(appdata, "**", "PassivePickerV4-STATUS.txt"),
                                                recursive=True)[0]).read(),
      "STATUS file flags passives missing from the catalog")
check(len(live(g6, 7)[0]) > 2, "stacking still works on a patched game")

# ------------------------------------------------------------------ 5. boot cost
g7 = FakeGame(path, junk_mb=64)
g7.tick(420)
mb = g7.bytes_read / 1048576
check(g7.phase() == "ready" and matches(g7, 7, profiles[0]),
      "with 64 MB of other memory: finds the table and applies")
check(mb < 8, "stops once the table is found: read %.1f MB of 64+ MB" % mb)
g8 = FakeGame(path, junk_mb=16, perks=[p for p in picker.CATALOG if p != 5])
g8.tick(420)
check(g8.phase() == "ready" and g8.state[b"rounds"] == 1,
      "a passive removed by a patch: ready after one round (was 12 full rescans)")

print("\n%d FAILED" % len(failed) if failed else "\nall in-game checks passed")
sys.exit(1 if failed else 0)
