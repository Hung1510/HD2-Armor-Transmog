#!/usr/bin/env python3
"""
Armor names: FileDiver's armor dump -> the mod's name table (tools/armor-names.json).

The game's memory only has armor ids (0xA9A71FE7); the names ("SR-64 Cinderblock") are in
its language files. tools/armor-names/ builds FileDiver's armor-set-json-dumper, which
reads a game install and prints every armor, helmet and cape with its id and name. This
script turns that output into a small, sorted, diff-friendly table the mod and the web
builder use (panel names, per-armor weight), and checks it against what the game had in
memory (ArmoryForge\\kits-dump.txt), so a new Warbond's armors show up as missing names.

    python tools/armor_names.py armors.json                      # writes tools/armor-names.json
    python tools/armor_names.py armors.json --check kits-dump.txt
    python tools/armor_names.py --check kits-dump.txt            # check the current table only
    python tools/armor_names.py armors.json --lang ja armors-ja.json --lang zh armors-zh.json

With --lang, each armor also gets its name in that language ("names": {"ja": ...}), and
tools/passive-text.json gets every armor passive's name and description in each language,
straight from the game's own text (matched to the English name through the kit ids).
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(HERE, "armor-names.json")
PASSIVE_TEXT = os.path.join(HERE, "passive-text.json")
LANGS = ("ja", "zh")
KINDS = {0: "armor", 1: "helmet", 2: "cape", "Armor": "armor", "Helmet": "helmet", "Cape": "cape"}
WEIGHTS = {0: "light", 1: "medium", 2: "heavy", "light": "light", "medium": "medium", "heavy": "heavy"}


class NamesError(Exception):
    pass


def read_text(path):
    """armors.json as Run-me.bat writes it (UTF-8), or as PowerShell's `>` does (UTF-16)."""
    raw = open(path, "rb").read()
    for bom, enc in ((b"\xff\xfe", "utf-16-le"), (b"\xfe\xff", "utf-16-be"), (b"\xef\xbb\xbf", "utf-8")):
        if raw.startswith(bom):
            return raw[len(bom):].decode(enc)
    if len(raw) > 1 and raw[1:2] == b"\0":
        return raw.decode("utf-16-le")
    return raw.decode("utf-8")


M64 = 0xFFFFFFFFFFFFFFFF


def murmur64a(data):
    """The engine's 64-bit string hash (MurmurHash64A, seed 0), as FileDiver's stingray.Sum."""
    mix, h = 0xC6A4A7935BD1E995, (len(data) * 0xC6A4A7935BD1E995) & M64
    full = len(data) - len(data) % 8
    for i in range(0, full, 8):
        k = (int.from_bytes(data[i:i + 8], "little") * mix) & M64
        k = ((k ^ (k >> 47)) * mix) & M64
        h = ((h ^ k) * mix) & M64
    tail = data[full:]
    if tail:
        h = ((h ^ int.from_bytes(tail, "little")) * mix) & M64
    h = ((h ^ (h >> 47)) * mix) & M64
    return h ^ (h >> 47)


def norm_id(v):
    """'0xa9a71fe7' / 2846301159 -> '0xA9A71FE7'. FileDiver prints the NAME instead of the
    hex when it knows the id's string (e.g. 'armor_warbond_5_3'): the id is then that
    string's thin hash, the top 32 bits of its 64-bit hash. None if it isn't an id."""
    if isinstance(v, int):
        n = v
    elif isinstance(v, str) and re.fullmatch(r"0x[0-9a-fA-F]{1,8}", v.strip()):
        n = int(v.strip(), 16)
    elif isinstance(v, str) and re.fullmatch(r"[a-z0-9_/]+", v.strip()):
        n = murmur64a(v.strip().encode()) >> 32
    else:
        return None
    return "0x%08X" % n if 0 < n < 2 ** 32 else None


def tidy(name):
    """'BFM-16 TANKER' -> 'BFM-16 Tanker': some names only exist in capitals; model codes
    (letters with digits) stay as they are, words get a capital first letter."""
    if not name or not name.isupper():
        return name
    words = []
    for i, w in enumerate(name.split(" ")):
        if re.search(r"\d", w):
            words.append(w)                              # BFM-16, CE-07
        elif i > 0 and w in ("OF", "THE", "AND", "A", "IN"):
            words.append(w.lower())
        else:
            words.append("-".join(p[:1] + p[1:].lower() for p in w.split("-")))
    return " ".join(words)


def majority_weight(kit):
    count = {}
    for body in kit.get("body_types") or []:
        for pc in body.get("pieces") or []:
            if pc.get("piece_type") in (0, "armor"):
                w = WEIGHTS.get(pc.get("weight"))
                if w:
                    count[w] = count.get(w, 0) + 1
    return max(count, key=count.get) if count else None


def convert(dump):
    """FileDiver armor-set-json-dumper output (a list of kits) -> {id: entry}"""
    if not isinstance(dump, list) or not dump:
        raise NamesError("expected FileDiver's armor list (a JSON array of kits)")
    out, skipped = {}, []
    for kit in dump:
        kid = norm_id(kit.get("id"))
        kind = KINDS.get(kit.get("kit_type"))
        name = (kit.get("name") or "").strip()
        if not kid or kind is None:
            skipped.append(str(kit.get("id")))
            continue
        if re.fullmatch(r"[0-9a-f]{8}", name):      # FileDiver prints the hash when the name isn't known
            name = ""
        name = tidy(name)
        entry = {"name": name, "kind": kind}
        passive = ((kit.get("passive") or {}).get("name") or "").strip()
        if kind == "armor" and passive:
            entry["passive"] = passive
        w = majority_weight(kit) if kind == "armor" else None
        if w:
            entry["weight"] = w
        if kid in out and out[kid] != entry:
            raise NamesError("id %s appears twice with different data" % kid)
        out[kid] = entry
    return out, skipped


