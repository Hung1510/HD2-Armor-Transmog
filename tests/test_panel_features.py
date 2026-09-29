#!/usr/bin/env python3
"""
The panel's v4.4 features, driven through the fake game like a player would
(mouse clicks, keys, clipboard) and checked against the game's memory and files.

    python tests/test_panel_features.py

1. Plain-language values: 75% resist / +30% / +50 armor / 2 s shown and typed,
   converted to the game's numbers correctly.
2. Undo: button and Ctrl+Z.
3. Share codes: Copy code -> the web builder (docs/core.js) and picker.py read it;
   a web-builder link -> Paste code loads it; junk is refused.
4. Presets tab: load built-ins and the installed build, save / overwrite / rename /
   delete your own, kept across restarts.
5. Quick-swap key: cycles presets with the panel closed, draws a toast, can be off.
6. Settings: swap_hotkey validated the same in picker.py and the web builder;
   saves from 4.3 still load.
"""
import base64
import glob
import json
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import picker  # noqa: E402
from harness import FakeGame  # noqa: E402

F7, F9, ENTER, Z = 0x76, 0x78, 0x0D, 0x5A
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def f32(v):
    return struct.unpack("<f", struct.pack("<f", v))[0]


def build(text):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p))
    return path, p


def preset(name):
    return open(os.path.join(ROOT, "presets", name), encoding="utf-8").read()


def values(g, perk, mid):
    return sorted(round(v, 5) for m, t, v, _ in g.rows(perk) if m == mid)


def live_matches(g, text):
    """The game's rows for every stack in `text` equal what picker.py computes."""
    _, profs = picker.load_config_text(text)
    for p in profs:
        _, rows, stats = picker.CATALOG[p["perk"]]
        over = {(m, t): f32(v) for m, t, v, _ in p["overrides"]}
        want = [(m, t, over.get((m, t), f32(v))) for m, t, v in rows]
        seen = set(want)
        for m, t, v, _ in p["rows"]:
            r = (m, t, f32(v))
            if r not in seen:
                seen.add(r)
                want.append(r)
        got = [(m, t, v) for m, t, v, _ in g.rows(p["perk"])]
        if got != want:
            return False
    return True


def open_panel(g):
    g.key(F7)
    g.tick(120)


def node(js):
    r = subprocess.run(["node", "-e", js], capture_output=True, text=True, cwd=ROOT)
    return r.returncode, (r.stdout + r.stderr).strip()


# ------------------------------------------------------------------ 1. plain-language values
sink = preset("01-kitchen-sink.ini")
path, _ = build(sink)
appdata = tempfile.mkdtemp()
g = FakeGame(path, appdata=appdata)
g.tick(420)
open_panel(g)

g.click("sel:11")                                   # Inflammable: fire_damage_taken x0.25
check("75%" in g.texts(), "Inflammable shows 75% (resist), not x0.25")
g.click("inc:1")
check(f32(0.2) in [f32(v) for v in values(g, 7, 0x4DF29271)], "+ on 75% resist -> 80% -> game gets x0.20")
g.click("value:1")
g.type_text("90")
g.key(ENTER)
check(f32(0.1) in [f32(v) for v in values(g, 7, 0x4DF29271)], "typing 90 -> game gets x0.10")

g.click("sel:1")                                    # Extra Padding: armor_rating +1.0 = +50 armor
check("+50" in g.texts(), "Extra Padding shows +50 (armor), not +1")
g.click("value:1")
g.type_text("100")
g.key(ENTER)
check(2.0 in values(g, 7, 0xAFAE3B47), "typing 100 armor -> game gets +2.0")

g.click("sel:16")                                   # Siege-Ready reload x1.3
check("+30%" in g.texts(), "Siege-Ready reload shows +30%")
g.click("dec_big:1")
check(f32(1.05) in [f32(v) for v in values(g, 7, 0xCC530B21)], "-- on +30% -> +5% -> game gets x1.05")

g.click("sel:7")                                    # Med-Kit base: stims +2, stim duration 2 s
texts = g.texts()
check("+6" in texts and "2 s" in texts, "Med-Kit shows +6 stims (Kitchen Sink sets 6) and 2 s")
g.click("sel:9")
check("+100%" in g.texts(), "Democracy Protects death save x2.0 shows +100%")

