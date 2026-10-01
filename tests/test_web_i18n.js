#!/usr/bin/env node
// The web builder in Simplified Chinese (docs/i18n.js): names from tools/lang_zh.lua via
// data.json, the page's own wording, sentences with numbers, effect hints.
//     node tests/test_web_i18n.js
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const docs = path.join(__dirname, "..", "docs");
const window = {};
vm.runInNewContext(fs.readFileSync(path.join(docs, "i18n.js"), "utf8"), { window, URLSearchParams, navigator: {}, location: { search: "" } });
const data = JSON.parse(fs.readFileSync(path.join(docs, "data.json"), "utf8"));
const I = window.PPI18N;
I._index(data);
let failed = 0;
function check(cond, what) { console.log((cond ? "ok    " : "FAIL  ") + what); if (!cond) failed++; }
const tr = I._tr;
check(tr("Med-Kit") === "医疗包" && tr("SR-64 Cinderblock") === 'SR-64"煤渣砖"', "passive and armor names: the game's own Chinese names (from data.json)");
check(tr("Choose passives") === "选择被动" && tr("How to use Armory Forge") === "军械工坊使用方法", "the page's own wording");
check(tr("Armor stack 2 / 3") === "护甲堆叠 2 / 3" && tr("0 of 30 ticked") === "已勾选 0 / 30", "sentences with numbers");
check(tr("Med-Kit (the armor's own passive)") === "医疗包（护甲自带被动）", "names inside sentences are looked up");
check(tr("radar ping, detection radius") === "雷达扫描间隔、敌人探测半径", "effect lists");
check(tr("mul; 0.5 = 50% resist · default 0.5") === "倍率；0.5 = 50% 抗性 · 默认 0.5", "effect hints");
check(tr("B-01 Tactical #2 (medium)") === 'B-01"战术" #2（中型）', "armor options with their weight");
check(tr("Something nobody wrote") === "Something nobody wrote", "unknown text stays as it is");
const lang = data.lang && data.lang.zh;
check(lang && Object.keys(lang.perk).length >= 31 && Object.keys(lang.armor).length > 200, "data.json carries the Chinese name tables");
if (failed) { console.log(`\n${failed} FAILED`); process.exit(1); }
console.log("\nall web language checks passed");
