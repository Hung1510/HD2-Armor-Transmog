/*
 * Super Earth Armory Forge - core logic for the web builder.
 * A line-for-line port of tools/picker.py: same config rules, same Lua text,
 * same .patch_0 bytes (tests/test_web_parity.js checks this against Python).
 * Pure functions only; works in the browser (window.PPCore) and in Node.
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.PPCore = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const TYPE_NAMES = { 0: "set", 1: "add", 2: "mul", 3: "time" };
  const TRUE = new Set(["on", "yes", "true", "1", "y"]);
  const FALSE = new Set(["off", "no", "false", "0", "n", ""]);

  class ConfigError extends Error {}

  // ------------------------------------------------------------------ catalog
  function makeCatalog(data) {
    const byId = new Map();
    for (const p of data.catalog) byId.set(p.id, p);
    const byName = new Map();
    for (const p of data.catalog) byName.set(norm(p.name), p.id);
    for (const [k, v] of Object.entries(data.aliases)) byName.set(k, v);
    return { data, byId, byName, list: data.catalog };
  }

  // an armor in a loadout: its id (0xA9A71FE7) or its name (tools/picker.py find_armor)
  function findArmor(cat, text, where) {
    const t = text.trim();
    if (/^0x[0-9A-Fa-f]{1,8}$/.test(t)) return parseInt(t, 16);
    const want = norm(t);
    const hit = (cat.data.armors || []).find((a) => norm(a.name) === want);   // sorted by id: the lower id
    if (!hit) throw new ConfigError(`${where}: unknown armor '${t}' (use its name, e.g. SR-64 Cinderblock, or its id 0x...)`);
    return hit.id;
  }

  function norm(s) {
    return s.toLowerCase().replace(/[^a-z0-9]/g, "");
  }

  function effectsOf(cat, pid) {
    const p = cat.byId.get(pid);
    const out = [];
    for (const [mid, typ, val] of p.rows) {
      const [key, hint] = cat.data.effects[String(mid)];
      out.push({ key, kind: "row", ident: [mid, typ], def: val, hint, type: typ });
    }
    for (const [stat, u1, u2] of p.stats) {
      const [key, hint] = cat.data.stat_effects[String(stat)];
      out.push({ key, kind: "stat", ident: [stat, u1], def: u2, hint, type: 2 });
    }
    return out;
  }

  function similarity(a, b) {
    // Ratcliff-Obershelp-ish ratio, good enough for "did you mean"
    a = a.toLowerCase(); b = b.toLowerCase();
    const m = a.length, n = b.length;
    if (!m && !n) return 1;
    const dp = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
    for (let i = 1; i <= m; i++)
      for (let j = 1; j <= n; j++)
        dp[i][j] = a[i - 1] === b[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
    return (2 * dp[m][n]) / (m + n);
  }

  function findPerk(cat, text, where) {
    const t = text.trim();
    if (/^[0-9]+$/.test(t) && cat.byId.has(parseInt(t, 10))) return parseInt(t, 10);
    const pid = cat.byName.get(norm(t));
    if (pid === undefined) {
      const close = cat.list.map((p) => [similarity(t, p.name), p.name])
        .filter((x) => x[0] >= 0.5).sort((x, y) => y[0] - x[0]).slice(0, 3).map((x) => x[1]);
      const hint = close.length ? " Did you mean: " + close.join(", ") + "?" : "";
      throw new ConfigError(`${where}: unknown passive '${t}'.${hint}`);
    }
    return pid;
  }

  // ------------------------------------------------------------------ ini (configparser subset)
  function stripInline(v) {
    // configparser: an inline comment prefix only counts after whitespace
    const m = v.match(/\s[;#]/);
    return m ? v.slice(0, m.index) : v;
  }

  function parseIni(text) {
    const sections = []; // [{name, items: [[k, v]]}]
    const seen = new Set();
    let cur = null, curKey = null, curIndent = 0;
    const lines = text.replace(/\r\n?/g, "\n").split("\n");
    lines.forEach((raw, i) => {
      const lineNo = i + 1;
      const stripped = raw.trim();
      if (!stripped || stripped.startsWith(";") || stripped.startsWith("#")) {
        if (!stripped) curKey = null;
        return;
      }
      const indent = raw.length - raw.replace(/^\s+/, "").length;
      const value = stripInline(raw).trim();
      if (cur && curKey !== null && indent > curIndent) {
        const it = cur.items.find((x) => x[0] === curKey);
        if (value) it[1] = it[1] + "\n" + value;
        return;
      }
      const sm = value.match(/^\[(.+)\]$/);
      if (sm) {
        if (seen.has(sm[1])) throw new ConfigError(`line ${lineNo}: section '${sm[1]}' already exists`);
        seen.add(sm[1]);
        cur = { name: sm[1], items: [] };
        sections.push(cur);
        curKey = null;
        return;
      }
      if (!cur) throw new ConfigError(`line ${lineNo}: text before the first [section]`);
      const eq = value.indexOf("=");
      if (eq < 0) throw new ConfigError(`line ${lineNo}: expected 'key = value', got '${value}'`);
      const k = value.slice(0, eq).trim(), v = value.slice(eq + 1).trim();
      if (!k) throw new ConfigError(`line ${lineNo}: empty key`);
      if (cur.items.some((x) => x[0] === k))
        throw new ConfigError(`line ${lineNo}: '${k}' appears twice in [${cur.name}]`);
      cur.items.push([k, v]);
      curKey = k; curIndent = indent;
    });
    return sections;
  }

  function num(text, where) {
    const t = text.trim();
    if (!t || /^[+-]?0[xob]/i.test(t) || !/^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(t))
      throw new ConfigError(`${where}: '${text}' is not a number`);
    return Number(t);
  }

  function intBase0(t, where) {
    const s = t.trim();
    let m;
    if ((m = s.match(/^([+-]?)0x([0-9a-f]+)$/i))) return (m[1] === "-" ? -1 : 1) * parseInt(m[2], 16);
    if ((m = s.match(/^([+-]?)0o([0-7]+)$/i))) return (m[1] === "-" ? -1 : 1) * parseInt(m[2], 8);
    if ((m = s.match(/^([+-]?)0b([01]+)$/i))) return (m[1] === "-" ? -1 : 1) * parseInt(m[2], 2);
    if (/^[+-]?(0|[1-9]\d*)$/.test(s)) return parseInt(s, 10);
    throw new ConfigError(`${where}: '${t}' is not an integer`);
  }

  function parseRaw(text, where, stat) {
    const out = [];
    for (const chunk of text.split(",").map((c) => c.trim()).filter(Boolean)) {
      const parts = chunk.split(/\s+/);
      if (parts.length !== 3) throw new ConfigError(`${where}: raw entry '${chunk}' needs 3 parts`);
      const a = intBase0(parts[0], where);
      if (stat) out.push([a, num(parts[1], where), num(parts[2], where)]);
      else {
        const b = intBase0(parts[1], where);
        if (!(b in TYPE_NAMES)) throw new ConfigError(`${where}: raw type must be 0..3`);
        out.push([a, b, num(parts[2], where)]);
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ config -> profiles
  function loadConfigText(cat, text) {
    const sections = parseIni(text);
    const settings = { retire: true, name: null, hotkey: null, swap_hotkey: null, panel_scale: null, panel: true, armors: new Map() };
    const profiles = [];
    for (const sec of sections) {
      if (sec.name === "settings") {
        for (const [k, v] of sec.items) {
          if (k === "retire") settings.retire = TRUE.has(v.trim().toLowerCase());
          else if (k === "name") settings.name = v.trim();
          else if (k === "hotkey") {
            const hk = v.trim().toUpperCase();
            if (!/^F([1-9]|1[0-2])$/.test(hk)) throw new ConfigError(`[settings]: hotkey must be F1..F12, got '${v.trim()}'`);
            settings.hotkey = hk;
          } else if (k === "swap_hotkey") {
            const hk = v.trim().toUpperCase();
            if (!/^(F([1-9]|1[0-2])|OFF)$/.test(hk)) throw new ConfigError(`[settings]: swap_hotkey must be F1..F12 or off, got '${v.trim()}'`);
            settings.swap_hotkey = hk;
          } else if (k === "panel_scale") {
            const t = v.trim(), pct = t.endsWith("%");
            const sc = parseFloat(pct ? t.slice(0, -1) : t) / (pct ? 100 : 1);
            if (!/^\s*[0-9.]+%?\s*$/.test(t) || !isFinite(sc))
              throw new ConfigError(`[settings]: panel_scale must be a number from 0.8 to 1.5, got '${t}'`);
            if (sc < 0.8 - 1e-9 || sc > 1.5 + 1e-9) throw new ConfigError(`[settings]: panel_scale must be from 0.8 to 1.5, got '${t}'`);
            settings.panel_scale = Math.round(sc * 10) / 10;
          } else if (k === "panel") {
            const pv = v.trim().toLowerCase();
            if (!TRUE.has(pv) && !["off", "no", "false", "0", "n"].includes(pv))
              throw new ConfigError(`[settings]: panel must be on or off, got '${v.trim()}'`);
            settings.panel = TRUE.has(pv); // off: no panel, no hotkeys, no controller polling
          } else if (k === "base") { /* written by the in-game panel; only the game reads it */ }
          else throw new ConfigError(`[settings]: unknown key '${k}'`);
        }
        continue;
      }
      const a = sec.name.match(/^\s*armor\s*:\s*(.+?)\s*$/i);
      if (a) {
        const where = `[${sec.name}]`;
        const kid = findArmor(cat, a[1], where);
        if (settings.armors.has(kid)) throw new ConfigError(`${where}: this armor has two sections`);
        const entry = {};
        for (const [k, v] of sec.items) {
          const lk = k.trim().toLowerCase();
          if (lk === "colours" || lk === "colors") continue;   // 6.0 test builds only; the feature was dropped
          if (lk === "weight") {
            const w = parseWeight(v, where);
            if (w !== null) entry.weight = w;
          } else throw new ConfigError(`${where}: unknown key '${k}' (only weight)`);
        }
        if (Object.keys(entry).length) settings.armors.set(kid, entry);
        continue;
      }
      const m = sec.name.match(/^\s*profile\s*:\s*(.+?)\s*$/i);
      if (!m) throw new ConfigError(`[${sec.name}]: sections must be [settings], [profile: <passive>] or [armor: <armor>]`);
      profiles.push(buildProfile(cat, m[1], sec.items, `[${sec.name}]`));
    }
    if (settings.swap_hotkey && settings.swap_hotkey === (settings.hotkey || "F7"))
      throw new ConfigError("[settings]: swap_hotkey and hotkey must be different keys");
    if (!profiles.length && !settings.armors.size) throw new ConfigError("no [profile: <passive>] section found");
    const seen = new Set();
    for (const p of profiles) {
      if (seen.has(p.perk)) throw new ConfigError(`two profiles use the same trigger passive: ${p.name}`);
      seen.add(p.perk);
    }
    return { settings, profiles };
  }

  function strength(typ, v) {
    if (typ === 2) return v <= 0 ? Infinity : Math.abs(Math.log(v));
    return Math.abs(v);
  }

  // weight = light | medium | heavy | game (tools/picker.py parse_weight)
  const WEIGHTS = { light: 0, medium: 1, heavy: 2 };
  const WEIGHT_NAMES = ["light", "medium", "heavy"];
  function parseWeight(v, where) {
    const w = v.trim().toLowerCase();
    if (["game", "default", "off", ""].includes(w)) return null;
    if (!(w in WEIGHTS)) throw new ConfigError(`${where}: weight must be light, medium, heavy or game, got '${v.trim()}'`);
    return WEIGHTS[w];
  }

  function buildProfile(cat, triggerText, items, where) {
    const trigger = findPerk(cat, triggerText, where);
    let policy = "stack";
    let weight = null;
    const enabled = [];
    const tweaks = new Map(); // "pid|key" -> value, insertion ordered
    let rawRows = [], rawStats = [];
    const notes = [];
    const nameOf = (pid) => cat.byId.get(pid).name;

    for (const [k, v] of items) {
      const lk = k.trim().toLowerCase();
      if (lk === "conflicts") {
        policy = v.trim().toLowerCase();
        if (policy !== "stack" && policy !== "strongest")
          throw new ConfigError(`${where}: conflicts must be 'stack' or 'strongest'`);
      } else if (lk === "weight") weight = parseWeight(v, where);
      else if (lk === "raw") rawRows = rawRows.concat(parseRaw(v, where + " raw", false));
      else if (lk === "raw_stats") rawStats = rawStats.concat(parseRaw(v, where + " raw_stats", true));
      else if (k.includes(".")) {
        const dot = k.lastIndexOf(".");
        const pid = findPerk(cat, k.slice(0, dot), where);
        const ekey = k.slice(dot + 1).trim();
        const keys = effectsOf(cat, pid).map((e) => e.key);
        if (!keys.includes(ekey))
          throw new ConfigError(`${where}: ${nameOf(pid)} has no effect '${ekey}'. It has: ${keys.join(", ")}`);
        tweaks.set(pid + "|" + ekey, num(v, `${where} ${k}`));
      } else {
        const pid = findPerk(cat, k, where);
        const val = v.trim().toLowerCase();
        if (TRUE.has(val)) {
          if (pid === trigger)
            notes.push(`${nameOf(pid)} is the trigger; its own effects are always on (tweak them with ${nameOf(pid)}.<effect>)`);
          else if (!enabled.includes(pid)) enabled.push(pid);
        } else if (!FALSE.has(val)) throw new ConfigError(`${where}: '${k} = ${v}' must be on or off`);
      }
    }
    for (const key of tweaks.keys()) {
      const [pidS, ekey] = key.split("|");
      const pid = parseInt(pidS, 10);
      if (pid !== trigger && !enabled.includes(pid))
        notes.push(`tweak ${nameOf(pid)}.${ekey} ignored: ${nameOf(pid)} is off`);
    }

    const sortedEnabled = enabled.slice().sort((a, b) => a - b);
    let rows = [], stats = [];
    for (const pid of sortedEnabled) {
      const pname = nameOf(pid);
      for (const e of effectsOf(cat, pid)) {
        const tk = pid + "|" + e.key;
        const val = tweaks.has(tk) ? tweaks.get(tk) : e.def;
        if (e.kind === "row") rows.push([e.ident[0], e.ident[1], val, `${pname}.${e.key}`]);
        else stats.push([e.ident[0], e.ident[1], val, `${pname}.${e.key}`]);
      }
    }
    for (const r of rawRows) rows.push([r[0], r[1], r[2], "raw"]);
    for (const r of rawStats) stats.push([r[0], r[1], r[2], "raw_stats"]);

    const overrides = [], statOverrides = [];
    const tname = nameOf(trigger);
    const baseRows = new Map();
    for (const e of effectsOf(cat, trigger)) {
      const tk = trigger + "|" + e.key;
      const val = tweaks.has(tk) ? tweaks.get(tk) : e.def;
      if (e.kind === "row") {
        baseRows.set(e.ident[0] + "|" + e.ident[1], val);
        if (val !== e.def) overrides.push([e.ident[0], e.ident[1], val, `${tname}.${e.key}`]);
      } else if (val !== e.def) statOverrides.push([e.ident[0], e.ident[1], val, `${tname}.${e.key}`]);
    }

    const rr = resolve(rows, policy, (r) => r[0] + "|" + r[1], (r) => [r[1], r[2]]);
    const sr = resolve(stats, policy, (r) => String(r[0]), (r) => [2, r[2]]);
    rows = rr.out; stats = sr.out;

    for (const r of rows) {
      const bk = r[0] + "|" + r[1];
      if (baseRows.has(bk)) {
        const bv = baseRows.get(bk);
        if (r[2] === bv) notes.push(`${r[3]} duplicates the trigger's own effect (applied once)`);
        else notes.push(`${r[3]} stacks ON TOP of the trigger's own ${fmtG(bv)} (${TYPE_NAMES[r[1]]})`);
      }
    }
    const state = {
      enabled: sortedEnabled,
      tweaks: [...tweaks.entries()]
        .map(([k, v]) => { const [pidS, key] = k.split("|"); return [parseInt(pidS, 10), key, v]; })
        .filter(([pid]) => pid === trigger || enabled.includes(pid)),
      raw: rawRows, raw_stats: rawStats,
    };
    return {
      perk: trigger, name: tname, policy, weight, rows, stats, state,
      enabled: sortedEnabled.map(nameOf),
      overrides, stat_overrides: statOverrides,
      notes: notes.concat(rr.report, sr.report),
    };
  }

  function resolve(rows, policy, ident, typVal) {
    const report = [];
    const groups = new Map();
    for (const r of rows) {
      const g = ident(r);
      if (!groups.has(g)) groups.set(g, []);
      groups.get(g).push(r);
    }
    let out = [];
    for (const rs of groups.values()) {
      let uniq = [];
      for (const r of rs) {
        if (uniq.every((u) => u[2] !== r[2])) uniq.push(r);
        else report.push(`${r[3]} duplicates an identical row (applied once)`);
      }
      const effName = (s) => s.split(".").pop();
      if (uniq.length > 1) {
        if (policy === "strongest") {
          let best = uniq[0];
          for (const u of uniq) if (strength(...typVal(u)) > strength(...typVal(best))) best = u;
          report.push(`conflict on ${effName(uniq[0][3])}: kept ${best[3]} = ${fmtG(best[2])}, dropped ` +
            uniq.filter((u) => u !== best).map((u) => `${u[3]} = ${fmtG(u[2])}`).join(", "));
          uniq = [best];
        } else {
          report.push(`conflict on ${effName(uniq[0][3])}: all apply together (` +
            uniq.map((u) => `${u[3]} = ${fmtG(u[2])}`).join(", ") + ")");
        }
      }
      out = out.concat(uniq);
    }
    return { out, report };
  }

  // Python's "%g"
  function fmtG(v) {
    if (v === 0) return Object.is(v, -0) ? "-0" : "0";
    const exp = Math.floor(Math.log10(Math.abs(v)));
    if (exp < -4 || exp >= 6) {
      let [m, e] = v.toExponential(5).split("e");
      m = m.replace(/\.?0+$/, "");
      const en = parseInt(e, 10);
      return m + "e" + (en < 0 ? "-" : "+") + String(Math.abs(en)).padStart(2, "0");
    }
    return String(parseFloat(v.toPrecision(6)));
  }

  // Python's repr(float)
  function pyRepr(v) {
    if (Object.is(v, -0)) return "-0.0";
    if (v === 0) return "0.0";
    const [mant, e] = v.toExponential().split("e");
    const exp = parseInt(e, 10);
    const neg = mant.startsWith("-");
    const digits = mant.replace("-", "").replace(".", "");
    if (exp < -4 || exp >= 16) {
      const m = digits.length > 1 ? digits[0] + "." + digits.slice(1) : digits;
      return (neg ? "-" : "") + m + "e" + (exp < 0 ? "-" : "+") + String(Math.abs(exp)).padStart(2, "0");
    }
    let s;
    if (exp < 0) s = "0." + "0".repeat(-exp - 1) + digits;
    else if (digits.length <= exp + 1) s = digits + "0".repeat(exp + 1 - digits.length) + ".0";
    else s = digits.slice(0, exp + 1) + "." + digits.slice(exp + 1);
    return (neg ? "-" : "") + s;
  }

  function luaNum(v) {
    const r = pyRepr(v);
    return r.includes("e") || r.includes(".") ? r : r + ".0";
  }

  const hex8 = (n) => "0x" + (n >>> 0).toString(16).toUpperCase().padStart(8, "0");

  // Lua string literal, same escaping as picker.py lua_str()
  const luaStr = (s) => '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"';

  // Same text as picker.py generate_lua(): the MOD table (settings + the starting
  // loadout), then the catalog, engine and in-game panel (data.engine).
  function generateLua(data, settings, profiles) {
    const L = [];
    L.push("-- Generated by tools/picker.py from a loadout.ini. Edit the ini (or use the in-game panel), not this.");
    L.push("local MOD = {");
    L.push(`    id = '${data.mod_id}',`);
    L.push(`    global = '${data.global}',`);
    L.push(`    title = '${data.title}',`);
    L.push(`    version = '${data.version}',`);
    L.push(`    author = '${data.author}',`);
    L.push(`    log = '${data.global}.log',`);
    L.push(`    name = ${luaStr(settings.name || data.title)},`);
    L.push(`    retire = ${settings.retire ? "true" : "false"},`);
    L.push(`    hotkey = '${settings.hotkey || data.default_hotkey}',`);
    L.push(`    swap_hotkey = '${settings.swap_hotkey || data.default_swap_hotkey}',`);
    L.push(`    panel_scale = ${(settings.panel_scale || data.default_panel_scale || 1).toFixed(1)},`);
    if (settings.panel === false) L.push("    no_panel = true,   -- panel = off: no panel, no hotkeys, no controller polling");
    if (settings.armors && settings.armors.size) {
      L.push("    -- [armor: ...] sections: one armor's own weight");
      L.push("    armors = {");
      for (const kid of [...settings.armors.keys()].sort((x, y) => x - y)) {
        const a = settings.armors.get(kid);
        const parts = [`id = ${hex8(kid)}`];
        if (a.weight !== undefined && a.weight !== null) parts.push(`weight = ${a.weight}`);
        L.push(`        { ${parts.join(", ")} },`);
      }
      L.push("    },");
    }
    L.push("    type_passive = 0x63CE0FEB,   -- HelldiverCustomizationPassiveBonusSettings");
    L.push("    type_kit     = 0xD9A55AA0,   -- HelldiverCustomizationKit");
    L.push("    -- the loadout this build starts with; the in-game panel starts from it");
    L.push("    default = {");
    for (const p of profiles) {
      const st = p.state;
      L.push("        {");
      L.push(`            perk = ${p.perk}, name = ${luaStr(p.name)}, conflicts = '${p.policy}',`);
      if (p.weight !== null && p.weight !== undefined) L.push(`            weight = ${p.weight},   -- ${WEIGHT_NAMES[p.weight]}`);
      L.push(`            enabled = { ${st.enabled.join(", ")} },`);
      L.push("            tweaks = {");
      for (const [pid, key, val] of st.tweaks) L.push(`                { ${pid}, '${key}', ${luaNum(val)} },`);
      L.push("            },");
      L.push("            raw = {");
      for (const r of st.raw) L.push(`                { ${hex8(r[0])}, ${r[1]}, ${luaNum(r[2])} },`);
      L.push("            },");
      L.push("            raw_stats = {");
      for (const r of st.raw_stats) L.push(`                { ${r[0]}, ${luaNum(r[1])}, ${luaNum(r[2])} },`);
      L.push("            },");
      L.push("        },");
    }
    L.push("    },");
    L.push("    -- built-in presets: the panel's Presets tab and the quick-swap key");
    L.push("    presets = {");
    for (const p of data.presets) {
      const text = p.ini.replace(/\r\n/g, "\n");
      const m = text.match(/^[ \t]*name[ \t]*=[ \t]*([^;#\r\n]+)/m);
      const name = m ? m[1].trim() : p.file.replace(/\.ini$/, "");
      L.push(`        { name = ${luaStr(name)}, text = [==[`);
      L.push(text.replace(/\n+$/, ""));
      L.push("]==] },");
    }
    L.push("    },");
    L.push("}");
    L.push("");
    return "-- HD2-Addon: " + data.mod_id + "\n" + L.join("\n") + "\n" + data.engine;
  }

  // ------------------------------------------------------------------ archive (.patch_0)
  const MASK = (1n << 64n) - 1n;
  const MIX = 0xC6A4A7935BD1E995n;

  function resourceHash(name) {
    const data = new TextEncoder().encode(name);
    let value = (BigInt(data.length) * MIX) & MASK;
    const end = Math.floor(data.length / 8) * 8;
    const dv = new DataView(data.buffer, data.byteOffset, data.byteLength);
    for (let i = 0; i < end; i += 8) {
      let word = dv.getBigUint64(i, true);
      word = (word * MIX) & MASK;
      word ^= word >> 47n;
      value = ((value ^ ((word * MIX) & MASK)) * MIX) & MASK;
    }
    if (end < data.length) {
      let tail = 0n;
      for (let i = data.length - 1; i >= end; i--) tail = (tail << 8n) | BigInt(data[i]);
      value = ((value ^ tail) * MIX) & MASK;
    }
    value ^= value >> 47n;
    value = (value * MIX) & MASK;
    return value ^ (value >> 47n);
  }

  const MAGIC = 0xF0000011, RTYPE = 0xA14E8DFA2CD117E2n, ENVELOPE_VERSION = 2;
  const ARCHIVE_NAME = "9ba626afa44a3aa3.patch_0";

  function archiveFor(data, fullLua) {
    const body = new TextEncoder().encode(fullLua);
    const resource = new Uint8Array(8 + body.length);
    const rv = new DataView(resource.buffer);
    rv.setUint32(0, body.length, true);
    rv.setUint32(4, ENVELOPE_VERSION, true);
    resource.set(body, 8);

    const count = 1;
    let offset = (104 + 80 * count + 15) & ~15;
    const total = offset + resource.length + ((16 - ((offset + resource.length) % 16)) % 16);
    const out = new Uint8Array(total);
    const dv = new DataView(out.buffer);
    // entry
    const e = 104;
    dv.setBigUint64(e + 0, resourceHash(data.mod_id), true);
    dv.setBigUint64(e + 8, RTYPE, true);
    dv.setBigUint64(e + 16, BigInt(offset), true);
    // e+24..e+55 four zero u64
    dv.setUint32(e + 56, resource.length, true);
    dv.setUint32(e + 60, 0, true);
    dv.setUint32(e + 64, 0, true);
    dv.setUint32(e + 68, 16, true);
    dv.setUint32(e + 72, 16, true);
    dv.setUint32(e + 76, 0, true);
    out.set(resource, offset);
    const end = total;
    // header "<III20sQQ24s"
    dv.setUint32(0, MAGIC, true);
    dv.setUint32(4, 1, true);
    dv.setUint32(8, count, true);
    dv.setBigUint64(32, BigInt(end), true);
    dv.setBigUint64(40, 0n, true);
    // types "<IIQIIII" at 72
    dv.setUint32(72, 0, true);
    dv.setUint32(76, 0, true);
    dv.setBigUint64(80, RTYPE, true);
    dv.setUint32(88, count, true);
    dv.setUint32(92, 0, true);
    dv.setUint32(96, 16, true);
    dv.setUint32(100, 16, true);
    return out;
  }

  function describeProfiles(profiles) {
    return profiles.map((p) => `${p.name} armour: ${p.enabled.join(", ") || "base perk tweaks only"}`).join("; ");
  }

  // the mod manager description's first sentence (tools/picker.py how_to_edit)
  function howToEdit(data, settings) {
    if (settings.panel === false) return "Panel off in this build: edit the loadout in the web builder";
    return `Press ${settings.hotkey || data.default_hotkey} in game to edit`;
  }

  function manifestFor(data, display, description, withIcon) {
    const m = {
      Version: 1, Guid: data.guid, Name: display, Description: description,
      Options: [{ Name: display, Description: description, Include: ["Addon"] }],
    };
    if (withIcon) m.IconPath = "icon.png";
    return JSON.stringify(m, null, 2) + "\n";
  }

  // ------------------------------------------------------------------ ini writer (GUI state -> ini)
  // state: {name, retire, profiles: [{perk, conflicts, enabled: [pid], tweaks: {"pid.key": value}}]}
  function serializeIni(cat, state) {
    const L = [];
    L.push("; Super Earth Armory Forge loadout - made with the web builder");
    L.push("; https://hung1510.github.io/Super-Earth-Armory-Forge/");
    L.push("");
    L.push("[settings]");
    L.push(`name   = ${(state.name || "My Armory Build").replace(/[;#\r\n]/g, " ").trim()}`);
    L.push(`retire = ${state.retire ? "true" : "false"}`);
    L.push(`hotkey = ${state.hotkey || "F7"}`);
    L.push(`swap_hotkey = ${state.swap_hotkey || "F9"}`);
    L.push(`panel_scale = ${(state.panel_scale || 1).toFixed(1)}`);
    if (state.panel === false) L.push("panel  = off");
    for (const p of state.profiles) {
      const tname = cat.byId.get(p.perk).name;
      L.push("");
      L.push(`[profile: ${tname}]`);
      L.push(`conflicts = ${p.conflicts}`);
      if (p.weight !== null && p.weight !== undefined) L.push(`weight    = ${WEIGHT_NAMES[p.weight]}`);
      for (const c of cat.list) {
        if (c.id === p.perk) continue;
        L.push(`${c.name.padEnd(34)} = ${p.enabled.includes(c.id) ? "on" : "off"}`);
      }
      const tw = Object.entries(p.tweaks || {});
      if (tw.length || p.raw || p.raw_stats) L.push("");
      if (p.raw) L.push(`raw       = ${p.raw.replace(/\s*\n\s*/g, ", ")}`);
      if (p.raw_stats) L.push(`raw_stats = ${p.raw_stats.replace(/\s*\n\s*/g, ", ")}`);
      for (const [k, v] of tw) {
        const [pidS, key] = k.split(".");
        L.push(`${(cat.byId.get(parseInt(pidS, 10)).name + "." + key).padEnd(34)} = ${pyRepr(v)}`);
      }
    }
    for (const [kid, a] of armorEntries(state)) {
      L.push("");
      L.push(`[armor: ${hex8(kid)}]${armorName(cat, kid) ? "   ; " + armorName(cat, kid) : ""}`);
      if (a.weight != null) L.push(`weight  = ${WEIGHT_NAMES[a.weight]}`);
    }
    return L.join("\n") + "\n";
  }

  // GUI state.armors {id: {weight}} -> [[id, entry]] by id, set ones only
  function armorEntries(state) {
    return Object.entries(state.armors || {})
      .map(([k, a]) => [parseInt(k, 10), a])
      .filter(([, a]) => a && a.weight != null)
      .sort((x, y) => x[0] - y[0]);
  }
  function armorName(cat, kid) {
    const a = (cat.data.armors || []).find((x) => x.id === kid);
    return a ? a.name : "";
  }

  // share links: the loadout in as few bytes as every loadout reader accepts (the in-game
  // panel's PP.compact writes the same shape): passives by number, only the ones that are
  // on, only changed values, no keys or panel settings (those stay the reader's own)
  function compactIni(cat, state) {
    const L = ["[settings]", `name=${(state.name || "My Armory Build").replace(/[;#\r\n=]/g, " ")}`];
    for (const p of state.profiles) {
      L.push(`[profile: ${p.perk}]`);
      if (p.conflicts === "strongest") L.push("conflicts=strongest");
      if (p.weight !== null && p.weight !== undefined) L.push(`weight=${WEIGHT_NAMES[p.weight]}`);
      for (const pid of [...p.enabled].filter((x) => x !== p.perk).sort((a, b) => a - b)) L.push(`${pid}=on`);
      const keys = Object.keys(p.tweaks || {}).filter((k) => {
        const pid = parseInt(k.split(".")[0], 10);
        const eff = cat.byId.has(pid) && effectsOf(cat, pid).find((e) => e.key === k.split(".")[1]);
        return eff && p.tweaks[k] !== eff.def && (pid === p.perk || p.enabled.includes(pid));
      }).sort();
      for (const k of keys) L.push(`${k}=${pyRepr(p.tweaks[k])}`);
      if (p.raw) L.push(`raw=${p.raw.trim().replace(/\s*\n\s*/g, ", ")}`);
      if (p.raw_stats) L.push(`raw_stats=${p.raw_stats.trim().replace(/\s*\n\s*/g, ", ")}`);
    }
    for (const [kid, a] of armorEntries(state)) {
      L.push(`[armor: ${hex8(kid)}]`);
      if (a.weight != null) L.push(`weight=${WEIGHT_NAMES[a.weight]}`);
    }
    return L.join("\n") + "\n";
  }

  // profiles (from loadConfigText) -> GUI state, keeping only tweaks that differ from defaults
  function stateFromText(cat, text) {
    const sections = parseIni(text);
    const parsed = loadConfigText(cat, text); // validates
    const state = { name: parsed.settings.name || "My Armory Build", retire: parsed.settings.retire,
      hotkey: parsed.settings.hotkey || "F7", swap_hotkey: parsed.settings.swap_hotkey || "F9",
      panel_scale: parsed.settings.panel_scale || 1, panel: parsed.settings.panel !== false, profiles: [], armors: {} };
    for (const [kid, a] of parsed.settings.armors) state.armors[kid] = Object.assign({}, a);
    for (const sec of sections) {
      const m = sec.name.match(/^\s*profile\s*:\s*(.+?)\s*$/i);
      if (!m) continue;
      const perk = findPerk(cat, m[1], sec.name);
      const prof = { perk, conflicts: "stack", enabled: [], tweaks: {} };
      for (const [k, v] of sec.items) {
        const lk = k.trim().toLowerCase();
        if (lk === "conflicts") prof.conflicts = v.trim().toLowerCase();
        else if (lk === "weight") prof.weight = parseWeight(v, sec.name);
        else if (lk === "raw" || lk === "raw_stats") prof[lk] = v;
        else if (k.includes(".")) {
          const dot = k.lastIndexOf(".");
          const pid = findPerk(cat, k.slice(0, dot), sec.name);
          const key = k.slice(dot + 1).trim();
          const eff = effectsOf(cat, pid).find((e) => e.key === key);
          const val = num(v, k);
          if (val !== eff.def) prof.tweaks[pid + "." + key] = val;
        } else if (TRUE.has(v.trim().toLowerCase())) {
          const pid = findPerk(cat, k, sec.name);
          if (pid !== perk && !prof.enabled.includes(pid)) prof.enabled.push(pid);
        }
      }
      state.profiles.push(prof);
    }
    return state;
  }

  return {
    ConfigError, TYPE_NAMES, WEIGHT_NAMES, ARCHIVE_NAME, makeCatalog, effectsOf, findPerk, parseIni,
    loadConfigText, generateLua, archiveFor, resourceHash, describeProfiles, manifestFor,
    serializeIni, stateFromText, pyRepr, fmtG, luaNum, howToEdit, compactIni,
  };
});
