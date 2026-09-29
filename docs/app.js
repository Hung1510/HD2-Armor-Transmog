/* Passive Picker v4 web builder - UI. All build logic lives in core.js. */
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const core = window.PPCore;
  let data, cat;
  let state, active = 0;
  const open = new Set();
  let search = "";
  let lastIni = "", lastOk = false;

  // ---------------------------------------------------------------- storage (optional)
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } },
  };

  // ---------------------------------------------------------------- helpers
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const human = (k) => k.replace(/^stat_/, "").replace(/_/g, " ");
  const nameOf = (pid) => cat.byId.get(pid).name;

  function toast(msg) {
    const t = $("toast");
    t.textContent = msg;
    t.classList.add("show");
    clearTimeout(toast.t);
    toast.t = setTimeout(() => t.classList.remove("show"), 2200);
  }

  function meaning(e, v) {
    if (e.kind === "stat" || e.type === 2) {
      if (v === 0) return "×0 (removes it completely)";
      const pct = Math.round((v - 1) * 1000) / 10;
      return `×${v} (${pct >= 0 ? "+" : ""}${pct}%)`;
    }
    if (e.type === 1) return e.key === "armor_rating" ? `+${v} (≈ +${Math.round(v * 50)} armor)` : `+${v}`;
    if (e.type === 3) return `${v} s`;
    return `set to ${v}`;
  }

  function blankProfile(perk) { return { perk, conflicts: "stack", enabled: [], tweaks: {} }; }
  function blankState() { return { name: "My Passive Stack", retire: true, hotkey: "F7", profiles: [blankProfile(7)] }; }

  // tweaks on passives that are off are kept in state (so toggling back restores them)
  // but left out of the ini so they don't produce "ignored" notes
  function effectiveState() {
    return {
      name: state.name, retire: state.retire, hotkey: state.hotkey,
      profiles: state.profiles.map((p) => {
        const tw = {};
        for (const [k, v] of Object.entries(p.tweaks)) {
          const pid = parseInt(k.split(".")[0], 10);
          if (pid === p.perk || p.enabled.includes(pid)) tw[k] = v;
        }
        return Object.assign({}, p, { tweaks: tw });
      }),
    };
  }

  // ---------------------------------------------------------------- compile + summary
  function compile() {
    lastIni = core.serializeIni(cat, effectiveState());
    $("iniView").textContent = lastIni;
    store.set("pp4-ini", lastIni);
    const notes = $("notes");
    notes.innerHTML = "";
    let parsed;
    try {
      parsed = core.loadConfigText(cat, lastIni);
      lastOk = true;
    } catch (e) {
      lastOk = false;
      notes.innerHTML = `<li class="bad">${esc(e.message)}</li>`;
      $("dlZip").disabled = true;
      return;
    }
    $("dlZip").disabled = false;
    let passives = 0, rows = 0, tweaks = 0, dups = 0;
    const items = [];
    for (const p of parsed.profiles) {
      passives += p.enabled.length;
      rows += p.rows.length + p.stats.length;
      tweaks += p.overrides.length + p.stat_overrides.length;
      if (parsed.profiles.length > 1) items.push(["good", `${p.name} armor: ${p.enabled.length} passives, ${p.rows.length + p.stats.length} rows`]);
      for (const n of p.notes) {
        if (/duplicates/.test(n)) { dups++; continue; }
        if (/all apply together|stacks ON TOP/.test(n)) items.push(["warn", n]);
        else items.push(["", n]);
      }
    }
    for (const sp of state.profiles)
      tweaks += Object.keys(sp.tweaks).filter((k) => {
        const pid = parseInt(k.split(".")[0], 10);
        return pid !== sp.perk && sp.enabled.includes(pid);
      }).length;
    if (dups) items.push(["", `${dups} effect(s) are shared by several passives; each applies once.`]);
    if (!passives && !tweaks) items.unshift(["", "Nothing selected yet. Switch passives on, or load a preset."]);
    else items.unshift(["good", "Ready to download."]);
    $("sPass").textContent = passives;
    $("sRows").textContent = rows;
    $("sTweaks").textContent = tweaks;
    notes.innerHTML = items.map(([c, t]) => `<li class="${c}">${esc(t)}</li>`).join("");
  }

  // ---------------------------------------------------------------- render
  function renderTabs() {
    const tabs = $("tabs");
    tabs.innerHTML = state.profiles.map((p, i) =>
      `<div class="tab" role="tab" tabindex="0" aria-selected="${i === active}" data-tab="${i}">${esc(nameOf(p.perk))} armor` +
      (state.profiles.length > 1 ? ` <span class="x" data-remove="${i}" title="Remove this armor" role="button" aria-label="Remove">&times;</span>` : "") +
      `</div>`).join("") +
      `<button class="tab" type="button" id="addTab" title="Give another armor passive its own stack">+ Add armor</button>`;
  }

  function effEditor(pid, e, prof) {
    const key = pid + "." + e.key;
    const has = Object.prototype.hasOwnProperty.call(prof.tweaks, key);
    const v = has ? prof.tweaks[key] : e.def;
    const guess = /\?/.test(e.hint);
    return `<div class="eff${has ? " changed" : ""}">
      <div class="lbl"><b>${esc(human(e.key))}${e.kind === "stat" ? " <small style='display:inline'>(stat list)</small>" : ""}${guess ? " ?" : ""}</b>
        <small>${esc(e.hint)} · default ${esc(e.def)}</small></div>
      <input type="number" step="any" inputmode="decimal" value="${esc(v)}" data-tweak="${esc(key)}" aria-label="${esc(nameOf(pid) + " " + human(e.key))}">
      <button class="reset" type="button" data-reset="${esc(key)}" ${has ? "" : "disabled"} title="Reset to default" aria-label="Reset">&#8634;</button>
      <div class="meaning">${esc(meaning(e, v))}</div>
    </div>`;
  }

  function renderProfile() {
    const prof = state.profiles[active];
    const used = new Set(state.profiles.map((p) => p.perk));
    const triggerOpts = cat.list.map((c) =>
      `<option value="${c.id}" ${c.id === prof.perk ? "selected" : ""} ${used.has(c.id) && c.id !== prof.perk ? "disabled" : ""}>${esc(c.name)}</option>`).join("");
    const baseEffects = core.effectsOf(cat, prof.perk);
    const q = search.trim().toLowerCase();
    const cards = cat.list.filter((c) => c.id !== prof.perk).filter((c) => {
      if (!q) return true;
      return c.name.toLowerCase().includes(q) || core.effectsOf(cat, c.id).some((e) => human(e.key).includes(q));
    });
    const onCount = prof.enabled.length;

    $("profileBody").innerHTML = `
      <div class="row" style="margin-bottom:12px">
        <div class="field grow"><label for="trigSel">Armor passive that gets the stack</label>
          <select id="trigSel">${triggerOpts}</select></div>
        <div class="field"><label>When passives overlap</label>
          <div class="seg" role="group" aria-label="Conflict policy">
            <button type="button" data-policy="stack" aria-pressed="${prof.conflicts === "stack"}">Stack all</button>
            <button type="button" data-policy="strongest" aria-pressed="${prof.conflicts === "strongest"}">Strongest only</button>
          </div></div>
      </div>
      <p class="hint" style="margin:-4px 0 14px">Wear any armor with <b>${esc(nameOf(prof.perk))}</b>. Use Armor Transmog if you want a different look.
        ${prof.conflicts === "stack" ? "Overlapping effects multiply or add together." : "Overlapping effects keep only the biggest one."}</p>

      <div class="base">
        <h3>${esc(nameOf(prof.perk))}: base perk values</h3>
        <p class="hint" style="margin:0 0 8px">Changing these <b>replaces</b> the armor's own values.</p>
        <div class="effects" style="border:0; padding:0">${baseEffects.map((e) => effEditor(prof.perk, e, prof)).join("")}</div>
      </div>

      <div class="toolbar">
        <input type="search" id="search" placeholder="Filter passives or effects…" value="${esc(search)}" class="grow" aria-label="Filter">
        <button class="btn small" type="button" id="allOn">All on</button>
        <button class="btn small" type="button" id="allOff">All off</button>
        <span class="hint">${onCount} on</span>
      </div>
      <div class="grid">
        ${cards.map((c) => {
          const on = prof.enabled.includes(c.id);
          const effs = core.effectsOf(cat, c.id);
          const isOpen = open.has(active + ":" + c.id);
          const chips = effs.map((e) => {
            const k = c.id + "." + e.key;
            const ch = Object.prototype.hasOwnProperty.call(prof.tweaks, k);
            return `<span class="chip${ch ? " changed" : ""}">${esc(human(e.key))}${e.kind === "stat" ? " (stat)" : ""}${ch ? " ✎" : ""}</span>`;
          }).join("");
          return `<div class="pcard${on ? " on" : ""}">
            <div class="top" data-open="${c.id}" aria-expanded="${isOpen}">
              <button class="switch" type="button" role="switch" aria-checked="${on}" data-toggle="${c.id}" aria-label="${esc(c.name)}"></button>
              <span class="name">${esc(c.name)}</span>
              <span class="hint">${isOpen ? "▴" : "▾"}</span>
            </div>
            <div class="sum">${chips}</div>
            ${isOpen ? `<div class="effects">${on ? "" : `<p class="hint" style="margin:0">Switch it on to apply these values.</p>`}${effs.map((e) => effEditor(c.id, e, prof)).join("")}</div>` : ""}
          </div>`;
        }).join("") || `<div class="empty">No passive matches “${esc(search)}”.</div>`}
      </div>`;
  }

  function render() {
    $("modName").value = state.name;
    $("hotkeySel").value = state.hotkey || "F7";
    renderTabs();
    renderProfile();
    compile();
  }

  // ---------------------------------------------------------------- events
  function bind() {
    $("modName").addEventListener("input", (e) => { state.name = e.target.value; compile(); });
    $("hotkeySel").addEventListener("change", (e) => { state.hotkey = e.target.value; compile(); });

    $("presetSel").addEventListener("change", (e) => {
      const p = data.presets.find((x) => x.file === e.target.value);
      e.target.value = "";
      if (!p) return;
      loadIni(p.ini, `Loaded preset: ${presetName(p)}`);
    });

    $("importBtn").addEventListener("click", () => $("importFile").click());
    $("importFile").addEventListener("change", async (e) => {
      const f = e.target.files[0];
      e.target.value = "";
      if (f) loadIni(await f.text(), `Imported ${f.name}`);
    });
    $("resetBtn").addEventListener("click", () => {
      state = blankState(); active = 0; open.clear(); search = "";
      history.replaceState(null, "", location.pathname);
      render(); toast("Cleared");
    });

    $("tabs").addEventListener("click", (e) => {
      const rm = e.target.closest("[data-remove]");
      if (rm) {
        const i = +rm.dataset.remove;
        state.profiles.splice(i, 1);
        active = Math.max(0, Math.min(active, state.profiles.length - 1));
        render();
        return;
      }
      if (e.target.closest("#addTab")) return openAdd();
      const t = e.target.closest("[data-tab]");
      if (t) { active = +t.dataset.tab; search = ""; render(); }
    });
    $("tabs").addEventListener("keydown", (e) => {
      const t = e.target.closest("[data-tab]");
      if (t && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); active = +t.dataset.tab; render(); }
    });

    const body = $("profileBody");
    body.addEventListener("change", (e) => {
      const prof = state.profiles[active];
      if (e.target.id === "trigSel") {
        const perk = +e.target.value;
        prof.enabled = prof.enabled.filter((x) => x !== perk);
        for (const k of Object.keys(prof.tweaks)) if (k.startsWith(prof.perk + ".")) delete prof.tweaks[k];
        prof.perk = perk;
        render();
      } else if (e.target.dataset.tweak) setTweak(e.target.dataset.tweak, e.target.value, true);
    });
    body.addEventListener("input", (e) => {
      if (e.target.id === "search") {
        search = e.target.value;
        const pos = e.target.selectionStart;
        renderProfile();
        const s = $("search"); s.focus(); s.setSelectionRange(pos, pos);
      } else if (e.target.dataset.tweak) setTweak(e.target.dataset.tweak, e.target.value, false);
    });
    body.addEventListener("click", (e) => {
      const prof = state.profiles[active];
      const pol = e.target.closest("[data-policy]");
      if (pol) { prof.conflicts = pol.dataset.policy; render(); return; }
      const tg = e.target.closest("[data-toggle]");
      if (tg) {
        const pid = +tg.dataset.toggle;
        const i = prof.enabled.indexOf(pid);
        if (i >= 0) prof.enabled.splice(i, 1);
        else { prof.enabled.push(pid); prof.enabled.sort((a, b) => a - b); }
        render();
        return;
      }
      const rs = e.target.closest("[data-reset]");
      if (rs) { delete prof.tweaks[rs.dataset.reset]; render(); return; }
      const op = e.target.closest("[data-open]");
      if (op) {
        const k = active + ":" + op.dataset.open;
        open.has(k) ? open.delete(k) : open.add(k);
        renderProfile();
        return;
      }
      if (e.target.id === "allOn" || e.target.id === "allOff") {
        prof.enabled = e.target.id === "allOn" ? cat.list.map((c) => c.id).filter((id) => id !== prof.perk) : [];
        render();
      }
    });

    $("dlZip").addEventListener("click", downloadZip);
    $("dlIni").addEventListener("click", () => saveBlob(new Blob([lastIni], { type: "text/plain" }), "loadout.ini"));
    $("shareBtn").addEventListener("click", async () => {
      const url = location.origin + location.pathname + "#ini=" + b64url(lastIni);
      history.replaceState(null, "", url);
      try { await navigator.clipboard.writeText(url); toast("Share link copied"); }
      catch (e) { toast("Link is in the address bar. Copy it from there"); }
    });

    $("addOk").addEventListener("click", (e) => {
      const perk = +$("addSel").value;
      if (!perk) return;
      state.profiles.push(blankProfile(perk));
      active = state.profiles.length - 1;
      render();
    });

    $("themeBtn").addEventListener("click", () => {
      const cur = document.documentElement.dataset.theme ||
        (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
      const next = cur === "light" ? "dark" : "light";
      document.documentElement.dataset.theme = next;
      store.set("pp4-theme", next);
    });
  }

  function setTweak(key, raw, final) {
    const prof = state.profiles[active];
    const [pidS, ekey] = key.split(".");
    const e = core.effectsOf(cat, +pidS).find((x) => x.key === ekey);
    const v = parseFloat(raw);
    if (!isFinite(v)) { if (final) renderProfile(); return; }
    if (v === e.def) delete prof.tweaks[key]; else prof.tweaks[key] = v;
    if (final) render();
    else {
      // live-update the meaning line without re-rendering (keeps focus)
      const input = document.querySelector(`[data-tweak="${CSS.escape(key)}"]`);
      if (input) {
        const box = input.closest(".eff");
        box.classList.toggle("changed", v !== e.def);
        box.querySelector(".meaning").textContent = meaning(e, v);
        box.querySelector(".reset").disabled = v === e.def;
      }
      compile();
    }
  }

  function openAdd() {
    const used = new Set(state.profiles.map((p) => p.perk));
    $("addSel").innerHTML = cat.list.filter((c) => !used.has(c.id))
      .map((c) => `<option value="${c.id}">${esc(c.name)}</option>`).join("");
    $("addDlg").showModal();
  }

  function presetName(p) {
    const m = p.ini.match(/^\s*name\s*=\s*([^;\n]+)/m);
    return m ? m[1].trim() : p.file;
  }

  function loadIni(text, msg) {
    try {
      state = core.stateFromText(cat, text);
      active = 0; open.clear(); search = "";
      render();
      if (msg) toast(msg);
    } catch (e) {
      toast("Could not load: " + e.message);
    }
  }

  // ---------------------------------------------------------------- downloads
  function saveBlob(blob, filename) {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  async function downloadZip() {
    if (!lastOk) return;
    if (typeof JSZip === "undefined") { toast("Zip library failed to load. Check your connection"); return; }
    const { settings, profiles } = core.loadConfigText(cat, lastIni);
    const lua = core.generateLua(data, settings, profiles);
    const archive = core.archiveFor(data, lua);
    const display = settings.name || data.title;
    const desc = core.describeProfiles(profiles) + ". " + data.credit;
    let icon = null;
    try { const r = await fetch("icon.png"); if (r.ok) icon = new Uint8Array(await r.arrayBuffer()); } catch (e) { /* optional */ }
    const zip = new JSZip();
    const date = new Date(1980, 0, 1);
    zip.file("manifest.json", core.manifestFor(data, display, desc, !!icon), { date });
    if (icon) zip.file("icon.png", icon, { date });
    zip.file("Addon/" + core.ARCHIVE_NAME, archive, { date });
    zip.file("Addon/" + core.ARCHIVE_NAME + ".stream", new Uint8Array(0), { date });
    zip.file("Addon/" + core.ARCHIVE_NAME + ".gpu_resources", new Uint8Array(0), { date });
    zip.file("loadout.ini", lastIni, { date });
    const blob = await zip.generateAsync({ type: "blob", compression: "DEFLATE" });
    const file = (display.replace(/[^A-Za-z0-9 _-]+/g, "").trim() || "Passive Picker v4") + ".zip";
    saveBlob(blob, file);
    toast(`Downloaded ${file}`);
  }

  function b64url(s) {
    const bytes = new TextEncoder().encode(s);
    let bin = "";
    bytes.forEach((b) => (bin += String.fromCharCode(b)));
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function unb64url(s) {
    const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
    return new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
  }

  // ---------------------------------------------------------------- start
  async function start() {
    const theme = store.get("pp4-theme");
    if (theme) document.documentElement.dataset.theme = theme;
    try {
      data = await (await fetch("data.json")).json();
    } catch (e) {
      $("profileBody").innerHTML = `<div class="empty">Could not load data.json. If you opened this file directly, serve the folder instead (GitHub Pages or <code>python -m http.server</code>).</div>`;
      return;
    }
    cat = core.makeCatalog(data);
    for (const p of data.presets) {
      const o = document.createElement("option");
      o.value = p.file;
      const d = (p.ini.match(/^;\s*[^:]+:\s*(.+)$/m) || [])[1] || "";
      o.textContent = presetName(p) + (d ? ": " + d.replace(/ on Med-Kit armour\.?$/, "") : "");
      $("presetSel").appendChild(o);
    }
    bind();
    state = blankState();
    const h = location.hash.match(/^#ini=(.+)$/);
    const saved = store.get("pp4-ini");
    if (h) {
      try { state = core.stateFromText(cat, unb64url(h[1])); toast("Loaded shared build"); }
      catch (e) { toast("Shared link is invalid: " + e.message); }
    } else if (saved) {
      try { state = core.stateFromText(cat, saved); } catch (e) { state = blankState(); }
    }
    render();
  }

  start();
})();
