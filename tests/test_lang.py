#!/usr/bin/env python3
"""
6.2: the panel in Simplified Chinese (tools/lang_zh.lua; translation by hd2modpj).

    python tests/test_lang.py

1. Keys tab, 简体中文: the panel's labels, passive names, effects and messages are Chinese;
   names inside sentences are looked up too ("Reset Scout" -> "重置 侦察").
2. The data stays English: loadout.ini, share codes and the log don't change with the
   language, so a loadout saved in Chinese loads in English and back.
3. A game font without Chinese characters: the panel stays English and the Keys tab says
   to set the game's text language to Chinese. Punctuation the font lacks gets an ASCII
   stand-in instead of a "?".
4. Every view, both editions: nothing left in English but key names and codes.
"""
import base64
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import picker  # noqa: E402
from harness import FakeGame  # noqa: E402

F7 = 0x76
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def pid(name):
    return next(k for k, v in picker.CATALOG.items() if v[0].lower() == name.lower())


def build(text, **kw):
    s, p = picker.load_config_text(text)
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.compile_loadout(s, p, **kw))
    return path


def forge(app, name):
    return os.path.join(app, "CowboyBingus", "Helldivers2", "ArmoryForge", name)


def session(lua, lang="zh", missing=None, wear=None):
    app = tempfile.mkdtemp()
    os.makedirs(os.path.dirname(forge(app, "x")))
    with open(forge(app, "panel-position.txt"), "w", encoding="utf-8") as f:
        f.write("lang = %s\n" % lang)
    g = FakeGame(lua, appdata=app)
    g.missing_glyphs = missing
    if wear:
        g.wear(wear)
    g.tick(420)
    g.key(F7)
    g.tick(120)
    return g, app


def joined(g):
    return " | ".join(g.texts())


SINK = open(os.path.join(HERE, "..", "presets", "01-kitchen-sink.ini"), encoding="utf-8").read()

# ------------------------------------------------------------------ 1. Chinese
g, app = session(build(SINK), wear=pid("Med-Kit"))
t = joined(g)
check("军械" in t and "工坊" in t and "+ 护甲" in t and "预设" in t, "title and tabs in Chinese")
check("医疗包" in t and "额外垫料" in t, "passive names: the game's own Chinese names")
check("医疗包：" in t and "个被动已堆叠" in t, "the header (what you're wearing) in Chinese")
g.click("sel:%d" % pid("Scout"))
t = joined(g)
check("重置 侦察" in t, "names inside sentences are looked up too: 'Reset Scout' -> '重置 侦察'")
g.click("guide")
t = joined(g)
check("使用方法" in t and "操作" in t and "CTRL+Z" in t and "BACK" in t, "Guide tab in Chinese; key names stay as printed on the keys")
check(not any(x.startswith(("，", "。", "）")) for x in g.texts()), "wrapped Chinese lines never start with a closing mark")

# ------------------------------------------------------------------ 2. data stays English
g.click("tab:1")
g.click("copy")
code = (g.clipboard() or "").split("#ini=")[1]
share = base64.urlsafe_b64decode(code + "=" * (-len(code) % 4)).decode()
check("[profile: %d]" % pid("Med-Kit") in share and not re.search(r"[\u4e00-\u9fff]", share), "share codes stay as they were (no Chinese)")
g.click("tick:%d" % pid("Servo-Assisted"))
g.key(F7)
saved = open(forge(app, "loadout.ini"), encoding="utf-8").read()
check("[profile: Med-Kit]" in saved and "Servo-Assisted" in saved and not re.search(r"[一-鿿]", saved),
      "loadout.ini stays English")
s, p = picker.load_config_text(saved)
check(any(x["perk"] == pid("Med-Kit") for x in p), "... and loads anywhere (English panel, web builder)")
check(b"Chinese can be drawn" in (g.state[b"pp"][b"font_result"] or b""), "the font test finds the Chinese characters")

# ------------------------------------------------------------------ 3. the game font
gn, _ = session(build(SINK), missing="all")
t = joined(gn)
check("ARMORY" in t and "军械" not in t, "a font without Chinese: the panel stays English")
gn.click("settings")
check(any("set the game's text language to Chinese" in x for x in gn.texts()), "... and the Keys tab says why")
gp, _ = session(build(SINK), missing={"，", "。"})
t = joined(gp)
check("军械" in t and "，" not in t and "。" not in t, "punctuation the font lacks gets an ASCII stand-in, the rest is Chinese")

# ------------------------------------------------------------------ 4. coverage
ALLOWED = re.compile(r"(?i)(F\d+|CTRL.*|PGUP.*|PGDN|ENTER|ESC|BACK|START|D-PAD|LB|RB|R-STICK|CLICK|WHEEL|DRAG|V[\d.]+|"
                     r"KEYS TAB|ENGLISH|English|LANGUAGE  /  语言|.*CTRL.*|.*loadout\.ini.*|.*SHODAN.*|.*bug.*|.*Esc.*)")


def leftovers(g, seen):
    for x in g.texts():
        if re.search(r"[A-Za-z]{3,}", x) and not ALLOWED.fullmatch(x):
            seen.add(x)


seen = set()
g, _ = session(build(SINK), wear=pid("Med-Kit"))
for k in ["sel:summary", "sel:weight", "sel:%d" % pid("Med-Kit"), "sel:%d" % pid("Siege-Ready"), "add", "addcancel",
          "presets", "settings", "guide", "tab:1", "remove"]:
    if k in g.regions():
        g.click(k)
        leftovers(g, seen)
gs, _ = session(build("[settings]\nname = x\n[profile: Med-Kit]\n", blank=True, swap_only=True), wear=pid("Siege-Ready"))
leftovers(gs, seen)
gs.click("wear")
gs.click([k for k in gs.regions() if k.startswith("swap:")][2])
leftovers(gs, seen)
gs.click("guide")
leftovers(gs, seen)
check(not seen, "every view, both editions: nothing left in English but keys and codes%s"
      % ("".join("\n        " + x for x in sorted(seen))))

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall language checks passed")
