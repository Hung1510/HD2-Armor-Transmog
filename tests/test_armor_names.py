#!/usr/bin/env python3
"""
Armor names (tools/armor_names.py): FileDiver's armor dump -> the mod's name table.

    python tests/test_armor_names.py

1. Ids are normalised (0xa9a71fe7 -> 0xA9A71FE7), kinds and the armor's passive and
   weight are kept, unknown names (FileDiver prints the hash) are left empty, broken
   entries are skipped and reported.
2. UTF-16 files (PowerShell's `>`) read the same as UTF-8 (Run-me.bat).
3. --check against a kits dump lists armors the game has that the table can't name
   (a new Warbond), and kind mismatches fail.
4. The tool, its build script and the table never go in a release zip.
"""
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import armor_names  # noqa: E402
import picker  # noqa: E402

failed = []


def check(cond, what):
    print(("ok    " if cond else "FAIL  ") + what)
    if not cond:
        failed.append(what)


SAMPLE = os.path.join(HERE, "fixtures", "armors-sample.json")

# ------------------------------------------------------------------ 1. conversion
kits, skipped = armor_names.convert(json.loads(armor_names.read_text(SAMPLE)))
cb = kits["0xA9A71FE7"]
check(cb == {"name": "SR-64 Cinderblock", "kind": "armor", "passive": "Siege-Ready", "weight": "heavy"},
      "an armor keeps its name, passive and weight (the armor pieces' majority)")
check(kits["0xAED67D10"]["weight"] == "light" and kits["0x2D61F0F9"] == {"name": "Some Helmet", "kind": "helmet"},
      "ids are upper-case 0x%08X; helmets and capes have no passive or weight")
check(kits["0x12345678"]["name"] == "", "a name FileDiver couldn't resolve (it prints the hash) is left empty")
check(skipped == ["not-an-id"], "an entry without a usable id is skipped and reported")
check(armor_names.norm_id(0xA9A71FE7) == "0xA9A71FE7" and armor_names.norm_id("0x0") is None, "ids as numbers work; 0 is not an id")
# FileDiver prints a known id's string instead of its hex; the id is its thin hash
# (0xB92E1781 was in the game's memory, kits-dump of 2026-10-01)
check(armor_names.norm_id("armor_warbond_5_3") == "0xB92E1781", "a named id (armor_warbond_5_3) resolves to the game's id")
check(armor_names.tidy("BFM-16 TANKER") == "BFM-16 Tanker" and armor_names.tidy("PILLAR OF THE ABYSS") == "Pillar of the Abyss"
      and armor_names.tidy("DP-8 Mountain-Scaled") == "DP-8 Mountain-Scaled", "names only in capitals are tidied; model codes stay")
try:
    armor_names.convert({"not": "a list"})
    check(False, "something that isn't FileDiver's list is refused")
except armor_names.NamesError:
    check(True, "something that isn't FileDiver's list is refused")

out = tempfile.mktemp(suffix=".json")
armor_names.write_table(kits, out, "armors-sample.json")
again = armor_names.load_table(out)
check(again == kits and list(again) == sorted(again), "the table round-trips and is sorted by id (small diffs)")

# ------------------------------------------------------------------ 2. UTF-16 input
u16 = tempfile.mktemp(suffix=".json")
with open(u16, "wb") as f:
    f.write(b"\xff\xfe" + open(SAMPLE, encoding="utf-8").read().encode("utf-16-le"))
check(armor_names.convert(json.loads(armor_names.read_text(u16)))[0] == kits, "a UTF-16 file (PowerShell >) reads the same")

# ------------------------------------------------------------------ 3. --check against the game
dump = tempfile.mktemp(suffix=".txt")
with open(dump, "w", encoding="utf-8") as f:
    f.write("kit 0xA9A71FE7 type 0 passive 16 (Siege-Ready) weight heavy\n"
            "kit 0xAED67D10 type 0 passive 13 (Reduced Signature) weight light\n"
            "kit 0x2D61F0F9 type 1 passive 0 (-) weight -\n"
            "kit 0xDEADBEEF type 0 passive 3 (Fortified) weight heavy\n")
missing, extra, wrong = armor_names.check(kits, dump)
check(missing == ["0xDEADBEEF"], "--check: an armor the game has but the table can't name is listed (new Warbond)")
check("0x4F079D05" in extra and not wrong, "--check: named but not in this dump is listed; kinds agree")
code = armor_names.main(["--check", dump, "-o", out])
check(code == 0, "the command-line check passes when only names are missing")
with open(dump, "a", encoding="utf-8") as f:
    f.write("kit 0x4F079D05 type 0 passive 3 (Fortified) weight heavy\n")       # the table says cape
check(armor_names.main(["--check", dump, "-o", out]) == 1, "... and fails on a kind mismatch")

# ------------------------------------------------------------------ 4. never in a release
check(not any("armor" in f for f in picker.RELEASE_TOOLS), "the names tool is not in the release allow-list")
check(os.path.exists(os.path.join(ROOT, "tools", "armor-names", "build.sh")), "the dumper build script is in the repo")

# ------------------------------------------------------------------ 5. other languages
# (the Japanese fixture's text is made up for the test; real text comes from the game)
out = tempfile.mkdtemp()
rc = armor_names.main([SAMPLE, "-o", os.path.join(out, "names.json"), "--passive-text", os.path.join(out, "pt.json"),
                       "--lang", "ja", os.path.join(HERE, "fixtures", "armors-sample-ja.json")])
names = json.load(open(os.path.join(out, "names.json"), encoding="utf-8"))["kits"]
pt = json.load(open(os.path.join(out, "pt.json"), encoding="utf-8"))["passives"]
check(rc == 0 and names["0xA9A71FE7"].get("names") == {"ja": "SR-64 シンダーブロック"},
      "--lang ja: each armor gets its Japanese name (matched by id)")
check(pt["Siege-Ready"]["ja"] == {"name": "攻城準備", "desc": "リロード速度が上昇"} and pt["Siege-Ready"]["en"]["desc"] == "Increases reload speed",
      "... and passive-text.json has each passive's name and description per language")
check(armor_names.main([SAMPLE, "-o", os.path.join(out, "n2.json"), "--lang", "xx", SAMPLE]) == 2, "an unknown language code is refused")

if failed:
    print("\n%d FAILED" % len(failed))
    sys.exit(1)
print("\nall armor name checks passed")