def description(passive):
    d = passive.get("description") or ""
    return " ".join(x.strip() for x in d if x and x.strip()) if isinstance(d, list) else str(d).strip()


def localize(kits, english, other, code):
    """adds names[code] to kits from another language's dump (same ids); returns
    {english passive name: {"name": ..., "desc": ...}} for that language"""
    en = {norm_id(k.get("id")): k for k in english if isinstance(k, dict)}
    passives = {}
    for kit in other:
        if not isinstance(kit, dict):
            continue
        kid = norm_id(kit.get("id"))
        name = (kit.get("name") or "").strip()
        if kid in kits and name and not re.fullmatch(r"[0-9a-f]{8}", name):
            kits[kid].setdefault("names", {})[code] = tidy(name)
        base = en.get(kid)
        lp = kit.get("passive") or {}
        ep = (base or {}).get("passive") or {}
        if base and ep.get("name") and lp.get("name"):
            passives.setdefault(ep["name"].strip(), {"name": lp["name"].strip(), "desc": description(lp)})
    return passives


def passive_text(english, others):
    """{english passive name: {"en": {"desc"}, "ja": {"name", "desc"}, ...}}"""
    out = {}
    for kit in english:
        p = (kit or {}).get("passive") or {}
        if isinstance(kit, dict) and p.get("name") and KINDS.get(kit.get("kit_type")) == "armor":
            out.setdefault(p["name"].strip(), {"en": {"desc": description(p)}})
    for code, table in others.items():
        for name, t in table.items():
            if name in out:
                out[name][code] = t
    return {k: out[k] for k in sorted(out)}


def write_table(kits, path=TABLE, source=None):
    doc = {
        "about": "Armor, helmet and cape names by id, from FileDiver's armor-set-json-dumper "
                 "(tools/armor-names/). Regenerate: python tools/armor_names.py armors.json",
        "source": source or "",
        "kits": {k: kits[k] for k in sorted(kits)},
    }
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
        f.write("\n")


def load_table(path=TABLE):
    with open(path, encoding="utf-8") as f:
        return json.load(f)["kits"]


def kits_in_dump(path):
    """{id: kind} from ArmoryForge\\kits-dump.txt (what the game had in memory)"""
    out = {}
    for line in read_text(path).splitlines():
        m = re.match(r"kit (0x[0-9A-Fa-f]{8}) type (\d)", line)
        if m:
            out[norm_id(m.group(1))] = KINDS.get(int(m.group(2)), "?")
    return out


def check(kits, dump_path):
    """ids the game has that the table doesn't (new armors) and the other way round"""
    game = kits_in_dump(dump_path)
    missing = sorted(k for k in game if k not in kits or not kits[k]["name"])
    extra = sorted(k for k in kits if k not in game)
    wrong = sorted(k for k in game if k in kits and kits[k]["kind"] != game[k])
    return missing, extra, wrong


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    ap.add_argument("armors", nargs="?", help="armors.json from Run-me.bat (FileDiver output)")
    ap.add_argument("--check", metavar="KITS_DUMP", help="compare with ArmoryForge\\kits-dump.txt")
    ap.add_argument("-o", "--output", default=TABLE)
    ap.add_argument("--lang", nargs=2, action="append", metavar=("CODE", "FILE"), default=[],
                    help="another language's dump (%s), e.g. --lang ja armors-ja.json" % ", ".join(LANGS))
    ap.add_argument("--passive-text", default=PASSIVE_TEXT)
    args = ap.parse_args(argv)
    if not args.armors and not args.check:
        ap.error("give armors.json, --check kits-dump.txt, or both")
    try:
        if args.armors:
            english = json.loads(read_text(args.armors))
            kits, skipped = convert(english)
            others = {}
            for code, path in args.lang:
                if code not in LANGS:
                    raise NamesError("--lang %s: use one of %s" % (code, ", ".join(LANGS)))
                others[code] = localize(kits, english, json.loads(read_text(path)), code)
                print("%s: %d armor names, %d passives" % (code, sum(1 for e in kits.values() if code in e.get("names", {})),
                                                          len(others[code])))
            write_table(kits, args.output, os.path.basename(args.armors))
            if args.lang:
                with open(args.passive_text, "w", encoding="utf-8", newline="\n") as f:
                    json.dump({"about": "Armor passive names and descriptions in the game's own languages, from FileDiver's "
                                        "armor dump (tools/armor_names.py --lang).",
                               "passives": passive_text(english, others)}, f, indent=1, ensure_ascii=False)
                    f.write("\n")
                print("wrote %s" % args.passive_text)
            counts = {}
            for e in kits.values():
                counts[e["kind"]] = counts.get(e["kind"], 0) + 1
            unnamed = sum(1 for e in kits.values() if not e["name"])
            print("wrote %s: %s%s" % (args.output, ", ".join("%d %s" % (n, k) for k, n in sorted(counts.items())),
                                      ("; %d without a name" % unnamed) if unnamed else ""))
            if skipped:
                print("skipped %d entr%s without an id: %s" % (len(skipped), "y" if len(skipped) == 1 else "ies",
                                                                ", ".join(skipped[:5])))
        else:
            kits = load_table(args.output)
        if args.check:
            missing, extra, wrong = check(kits, args.check)
            print("checked against %s: %d in the game without a name, %d named but not in the game, %d kind mismatch"
                  % (args.check, len(missing), len(extra), len(wrong)))
            for k in missing[:20]:
                print("  no name: %s" % k)
            for k in wrong[:20]:
                print("  kind differs: %s" % k)
            return 1 if wrong else 0
    except (NamesError, ValueError, OSError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
