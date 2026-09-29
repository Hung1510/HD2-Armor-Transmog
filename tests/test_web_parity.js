#!/usr/bin/env node
/*
 * Checks the web builder (docs/core.js) against the Python builder (tools/picker.py):
 * for every preset and example loadout, the generated Lua text and the .patch_0 bytes
 * must be identical. Also round-trips each loadout through the GUI state
 * (ini -> state -> ini) and checks the result compiles to the same bytes.
 *
 *   python tools/picker.py export-web
 *   node tests/test_web_parity.js
 */
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const core = require("../docs/core.js");

const root = path.join(__dirname, "..");
const data = JSON.parse(fs.readFileSync(path.join(root, "docs", "data.json"), "utf8"));
const cat = core.makeCatalog(data);
const py = process.env.PYTHON || "python3";

const pyDump = `
import sys, json
sys.path.insert(0, ${JSON.stringify(path.join(root, "tools"))})
import picker
text = sys.stdin.read()
s, p = picker.load_config_text(text)
full = picker.compile_loadout(s, p)
sys.stdout.write(json.dumps({"lua": full, "archive": picker.archive_for(full).hex()}))
`;

function pyBuild(text) {
  return JSON.parse(execFileSync(py, ["-c", pyDump], { input: text, maxBuffer: 1 << 26 }).toString());
}

function jsBuild(text) {
  const { settings, profiles } = core.loadConfigText(cat, text);
  const lua = core.generateLua(data, settings, profiles);
  return { lua, archive: Buffer.from(core.archiveFor(data, lua)).toString("hex") };
}

const files = [];
for (const dir of ["presets", "examples"])
  for (const f of fs.readdirSync(path.join(root, dir)).filter((f) => f.endsWith(".ini")).sort())
    files.push(path.join(dir, f));
files.push("loadout.ini");

// extra edge cases the presets don't cover
const extra = {
  "edge: raw rows + stat overrides + strongest": `
[settings]
name = Edge
retire = false
[profile: Siege-Ready]
conflicts = strongest
Fortified = on
Ballistic Padding = on   ; inline comment
Siege-Ready.stat_ammo_capacity = 2
raw = 0xAFAE3B47 1 2.5, 0x14ECCE15 2 0.25
raw_stats = 13 0.0 1.75
[profile: 9]
Democracy Protects.death_save = 0.000015
Scout = yes
`,
};

let failed = 0;
function check(label, text) {
  const a = pyBuild(text), b = jsBuild(text);
  const luaOk = a.lua === b.lua, arcOk = a.archive === b.archive;
  // GUI round trip
  const state = core.stateFromText(cat, text);
  const again = jsBuild(core.serializeIni(cat, state));
  const rtOk = again.archive === b.archive;
  const ok = luaOk && arcOk && rtOk;
  if (!ok) {
    failed++;
    if (!luaOk) {
      const al = a.lua.split("\n"), bl = b.lua.split("\n");
      const i = al.findIndex((l, k) => l !== bl[k]);
      console.log(`  first Lua diff at line ${i + 1}:\n    py: ${al[i]}\n    js: ${bl[i]}`);
    }
  }
  console.log(`${ok ? "ok  " : "FAIL"} ${label}  (lua ${luaOk ? "=" : "!="}, patch_0 ${arcOk ? "=" : "!="}, gui round-trip ${rtOk ? "=" : "!="})`);
}

for (const f of files) check(f, fs.readFileSync(path.join(root, f), "utf8"));
for (const [label, text] of Object.entries(extra)) check(label, text);

// number formatting spot checks against Python
const nums = [0, -0, 0.05, 1.5, 30, 2, 1e-5, 1.5e-5, 0.0001, 123456789.125, 1e16, 2.5e20, -0.3];
const pyNums = JSON.parse(execFileSync(py, ["-c",
  "import sys,json; v=json.loads(sys.stdin.read()); v[1]=-0.0; print(json.dumps([[repr(float(x)), '%g' % x] for x in v]))"],
  { input: JSON.stringify(nums) }).toString());
nums.forEach((n, i) => {
  const js = [core.pyRepr(n), core.fmtG(n)];
  if (js[0] !== pyNums[i][0] || js[1] !== pyNums[i][1]) {
    failed++;
    console.log(`FAIL number ${n}: py ${pyNums[i]} js ${js}`);
  }
});

// error messages exist for typos
try { core.loadConfigText(cat, "[profile: Med-Kit]\nDemocracy Protect = on\n"); failed++; console.log("FAIL typo accepted"); }
catch (e) { if (!/Did you mean: Democracy Protects/.test(e.message)) { failed++; console.log("FAIL typo msg: " + e.message); } }

console.log(failed ? `\n${failed} FAILED` : "\nall parity checks passed");
process.exit(failed ? 1 : 0);
