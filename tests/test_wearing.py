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
4. While the panel is open the game gets no keyboard or mouse (like SHODAN Stat Editor):
   its raw mouse and keyboard are taken once the panel key is let go and given back exactly
   as the game last registered them; the window filter drops key presses and clicks and
   keeps the wheel for the panel's lists; the panel's own clicks still work. Keys tab:
   Blocked / Let through. Never touches another thread's registration, and never leaves
   the game without a mouse and keyboard if giving them back fails.
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

# ------------------------------------------------------------------ 4. the game's input
gm = FakeGame(build(BASE), appdata=tempfile.mkdtemp())
gm.tick(420)
G = gm.L.globals()


def raw():
    return sorted((d[b"usage"], d[b"flags"], d[b"target"]) for d in G[b"RAW"].values())


def gi():
    return gm.state[b"pp"][b"gi"]


def msg(kind, value=1):
    return G[b"GAME_MSG"](kind.encode(), value)


GAME_RAW = [(2, 0x30, b"game window"), (6, 0x30, b"game window")]
check(raw() == GAME_RAW and msg("key") and msg("click"), "panel closed: the game has its raw mouse and keyboard, keys and clicks pass")
G[b"KEYS"][F7] = True                                                # F7 still held: nothing taken yet
gm.tick(30)
check(raw() == GAME_RAW, "the panel waits for its key to be let go before taking the game's input")
G[b"KEYS"][F7] = None
gm.tick(60)
check(raw() == [], "panel open: the game's raw mouse and keyboard are taken away")
check(not msg("key") and not msg("click"), "... key presses and clicks to the game window are dropped")
gm.tick(60)
gm.click("add")
check(gm.state[b"ui"][b"adding"], "the panel's own clicks still work (read from Windows)")
gm.click("addcancel")
gm.click("sel:%d" % SR)
G[b"RAW"][1] = gm.L.table_from({b"page": 1, b"usage": 2, b"flags": 0x100, b"target": b"game window"})   # the game registers again
gm.tick(40)
check(raw() == [], "the game registering its mouse again while open is undone")
gm.key(F7)
gm.tick(2)
check(raw() == [(2, 0x100, b"game window"), (6, 0x30, b"game window")],
      "closing the panel gives both back, as the game last registered them")
check(msg("key") and msg("click") and gm.L.eval(b"FILTER.flag") == 0, "... and keys and clicks pass again")

# the wheel scrolls the panel's lists through the window filter while the game's input is held
sc = FakeGame(build(BASE), appdata=tempfile.mkdtemp())
sc.set_resolution(1280, 720)
sc.tick(420)
sc.key(F7)
sc.tick(120)
sc.click("add")
top = sc.state[b"ui"][b"scroll"][b"add"] or 0
sc.scroll_wheel(next(k for k in sc.regions() if k.startswith("addpick:")), -2)
check((sc.state[b"ui"][b"scroll"][b"add"] or 0) > top, "the wheel still scrolls the panel's lists (from the window filter)")

# Keys tab: Let through
gm.key(F7)
gm.tick(120)
check(raw() == [] and gi()[b"state"] == b"held", "open again: held")
gm.click("settings")
gm.click("blockin:off")
check(raw() == [(2, 0x100, b"game window"), (6, 0x30, b"game window")] and msg("key"),
      "Keys tab, Let through: the game gets its input while the panel is open")
gm.key(F7)
gm.key(F7)
gm.tick(120)
check(raw() != [], "... and it stays let through")
gm.click("settings")
gm.click("blockin:on")
gm.tick(40)
check(raw() == [], "Blocked again")
gm.click("report")
rep = gm.clipboard() or ""
check("game input while open: blocked (held)" in rep and "dropped:" in rep, "the problem report says what the panel holds")
gm.key(F7)

# a raw registration owned by another thread is never touched
G[b"RAW_OTHER_THREAD"] = True
gm.key(F7)
gm.tick(60)
check(len(raw()) == 2 and "another thread" in gi()[b"state"].decode(), "raw input owned by another thread is left alone")
gm.key(F7)
G[b"RAW_OTHER_THREAD"] = False

# giving it back fails: the game still gets a mouse and keyboard, and blocking stops for the session
gm.key(F7)
gm.tick(60)
check(raw() == [], "held")
G[b"RAW_FAIL_GIVE"] = True
gm.key(F7)
gm.tick(2)
check([u for u, _, _ in raw()] == [2, 6] and all(t is None for _, _, t in raw()),
      "giving it back fails: registered again without a window, so the game keeps its input")
check(gi()[b"broken"], "... and blocking is off for the session")
G[b"RAW_FAIL_GIVE"] = False
calls = G[b"RAW_CALLS"]
gm.key(F7)
gm.tick(60)
gm.key(F7)
check(G[b"RAW_CALLS"] == calls, "... nothing is taken after that")

# no window filter: raw input is still held, and it says why
gf = FakeGame(build(BASE), appdata=tempfile.mkdtemp())
gf.L.globals()[b"FILTER_FAIL"] = True
gf.tick(420)
gf.key(F7)
gf.tick(60)
check(gf.state[b"pp"][b"gi"][b"filter_failed"] is not None and len(list(gf.L.globals()[b"RAW"].values())) == 0,
      "no window filter: the raw mouse and keyboard are still held, and the log says why")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall wearing checks passed")