# ------------------------------------------------------------------ 2. undo
before = values(g, 7, 0xCB814D05)
g.click("inc:1")
after = values(g, 7, 0xCB814D05)
g.click("undo")
check(after != before and values(g, 7, 0xCB814D05) == before, "Undo button puts the last change back")
g.click("inc_big:1")
g.ctrl(Z)
check(values(g, 7, 0xCB814D05) == before, "Ctrl+Z puts the last change back")
check(2.0 in values(g, 7, 0xAFAE3B47), "earlier changes are still there after undo")

# ------------------------------------------------------------------ 3. share codes
g.click("copy")
code = g.clipboard() or ""
check(code.startswith("https://hung1510.github.io/Super-Earth-Armory-Forge/#ini="), "Copy code puts a web-builder link on the clipboard")
ini = base64.urlsafe_b64decode(code.split("#ini=")[1] + "=" * (-len(code.split("#ini=")[1]) % 4)).decode()
check(live_matches(g, ini), "picker.py reads the copied code back to exactly the game's rows")
rc, out = node("""
const core=require('./docs/core.js'); const data=require('./docs/data.json'); const cat=core.makeCatalog(data);
const code=%s; const b=code.split('#ini=')[1].replace(/-/g,'+').replace(/_/g,'/');
const text=Buffer.from(b,'base64').toString('utf8');
const st=core.stateFromText(cat,text); const {profiles}=core.loadConfigText(cat, core.serializeIni(cat, st));
console.log(profiles.length+' '+profiles[0].enabled.length);""" % json.dumps(code))
check(rc == 0 and out.split()[0] == "1", "the web builder opens the copied code (%s)" % out[:60])

stealth = preset("03-stealth.ini")
rc, link = node("""
const core=require('./docs/core.js'); const data=require('./docs/data.json'); const cat=core.makeCatalog(data);
const ini=core.serializeIni(cat, core.stateFromText(cat, %s));
const b64=Buffer.from(ini,'utf8').toString('base64').replace(/\\+/g,'-').replace(/\\//g,'_').replace(/=+$/,'');
console.log('https://hung1510.github.io/HD2-Armor-Transmog/#ini='+b64);   // an old (pre-rename) link still pastes""" % json.dumps(stealth))
g.clipboard(link)
g.click("paste")
check(live_matches(g, stealth), "Paste code with a web-builder share link loads it into the game")
g.clipboard("hello, not a code")
g.click("paste")
check(live_matches(g, stealth) and any("No Armory Forge code" in t for t in g.texts()),
      "junk on the clipboard is refused with a message")
g.click("undo")
check(2.0 in values(g, 7, 0xAFAE3B47), "Undo after a paste brings the previous stacks back")

# ------------------------------------------------------------------ 4. presets tab
g.click("presets")
regs = g.regions()
check(all(k in regs for k in ["pre:installed:0"] + ["pre:builtin:%d" % i for i in range(1, 7)]),
      "Presets tab lists Installed build + the 6 built-in presets")
g.click("pre:builtin:2")
g.render("/tmp/pp-presets.png")
g.click("pload")
check(live_matches(g, preset("02-tank.ini")), "Load this preset (Tank) applies it")

g.click("presets")
g.click("psave")
g.type_text("My Tank")
g.key(ENTER)
mine = glob.glob(os.path.join(appdata, "**", "my-presets.txt"), recursive=True)
text = open(mine[0], encoding="utf-8").read() if mine else ""
check("### preset: My Tank" in text, "+ Save current stack, typed name 'My Tank' saved to my-presets.txt")
check(live_matches(g, "\n".join(l for l in text.split("### preset: My Tank")[1].split("### end")[0].splitlines()[1:])),
      "the saved preset holds the current stacks")

g.click("tab:1")
g.click("sel:2")
g.click("tick:2")                                   # Scout on
g.click("presets")
g.click("pre:user:1")
g.click("pover")
g.click("pover")
text = open(mine[0], encoding="utf-8").read()
check("Scout                              = on" in text, "Save current here (confirmed) overwrites your preset")
g.click("pren")
g.type_text("Scout Tank")
g.key(ENTER)
check("### preset: Scout Tank" in open(mine[0], encoding="utf-8").read(), "Rename works")

