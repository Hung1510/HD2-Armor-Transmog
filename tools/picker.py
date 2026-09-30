#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Super Earth Armory Forge - build a Helldivers 2 armour-passive stack from a plain config
=======================================================================================
Started from mostlycloudy's Passive Picker v3 (engine credit: mostlycloudy, SHODAN).
v3 is configured by commenting out hex rows inside the mod's Lua; Armory Forge
generates that Lua from a readable loadout.ini and edits it live in game.

  python tools/picker.py init                      # write a fresh loadout.ini
  python tools/picker.py list                      # every passive + effect + default
  python tools/picker.py build loadout.ini         # preview what will be built
  python tools/picker.py build loadout.ini --zip "My Stack.zip"   # installable mod

Python 3.8+, no third-party packages. If `lupa` is installed the generated Lua
is syntax-checked before packing (pip install lupa).
"""
from __future__ import annotations

import argparse
import configparser
import difflib
import json
import math
import os
import re
import struct
import sys
import uuid
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE_FILES = [os.path.join(HERE, f) for f in ("engine.lua", "panel.lua", "main.lua")]

MOD_ID = "mods/community/passive_picker_v4"
GLOBAL = "ArmoryForge"
TITLE = "Super Earth Armory Forge"
VERSION = "5.2"
AUTHOR = "mostlycloudy (original v3), Hung1510 (v4 edit)"
DEFAULT_HOTKEY = "F7"
DEFAULT_PANEL_SCALE = 1.0      # F7 panel size, 0.8 .. 1.5
DEFAULT_SWAP_HOTKEY = "F9"     # F6 = Refresh Operations, F8 = SHODAN Stat Editor

# --------------------------------------------------------------------------- catalog
# type: 0 Set, 1 Add, 2 Multiply, 3 Time
TYPE_NAMES = {0: "set", 1: "add", 2: "mul", 3: "time"}

# modifier id -> (effect key, hint). Names are INFERRED from the passive
# descriptions; the game only knows the hashes. '?' marks a guess.
EFFECTS = {
    0xAFAE3B47: ("armor_rating", "add; 1.0 = +50 armour"),
    0x21A7BA64: ("radar_ping", "time; seconds between radar pings"),
    0x14ECCE15: ("detection_radius", "mul; 0.7 = -30%"),
    0xC36935A9: ("crouch_prone_recoil", "mul; 0.7 = -30%"),
    0x1F98D152: ("explosive_damage_taken", "mul; 0.5 = 50% resist"),
    0x4BDF39C4: ("arc_damage_taken", "mul; 0.05 = 95% resist"),
    0x8933E7F4: ("arc_secondary", "mul; arc-related, exact effect ?"),
    0xF6FA9626: ("throwables", "add; extra grenades"),
    0x2875F44A: ("stims", "add; extra stims"),
    0x93EB16A7: ("stim_duration", "time; extra seconds"),
    0x26C969A1: ("throw_range", "mul; 1.3 = +30%"),
    0x86A99BB9: ("limb_health", "mul; 1.5 = +50%"),
    0xCB814D05: ("death_save", "mul; 1.5 = the stock 50% chance. 2.0 = 100%? (untested)"),
    0xA68930C2: ("chest_bleed", "mul; 0.0 = no chest bleeding"),
    0xCC530B21: ("primary_reload_speed", "mul; 1.3 = +30%"),
    0xFBF54A40: ("limb_injury_avoid", "mul; 1.5 = stock 50% chance"),
    0x2559B40D: ("melee_damage", "mul; 1.4 = +40%"),
    0x4DF29271: ("fire_damage_taken", "mul; 0.25 = 75% resist"),
    0xC8CCB6FA: ("ergonomics", "add; +ergo"),
    0x0DFF0E42: ("melee_flag", "set; flag, effect ?"),
    0x6E99CCE5: ("gas_damage_taken", "mul; 0.2 = 80% resist"),
    0x73734D67: ("flinch", "set; 0.0 = no flinch"),
    0xB5A50096: ("elemental_damage_taken", "mul; fire/gas/acid/arc"),
    0x33C9C713: ("ammo_capacity", "mul; 1.2 = +20% ?"),
    0x54A69284: ("death_explosion_delay", "time; seconds"),
    0xB4F88129: ("sidearm_reload_speed", "mul; 1.4 = +40%"),
    0xAD5289FE: ("sidearm_draw_speed", "mul; 1.5 = +50%"),
    0x22035F3C: ("sidearm_recoil", "mul; 0.3 = -70%"),
    0x00000000: ("revive_marker", "set; placeholder row - revive is probably tied to perk id"),
    0x2CFAECA3: ("chest_damage_taken", "mul; 0.75 = 25% resist"),
    0xAF8B7112: ("movement_noise", "mul; 0.5 = -50%"),
    0x432A7993: ("poi_range", "mul; 1.3 = +30%"),
    0xB62B4AFD: ("leg_injury_immunity", "set; 1.0 = immune"),
    0x11A3C04C: ("stagger", "mul; 0.7 = -30%"),
    0xA189ADB6: ("stamina_on_damage", "add"),
    0x25A59469: ("impact_damage_taken", "mul; 0.7 = -30%"),
    0xCD79A687: ("move_speed_a", "mul; walk or run speed ?"),
    0xF6D67313: ("move_speed_b", "mul; walk or run speed ?"),
    0x6938BD56: ("slide_flag", "set; slide-related ?"),
    0x35F17BEC: ("support_reload_speed", "mul; 1.3 = +30%"),
}
STAT_EFFECTS = {
    11: ("stat_flinch", "stat; 0.05 = -95%"),
    12: ("stat_ammo_capacity", "stat; 1.2 = +20%"),
    13: ("stat_primary_reload", "stat; 1.3 = +30%"),
    14: ("stat_support_reload", "stat; 1.3 = +30%"),
    15: ("stat_sidearm_reload", "stat"),
    16: ("stat_sidearm_draw", "stat"),
    17: ("stat_sidearm_recoil", "stat"),
}

# perk id -> (name, [(modifier_id, type, value)], [(stat, unk1, unk2)])
CATALOG = {
    1: ("Extra Padding", [(0xAFAE3B47, 1, 1.0)], []),
    2: ("Scout", [(0x21A7BA64, 3, 2.0), (0x14ECCE15, 2, 0.7)], []),
    3: ("Fortified", [(0xC36935A9, 2, 0.7), (0x1F98D152, 2, 0.5)], []),
    5: ("Electrical Conduit", [(0x4BDF39C4, 2, 0.05), (0x8933E7F4, 2, 0.05)], []),
    6: ("Engineering Kit", [(0xC36935A9, 2, 0.7), (0xF6FA9626, 1, 2.0)], []),
    7: ("Med-Kit", [(0x2875F44A, 1, 2.0), (0x93EB16A7, 3, 2.0)], []),
    8: ("Servo-Assisted", [(0x26C969A1, 2, 1.3), (0x86A99BB9, 2, 1.5)], []),
    9: ("Democracy Protects", [(0xCB814D05, 2, 1.5), (0xA68930C2, 2, 0.0)], []),
    10: ("Reinforced Epaulettes", [(0xCC530B21, 2, 1.3), (0xFBF54A40, 2, 1.5),
                                   (0x2559B40D, 2, 1.2)], [(13, 0.0, 1.3)]),
    11: ("Inflammable", [(0x4DF29271, 2, 0.25)], []),
    12: ("Peak Physique", [(0x2559B40D, 2, 1.4), (0xC8CCB6FA, 1, 30.0),
                           (0x0DFF0E42, 0, 1.0)], []),
    13: ("Advanced Filtration", [(0x6E99CCE5, 2, 0.2)], []),
    14: ("Unflinching", [(0x73734D67, 0, 0.0), (0xAFAE3B47, 1, 0.5),
                         (0x21A7BA64, 3, 2.0)], [(11, 0.0, 0.05)]),
    15: ("Acclimated", [(0xB5A50096, 2, 0.5), (0x8933E7F4, 2, 0.05)], []),
    16: ("Siege-Ready", [(0xCC530B21, 2, 1.3), (0x33C9C713, 2, 1.2)],
          [(13, 0.0, 1.3), (12, 0.0, 1.2)]),
    17: ("Integrated Explosives", [(0x54A69284, 3, 1.5), (0xF6FA9626, 1, 2.0)], []),
    18: ("Gunslinger", [(0xB4F88129, 2, 1.4), (0xAD5289FE, 2, 1.5), (0x22035F3C, 2, 0.3)],
          [(15, 0.0, 1.6), (16, 0.0, 1.5), (17, 0.0, 0.3)]),
    19: ("Adreno-Defibrillator", [(0x00000000, 0, 0.0), (0x93EB16A7, 3, 2.0),
                                  (0x4BDF39C4, 2, 0.5), (0x8933E7F4, 2, 0.05)], []),
    20: ("Ballistic Padding", [(0x2CFAECA3, 2, 0.75), (0x1F98D152, 2, 0.75),
                               (0xA68930C2, 2, 0.0)], []),
    21: ("Desert Stormer", [(0xB5A50096, 2, 0.6), (0x8933E7F4, 2, 0.06),
                            (0x26C969A1, 2, 1.2)], []),
    31: ("Feet First", [(0xAF8B7112, 2, 0.5), (0x432A7993, 2, 1.3), (0xB62B4AFD, 0, 1.0)], []),
    32: ("Reduced Signature", [(0xAF8B7112, 2, 0.5), (0x14ECCE15, 2, 0.6)], []),
    33: ("Rock-Solid", [(0x2559B40D, 2, 1.4), (0x0DFF0E42, 0, 1.0), (0x11A3C04C, 2, 0.7)], []),
    34: ("Supplemental Adrenaline", [(0xA189ADB6, 1, 2.0), (0xAFAE3B47, 1, 0.5)], []),
    35: ("Concussive Padding, Reinforced", [(0x1F98D152, 2, 0.5), (0xAFAE3B47, 1, 0.6)], []),
    36: ("Concussive Padding, Grenadier", [(0x1F98D152, 2, 0.5), (0xF6FA9626, 1, 2.0)], []),
    37: ("Concussive Padding, Hazmat", [(0x1F98D152, 2, 0.5), (0x6E99CCE5, 2, 0.75),
                                        (0x22035F3C, 2, 0.7)], [(17, 0.0, 0.7)]),
    38: ("Oxygenator", [(0xCD79A687, 2, 1.1), (0xF6D67313, 2, 1.1), (0x6938BD56, 0, 0.0)], []),
    39: ("Kinetic Displacement Mitigation", [(0x4DF29271, 2, 0.5), (0xFBF54A40, 2, 1.5),
                                             (0x25A59469, 2, 0.7)], []),
    40: ("Blunt-Force Mitigation", [(0x11A3C04C, 2, 0.7), (0x25A59469, 2, 0.7),
                                    (0xAFAE3B47, 1, 0.5)], []),
    41: ("True Grit", [(0x35F17BEC, 2, 1.3), (0xC8CCB6FA, 1, 20.0)], [(14, 0.0, 1.3)]),
}
ALIASES = {"rocksolid": 33, "supplementaryadrenaline": 34, "medkit": 7}


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


PERK_BY_NAME = {norm(n): pid for pid, (n, _, _) in CATALOG.items()}
PERK_BY_NAME.update(ALIASES)


def find_perk(text: str, where: str) -> int:
    t = text.strip()
    if t.isdigit() and int(t) in CATALOG:
        return int(t)
    pid = PERK_BY_NAME.get(norm(t))
    if pid is None:
        names = [n for n, _, _ in CATALOG.values()]
        close = difflib.get_close_matches(t, names, n=3, cutoff=0.5)
        hint = (" Did you mean: " + ", ".join(close) + "?") if close else ""
        raise ConfigError("%s: unknown passive '%s'.%s" % (where, t, hint))
    return pid


def effects_of(pid):
    """[(key, kind, ident, default, hint)] for one passive; kind 'row' or 'stat'."""
    name, rows, stats = CATALOG[pid]
    out = []
    for mid, typ, val in rows:
        key, hint = EFFECTS[mid]
        out.append((key, "row", (mid, typ), val, hint))
    for stat, u1, u2 in stats:
        key, hint = STAT_EFFECTS[stat]
        out.append((key, "stat", (stat, u1), u2, hint))
    return out


class ConfigError(Exception):
    pass


# --------------------------------------------------------------------------- config
TRUE = {"on", "yes", "true", "1", "y"}
FALSE = {"off", "no", "false", "0", "n", ""}


def num(text: str, where: str) -> float:
    try:
        v = float(text)
    except ValueError:
        raise ConfigError("%s: '%s' is not a number" % (where, text))
    if math.isnan(v) or math.isinf(v):
        raise ConfigError("%s: value must be finite" % where)
    return v


def strength(typ, v):
    """How far a value is from 'no effect'. Used by conflicts = strongest."""
    if typ == 2:
        return math.inf if v <= 0 else abs(math.log(v))
    return abs(v)


def load_config(path):
    with open(path, encoding="utf-8") as f:
        return load_config_text(f.read(), path)


def load_config_text(text, source="<loadout>"):
    cp = configparser.ConfigParser(delimiters=("=",), inline_comment_prefixes=(";", "#"),
                                   interpolation=None, strict=True)
    cp.optionxform = str
    cp.read_string(text, source)

    settings = {"retire": True, "name": None, "hotkey": None, "swap_hotkey": None, "panel_scale": None}
    if cp.has_section("settings"):
        s = cp["settings"]
        for k, v in s.items():
            if k == "retire":
                settings["retire"] = v.strip().lower() in TRUE
            elif k == "name":
                settings["name"] = v.strip()
            elif k == "hotkey":
                hk = v.strip().upper()
                if not re.match(r"^F([1-9]|1[0-2])$", hk):
                    raise ConfigError("[settings]: hotkey must be F1..F12, got '%s'" % v.strip())
                settings["hotkey"] = hk
            elif k == "swap_hotkey":
                hk = v.strip().upper()
                if not re.match(r"^(F([1-9]|1[0-2])|OFF)$", hk):
                    raise ConfigError("[settings]: swap_hotkey must be F1..F12 or off, got '%s'" % v.strip())
                settings["swap_hotkey"] = hk
            elif k == "panel_scale":
                try:
                    sc = float(v.strip().rstrip("%")) / (100.0 if v.strip().endswith("%") else 1.0)
                except ValueError:
                    raise ConfigError("[settings]: panel_scale must be a number from 0.8 to 1.5, got '%s'" % v.strip())
                if not (0.8 - 1e-9 <= sc <= 1.5 + 1e-9):
                    raise ConfigError("[settings]: panel_scale must be from 0.8 to 1.5, got '%s'" % v.strip())
                settings["panel_scale"] = math.floor(sc * 10 + 0.5) / 10.0     # half up, like the web builder and the game
            elif k == "base":
                pass            # written by the in-game panel; only the game reads it
            else:
                raise ConfigError("[settings]: unknown key '%s'" % k)

    if settings["swap_hotkey"] and settings["swap_hotkey"] == (settings["hotkey"] or DEFAULT_HOTKEY):
        raise ConfigError("[settings]: swap_hotkey and hotkey must be different keys")
    profiles = []
    for sec in cp.sections():
        if sec == "settings":
            continue
        m = re.match(r"^\s*profile\s*:\s*(.+?)\s*$", sec, re.I)
        if not m:
            raise ConfigError("[%s]: sections must be [settings] or [profile: <passive>]" % sec)
        profiles.append(build_profile(m.group(1), cp[sec], "[%s]" % sec))
    if not profiles:
        raise ConfigError("no [profile: <passive>] section found")
    seen = {}
    for p in profiles:
        if p["perk"] in seen:
            raise ConfigError("two profiles use the same trigger passive: %s" % p["name"])
        seen[p["perk"]] = True
    return settings, profiles


def parse_raw(text, where, stat):
    out = []
    for chunk in filter(None, (c.strip() for c in text.split(","))):
        parts = chunk.split()
        if len(parts) != 3:
            raise ConfigError("%s: raw entry '%s' needs 3 parts" % (where, chunk))
        a = int(parts[0], 0)
        if stat:
            out.append((a, num(parts[1], where), num(parts[2], where)))
        else:
            b = int(parts[1], 0)
            if b not in TYPE_NAMES:
                raise ConfigError("%s: raw type must be 0..3" % where)
            out.append((a, b, num(parts[2], where)))
    return out


def build_profile(trigger_text, sec, where):
    trigger = find_perk(trigger_text, where)
    policy = "stack"
    enabled = []
    tweaks = {}          # (pid, key) -> value
    raw_rows, raw_stats = [], []
    notes = []

    for k, v in sec.items():
        lk = k.strip().lower()
        if lk == "conflicts":
            policy = v.strip().lower()
            if policy not in ("stack", "strongest"):
                raise ConfigError("%s: conflicts must be 'stack' or 'strongest'" % where)
        elif lk == "raw":
            raw_rows += parse_raw(v, where + " raw", stat=False)
        elif lk == "raw_stats":
            raw_stats += parse_raw(v, where + " raw_stats", stat=True)
        elif "." in k:
            pname, _, ekey = k.rpartition(".")
            pid = find_perk(pname, where)
            keys = {e[0]: e for e in effects_of(pid)}
            if ekey.strip() not in keys:
                raise ConfigError("%s: %s has no effect '%s'. It has: %s"
                                  % (where, CATALOG[pid][0], ekey.strip(), ", ".join(keys)))
            tweaks[(pid, ekey.strip())] = num(v, "%s %s" % (where, k))
        else:
            pid = find_perk(k, where)
            val = v.strip().lower()
            if val in TRUE:
                if pid == trigger:
                    notes.append("%s is the trigger; its own effects are always on "
                                 "(tweak them with %s.<effect>)" % (CATALOG[pid][0], CATALOG[pid][0]))
                elif pid not in enabled:
                    enabled.append(pid)
            elif val not in FALSE:
                raise ConfigError("%s: '%s = %s' must be on or off" % (where, k, v))

    # tweaks on a passive that is neither enabled nor the trigger do nothing
    for (pid, key) in tweaks:
        if pid != trigger and pid not in enabled:
            notes.append("tweak %s.%s ignored: %s is off" % (CATALOG[pid][0], key, CATALOG[pid][0]))

    rows, stats = [], []           # (id, typ, val, source) / (stat, u1, u2, source)
    for pid in sorted(enabled):
        pname = CATALOG[pid][0]
        for key, kind, ident, default, _ in effects_of(pid):
            val = tweaks.get((pid, key), default)
            if kind == "row":
                rows.append((ident[0], ident[1], val, "%s.%s" % (pname, key)))
            else:
                stats.append((ident[0], ident[1], val, "%s.%s" % (pname, key)))
    for r in raw_rows:
        rows.append((r[0], r[1], r[2], "raw"))
    for r in raw_stats:
        stats.append((r[0], r[1], r[2], "raw_stats"))

    # trigger's own effects -> overrides when tweaked
    overrides, stat_overrides = [], []
    tname = CATALOG[trigger][0]
    base_rows = {}
    for key, kind, ident, default, _ in effects_of(trigger):
        val = tweaks.get((trigger, key), default)
        if kind == "row":
            base_rows[ident] = val
            if val != default:
                overrides.append((ident[0], ident[1], val, "%s.%s" % (tname, key)))
        elif val != default:
            stat_overrides.append((ident[0], ident[1], val, "%s.%s" % (tname, key)))

    rows, row_report = resolve(rows, policy, lambda r: (r[0], r[1]), lambda r: (r[1], r[2]))
    stats, stat_report = resolve(stats, policy, lambda r: r[0], lambda r: (2, r[2]))

    # rows that land on a base-perk modifier: same value -> skipped by the engine,
    # different value -> stacks with the base perk
    for r in rows:
        if (r[0], r[1]) in base_rows:
            bv = base_rows[(r[0], r[1])]
            if r[2] == bv:
                notes.append("%s duplicates the trigger's own effect (applied once)" % r[3])
            else:
                notes.append("%s stacks ON TOP of the trigger's own %s (%s)"
                             % (r[3], fmt(bv), TYPE_NAMES[r[1]]))

    state = dict(
        enabled=sorted(enabled),
        tweaks=[(pid, key, val) for (pid, key), val in tweaks.items() if pid == trigger or pid in enabled],
        raw=raw_rows, raw_stats=raw_stats)
    return dict(perk=trigger, name=tname, policy=policy, rows=rows, stats=stats, state=state,
                enabled=[CATALOG[pid][0] for pid in sorted(enabled)],
                tweaked=sorted("%s.%s" % (CATALOG[pid][0], key) for (pid, key) in tweaks),
                overrides=overrides, stat_overrides=stat_overrides,
                notes=notes + row_report + stat_report)


def resolve(rows, policy, ident, typ_val):
    """Collapse exact duplicates; apply the conflict policy to same-ident rows."""
    report = []
    groups = {}
    order = []
    for r in rows:
        g = ident(r)
        if g not in groups:
            groups[g] = []
            order.append(g)
        groups[g].append(r)
    out = []
    for g in order:
        rs = groups[g]
        uniq = []
        for r in rs:
            if all(u[2] != r[2] for u in uniq):
                uniq.append(r)
            else:
                report.append("%s duplicates an identical row (applied once)" % r[3])
        if len(uniq) > 1:
            if policy == "strongest":
                best = max(uniq, key=lambda r: strength(*typ_val(r)))
                report.append("conflict on %s: kept %s = %s, dropped %s" % (
                    uniq[0][3].split(".")[-1], best[3], fmt(best[2]),
                    ", ".join("%s = %s" % (u[3], fmt(u[2])) for u in uniq if u is not best)))
                uniq = [best]
            else:
                report.append("conflict on %s: all apply together (%s)" % (
                    uniq[0][3].split(".")[-1],
                    ", ".join("%s = %s" % (u[3], fmt(u[2])) for u in uniq)))
        out += uniq
    return out, report


def fmt(v):
    return ("%g" % v)


# --------------------------------------------------------------------------- lua
def lua_num(v):
    r = repr(float(v))
    return r if ("e" in r or "." in r) else r + ".0"


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'


def catalog_lua():
    L = ["-- ================================================================ catalog",
         "-- Generated by tools/picker.py from its CATALOG / EFFECTS tables. Effect names are",
         "-- inferred from the passive descriptions; see TESTING.md for what is confirmed.",
         "local CATALOG = {"]
    for pid, (name, rows, stats) in CATALOG.items():
        L.append("    { id = %d, name = %s, rows = { %s }, stats = { %s } }," % (
            pid, lua_str(name),
            ", ".join("{ 0x%08X, %d, %s }" % (m, ty, lua_num(v)) for m, ty, v in rows),
            ", ".join("{ %d, %s, %s }" % (s, lua_num(a), lua_num(b)) for s, a, b in stats)))
    L.append("}")
    L.append("local EFFECT_NAMES = {")
    for mid, (key, hint) in EFFECTS.items():
        L.append("    [0x%08X] = { %s, %s }," % (mid, lua_str(key), lua_str(hint)))
    L.append("}")
    L.append("local STAT_NAMES = {")
    for stat, (key, hint) in STAT_EFFECTS.items():
        L.append("    [%d] = { %s, %s }," % (stat, lua_str(key), lua_str(hint)))
    L.append("}")
    L.append("local ALIASES = {")
    for k, v in ALIASES.items():
        L.append("    [%s] = %d," % (lua_str(k), v))
    L.append("}")
    return "\n".join(L) + "\n\n"


def engine_text():
    """Everything after the MOD table: catalog, engine, panel, startup."""
    parts = [catalog_lua()]
    for path in ENGINE_FILES:
        with open(path, encoding="utf-8") as f:
            parts.append(f.read())
    return "\n".join(parts)


def generate_lua(settings, profiles, blank=False):
    L = []
    L.append("-- Generated by tools/picker.py from a loadout.ini. Edit the ini (or use the in-game panel), not this.")
    L.append("local MOD = {")
    L.append("    id = '%s'," % MOD_ID)
    L.append("    global = '%s'," % GLOBAL)
    L.append("    title = '%s'," % TITLE)
    L.append("    version = '%s'," % VERSION)
    L.append("    author = '%s'," % AUTHOR)
    L.append("    log = '%s.log'," % GLOBAL)
    L.append("    name = %s," % lua_str(settings["name"] or TITLE))
    L.append("    retire = %s," % ("true" if settings["retire"] else "false"))
    L.append("    hotkey = '%s'," % (settings.get("hotkey") or DEFAULT_HOTKEY))
    L.append("    swap_hotkey = '%s'," % (settings.get("swap_hotkey") or DEFAULT_SWAP_HOTKEY))
    L.append("    panel_scale = %.1f," % (settings.get("panel_scale") or DEFAULT_PANEL_SCALE))
    if blank:
        L.append("    blank = true,   -- the release: nothing built in; keeps what you make in the panel")
    L.append("    type_passive = 0x63CE0FEB,   -- HelldiverCustomizationPassiveBonusSettings")
    L.append("    type_kit     = 0xD9A55AA0,   -- HelldiverCustomizationKit")
    L.append("    -- the loadout this build starts with; the in-game panel starts from it")
    L.append("    default = {")
    for p in profiles:
        st = p["state"]
        L.append("        {")
        L.append("            perk = %d, name = %s, conflicts = '%s'," % (p["perk"], lua_str(p["name"]), p["policy"]))
        L.append("            enabled = { %s }," % ", ".join(str(x) for x in st["enabled"]))
        L.append("            tweaks = {")
        for pid, key, val in st["tweaks"]:
            L.append("                { %d, '%s', %s }," % (pid, key, lua_num(val)))
        L.append("            },")
        L.append("            raw = {")
        for r in st["raw"]:
            L.append("                { 0x%08X, %d, %s }," % (r[0] % (1 << 32), r[1], lua_num(r[2])))
        L.append("            },")
        L.append("            raw_stats = {")
        for r in st["raw_stats"]:
            L.append("                { %d, %s, %s }," % (r[0], lua_num(r[1]), lua_num(r[2])))
        L.append("            },")
        L.append("        },")
    L.append("    },")
    L.append("    -- built-in presets: the panel's Presets tab and the quick-swap key")
    L.append("    presets = {")
    for name, text in builtin_presets():
        L.append("        { name = %s, text = [==[" % lua_str(name))
        L.append(text.rstrip("\n"))
        L.append("]==] },")
    L.append("    },")
    L.append("}")
    L.append("")
    return "\n".join(L) + "\n" + engine_text()


PRESET_NAME = re.compile(r"^[ \t]*name[ \t]*=[ \t]*([^;#\r\n]+)", re.M)


def builtin_presets():
    """[(name, ini text)] from presets/*.ini, in file order (same rule in docs/core.js)."""
    out = []
    for path in preset_files(os.path.join(os.path.dirname(HERE), "presets")):
        with open(path, encoding="utf-8") as f:
            text = f.read().replace("\r\n", "\n")
        m = PRESET_NAME.search(text)
        name = m.group(1).strip() if m else os.path.splitext(os.path.basename(path))[0]
        if "]==]" in text:
            raise ConfigError("%s contains ']==]', which the Lua long string cannot hold" % path)
        out.append((name, text))
    return out


# --------------------------------------------------------------------------- archive
# Archive + envelope format unchanged from mostlycloudy's passive_picker.py.
MAGIC = 0xF0000011
TYPE = 0xA14E8DFA2CD117E2
ENVELOPE_VERSION = 2
FAMILY = "9ba626afa44a3aa3"
ARCHIVE_NAME = FAMILY + ".patch_0"
GUID_NS = uuid.UUID("6f9619ff-8b86-d011-b42d-00c04fc964ff")
_M = (1 << 64) - 1
_MIX = 0xC6A4A7935BD1E995


def resource_hash(name):
    data = name.encode("utf-8")
    value = len(data) * _MIX & _M
    end = len(data) // 8 * 8
    for (word,) in struct.iter_unpack("<Q", data[:end]):
        word = word * _MIX & _M
        word ^= word >> 47
        value = (value ^ (word * _MIX & _M)) * _MIX & _M
    if data[end:]:
        value = (value ^ int.from_bytes(data[end:], "little")) * _MIX & _M
    value ^= value >> 47
    value = value * _MIX & _M
    return value ^ (value >> 47)


def make_archive(resources):
    pairs = [(resource_hash(n), r) for n, r in sorted(resources.items())]
    count = len(pairs)
    offset = (104 + 80 * count + 15) & ~15
    entries, body = bytearray(), bytearray(offset)
    for index, (name_hash, resource) in enumerate(pairs):
        entries += struct.pack("<7Q6I", name_hash, TYPE, offset,
                               0, 0, 0, 0, len(resource), 0, 0, 16, 16, index)
        body += resource
        body += b"\0" * (-len(body) % 16)
        offset = len(body)
    header = struct.pack("<III20sQQ24s", MAGIC, 1, count, b"", offset, 0, b"")
    types = struct.pack("<IIQIIII", 0, 0, TYPE, count, 0, 16, 16)
    body[:104 + len(entries)] = header + types + entries
    return bytes(body)


def write_zip(archive, out, display, description):
    guid = str(uuid.uuid5(GUID_NS, MOD_ID))
    manifest = {
        "Version": 1, "Guid": guid, "Name": display, "Description": description,
        "Options": [{"Name": display, "Description": description, "Include": ["Addon"]}],
    }
    files = {
        "manifest.json": (json.dumps(manifest, indent=2) + "\n").encode(),
        "Addon/" + ARCHIVE_NAME: archive,
        "Addon/" + ARCHIVE_NAME + ".stream": b"",
        "Addon/" + ARCHIVE_NAME + ".gpu_resources": b"",
    }
    d = os.path.dirname(os.path.abspath(out))
    os.makedirs(d, exist_ok=True)
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for p, content in sorted(files.items()):
            info = zipfile.ZipInfo(p, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, content)
    return guid


def compile_lua(text):
    try:
        from lupa.luajit21 import LuaRuntime
    except Exception:
        try:
            from lupa import LuaRuntime
        except Exception:
            return None, "lupa not installed - skipped (pip install lupa)"
    lua = LuaRuntime(unpack_returned_tuples=True)
    f = lua.eval("function(s,n) local fn,e = (loadstring or load)(s,n); return fn ~= nil, e end")
    ok, err = f(text, "armory_forge")
    return ok, err


def compile_loadout(settings, profiles, blank=False):
    """Full Lua text (with the HD2-Addon marker) for one loadout."""
    return "-- HD2-Addon: " + MOD_ID + "\n" + generate_lua(settings, profiles, blank)


def archive_for(full_lua):
    body = full_lua.encode("utf-8")
    return make_archive({MOD_ID: struct.pack("<II", len(body), ENVELOPE_VERSION) + body})


def describe_profiles(profiles):
    return "; ".join("%s armour: %s" % (
        p["name"], ", ".join(enabled_names(p)) or "base perk tweaks only") for p in profiles)


def enabled_names(p):
    return list(p["enabled"])


CREDIT = ("Super Earth Armory Forge by Hung1510. Engine started from Passive Picker v3 by mostlycloudy. "
          "Requires Bingus Shared Loader. Single-player / private lobbies only.")


# --------------------------------------------------------------------------- commands
def print_plan(settings, profiles):
    for p in profiles:
        print("Profile: wear armour with %s (perk %d)   conflicts = %s"
              % (p["name"], p["perk"], p["policy"]))
        if p["overrides"] or p["stat_overrides"]:
            print("  base perk changed:")
            for r in p["overrides"] + p["stat_overrides"]:
                print("    %-40s -> %s" % (r[3], fmt(r[2])))
        print("  adds %d passive rows, %d stat rows:" % (len(p["rows"]), len(p["stats"])))
        cur = None
        def order(r):
            src = r[3].split(".")[0]
            pid = PERK_BY_NAME.get(norm(src), 999)
            return pid
        for r in sorted(p["rows"] + p["stats"], key=order):
            src = r[3].split(".")[0]
            if src != cur:
                print("    %s" % src)
                cur = src
            print("      %-34s %s" % (r[3].split(".")[-1], fmt(r[2])))
        for n in p["notes"]:
            print("  note: %s" % n)
        print()


def cmd_build(args):
    try:
        settings, profiles = load_config(args.config)
    except (ConfigError, configparser.Error) as e:
        print("CONFIG ERROR: %s" % e)
        return 1
    print_plan(settings, profiles)
    full = compile_loadout(settings, profiles)
    ok, err = compile_lua(full)
    print("Lua syntax        : %s" % ("OK" if ok else ("skipped - " + err if ok is None else "FAIL: %s" % err)))
    if ok is False:
        print("REFUSING to pack. This is a bug in the generator; report it with your loadout.ini.")
        return 1
    if args.dump_lua:
        os.makedirs(os.path.dirname(os.path.abspath(args.dump_lua)), exist_ok=True)
        with open(args.dump_lua, "w", encoding="utf-8", newline="\n") as f:
            f.write(full)
        print("Wrote Lua         : %s" % args.dump_lua)
    if not args.zip:
        print("\nPreview only. Add --zip \"My Stack.zip\" to build the installable mod.")
        return 0
    archive = archive_for(full)
    display = args.name or settings["name"] or TITLE
    desc = "v%s. Press %s in game to edit. %s. %s" % (VERSION, settings.get("hotkey") or DEFAULT_HOTKEY,
                                                     describe_profiles(profiles), CREDIT)
    guid = write_zip(archive, args.zip, display, desc)
    print("Wrote zip         : %s  (%d bytes Lua, guid %s)" % (args.zip, len(full.encode("utf-8")), guid))
    print("Install it with your mod manager. Remove the original Passive Picker v3 first.")
    return 0


def _zip_write(z, path, content):
    info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    z.writestr(info, content)


def preset_files(folder):
    return sorted(os.path.join(folder, f) for f in os.listdir(folder) if f.endswith(".ini"))


def cmd_release(args):
    """The release zip: one blank build (no mod-manager options). Everything is picked in
    game with the panel; the presets ride along inside it for the Presets tab."""
    root = os.path.dirname(HERE)
    settings, _ = load_config_text("[settings]\nname = %s\n[profile: Med-Kit]\n" % TITLE)
    full = compile_loadout(settings, [], blank=True)
    ok, err = compile_lua(full)
    if ok is False:
        print("Lua FAIL: %s" % err)
        return 1
    presets = builtin_presets()
    for name, _ in presets:
        print("  preset in the panel: %s" % name)
    guid = str(uuid.uuid5(GUID_NS, MOD_ID))
    manifest = {
        "Version": 1, "Guid": guid, "Name": TITLE,
        "Description": "v%s. Press %s in game to open the armory: tick any armor passives, "
                       "change their values live, save and swap loadouts (%s). Or build one at "
                       "https://hung1510.github.io/Super-Earth-Armory-Forge/ . %s"
                       % (VERSION, DEFAULT_HOTKEY, DEFAULT_SWAP_HOTKEY, CREDIT),
    }
    icon = os.path.join(root, "docs", "icon.png")
    if os.path.exists(icon):
        manifest["IconPath"] = "icon.png"
    extras = ["README.md", "CREDITS.txt", "CHANGELOG.md", "TESTING.md", "loadout.ini"]
    trees = ["tools", "examples", "presets"]
    archive = archive_for(full)
    os.makedirs(os.path.dirname(os.path.abspath(args.zip)), exist_ok=True)
    with zipfile.ZipFile(args.zip, "w", compression=zipfile.ZIP_DEFLATED) as z:
        _zip_write(z, "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode())
        if os.path.exists(icon):
            _zip_write(z, "icon.png", open(icon, "rb").read())
        _zip_write(z, ARCHIVE_NAME, archive)
        _zip_write(z, ARCHIVE_NAME + ".stream", b"")
        _zip_write(z, ARCHIVE_NAME + ".gpu_resources", b"")
        for f in extras:
            fp = os.path.join(root, f)
            if os.path.exists(fp):
                _zip_write(z, f, open(fp, "rb").read())
        for tree in trees:
            for dirpath, dirs, files in os.walk(os.path.join(root, tree)):
                dirs[:] = [d for d in dirs if d != "__pycache__"]
                for f in sorted(files):
                    fp = os.path.join(dirpath, f)
                    _zip_write(z, os.path.relpath(fp, root).replace(os.sep, "/"),
                               open(fp, "rb").read())
    print("Wrote release     : %s  (blank build, %d presets in the panel, guid %s)" % (args.zip, len(presets), guid))
    return 0


def cmd_export_web(args):
    """Write docs/data.json: catalog, effect names, engine and presets for the web builder."""
    root = os.path.dirname(HERE)
    data = {
        "mod_id": MOD_ID, "global": GLOBAL, "title": TITLE, "version": VERSION,
        "default_hotkey": DEFAULT_HOTKEY, "default_swap_hotkey": DEFAULT_SWAP_HOTKEY,
        "default_panel_scale": DEFAULT_PANEL_SCALE,
        "author": AUTHOR, "credit": CREDIT, "guid": str(uuid.uuid5(GUID_NS, MOD_ID)),
        "catalog": [{"id": pid, "name": n, "rows": [list(r) for r in rows],
                     "stats": [list(s) for s in stats]}
                    for pid, (n, rows, stats) in CATALOG.items()],
        "effects": {str(k): list(v) for k, v in EFFECTS.items()},
        "stat_effects": {str(k): list(v) for k, v in STAT_EFFECTS.items()},
        "aliases": ALIASES,
        "engine": engine_text(),
        "presets": [{"file": os.path.basename(p), "ini": open(p, encoding="utf-8").read()}
                    for p in preset_files(os.path.join(root, "presets"))],
    }
    text = json.dumps(data, indent=1, sort_keys=True) + "\n"
    if args.check:
        cur = open(args.output, encoding="utf-8").read() if os.path.exists(args.output) else ""
        if cur != text:
            print("%s is out of date: run  python tools/picker.py export-web" % args.output)
            return 1
        print("%s is up to date" % args.output)
        return 0
    with open(args.output, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("Wrote %s (%d bytes)" % (args.output, len(text)))
    return 0


# --------------------------------------------------------------------------- check-dump
def _f32(v):
    return struct.unpack("<f", struct.pack("<f", float(v)))[0]


def _short(v):
    """Shortest decimal that is the same float32 (what you'd type into CATALOG)."""
    x = _f32(v)
    for p in range(1, 10):
        s = "%.*g" % (p, x)
        if _f32(float(s)) == x:
            break
    else:
        s = repr(x)
    return s if any(c in s for c in ".en") else s + ".0"


def default_dump_path():
    base = os.environ.get("LOCALAPPDATA")
    if not base:
        return None
    for leaf in ("ArmoryForge", "PassivePicker"):
        path = os.path.join(base, "CowboyBingus", "Helldivers2", leaf, "passives-dump.txt")
        if os.path.exists(path):
            return path
    return os.path.join(base, "CowboyBingus", "Helldivers2", "ArmoryForge", "passives-dump.txt")


def parse_dump(path):
    meta, perks, cur = {}, {}, None
    with open(path, encoding="utf-8") as f:
        for line in f:
            w = line.split()
            if not w or w[0].startswith("#"):
                continue
            if w[0] == "perk":
                cur = {"name": int(w[3], 16) if len(w) > 3 else 0, "modified": "modified" in w,
                       "rows": [], "stats": []}
                perks[int(w[1])] = cur
            elif w[0] == "row" and cur is not None:
                cur["rows"].append((int(w[1], 16), int(w[2]), float(w[3])))
            elif w[0] == "stat" and cur is not None:
                cur["stats"].append((int(w[1]), float(w[2]), float(w[3])))
            elif w[0] == "end":
                cur = None
            else:
                meta[w[0]] = " ".join(w[1:])
    return meta, perks


def catalog_line(pid, name, rows, stats):
    r = ", ".join("(0x%08X, %d, %s)" % (m, ty, _short(v)) for m, ty, v in rows)
    s = ", ".join("(%d, %s, %s)" % (st, _short(a), _short(b)) for st, a, b in stats)
    return "    %d: (%s, [%s], [%s])," % (pid, json.dumps(name), r, s)


def cmd_check_dump(args):
    path = args.dump or default_dump_path()
    if not path or not os.path.exists(path):
        print("No dump found at %s" % path)
        print("Start the game once with the mod installed; it writes passives-dump.txt")
        print("to %LOCALAPPDATA%\\CowboyBingus\\Helldivers2\\ArmoryForge\\ when its scan finishes.")
        return 2
    meta, perks = parse_dump(path)
    print("Dump      : %s" % path)
    print("Written   : %s by mod v%s, game.dll stamp %s" % (meta.get("written", "?"), meta.get("mod", "?"),
                                                           meta.get("game_stamp", "?")))
    print("In game   : %d armor passives; in CATALOG: %d" % (len(perks), len(CATALOG)))
    print()

    def game_rows(e):
        return [(m, ty, _f32(v)) for m, ty, v in e["rows"]], [(s, _f32(a), _f32(b)) for s, a, b in e["stats"]]

    issues = 0
    new_effects, new_stats = {}, {}
    for pid in sorted(perks):
        e = perks[pid]
        rows, stats = game_rows(e)
        for m, ty, _ in rows:
            if m not in EFFECTS:
                new_effects.setdefault(m, (ty, pid))
        for st, _, _ in stats:
            if st not in STAT_EFFECTS:
                new_stats.setdefault(st, pid)
        if e["modified"]:
            print("WARNING   perk %d was already changed by another mod when dumped; its values may not be the game's." % pid)
            issues += 1
        if pid == 0 and rows in ([], [(0, 0, 0.0)]) and not stats:
            print("OK        perk 0 is the game's empty \"no passive\" entry (gear without a passive); ignored.")
            continue
        if pid not in CATALOG:
            issues += 1
            print("NEW       perk %d (name hash 0x%08X): not in CATALOG. Add to CATALOG in tools/picker.py,"
                  " then replace the name:" % (pid, e["name"]))
            print(catalog_line(pid, "NEW PASSIVE %d" % pid, rows, stats))
            print()
            continue
        name, crow, cstat = CATALOG[pid]
        want_rows = [(m, ty, _f32(v)) for m, ty, v in crow]
        want_stats = [(s, _f32(a), _f32(b)) for s, a, b in cstat]
        if rows != want_rows or stats != want_stats:
            issues += 1
            print("CHANGED   perk %d %s: the game's values differ from CATALOG." % (pid, name))
            gone = [("row", r) for r in want_rows if r not in rows] + [("stat", s) for s in want_stats if s not in stats]
            added = [("row", r) for r in rows if r not in want_rows] + [("stat", s) for s in stats if s not in want_stats]
            for kind, r in gone:
                print("          was  %s" % _describe(kind, r))
            for kind, r in added:
                print("          now  %s" % _describe(kind, r))
            print("          replace its CATALOG line with:")
            print(catalog_line(pid, name, rows, stats))
            print()
    for pid in sorted(set(CATALOG) - set(perks)):
        issues += 1
        print("MISSING   perk %d %s: in CATALOG but not in the game (removed or renumbered?)." % (pid, CATALOG[pid][0]))
    if new_effects or new_stats:
        print()
        print("New effect ids: add to EFFECTS / STAT_EFFECTS in tools/picker.py with a real name:")
        for m, (ty, pid) in sorted(new_effects.items()):
            print('    0x%08X: ("effect_%08x", "%s; ? (first seen on perk %d)"),' % (m, m, TYPE_NAMES.get(ty, "?"), pid))
        for st, pid in sorted(new_stats.items()):
            print('    %d: ("stat_%d", "stat; ? (first seen on perk %d)"),' % (st, st, pid))
    print()
    if issues:
        print("%d difference(s). After editing tools/picker.py run:" % issues)
        print("  python tools/picker.py export-web")
        print("  python tests/test_ingame.py")
        return 1
    print("CATALOG matches the game: nothing to update.")
    return 0


def _describe(kind, r):
    if kind == "row":
        key = EFFECTS.get(r[0], ("effect_%08x" % r[0],))[0]
        return "0x%08X %-4s %-10s %s" % (r[0], TYPE_NAMES.get(r[1], "?"), _short(r[2]), key)
    key = STAT_EFFECTS.get(r[0], ("stat_%d" % r[0],))[0]
    return "stat %-3d %s %s  %s" % (r[0], _short(r[1]), _short(r[2]), key)


def cmd_list(args):
    for pid, (name, _, _) in CATALOG.items():
        print("%-34s perk %d" % (name, pid))
        for key, kind, ident, default, hint in effects_of(pid):
            print("    %-26s default %-6s %s" % (key, fmt(default), hint))
    return 0


def cmd_init(args):
    out = args.output
    if os.path.exists(out) and not args.force:
        print("%s already exists (use --force to overwrite)" % out)
        return 1
    L = []
    L.append("; ================================================================")
    L.append("; Super Earth Armory Forge loadout")
    L.append("; Build:  python tools/picker.py build loadout.ini --zip \"My Stack.zip\"")
    L.append("; List every effect + default:  python tools/picker.py list")
    L.append("; ================================================================")
    L.append("")
    L.append("[settings]")
    L.append("name   = My Armory Build   ; name shown in the mod manager")
    L.append("retire = true               ; true: patch once. false: re-check every 5s")
    L.append("hotkey = F7                 ; opens the in-game panel (F1..F12)")
    L.append("swap_hotkey = F9            ; cycles your presets in game (F1..F12 or off)")
    L.append("panel_scale = 1.0           ; F7 panel size, 0.8 .. 1.5 (Ctrl +/- in game)")
    L.append("")
    L.append("; One [profile: <passive>] per armour passive you want to boost.")
    L.append("; Wear armour that HAS that passive and it gets everything set 'on'.")
    L.append("; Add more sections (e.g. [profile: Siege-Ready]) for different stacks.")
    L.append("[profile: Med-Kit]")
    L.append("conflicts = stack   ; stack: shared effects all apply | strongest: keep the biggest one")
    L.append("")
    L.append("; ---- passives to add ----")
    for pid, (name, _, _) in CATALOG.items():
        if pid == 7:
            continue
        L.append("%-34s = off" % name)
    L.append("")
    L.append("; ---- value tweaks:  <Passive>.<effect> = number ----")
    L.append("; Tweaking the trigger passive (Med-Kit here) REPLACES its own value.")
    L.append("; Tweaking any other passive changes the value it adds. Examples:")
    L.append(";Med-Kit.stims                    = 6")
    L.append(";Democracy Protects.death_save    = 2.0")
    L.append("")
    L.append("; ---- advanced: raw rows  (hex_id type value, comma separated) ----")
    L.append("; type 0 set, 1 add, 2 multiply, 3 time")
    L.append(";raw       = 0xAFAE3B47 1 2.0")
    L.append(";raw_stats = 13 0.0 1.5")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    print("Wrote %s - turn passives 'on', then build." % out)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="picker", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("init", help="write a fresh loadout.ini")
    i.add_argument("-o", "--output", default="loadout.ini")
    i.add_argument("--force", action="store_true")
    i.set_defaults(func=cmd_init)
    l = sub.add_parser("list", help="show every passive, effect key and default")
    l.set_defaults(func=cmd_list)
    b = sub.add_parser("build", help="preview / build a mod from a loadout.ini")
    b.add_argument("config")
    b.add_argument("--zip", help="write an installable mod .zip")
    b.add_argument("--name", help="display name in the mod manager")
    b.add_argument("--dump-lua", help="also write the generated Lua here")
    b.set_defaults(func=cmd_build)
    r = sub.add_parser("release", help="one zip with every preset as a pick-one option")
    r.add_argument("--presets", default=os.path.join(os.path.dirname(HERE), "presets"))
    r.add_argument("--zip", required=True)
    r.set_defaults(func=cmd_release)
    w = sub.add_parser("export-web", help="write docs/data.json for the web builder")
    w.add_argument("-o", "--output", default=os.path.join(os.path.dirname(HERE), "docs", "data.json"))
    w.add_argument("--check", action="store_true", help="fail if data.json is stale")
    w.set_defaults(func=cmd_export_web)
    d = sub.add_parser("check-dump", help="compare the game's passives (passives-dump.txt) with CATALOG")
    d.add_argument("dump", nargs="?", help="path to passives-dump.txt (default: %%LOCALAPPDATA%%\\...\\ArmoryForge)")
    d.set_defaults(func=cmd_check_dump)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
