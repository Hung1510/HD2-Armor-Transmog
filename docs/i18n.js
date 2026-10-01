/* Super Earth Armory Forge web builder - the page in Simplified Chinese (简体中文).
   Like the in-game panel, the page is written in English and translated where it's shown:
   every text node and title / placeholder is looked up when it appears (a MutationObserver),
   so app.js needs no changes for new text. Names (passives, effects, armors, presets) come
   from tools/lang_zh.lua via data.json (hd2modpj's translation, the game's own names); the
   page's own wording is below. The loadout.ini view, share links and downloads stay English. */
(function () {
  "use strict";
  const PAGE = {
    // strip, title, tabs
    "Ministry of Defense ·": "国防部 ·",
    "Super Earth Armory Forge": "超级地球军械工坊",
    "Download mod": "下载模组",
    "Nexus (Lite)": "Nexus（轻量版）",
    "☕ Support on Ko-fi": "☕ 在 Ko-fi 支持作者",
    "Armory": "军械",
    "Forge": "工坊",
    "Plan an armor passive stack and download it as a ready-to-install mod.": "规划护甲被动堆叠，下载为可直接安装的模组。",
    "This page is optional": "本页面可选",
    ": the mod has the same editor in game. Install it and press": "：模组在游戏里有同样的编辑器。安装后按",
    "+ Armor": "+ 护甲",
    "Guide": "指南",
    // guide
    "How to use Armory Forge": "军械工坊使用方法",
    "On this page (optional)": "在本页面（可选）",
    "Each tab is an": "每个标签页是一个",
    "armor passive": "护甲被动",
    ": everything you tick goes onto every armor with that passive.": "：你勾选的一切都会加到所有带该被动的护甲上。",
    "adds another one.": "再添加一个。",
    "Tick passives to stack them; open one to change its values (the line under each says what it means in game).":
      "勾选被动即可堆叠；展开一个可改数值（每项下面一行说明它在游戏里的含义）。",
    "Armor weight": "护甲重量",
    "makes that passive's armors light, medium or heavy; the": "让该被动的护甲变为轻型、中型或重型；",
    "card does it for one armor.": "卡片则只改一件护甲。",
    "Download": "下载",
    "builds a ready-to-install mod with this loadout, or": "用这套配装生成可直接安装的模组，或用",
    "Copy share link": "复制分享链接",
    "Save .ini": "保存 .ini",
    "to share it.": "分享它。",
    "You don't need this page: the mod has the same editor in game.": "不用本页面也行：模组在游戏里有同样的编辑器。",
    "In game": "游戏内",
    "Install the mod with": "安装模组，需要",
    "and start the game.": "，然后启动游戏。",
    "Press": "按",
    ". The panel opens on the tab of the armor you're wearing; the box at the top shows it, and offers to add its tab if there isn't one.":
      "。面板会打开你所穿护甲的标签页；顶部的框显示它，没有标签页时可一键添加。",
    "Tick passives on the left, click a name to change its values on the right. It applies at once and saves when you close the panel.":
      "在左边勾选被动，点击名称在右边改数值。即时生效，关闭面板时保存。",
    "Presets": "预设",
    "saves loadouts;": "保存配装；",
    "swaps between them with the panel closed.": "在面板关闭时切换配装。",
    "Copy code": "复制代码",
    "Paste code": "粘贴代码",
    "share them (this page reads them too).": "分享配装（本页面也认）。",
    "The": "面板里的",
    "tab in the panel has all of this, and": "标签页有以上全部内容，",
    "Keys": "按键",
    "changes F7 / F9.": "页可以改 F7 / F9。",
    "The Passive Swap (Lite) edition on Nexus works the same way, with one passive per armor instead of a stack.":
      "Nexus 上的被动替换（轻量）版用法相同，只是每件护甲换一个被动，不叠加。",
    "Controls in game": "游戏内操作",
    "Open / close the panel": "打开 / 关闭面板",
    "Next preset (panel closed)": "下一个预设（面板关闭时）",
    "Undo": "撤销",
    "Search passives and effects": "搜索被动与效果",
    "Scroll a long list (or the mouse wheel)": "滚动长列表（或用鼠标滚轮）",
    "Panel size; drag the top strip to move it": "面板尺寸；拖动顶部条移动面板",
    "Controller: open / close": "手柄：打开 / 关闭",
    "Move, select": "移动、选择",
    "Back / close": "返回 / 关闭",
    "Tabs": "切换标签页",
    "Undo, tick the chosen passive": "撤销、勾选选中的被动",
    "While the panel is open the game ignores your keyboard and mouse (Keys tab: Blocked / Let through). Single-player and private lobbies only.":
      "面板打开时游戏会忽略你的键盘和鼠标（按键页：拦截 / 放行）。仅限单人 / 私人房间。",
    // stack editor
    "Choose passives": "选择被动",
    "Import": "导入",
    "Start over": "重新开始",
    "Stack onto armor with this passive": "堆叠到带此被动的护甲上",
    "Game (as the armor is)": "游戏原值（护甲本身）",
    "Light": "轻型", "Medium": "中型", "Heavy": "重型",
    "When passives overlap": "被动重叠时",
    "Stack all": "全部叠加",
    "Strongest only": "仅取最强",
    "Values here replace the originals.": "这里的数值会替换原本的数值。",
    "tick all": "全选",
    "clear": "清除",
    "Search passives or effects": "搜索被动或效果",
    "Remove this armor stack": "移除这个护甲堆叠",
    "Give another armor passive its own stack": "给另一个护甲被动一套自己的堆叠",
    "How to use it (G)": "使用方法（G）",
    "Previous armor stack (Q)": "上一个护甲堆叠（Q）",
    "Next armor stack (E)": "下一个护甲堆叠（E）",
    "Reset to default": "恢复默认",
    "Reset": "重置",
    "Conflict policy": "冲突规则",
    "Filter": "筛选",
    "What's new": "更新内容",
    "Overlapping effects multiply or add together.": "重叠的效果会相乘或相加。",
    "Overlapping effects keep only the biggest one.": "重叠的效果只保留最大的那个。",
    // summary card
    "Custom variant": "自定义版本",
    "My Armory Build": "我的军械配装",
    "Unnamed build": "未命名配装",
    "Passives": "被动",
    "Rows added": "新增行",
    "Edited": "已改",
    "Stacked passives": "已堆叠的被动",
    "Nothing yet. Tick passives, or start from a preset.": "还没有。勾选被动，或从预设开始。",
    "Share link": "分享链接",
    "Name in your mod manager": "在模组管理器里的名称",
    "Start from a preset": "从预设开始",
    "Choose…": "选择…",
    "Panel key": "面板键",
    "Swap key": "切换键",
    "Off": "关",
    "Panel size": "面板尺寸",
    "In-game panel": "游戏内面板",
    "On: panel, hotkeys and controller": "开：面板、快捷键与手柄",
    "Off: this loadout only, no panel or hotkeys": "关：只用这套配装，没有面板与快捷键",
    "Show loadout.ini": "显示 loadout.ini",
    "Kitchen Sink: 22 passives stacked on Med-Kit armour. The in-game-tested default.": "万金油：医疗包护甲上叠加 22 个被动。游戏内测试过的默认配装。",
    "Tank: armour, damage resistance and no flinch": "重装坦克：护甲值、伤害抗性、不畏缩",
    "Stealth: low detection, quiet movement, speed": "潜行：低侦测、安静移动、速度",
    "Survivor: more stims, death save, elemental resistance": "生存者：更多治疗针、免死、元素抗性",
    "Demolitionist: extra grenades, throw range, explosive resistance": "爆破手：额外手雷、投掷距离、爆炸抗性",
    "Gunner: reload speed, ammo, sidearm handling, ergonomics": "枪手：装填速度、弹药、副武器操控、人机工效",
    "Or type the Reinforce stratagem: up, down, right, left, up": "或输入增援战略配备：上、下、右、左、上",
    "Save loadout.ini": "保存 loadout.ini",
    "Shortcuts": "快捷键",
    // one armor
    "One armor": "单件护甲",
    "Give one armor its own weight class, whatever its passive's tab says. In game it shows when the armor is next built: re-select it in the armory, or re-equip it. In game, the":
      "给一件护甲单独设重量等级，不管它被动标签页的设置。游戏里在下次生成这件护甲时生效：在军械里重新选中或重新装备。游戏内，你护甲标签页的",
    "row of your armor's tab does the same for the armor you're wearing.": "一行可以对你正穿的护甲做同样的设置。",
    "Armor": "护甲",
    "Weight": "重量",
    "As its passive": "同其被动",
    "No armor changed yet.": "还没有改动任何护甲。",
    "Remove": "移除",
    // install
    "How to install": "安装方法",
    "Install": "安装",
    "Remove Passive Picker v3 if you have it.": "如果装了 Passive Picker v3，请先移除。",
    "Add the zip to your mod manager and deploy.": "把 zip 加进模组管理器并部署。",
    "Restart the game and wear armor with the passive you picked.": "重启游戏，穿上带你所选被动的护甲。",
    "Change anything later in game with": "之后在游戏里随时修改：",
    "Not working? Check": "不起作用？查看",
    ". Single-player and private lobbies only.": "。仅限单人 / 私人房间。",
    "Engine, archive format and passive data from": "引擎、存档格式与被动数据来自",
    "'s Passive Picker v3 (engine credit also SHODAN). Effect names are inferred from the game; ones marked":
      " 的 Passive Picker v3（引擎同样致谢 SHODAN）。效果名称是从游戏推断的；标着",
    "are guesses.": "的是推测。",
    "A well-equipped Helldiver is a free Helldiver.": "装备精良的绝地潜兵才是自由的绝地潜兵。",
    "Custom armor is approved for single-player and private lobbies only.": "自定义护甲仅批准用于单人与私人房间。",
    "Search": "搜索",
    "Add another armor": "再添加一件护甲",
    "Armor with this passive gets its own separate stack.": "带此被动的护甲会有自己独立的堆叠。",
    "Cancel": "取消",
    "Add": "添加",
    "Super Earth Armory Forge by Hung1510 ·": "超级地球军械工坊，作者 Hung1510 ·",
    "source": "源代码",
    "· free forever; if it helps you,": "· 永久免费；如果对你有帮助，",
    "a Ko-fi tip": "在 Ko-fi 打赏",
    "is much appreciated ·": "不胜感激 ·",
    "report a wrong effect name": "报告错误的效果名称",
    "· started from": "· 起源于",
    "by mostlycloudy · Chinese translation: hd2modpj · fonts: Saira, Barlow (SIL OFL) · fan-made, not affiliated with Arrowhead Game Studios or Sony.":
      "，作者 mostlycloudy · 中文翻译：hd2modpj · 字体：Saira、Barlow（SIL OFL）· 同人作品，与 Arrowhead Game Studios 或 Sony 无关。",
    // toasts
    "Cleared": "已清除",
    "Share link copied": "分享链接已复制",
    "Link is in the address bar. Copy it from there": "链接在地址栏里，从那里复制",
    "Reinforce: build inbound": "增援：配装即将抵达",
    "Zip library failed to load. Check your connection": "压缩库加载失败，请检查网络",
    "Loaded shared build": "已载入分享的配装",
  };
  // sentences with numbers or names in them; $n parts are looked up again
  const RULES = [
    [/^Armor stack (\d+) \/ (\d+)$/, "护甲堆叠 $1 / $2"],
    [/^(\d+) of (\d+) ticked$/, "已勾选 $1 / $2"],
    [/^Notes \((\d+)\)$/, "备注（$1）"],
    [/^(\d+) edited$/, "已改 $1 项"],
    [/^(.+) \(the armor's own passive\)$/, "$1（护甲自带被动）"],
    [/^(.+) \(base\)$/, "$1（基础）"],
    [/^Wear any armor with (.+) to get this stack \(Armor Transmog changes the look\)\. (.+)$/,
      "穿上任意带$1的护甲即可获得这套堆叠（外观可用 Armor Transmog 更换）。$2"],
    [/^Every (.+) armor moves and gets armor like (\w+) armor, and keeps its look\.$/,
      "所有$1护甲的移动与护甲值都按$2护甲计算，外观不变。"],
    [/^(.+?)( #\d+)? \((light|medium|heavy)\)$/, "$1$2（$3）"],
    [/^(.+) armor: (\d+) passives, (\d+) rows$/, "$1护甲：$2 个被动，$3 行"],
    [/^(\d+) effect\(s\) are shared by several passives; each applies once\.$/, "$1 个效果被多个被动共用；每个只生效一次。"],
    [/^(.+) armor$/, "$1护甲"],
    [/^Loaded preset: (.+)$/, "已载入预设：$1"],
    [/^Imported (.+)$/, "已导入 $1"],
    [/^Downloaded (.+)$/, "已下载 $1"],
    [/^Could not load: (.+)$/, "无法载入：$1"],
    [/^Shared link is invalid: (.+)$/, "分享链接无效：$1"],
    [/^(.*) · default (.+)$/, "$1 · 默认 $2"],
    [/^set to (.+)$/, "设为 $1"],
    [/^×0 \(removes it completely\)$/, "×0（完全移除）"],
    [/^\+(\S+) \(≈ \+(\d+) armor\)$/, "+$1（≈ +$2 护甲值）"],
  ];
  const WORD = { light: "轻型", medium: "中型", heavy: "重型",
    // weapon stats (stat_primary_reload -> "primary reload")
    "primary reload": "主武器装填（武器属性）", "sidearm reload": "副武器装填（武器属性）",
    "sidearm draw": "副武器切换（武器属性）", "support reload": "支援武器装填（武器属性）" };
  // effect hints: "mul; 0.5 = 50% resist"
  const KIND = { add: "加值", mul: "倍率", set: "设定", stat: "武器属性", time: "时间" };
  const HINT = [
    [/^no chest bleeding$/, "不会胸部出血"], [/^no flinch$/, "不畏缩"], [/^immune$/, "免疫"],
    [/^extra grenades$/, "额外手雷"], [/^extra stims$/, "额外治疗针"], [/^extra seconds$/, "额外秒数"],
    [/^seconds$/, "秒"], [/^seconds between radar pings$/, "雷达扫描间隔（秒）"], [/^\+50 armour$/, "+50 护甲值"],
    [/^\+ergo$/, "+人机工效"], [/^stock 50% chance$/, "原本的 50% 几率"],
    [/^the stock 50% chance\. 2\.0 = 100%\? \(untested\)$/, "原本的 50% 几率。2.0 = 100%？（未测试）"],
    [/^arc-related, exact effect \?$/, "电弧相关，具体效果未知"], [/^fire\/gas\/acid\/arc$/, "火焰/毒气/酸液/电弧"],
    [/^walk or run speed \?$/, "步行或奔跑速度？"], [/^flag, effect \?$/, "开关，效果未知"],
    [/^placeholder row - revive is probably tied to perk id$/, "占位行：复活大概与被动 id 绑定"],
    [/^slide-related \?$/, "滑铲相关？"], [/^(.+)% resist$/, "$1% 抗性"],
  ];
  function hint(s) {
    const m = s.match(/^(add|mul|set|stat|time)(?:; (.+))?$/);
    if (!m) return null;
    let rest = m[2] || "";
    const eq = rest.match(/^([\d.]+ = )(.+?)( \?)?$/);
    const head = eq ? eq[1] : "", body = eq ? eq[2] : rest;
    let t = body;
    for (const [re, rep] of HINT) if (re.test(body)) { t = body.replace(re, rep); break; }
    return KIND[m[1]] + (rest ? "；" + head + t + (eq && eq[3] ? "？" : "") : "");
  }

  let names = null;            // english (lower case) -> chinese, from data.json
  function index(data) {
    names = {};
    const g = (data && data.lang && data.lang.zh) || {};
    for (const group of ["perk", "effect", "unit", "preset", "desc", "armor", "ui"])
      for (const [k, v] of Object.entries(g[group] || {})) names[k.toLowerCase()] = v;
    for (const [k, v] of Object.entries(PAGE)) names[k.toLowerCase()] = v;
  }

  function tr(s) {
    if (!names || !s || !/[A-Za-z]/.test(s)) return s;
    const hit = names[s.toLowerCase()];
    if (hit) return hit;
    if (WORD[s.toLowerCase()]) return WORD[s.toLowerCase()];
    const dflt = s.match(/^(.*) · default (.+)$/);
    if (dflt) return tr(dflt[1]) + " · 默认 " + dflt[2];
    if (s.includes(", ")) {                     // "radar ping, detection radius"
      const parts = s.split(", ").map((p) => names[p.toLowerCase()] || WORD[p.toLowerCase()]);
      if (parts.every(Boolean)) return parts.join("、");
    }
    const h = hint(s);
    if (h) return h;
    for (const [re, rep] of RULES) {
      if (!rep) continue;
      const m = s.match(re);
      if (m) return rep.replace(/\$(\d)/g, (_, d) => (m[+d] === undefined ? "" : tr(m[+d])));
    }
    return s;
  }

  // ---------------------------------------------------------------- the page
  let lang = "en", busy = false;
  const ATTRS = ["placeholder", "title", "aria-label"];
  const skip = (el) => !el || el.closest("pre, code, script, style, [data-no-i18n]");

  function apply(node) {
    if (node.nodeType === 3) {
      const el = node.parentElement;
      if (skip(el)) return;
      if (node.__zh !== node.nodeValue) node.__en = node.nodeValue;        // new English text
      const en = node.__en;
      if (en === undefined) return;
      let out = en;
      if (lang === "zh") {
        const m = en.match(/^(\s*)([\s\S]*?)(\s*)$/);
        const t = tr(m[2].replace(/\s+/g, " "));
        out = t === m[2].replace(/\s+/g, " ") ? en : m[1] + t + m[3];
      }
      node.__zh = out;
      if (node.nodeValue !== out) node.nodeValue = out;
      return;
    }
    if (node.nodeType !== 1 || skip(node)) return;
    for (const a of ATTRS) {
      if (!node.hasAttribute(a)) continue;
      const key = "__en_" + a, mark = "__zh_" + a;
      const v = node.getAttribute(a);
      if (node[mark] !== v) node[key] = v;
      const out = lang === "zh" ? tr(node[key]) : node[key];
      node[mark] = out;
      if (v !== out) node.setAttribute(a, out);
    }
    for (const c of node.childNodes) apply(c);
  }

  function run(root) {
    if (busy) return;
    busy = true;
    try { apply(root || document.body); } finally { busy = false; }
  }

  function set(l) {
    lang = l === "zh" ? "zh" : "en";
    try { localStorage.setItem("af-lang", lang); } catch (e) { /* private mode */ }
    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    const b = document.getElementById("langBtn");
    if (b) b.textContent = lang === "zh" ? "English" : "简体中文";
    run();
  }

  function start(data) {
    index(data);
    let saved = null;
    try { saved = localStorage.getItem("af-lang"); } catch (e) { /* private mode */ }
    const q = new URLSearchParams(location.search).get("lang");
    const pick = q || saved || ((navigator.language || "").toLowerCase().startsWith("zh") ? "zh" : "en");
    new MutationObserver((list) => {
      if (busy || lang === "en") return;
      busy = true;
      try {
        for (const m of list) {
          if (m.type === "characterData") apply(m.target);
          else if (m.type === "attributes") apply(m.target);
          else m.addedNodes.forEach(apply);
        }
      } finally { busy = false; }
    }).observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ATTRS });
    const b = document.getElementById("langBtn");
    if (b) b.addEventListener("click", (e) => { e.preventDefault(); set(lang === "zh" ? "en" : "zh"); });
    set(pick);
  }

  window.PPI18N = { start, tr: (s) => (lang === "zh" ? tr(s) : s), lang: () => lang,
                    _index: index, _tr: tr };   // tests/test_web_i18n.js
})();
