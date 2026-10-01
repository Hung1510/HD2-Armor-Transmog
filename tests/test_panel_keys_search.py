#!/usr/bin/env python3
"""
Keys tab and passive search, driven like a player would.

    python tests/test_panel_keys_search.py

1. Keys tab: pick the panel key and the quick-swap key (F1..F12, quick-swap also OFF).
   The new key opens the panel at once, the old one doesn't; keys never clash; they are
   saved, survive a restart, and are not undo steps.
2. A bad key in a hand-edited loadout.ini falls back to F7 / F9, so the panel always opens.
3. Search: Ctrl+F or a click, type, the lists (stack, + Armor, swap edition) show only
   matching passives, by name or effect; Esc and Clear bring everything back.
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

F = {n: 0x6F + n for n in range(1, 13)}          # F1..F12 virtual keys
ESC, ENTER, BACK = 0x1B, 0x0D, 0x08
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


def is_open(g):
    return bool(g.state[b"ui"][b"open"])


def forge(appdata):
    return os.path.join(appdata, "CowboyBingus", "Helldivers2", "ArmoryForge")


sink = open(os.path.join(ROOT, "presets", "01-kitchen-sink.ini"), encoding="utf-8").read()
LUA = build(sink)

# ------------------------------------------------------------------ 1. Keys tab
appdata = tempfile.mkdtemp()
g = FakeGame(LUA, appdata=appdata)
g.tick(420)
g.key(F[7])
g.tick(120)
check(is_open(g), "F7 opens the panel")
g.click("settings")
regs = g.regions()
check(all("key:hotkey:F%d" % n in regs for n in range(1, 13)) and "key:swap_hotkey:OFF" in regs,
      "the Keys tab lists F1..F12 for both keys, and OFF for quick-swap")
check(not regs["key:swap_hotkey:F7"][4], "the panel's own key can't be picked for quick-swap")
g.click("key:hotkey:F6")
check(any("opens with F6" in t for t in g.texts()), "a message says the panel key changed")
check(len(g.state[b"ui"][b"history"]) == 0, "changing a key is not an undo step")
g.key(F[7])
g.tick(30)
check(is_open(g), "the old key F7 no longer closes the panel")
g.key(F[6])
g.tick(30)
check(not is_open(g), "the new key F6 closes it")
g.key(F[6])
g.tick(120)
check(is_open(g), "... and opens it")
g.click("settings")
g.click("key:hotkey:F9")                      # F9 is the quick-swap key: it turns quick-swap off
g.tick(10)
g.click("key:hotkey:F6")
g.click("key:swap_hotkey:F10")
g.key(F[6])
g.tick(200)
ini = open(os.path.join(forge(appdata), "loadout.ini"), encoding="utf-8").read()
check("hotkey = F6" in ini and "swap_hotkey = F10" in ini, "the keys are saved to loadout.ini")
g2 = FakeGame(LUA, appdata=appdata)
g2.tick(420)
g2.key(F[6])
g2.tick(120)
check(is_open(g2), "after a restart F6 opens the panel")

# picking the quick-swap key as the panel key turns quick-swap off
g2.click("settings")
g2.click("key:hotkey:F10")
g2.tick(10)
check("key:swap_hotkey:OFF" in g2.regions(), "the Keys tab stays open after a change")
g2.key(F[10])
g2.tick(200)
ini = open(os.path.join(forge(appdata), "loadout.ini"), encoding="utf-8").read()
check("hotkey = F10" in ini and "swap_hotkey = OFF" in ini, "taking the quick-swap key for the panel turns quick-swap off")

# ------------------------------------------------------------------ 2. bad keys in the ini
appdata2 = tempfile.mkdtemp()
os.makedirs(forge(appdata2))
bad = sink.replace("[settings]", "[settings]\nhotkey = G\nswap_hotkey = F99", 1)
LUA_BLANK = build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True)
with open(os.path.join(forge(appdata2), "loadout.ini"), "w", encoding="utf-8") as f:
    f.write(bad)
g3 = FakeGame(LUA_BLANK, appdata=appdata2)
g3.tick(420)
g3.key(F[7])
g3.tick(120)
check(is_open(g3), "hotkey = G in loadout.ini: F7 still opens the panel")
g3.click("settings")
check(g3.regions()["key:hotkey:F7"][4] and any(t == "F9" for t in g3.texts()),
      "the Keys tab shows the keys that actually work (F7, F9)")

# ------------------------------------------------------------------ 3. search
g4 = FakeGame(LUA, appdata=tempfile.mkdtemp())
g4.tick(420)
g4.key(F[7])
g4.tick(120)
g4.click("tab:1")
all_ticks = {k for k in g4.regions() if k.startswith("tick:")}
g4.ctrl(0x46)                                   # Ctrl+F
g4.type_text("siege")
ticks = {k for k in g4.regions() if k.startswith("tick:")}
check(ticks == {"tick:%d" % pid_of("Siege-Ready")}, "Ctrl+F then 'siege': only Siege-Ready is listed (%s)" % sorted(ticks))
check(not any("f" == t[-1:] and "SIEGE" in t for t in g4.texts() if t.startswith("F")), "the F of Ctrl+F is not typed")
check(any(t.startswith("SIEGE") for t in g4.texts()), "the field shows what you typed")
for _ in range(5):
    g4.key(BACK)
g4.type_text("reload")
ticks = {k for k in g4.regions() if k.startswith("tick:")}
check(len(ticks) >= 2 and "tick:%d" % pid_of("Siege-Ready") in ticks,
      "'reload' finds passives by effect name (%d found)" % len(ticks))
g4.click("tick:%d" % pid_of("Siege-Ready"))
check(g4.state[b"ui"][b"search"] == b"reload", "ticking a result keeps the search")
g4.type_text("zzz")                              # not focused any more: typing does nothing
check(g4.state[b"ui"][b"search"] == b"reload", "typing while the field isn't focused changes nothing")
g4.click("search")
g4.type_text("zz")
base = "sel:%d" % pid_of("Med-Kit")
check(any("Nothing matches" in t for t in g4.texts()) and not any(k.startswith("sel:") and k not in (base, "sel:summary", "sel:weight") for k in g4.regions()),
      "no match: an empty list and a message")
g4.key(ESC)
check({k for k in g4.regions() if k.startswith("tick:")} == all_ticks, "Esc clears the search, the full list is back")
g4.click("search")
g4.type_text("scout")
g4.key(ENTER)
g4.click("search:clear")
check({k for k in g4.regions() if k.startswith("tick:")} == all_ticks, "Clear brings the full list back")
g4.click("add")
g4.click("search")
g4.type_text("grit")
picks = {k for k in g4.regions() if k.startswith("addpick:")}
check(picks == {"addpick:%d" % pid_of("True Grit")}, "+ Armor: search finds True Grit (%s)" % sorted(picks))

# swap edition list
g5 = FakeGame(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True, swap_only=True), appdata=tempfile.mkdtemp())
g5.tick(420)
g5.key(F[7])
g5.tick(120)
g5.click("tab:1")
g5.ctrl(0x46)
g5.type_text("padding")
opts = {k for k in g5.regions() if k.startswith("swap:")}
check("swap:0" in opts and "swap:%d" % pid_of("Extra Padding") in opts and "swap:%d" % pid_of("Scout") not in opts,
      "swap edition: search filters the list and keeps Original")

# ------------------------------------------------------------------ 4. found in review
g6 = FakeGame(LUA, appdata=tempfile.mkdtemp())
g6.tick(420)
g6.key(F[7])
g6.tick(120)
g6.click("tab:1")
g6.click("tick:%d" % pid_of("Scout"))            # an undoable change
g6.click("settings")
g6.click("key:hotkey:F6")
g6.ctrl(0x5A)                                     # Ctrl+Z
check(is_open(g6), "Ctrl+Z with the panel open")
g6.key(F[6])
g6.tick(30)
check(not is_open(g6), "Ctrl+Z undoes the last change but keeps the new panel key (F6 still closes the panel)")

g7 = FakeGame(LUA, appdata=tempfile.mkdtemp())
g7.tick(420)
g7.key(F[7])
g7.tick(120)
g7.click("tab:1")
g7.ctrl(0x46)
g7.type_text("re")
g7.ctrl(0x30)                                     # Ctrl+0 while typing
g7.ctrl(0x5A)                                     # Ctrl+Z while typing
check(g7.state[b"ui"][b"search"] == b"re", "Ctrl shortcuts aren't typed into the search field (%r)" % g7.state[b"ui"][b"search"])

_s, _ = picker.load_config_text("[settings]\nname = x\n[profile: Med-Kit]\n")
LUA_EMPTY = tempfile.mktemp(suffix=".lua")
with open(LUA_EMPTY, "w", encoding="utf-8") as f:
    f.write(picker.compile_loadout(_s, [], blank=True))       # nothing stacked: the "Empty" screen
g8 = FakeGame(LUA_EMPTY, appdata=tempfile.mkdtemp())
g8.tick(420)
g8.key(F[7])
g8.tick(120)
g8.ctrl(0x46)
g8.type_text("abc")
check(not g8.state[b"ui"][b"search_on"] and g8.state[b"ui"][b"search"] == b"",
      "Ctrl+F on the empty screen (no search field shown) does nothing")

appdata9 = tempfile.mkdtemp()
os.makedirs(forge(appdata9))
with open(os.path.join(forge(appdata9), "loadout.ini"), "w", encoding="utf-8") as f:
    f.write(sink.replace("[settings]", "[settings]\nhotkey = G\nswap_hotkey = F9", 1))
g9 = FakeGame(LUA_BLANK, appdata=appdata9)
g9.tick(420)
g9.key(F[7])
g9.tick(120)
g9.click("tab:1")
g9.click("tick:%d" % pid_of("Scout"))
g9.key(F[7])
g9.tick(200)
ini = open(os.path.join(forge(appdata9), "loadout.ini"), encoding="utf-8").read()
check("hotkey = F7" in ini and "hotkey = G" not in ini, "a bad key in the ini is replaced by the default when saved")

many = "[settings]\nname = many\n" + "".join("[profile: %s]\nScout = on\n" % n for n in
       ("Concussive Padding, Reinforced", "Concussive Padding, Grenadier", "Kinetic Displacement Mitigation",
        "Supplemental Adrenaline", "Integrated Explosives"))
g10 = FakeGame(build(many), appdata=tempfile.mkdtemp())
g10.tick(420)
g10.key(F[7])
g10.tick(120)
check(all("tab:%d" % n in g10.regions() for n in range(1, 6)), "5 armor stacks with long names: every tab is reachable")

# 12 stacks (BONHakyla's case, at 150%): the tab row scrolls with < >, nothing is cut off
names = [v[0] for k, v in sorted(picker.CATALOG.items()) if k != 7][:12]
twelve = "[settings]\nname = many\npanel_scale = 1.5\n" + "".join("[profile: %s]\nScout = on\n" % n for n in names)
g11 = FakeGame(build(twelve), appdata=tempfile.mkdtemp())
g11.set_resolution(1920, 1080)
g11.tick(420)
g11.key(F[7])
g11.tick(120)
regs = g11.regions()
shown = [n for n in range(1, 13) if "tab:%d" % n in regs]
check("tabs:next" in regs and "tabs:prev" in regs and 1 in shown and 12 not in shown,
      "12 stacks: the tab row gets < > arrows (%d tabs shown)" % len(shown))
for _ in range(12):
    if "tab:12" in g11.regions():
        break
    g11.click("tabs:next")
check("tab:12" in g11.regions(), "> scrolls until the last stack's tab shows")
g11.click("tab:12")
check(g11.state[b"ui"][b"tab"] == 12 and any(names[11].upper()[:6] in t for t in g11.texts()),
      "... and it opens: stack 12 can be edited")
first_before = g11.state[b"ui"][b"tab_first"]
g11.click("tabs:prev")
check(g11.state[b"ui"][b"tab_first"] == first_before - 1 and g11.state[b"ui"][b"tab"] == 12,
      "< scrolls back one tab (and doesn't change the open stack)")
g11.click("presets")
g11.pad_connect()
g11.tick(70)
g11.pad("BACK", "START")
g11.tick(120)
g11.pad("BACK", "START")
g11.tick(120)
seen = set()
for _ in range(16):
    g11.pad("RB")
    t = g11.state[b"ui"][b"tab"]
    if not (g11.state[b"ui"][b"adding"] or g11.state[b"ui"][b"presets"] or g11.state[b"ui"][b"settings"]):
        seen.add(t)
        if t in (8, 12):
            check("tab:%d" % t in g11.regions(), "RB to stack %d brings its tab into view" % t)
check(seen == set(range(1, 13)), "RB reaches all 12 stacks (%s)" % sorted(seen))

# ------------------------------------------------------------------ language (6.2 groundwork)
appl = tempfile.mkdtemp()
gl = FakeGame(LUA, appdata=appl)
gl.tick(420)
gl.key(0x76)
gl.tick(120)
gl.click("settings")
check(all("lang:" + c in gl.regions() for c in ("en", "zh", "ja")), "Keys tab: Language buttons English / 简体中文 / 日本語")
gl.click("lang:ja")
pos = open(os.path.join(appl, "CowboyBingus", "Helldivers2", "ArmoryForge", "panel-position.txt"), encoding="utf-8").read()
check(gl.state[b"ui"][b"lang"] == b"ja" and "lang = ja" in pos, "picking one is saved")
check(any("日本語" in t for t in gl.texts()), "... and says so in that language")
gl.click("report")
check("language=ja; font test:" in (gl.clipboard() or ""), "the problem report has the language and the font test")
gl2 = FakeGame(LUA, appdata=appl)
gl2.tick(420)
gl2.key(0x76)
gl2.tick(120)
check(gl2.state[b"ui"][b"lang"] == b"ja", "the language is remembered next session")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall keys and search checks passed")