g2 = FakeGame(path, appdata=appdata)
g2.tick(420)
open_panel(g2)
g2.click("presets")
check("pre:user:1" in g2.regions() and "Scout Tank" in g2.texts(), "your presets are there after a restart")
g2.click("pre:user:1")
g2.click("pdel")
g2.click("pdel")
check("Scout Tank" not in open(mine[0], encoding="utf-8").read(), "Delete (confirmed) removes it")

# ------------------------------------------------------------------ 5. quick-swap
g3 = FakeGame(path, appdata=tempfile.mkdtemp())
g3.tick(420)
g3.key(F9)
g3.tick(3)
check(live_matches(g3, preset("01-kitchen-sink.ini")) and g3.state[b"ui"][b"open"] is False,
      "F9 with the panel closed: first built-in preset applied, panel stays closed")
check(any("Kitchen Sink" in t for t in g3.texts()) and any("ARMORY FORGE" in t for t in g3.texts()),
      "F9 draws a toast with the preset's name")
g3.render("/tmp/pp-toast.png", crop=False)
g3.tick(30)                                          # presses closer than 0.25 s are ignored on purpose
g3.key(F9)
g3.tick(3)
check(live_matches(g3, preset("02-tank.ini")), "F9 again: next preset (Tank)")
g3.tick(200)
check(g3.state[b"ui"] and not any("Tank" in t for t in g3.texts()), "the toast goes away after ~2 s")

g4 = FakeGame(path, appdata=appdata)            # appdata has no user presets left -> make one
g4.tick(420)
open_panel(g4)
g4.click("presets")
g4.click("psave")
g4.key(ENTER)
g4.key(F7)
g4.tick(10)
g4.key(F9)
g4.tick(3)
check(any("My preset 1" in t for t in g4.texts()), "with your own presets saved, F9 cycles those")

off = sink.replace("[settings]", "[settings]\nswap_hotkey = off", 1)
path_off, _ = build(off)
g5 = FakeGame(path_off, appdata=tempfile.mkdtemp())
g5.tick(420)
rows_before = g5.rows(7)
g5.key(F9)
g5.tick(3)
check(g5.rows(7) == rows_before, "swap_hotkey = off: F9 does nothing")

# ------------------------------------------------------------------ 6. settings + upgrade
for bad in ("F7", "F13", "banana"):
    try:
        picker.load_config_text("[settings]\nswap_hotkey = %s\n[profile: Med-Kit]\n" % bad)
        ok = False
    except picker.ConfigError:
        ok = True
    rc, out = node("""const core=require('./docs/core.js'),data=require('./docs/data.json'),cat=core.makeCatalog(data);
try{core.loadConfigText(cat,%s);console.log('accepted')}catch(e){console.log('refused')}"""
                   % json.dumps("[settings]\nswap_hotkey = %s\n[profile: Med-Kit]\n" % bad))
    check(ok and out == "refused", "swap_hotkey = %s refused by picker.py and the web builder" % bad)

path6, prof6 = build(preset("02-tank.ini"))
ad6 = tempfile.mkdtemp()
g6 = FakeGame(path6, appdata=ad6)
g6.tick(420)
open_panel(g6)
g6.click("sel:9")
g6.click("inc:1")
g6.key(F7)
g6.tick(120)
saved = glob.glob(os.path.join(ad6, "**", "loadout.ini"), recursive=True)[0]
old_style = "".join(l for l in open(saved, encoding="utf-8", newline="").readlines() if not l.startswith("swap_hotkey"))
open(saved, "w", encoding="utf-8", newline="").write(old_style)       # what 4.3 wrote
g7 = FakeGame(path6, appdata=ad6)
g7.tick(420)
check(g7.state[b"loadout_source"] == b"saved" and f32(1.55) in [f32(v) for v in values(g7, 7, 0xCB814D05)],
      "a loadout.ini saved by 4.3 (no swap_hotkey line) still loads after updating")

print("\n%d FAILED" % len(failed) if failed else "\nall panel feature checks passed")
sys.exit(1 if failed else 0)
