#!/usr/bin/env python3
"""
The research build (python tools/picker.py research): armor kit dump + weight experiment.

    python tests/test_research.py

1. Release and web-builder builds carry none of the research code.
2. The research build finds armor kit records (absolute pointers as loaded, and file-form
   relative ones), writes them to kits-dump.txt with every piece's slot and weight, and
   counts every table type it sees.
3. With --weight light, only the ARMOR pieces of ARMOR kits change; undergarments,
   helmets and capes are left alone, and passives still apply as usual.
4. With --weight none, nothing in memory changes.
"""
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import picker  # noqa: E402
from harness import GAME_BASE, FakeGame  # noqa: E402

TYPE_KIT = 0xD9A55AA0
failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


def lut_of(kid, slot):
    """a colour LUT hash too big for a Lua number, so a lossy copy would show"""
    return 0xFC00000000000001 + (kid << 20) + (slot << 4)


def kit_block(at, kid, ktype, passive, bodies, relative=False):
    """One LDLD block holding a HelldiverCustomizationKit at address `at` (the header).
    bodies: [(body_type, [(slot, piece_type, weight), ...]), ...]"""
    rec = at + 24
    body_off = 64
    piece_off = body_off + 24 * len(bodies)
    blob = bytearray(64)
    struct.pack_into("<IIIIIIII", blob, 0, kid, 0, 0x5E7, 1, 2, 3, 1, passive)
    struct.pack_into("<QII", blob, 32, 0xA0C1100000000000 + kid, ktype, 0)
    struct.pack_into("<qq", blob, 48, body_off if relative else rec + body_off, len(bodies))
    pieces = bytearray()
    weights_at = []
    for btype, plist in bodies:
        start = piece_off + len(pieces)
        blob += struct.pack("<IIqq", btype, 0, start if relative else rec + start, len(plist))
        for slot, ptype, weight in plist:
            weights_at.append((rec + piece_off + len(pieces) + 16, ptype, weight))
            p = bytearray(96)
            struct.pack_into("<QIIIIQ", p, 0, 0x9A7B000000000000 + slot, slot, ptype, weight, 0, lut_of(kid, slot))
            pieces += p
    blob += pieces
    hdr = b"LDLD" + struct.pack("<III", 1, TYPE_KIT, len(blob)) + b"\0" * 8
    return hdr + bytes(blob), weights_at


def game_with_kits(lua_path):
    g = FakeGame(lua_path, appdata=tempfile.mkdtemp())
    mem = g.mem[GAME_BASE]
    pieces = {}
    at = 0x10000
    for name, args in (
        ("armor", dict(kid=0x1111, ktype=0, passive=7, bodies=[(1, [(2, 0, 2), (3, 1, 1), (6, 0, 2)])])),
        ("helmet", dict(kid=0x2222, ktype=1, passive=0, bodies=[(1, [(0, 0, 2)])])),
        ("file-form", dict(kid=0x3333, ktype=0, passive=11, bodies=[(0, [(2, 0, 1)]), (1, [(2, 0, 1)])], relative=True)),
        ("cape", dict(kid=0x4444, ktype=2, passive=0, bodies=[(3, [(1, 0, 1)])])),
    ):
        block, weights = kit_block(GAME_BASE + at, **args)
        mem[at:at + len(block)] = block
        pieces[name] = weights
        at += (len(block) + 64 + 15) & ~15
    return g, pieces


def weight_now(g, addr):
    return struct.unpack("<I", g._read(addr, 4))[0]


def dump_of(g):
    path = os.path.join(os.environ["LOCALAPPDATA"], "CowboyBingus", "Helldivers2", "ArmoryForge", "kits-dump.txt")
    return open(path, encoding="utf-8").read() if os.path.exists(path) else ""


