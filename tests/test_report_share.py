#!/usr/bin/env python3
"""
5.6: panel off, short share codes, the problem report, the value-edit hint.

    python tests/test_report_share.py

1. panel = off: the build still applies its loadout, but nothing reads keys or the
   controller and nothing is drawn. The status file says so.
2. Share codes are short (passives by number, only what is on or changed), and a code
   copied in game loads to the same loadout in picker.py (and so the web builder).
   Old long codes still paste.
3. The problem report counts panel key presses (also ones made while the game was not
   the active window), lists other mods on the update bus and new globals, lands in the
   status file and on the clipboard.
4. The full edition says how to edit values; the Passive Swap edition doesn't.
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


def build(text, **kw):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p, **kw))
    return path


def status_text(appdata):
    path = os.path.join(appdata, "CowboyBingus", "Helldivers2", "Logs", "ArmoryForge-STATUS.txt")
    return open(path, encoding="utf-8").read() if os.path.exists(path) else ""


def unb64(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4)).decode("utf-8")


def norm(profiles):
    """What a loadout does, whatever text it came from: tweaks equal to the game value drop out."""
    out = []
    for p in profiles:
        st = p["state"]
        defaults = {(pid, e[0]): e[3] for pid in [p["perk"]] + list(st["enabled"]) for e in picker.effects_of(pid)}
        tweaks = sorted((pid, k, v) for pid, k, v in st["tweaks"]
                        if v != defaults.get((pid, k)) and (pid == p["perk"] or pid in st["enabled"]))
        out.append((p["perk"], p["policy"], sorted(st["enabled"]), tweaks,
                    [tuple(r) for r in st["raw"]], [tuple(r) for r in st["raw_stats"]]))
    return out


sink = open(os.path.join(ROOT, "presets", "01-kitchen-sink.ini"), encoding="utf-8").read()

# ------------------------------------------------------------------ 1. panel = off
s, _ = picker.load_config_text("[settings]\npanel = off\n[profile: Med-Kit]\nFortified = on\n")
check(s["panel"] is False, "picker.py reads panel = off")
try:
    picker.load_config_text("[settings]\npanel = maybe\n[profile: Med-Kit]\n")
    check(False, "panel = maybe is refused")
except picker.ConfigError:
    check(True, "panel = maybe is refused")
lua_on = picker.compile_loadout(*picker.load_config_text(sink))
check("no_panel = true" not in lua_on, "builds with the panel on are unchanged (no new line)")
check("Panel off in this build" in picker.how_to_edit({"panel": False}) and "F7" in picker.how_to_edit({}),
      "the mod manager text says the panel is off instead of 'Press F7'")

app = tempfile.mkdtemp()
off = FakeGame(build(sink.replace("[settings]", "[settings]\npanel = off", 1)), appdata=app)
off.L.execute(b"""
CALLS = 0
local kd, pad = PP_TEST_INPUT.key_down, PP_TEST_INPUT.pad
PP_TEST_INPUT.key_down = function(...) CALLS = CALLS + 1 return kd(...) end
PP_TEST_INPUT.pad = function(...) CALLS = CALLS + 1 return pad(...) end
""")
off.tick(420)
off.pad_connect()
off.key(F7)
off.pad("BACK", "START")
off.tick(120)
g_ = off.L.globals()
check(off.phase() == "ready", "panel off: the mod still starts")
med = pid_of("Med-Kit")
check(off.rows(med) != [] and off.record_bytes(med) != off.pristine_record_bytes(med), "panel off: the loadout is still applied")
check(g_[b"CALLS"] == 0, "panel off: no key or controller is read (%d reads)" % g_[b"CALLS"])
check(off.state[b"ui"] is None and len(off.draw_calls()) == 0, "panel off: F7 and Back + Start draw nothing")
check("panel: off in this build" in status_text(app), "the status file says the panel is off")

# ------------------------------------------------------------------ 2. short share codes
app = tempfile.mkdtemp()
g = FakeGame(build(sink), appdata=app)
g.tick(420)
g.key(F7)
g.tick(120)
g.click("tab:1")
g.click("copy")
link = g.clipboard() or ""
code = link.split("#ini=", 1)[-1]
text = unb64(code)
long_code = len(base64.urlsafe_b64encode(g.state[b"serialize"]()).rstrip(b"="))
check(link.startswith("https://hung1510.github.io/Super-Earth-Armory-Forge/#ini="), "Copy code is still a web-builder link")
check(len(code) * 4 < long_code, "the code is under a quarter of the old length (%d vs %d characters)" % (len(code), long_code))
check("= off" not in text and "hotkey" not in text, "only what is on goes in; keys stay the reader's own")
s2, p2 = picker.load_config_text(text)
s1, p1 = picker.load_config_text(sink)
check(norm(p2) == norm(p1), "picker.py (and so the web builder) loads the code to the same loadout")

# it pastes back in game, and an old long code still pastes
g.click("clear")
g.click("clear")                                      # click twice to confirm
g.clipboard(link)
g.click("paste")
check(norm(picker.load_config_text(g.state[b"serialize"]().decode())[1]) == norm(p1),
      "the short code pastes back to the same loadout in game")
g.clipboard("https://hung1510.github.io/Super-Earth-Armory-Forge/#ini=" +
            base64.urlsafe_b64encode(sink.encode()).decode().rstrip("="))
g.click("paste")
check(norm(picker.load_config_text(g.state[b"serialize"]().decode())[1]) == norm(p1), "an old full-length code still pastes")

# ------------------------------------------------------------------ 3. problem report
app = tempfile.mkdtemp()
r = FakeGame(build(sink), appdata=app)
r.L.execute(b"ACTIVE = false; PP_TEST_INPUT.focused = function() return ACTIVE end")
r.tick(420)
r.L.execute(b"SOME_OTHER_MOD = {}; OCLAW_UPDATE_BUS.jobs.OtherMod = function() end")
r.key(F7)                                             # the game is not the active window
check(not r.state[b"ui"][b"open"], "F7 while another window is active does nothing")
r.L.execute(b"ACTIVE = true")
r.key(F7)
r.tick(400)                                           # the report is rewritten at most every 5 s
st = status_text(app)
check("panel key presses seen=1 (while the game was not the active window: 1)" in st,
      "the status file counts panel key presses, also the ones the game didn't get")
check("panel opened=1" in st and "drawn=" in st, "... and whether the panel opened and drew")
check("OtherMod" in st and "ArmoryForge" in st, "... the other mods sharing the update bus")
check("SOME_OTHER_MOD" in st, "... and globals other mods added")
r.click("settings")
check("report" in r.regions(), "the Keys tab has a Copy problem report button")
r.click("report")
clip = r.clipboard() or ""
check("problem report" in clip and "panel opened=1" in clip and "--- log (last 20) ---" in clip and "panel opened" in clip,
      "Copy problem report puts the report and the end of the log on the clipboard")
check(any("Problem report copied" in t for t in r.texts()), "... and says so")

# ------------------------------------------------------------------ 4. the value-edit hint
check(any("Click a name to edit its values" in t for t in g.texts()), "full edition: the header says names open their values")
sw = FakeGame(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True, swap_only=True), appdata=tempfile.mkdtemp())
sw.tick(420)
sw.key(F7)
sw.tick(120)
check(not any("edit its values" in t for t in sw.texts()), "Passive Swap edition: no value-edit hint")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall report / share checks passed")