def build(weight, lut=16):
    s, _ = picker.load_config_text("[settings]\nname = x\n[profile: Med-Kit]\n")
    path = tempfile.mktemp(suffix=".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(picker.research_lua(s, weight, lut))
    return path


# ------------------------------------------------------------------ 1. not in releases
s, p = picker.load_config_text("[settings]\nname = x\n[profile: Med-Kit]\nFortified = on\n")
normal = picker.compile_loadout(s, p) + picker.compile_loadout(s, [], blank=True, swap_only=True)
check("research build only" not in normal and "research = {" not in normal,
      "normal and Passive Swap builds carry no research code")
check("research.lua" not in picker.RELEASE_TOOLS, "research.lua is not shipped in release zips")

# ------------------------------------------------------------------ 2 + 3. dump and light experiment
g, pieces = game_with_kits(build(0))
g.tick(1200)
text = dump_of(g)
check(g.phase() == "ready", "the research build still starts and applies passives")
check(all("kit 0x0000%s " % k in text for k in ("1111", "2222", "3333")), "kits-dump.txt lists the test's three kits")
check("kit 0x00001111 type 0 passive 7 (Med-Kit) weight heavy" in text, "a kit line has its passive and weight (as found)")
check("piece torso          type 0 weight heavy  path" in text and "-> light" in text,
      "every piece is listed with slot and weight, and changed ones say so")
check("type 0xD9A55AA0 " in text and "type 0x63CE0FEB " in text, "table types seen are counted")
check("  head " in text, "the first kits' raw bytes are included for checking the layout")
arm = pieces["armor"]
check(weight_now(g, arm[0][0]) == 0 and weight_now(g, arm[2][0]) == 0, "armor kit: armor pieces are now light")
check(weight_now(g, arm[1][0]) == 1, "armor kit: the undergarment piece is left alone")
check(weight_now(g, pieces["helmet"][0][0]) == 2, "helmet kits are left alone")
check(all(weight_now(g, a) == 0 for a, _, _ in pieces["file-form"]), "file-form (relative) pointers are followed too")
check("failed 0" in text and "pieces changed 0," not in text, "the dump counts the changes (%s)" %
      next((ln for ln in text.splitlines() if ln.startswith("pieces changed")), "-"))

# ------------------------------------------------------------------ 5. F10: where is the equipped armor?
LOAD = 0x30000000
g3, _ = game_with_kits(build(None, lut=7))
g3.mem[LOAD] = bytearray(0x10000)
struct.pack_into("<III", g3.mem[LOAD], 0x100, 0x1111, 0, 0)      # a loadout: armor, helmet, cape
struct.pack_into("<I", g3.mem[LOAD], 0x108, 0x2222)
struct.pack_into("<I", g3.mem[LOAD], 0x110, 0x4444)
struct.pack_into("<I", g3.mem[LOAD], 0x800, 0x1111)               # an armor id on its own: not a loadout
g3.tick(420)
lpath = os.path.join(os.environ["LOCALAPPDATA"], "CowboyBingus", "Helldivers2", "ArmoryForge", "loadout-research.txt")
g3.key(0x79)
g3.tick(300)
lt = open(lpath, encoding="utf-8").read() if os.path.exists(lpath) else ""
check("at 0x30000100: armor 0x00001111 (Med-Kit) | helmet 0x00002222 (+8) | cape 0x00004444 (+16)" in lt,
      "F10 finds the armor + helmet + cape ids stored together")
check("0x30000800" not in lt, "... and not an armor id on its own")
check(not any("0x%X" % (GAME_BASE + 0x10000) in ln for ln in lt.splitlines()), "... nor the kit records themselves")
struct.pack_into("<I", g3.mem[LOAD], 0x100, 0x3333)               # the player equips another armor
g3.key(0x79)
g3.tick(300)
lt = open(lpath, encoding="utf-8").read()
check("CHANGED 0x30000100: armor 0x00001111 (Med-Kit) -> armor 0x00003333 (Inflammable)" in lt,
      "F10 again: the place that now holds the new armor is reported")

# ------------------------------------------------------------------ 6. F11: another armor's colours
arm_pieces = [GAME_BASE + 0x10000 + 24 + 64 + 24 + i * 96 for i in range(3)]   # kit 0x1111, one body
before = [bytes(g3._read(a + 24, 8)) for a in arm_pieces]
known = {struct.pack("<Q", lut_of(0x3333, 2))} | {struct.pack("<Q", g3.lut(kid, s)) for kid in g3.kit_pieces for s in range(10)}
g3.key(0x7A)
after = [bytes(g3._read(a + 24, 8)) for a in arm_pieces]
check(after != before and all(a in known for a in after),
      "F11: the Med-Kit armor takes another armor's colour LUT, all 64 bits exact")
for presses in range(1, 60):  # noqa: B007 (reported below)
    if [bytes(g3._read(a + 24, 8)) for a in arm_pieces] == before:
        break
    g3.key(0x7A)
check([bytes(g3._read(a + 24, 8)) for a in arm_pieces] == before, "F11 after the last armor: its own colours back (%d presses)" % presses)

# ------------------------------------------------------------------ 4. dump only
g2, pieces2 = game_with_kits(build(None))
g2.tick(1200)
text2 = dump_of(g2)
check("experiment none (dump only)" in text2 and "pieces changed 0" in text2, "--weight none only dumps")
check(all(weight_now(g2, a) == w for kind in pieces2.values() for a, _, w in kind), "... and changes nothing in memory")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall research checks passed")
