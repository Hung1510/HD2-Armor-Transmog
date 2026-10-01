<p align="center"><img src="docs/img/banner.png" alt="Super Earth Armory Forge: armor passive editor for Helldivers 2"></p>

<p align="center">
<a href="https://github.com/Hung1510/Super-Earth-Armory-Forge/actions/workflows/tests.yml"><img src="https://github.com/Hung1510/Super-Earth-Armory-Forge/actions/workflows/tests.yml/badge.svg" alt="tests"></a>
<a href="https://github.com/Hung1510/Super-Earth-Armory-Forge/releases/latest"><img src="https://img.shields.io/github/v/release/Hung1510/Super-Earth-Armory-Forge?color=ffe710&labelColor=0b0c0d" alt="latest release"></a>
<a href="https://ayakamods.com/mods/super-earth-armory-forge.4359/"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fgist.githubusercontent.com%2FHung1510%2F996afff3a389ecbb7e77691ec94cab6a%2Fraw%2Fayakamods-downloads.json" alt="AyakaMods downloads"></a>
<a href="https://ayakamods.com/mods/super-earth-armory-forge.4359/"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fgist.githubusercontent.com%2FHung1510%2F996afff3a389ecbb7e77691ec94cab6a%2Fraw%2Fayakamods-views.json" alt="AyakaMods views"></a>
<a href="https://ayakamods.com/mods/super-earth-armory-forge.4359/"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fgist.githubusercontent.com%2FHung1510%2F996afff3a389ecbb7e77691ec94cab6a%2Fraw%2Fayakamods-rating.json" alt="rating"></a>
<a href="https://www.nexusmods.com/helldivers2/mods/16789"><img src="https://img.shields.io/badge/Nexus%20Mods-Lite%20edition-ffe710?labelColor=0b0c0d" alt="Nexus Mods"></a>
<a href="https://github.com/Hung1510/Super-Earth-Armory-Forge/releases"><img src="https://img.shields.io/github/downloads/Hung1510/Super-Earth-Armory-Forge/total?label=GitHub%20downloads&color=ffe710&labelColor=0b0c0d&cacheSeconds=3600" alt="GitHub downloads"></a>
<a href="TESTING.md"><img src="https://img.shields.io/badge/armor%20passives-31%2F31-ffe710?labelColor=0b0c0d" alt="passives"></a>
<a href="#languages"><img src="https://img.shields.io/badge/languages-English%20%C2%B7%20%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-ffe710?labelColor=0b0c0d" alt="English, 简体中文"></a>
<a href="https://ko-fi.com/phamtrangiahung"><img src="https://img.shields.io/badge/Ko--fi-support%20the%20mod-ffe710?logo=ko-fi&logoColor=ffe710&labelColor=0b0c0d" alt="Support on Ko-fi"></a>
</p>

**Install it, then press <kbd>F7</kbd> in game.** Tick passives, type values like `75%` or `+50 armor`, save loadouts and swap them with <kbd>F9</kbd>. Everything applies at once. Prefer to plan ahead? Use the **[web builder](https://hung1510.github.io/Super-Earth-Armory-Forge/)**.

<table>
<tr>
<td width="33%"><img src="docs/img/panel-preview.png" alt="F7 panel"><br><sub><b>F7 in game.</b> Tick passives, edit values live.</sub></td>
<td width="33%"><img src="docs/img/panel-presets.png" alt="Presets tab"><br><sub><b>Presets.</b> Standard loadouts and your own; <kbd>F9</kbd> swaps them.</sub></td>
<td width="33%"><img src="docs/img/web-builder.png" alt="Web builder"><br><sub><b>Web builder.</b> Optional: plan a build in the browser.</sub></td>
</tr>
</table>

Armory Forge started as an edit of **[Modular Armor Passives / Passive Picker v3](https://ayakamods.com/mods/modular-armor-passives.4350/) by mostlycloudy**, and its memory-patching core, archive format and passive data still come from that mod (engine credit also to SHODAN). The in-game terminal, loadouts, config layer and web builder are Armory Forge's own. See [CREDITS.txt](CREDITS.txt).

- **Languages:** English · 简体中文 (Simplified Chinese), in game and in the web builder. [More below](#languages).
- **Requires:** [Bingus Shared Loader](https://ayakamods.com/mods/bingus-shared-loader.3861/)
- **Single-player / private lobbies only.** Don't use it in public matchmaking.
- Download: [AyakaMods](https://ayakamods.com/mods/super-earth-armory-forge.4359/) · [GitHub Releases](https://github.com/Hung1510/Super-Earth-Armory-Forge/releases/latest) (full edition) · [Nexus Mods: Passive Swap - Armory Forge Lite](https://www.nexusmods.com/helldivers2/mods/16789) (Passive Swap edition)
- **Two editions:** the **full edition** (`Super-Earth-Armory-Forge.zip`) stacks passives and edits values. The **Passive Swap edition** (`Super-Earth-Armory-Forge-Passive-Swap.zip`) gives each armor one other passive at the game's own values, with no stacking and no value editing. Install one or the other.
- **Support:** the mod is free and always will be. If it's worth a coffee to you, **[tip on Ko-fi](https://ko-fi.com/phamtrangiahung)**. I'd really appreciate it, and it helps me keep updating the mod.

## Ways to use it

| You want | Do this |
|---|---|
| Build in game (most people) | Download **[Super-Earth-Armory-Forge.zip](https://github.com/Hung1510/Super-Earth-Armory-Forge/releases/latest)**, add it to your mod manager (there are no options to pick), start the game, press **F7** |
| A ready-made build | Same zip, then F7, then **Presets**: *Kitchen Sink, Tank, Stealth, Survivor, Demolitionist, Gunner* |
| Plan a build before playing | **[Web builder](https://hung1510.github.io/Super-Earth-Armory-Forge/)**, then *Download mod (.zip)* |
| Scripting / version control | `python tools\picker.py build loadout.ini --zip "My Stack.zip"` (below) |

Then:
1. Remove Passive Picker v3 if you have it. Passive Picker v4 is this mod under its old name; the update replaces it and keeps your saved builds.
2. Deploy, **fully restart the game**, and wear armor with the passive your stack is on (for example Med-Kit; use Armor Transmog if you want a different look).
3. Check `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ArmoryForge-STATUS.txt`. It should say `OK - perk stacked` once something is stacked; a fresh install shows a *Press F7* card when the game is ready.

## Languages

**English** and **简体中文 (Simplified Chinese)**, in the panel and the web builder.

- **In game:** F7 → **Keys** tab → *Language / 语言* → 简体中文. Remembered next time.
- **Web builder:** 简体中文 at the top right (or add `?lang=zh` to the link). Browsers set to Chinese get it by default.
- Passive and armor names are the **game's own official Chinese names**. The translation is by **hd2modpj**, from their *Super Earth Armory Forge 简体中文* addon, now built in: you don't need the addon any more.
- The panel draws with the game's own font. Set the game's **text language** to Chinese (简体 or 繁體) and the characters are there. If the font can't draw them, the panel stays English and the Keys tab says so.
- Your `loadout.ini`, share codes and the problem report stay in English, so loadouts move between languages unchanged.
- **Translators:** the panel's text lives in [`tools/lang_zh.lua`](tools/lang_zh.lua) (English → Chinese tables) and the web page's in [`docs/i18n.js`](docs/i18n.js). Anything missing simply shows in English; corrections are welcome as issues or pull requests.

> **简体中文：** 按 F7 →「按键」页 → Language / 语言 → 简体中文。被动与护甲名称为游戏官方中文译名；请把游戏的文字语言设为中文（简体或繁體）。网页版生成器右上角点「简体中文」。中文翻译：hd2modpj。

## The armory terminal (F7)

- **Left:** every armor passive with a tick box. Ticked = stacked onto your armor. Click a name to see what it does (*+2 stims; stims last 2 s longer*) and its values. **Stack summary** at the top shows everything on the armor added together.
- **Right:** the chosen passive's values, in plain terms (`75%` resist, `+30%`, `+50` armor). `--` `-` `+` `++` change them, `R` resets, or click a value and type one, e.g. `75` for 75% (Enter to set, Esc to cancel). The armor's own passive (e.g. Med-Kit) is listed first; its values **replace** the originals.
- **Tabs:** one per armor passive you stack onto. **+ Armor** adds another (e.g. a separate Siege-Ready stack), and pointing at a passive there lists the armors that carry it. **Remove armor** (click twice) puts the game's own values back.
- **Which armor do I wear?** Your armor's passive shows *Wear any of: …*, e.g. Med-Kit: CM-09 Bonesnapper, CM-14 Physician, …
- **Armor weight:** the *Armor weight* row sets how every armor with that passive moves: *Light* (armor 50, speed 550, stamina regen 125), *Medium* (100 / 500 / 100), *Heavy* (150 / 450 / 50) or *Game*. The look doesn't change, so a heavy armor can run like a light one. Also `weight = light` in a `[profile]`. Full edition only.
- **Lots of armors:** when the tabs don't fit, `<` `>` scroll the row; LB / RB reach every tab.
- **Weight for one armor:** under *Armor weight*, *Only the armor you're wearing* sets just that armor (full edition). Saved as `[armor: <name or id>]` with `weight = light`.
- **It knows what you wear:** the box at the top shows your armor and its tab's state (click it to jump there, or to add the tab); the panel opens on your armor's tab, and *+ Armor* lists your armor's passive first.
- **Guide tab:** step-by-step use and every control, in the panel and in the web builder (G).
- **The game ignores your keyboard and mouse while the panel is open** (no moving, shooting, turning or clicking the armory behind it); the wheel still scrolls the panel. Keys tab: *Blocked / Let through*.
- **Confirmed or not:** each value says *UNTESTED* or *CONFIRMED IN GAME* (from [TESTING.md](TESTING.md)).
- **When two passives change the same thing:** *Stack all* or *Strongest only*.
- Every change applies at once and is saved to `%LOCALAPPDATA%\CowboyBingus\Helldivers2\ArmoryForge\loadout.ini`, the same format as the web builder, so you can import it there to share. Installing a web-builder build starts fresh from that build; the release zip always keeps what you made.
- **Presets tab:** load a standard preset or one of yours. **+ Save current stack** saves what you have; rename, overwrite or delete your own. Saved in `ArmoryForge\my-presets.txt`.
- **Quick-swap (F9):** cycles your presets in game without opening the panel (built-ins if you have none saved). Set `swap_hotkey = F9` or `OFF` in `[settings]`.
- **Undo / Ctrl+Z** takes back the last change (up to 30).
- **Panel size:** `[-] 100% [+]` at the top, or **Ctrl +** / **Ctrl -** (Ctrl 0 resets), 80 to 150%. Also `panel_scale = 1.2` in `[settings]`.
- **Move it:** drag the top strip anywhere on the screen; the spot is remembered. **Ctrl 0** puts it back.
- **Long lists scroll:** mouse wheel over the list, the bar on its right, or PageUp / PageDown.
- **Copy code / Paste code:** your build as one short line of text for Discord etc. (only what you changed). Web-builder share links paste too.
- **Something wrong?** **Copy problem report** on the Keys tab, then paste it in your bug report. The same report is in `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ArmoryForge-STATUS.txt`, even if the panel never opens.
- **No panel at all:** in the web builder, set *In-game panel* to *Off* (or `panel = off` in `[settings]`). The build just applies its loadout, and no keys or controller are read.
- **Controller:** **Back + Start** opens the panel. D-pad / left stick moves, **A** selects, **B** goes back, **LB / RB** switch tabs, **X** undoes, **Y** ticks, right stick scrolls.
- **Search:** **Ctrl+F** (or click the field above a list) and type part of a passive's name or effect, e.g. `reload`. Esc clears it.
- **Language:** English or 简体中文 on the Keys tab ([Languages](#languages)).
- **Keys tab:** pick the panel key (F1–F12) and the quick-swap key (F1–F12 or off). Also `hotkey = F7` / `swap_hotkey = F9` in `[settings]`. A bad key there falls back to F7 / F9, so the panel always opens. SHODAN Stat Editor uses F8, and its panel sits on the right while this one sits on the left.
- If a change doesn't show, re-equip the armor or start a mission.


## How it's built

A mod that edits a live game's data while you play, built and tested like a production system. The full write-up, with diagrams, is in **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

- **Memory patching done safely.** Finds the game's armor-passive table in memory in a per-frame time budget. It never overwrites the game's rows: it builds a new modifier array and switches the record to it with one atomic 16-byte pointer+count store, double-buffered and verified by read-back, with automatic rollback. Every original byte can be restored, and records another mod already changed are left alone.
- **An in-game UI from scratch.** An immediate-mode panel on the engine's raw GUI calls: whole-pixel layout that stays sharp from 720p to 4K, drag, scroll, search, undo, presets, share codes and typed values in plain units. Mouse and keyboard come through the Windows API and controllers through XInput, both over LuaJIT FFI, with spatial focus navigation for the controller.
- **One format, three implementations, identical output.** The same `.ini` is parsed and compiled by Python (CLI), JavaScript (the web builder) and Lua (in game). A parity test requires Python and JS to produce **byte-identical** mod archives.
- **Tested without the game.** A fake game runs the real mod code under LuaJIT, with memory laid out like the game's, a GUI, a mouse, a keyboard and an Xbox controller. 600+ checks drive it like a player and verify both the screen and the game's memory. Layout checks use real font metrics at every resolution and size.
- **Research builds, then features.** Armor weight was found the measured way: a research build dumped every armor record (layout from FileDiver's open-source data library), an experiment changed one field, and the result was confirmed in game before any feature code was written. The same method located the equipped-armor loadout (a helmet, cape, armor id triple, found by diffing two full memory scans). It also ruled features out: live colour-scheme swaps worked for a second, then the game unloaded the textures and the armor went black, so that feature was dropped instead of shipped.
- **Data tooling.** `tools/armor-names/` reproducibly builds FileDiver's armor dumper for Windows in CI, from a pinned commit, with a double-click runner. `tools/armor_names.py` turns its output into the mod's id-to-name table and checks it against what the game had in memory, so a new Warbond's armors show up as a list of missing names.
- **Two editions from one codebase.** The Nexus build limits itself to one game passive per armor at the game's own values. The engine enforces it, and a test attacks it with a hostile save file.
- **CI/CD.** Lint, all suites on every push, and tag-to-release: both editions built, release notes from the changelog, zips checked so no script or executable slips in.

## What Armory Forge adds over Passive Picker v3

| Passive Picker v3 | Armory Forge |
|---|---|
| comment out hex rows in a 1,000-line Lua | web builder, or `Democracy Protects = on` in `loadout.ini` |
| one trigger armor | one stack per armor passive, several at once |
| base perk can't be changed | `Med-Kit.stims = 6` **replaces** the base value |
| hex values | named effects: `Democracy Protects.death_save = 2.0` |
| conflicts always multiply | `conflicts = stack` or `strongest` |
| rebuild and reinstall for every change | F7 in-game panel, live |
| one build per zip | one install; loadouts saved, loaded and swapped (F9) in game |
| raw game numbers | plain values: `75%` resist, `+30%`, `+50` armor |

## What's confirmed in game

Effect names are **inferred** from the passive descriptions; the game only stores hashes. The mod itself is confirmed to load and patch in game. Most individual effects are still **untested**. See **[TESTING.md](TESTING.md)** for the status of each one and how to test it. Report results with an [Effect test result](https://github.com/Hung1510/Super-Earth-Armory-Forge/issues/new?template=effect_report.yml) issue.

Known limits:
- `death_save = 2.0` = 100% is a best guess.
- Adreno-Defibrillator's revive is probably tied to the perk ID, so it likely won't work when stacked.
- Some passives store their effect in both lists (Epaulettes, Unflinching, Siege-Ready, Gunslinger, Hazmat, True Grit): a normal effect and a `(stat)` effect. Change both.

## Command line (Python 3.8+)

```powershell
git clone https://github.com/Hung1510/Super-Earth-Armory-Forge.git
cd Super-Earth-Armory-Forge
pip install lupa                                   # optional: Lua syntax check

python tools\picker.py list                        # every passive, effect, default
python tools\picker.py build loadout.ini           # preview
python tools\picker.py build loadout.ini --zip "My Stack.zip"
python tools\picker.py release --zip dist\Super-Earth-Armory-Forge.zip   # the release zip
```

The web builder can import and export the same `loadout.ini`.

```ini
[settings]
name   = My Stack
retire = true                    ; false = re-check every 5s

[profile: Med-Kit]               ; armor that HAS Med-Kit gets this stack
conflicts = stack                ; or: strongest
Democracy Protects = on
Siege-Ready        = on
Med-Kit.stims                    = 6      ; replaces the base +2
Democracy Protects.death_save    = 2.0
Siege-Ready.ammo_capacity        = 1.5    ; both-list passives: set both lines
Siege-Ready.stat_ammo_capacity   = 1.5

[profile: Siege-Ready]           ; a second, independent stack
Scout = on
```

Advanced: `raw = 0xHEXID type value, ...` and `raw_stats = stat unk1 unk2, ...` append arbitrary rows. Types are 0 set, 1 add, 2 multiply, 3 time.

## Project layout

```
tools/picker.py            catalog, config parser, Lua generator, .patch_0 + zip writer, CLI
tools/engine.lua           runtime engine: finds the perk records, applies/restores stacks, loadout file
tools/panel.lua            the F7 in-game panel (drawing, mouse, keyboard)
tools/lang_zh.lua          the panel in Simplified Chinese (hd2modpj): English -> Chinese tables
docs/i18n.js               the web builder in Simplified Chinese (names from lang_zh.lua via data.json)
tools/window_filter.py     the game-window input filter (x64), assembled into panel.lua
tools/main.lua             per-frame tick and startup
docs/                      web builder (GitHub Pages): index.html, app.js (UI), core.js (build logic)
docs/data.json             generated by `picker.py export-web`, never hand-edited
presets/*.ini              the standard presets (Presets tab, F9)
tests/harness.py           fake game for LuaJIT: memory, engine GUI, keyboard, mouse
tests/test_ingame.py       real mod vs fake game: rows match picker.py, panel flows, save/restore, other mods left alone
tests/test_panel_features.py  presets, quick-swap, undo, share codes, plain values
tests/test_release.py      release zip, blank install, saves from before the rename
tests/test_panel_layout.py no overlapping or clipped text in any panel view, 720p to 4K
tests/test_panel_scale.py  panel size setting, Ctrl +/-, whole-pixel drawing
tests/test_panel_scroll_drag.py  scrolling long lists, dragging the panel
tests/test_panel_keys_search.py  Keys tab, bad-key fallback, passive search
tests/test_swap_edition.py the Passive Swap (Nexus) edition, incl. a hostile save file
tests/test_controller.py   the whole panel driven with a fake Xbox controller
tests/test_passive_info.py passive descriptions, armor lists, stack summary, Remove armor
tests/test_report_share.py panel off, short share codes, the problem report
tools/research.lua         research builds only (`picker.py research`): armor kit dump, weight experiment
tests/test_research.py     the research build, and that no release carries it
tests/test_wearing.py      what you wear, one armor's weight, the game's input while the panel is open
tests/test_window_filter.py the game-window input filter's machine code, run on an x64 emulator
tests/test_lang.py         the panel in Simplified Chinese: coverage, fonts without Chinese, data stays English
tests/test_web_i18n.js     the web builder in Simplified Chinese
tests/test_weight.py       armor weight: loadout line, panel, undo, save, share codes, Passive Swap untouched
tools/armor-names/         builds FileDiver's armor dumper for Windows (CI: armor-names-tool.yml) with a double-click runner
tools/armor_names.py       FileDiver's armor list -> tools/armor-names.json (ids to names), checked against the game's kits
tests/test_armor_names.py  the name table conversion and game check
tools/passives.json        plain description + armors per passive (wiki data; corrections welcome)
tests/run_all.py           runs every suite and prints one summary
tools/release_notes.py     release notes for a tag, from CHANGELOG.md (release workflow)
docs/ARCHITECTURE.md       how it all works: engine, safety rules, panel, editions, tests
pyproject.toml             lint settings (ruff)
tests/test_web_parity.js   web builder output must be byte-identical to Python
tools/ayakamods_stats.py   reads AyakaMods downloads/views/rating into shields.io badge files
tools/update_badges_local.ps1  runs it through the installed Edge on a Windows PC (passes Cloudflare) and pushes to the badges Gist
TESTING.md                 in-game verification status per effect
```

## When the game updates

Nothing to do for new armor that uses an existing passive; stacks are per passive, not per armor.

On patch day:
1. Start the game once with the mod. Check `ArmoryForge-STATUS.txt`:
   - `found=31 of 31`: all good.
   - `NOT in the catalog=N`: new passives exist.
   - `found=0`: the game's data layout changed. The mod safely does nothing; disable it until it's updated.
2. The mod has written every armor passive the game has, with the game's own values, to `%LOCALAPPDATA%\CowboyBingus\Helldivers2\ArmoryForge\passives-dump.txt`. Compare it with the catalog:
   ```
   python tools\picker.py check-dump
   ```
   It prints **NEW** passives and **CHANGED** values as ready-to-paste `CATALOG` lines, **MISSING** passives, and new effect IDs for `EFFECTS`. It exits 0 when nothing changed.
3. Paste the lines into `tools/picker.py`, give new passives and effects real names, then run `python tools\picker.py export-web` and `python tests\test_ingame.py`. Commit, tag and release.

## AyakaMods badges

The download/view/rating badges (and the numbers on the portfolio) come from a public Gist: `https://gist.githubusercontent.com/Hung1510/996afff3a389ecbb7e77691ec94cab6a/raw/ayakamods.json`, plus one `ayakamods-*.json` badge file per number. The Gist's id is in `tools/badges-gist.txt`. A Gist rather than a branch of this repo, so updates don't show *"recent pushes, Compare & pull request"* on GitHub. AyakaMods sits behind a Cloudflare JavaScript challenge that plain HTTP clients (and GitHub Actions) can't pass, so a Windows PC reads it through the installed Edge (Playwright drives it off-screen; nothing extra to download):

```powershell
python -m pip install playwright

# once, by hand: should print "pushed: {...}" or "no change: {...}"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\update_badges_local.ps1

# then every 3 hours while you're logged in (run from the repo folder)
$script = (Resolve-Path tools\update_badges_local.ps1).Path
Register-ScheduledTask -TaskName "Armory Forge AyakaMods badges" `
  -Action (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`"") `
  -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 3)) `
  -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10))
```

It only commits when a number changed, never lowers downloads/views, and logs to `%LOCALAPPDATA%\ArmoryForgeBadges\last-run.log`. Remove it with `Unregister-ScheduledTask -TaskName "Armory Forge AyakaMods badges"`.

## Contributing

- **Effect name confirmed or wrong:** edit `EFFECTS` / `STAT_EFFECTS` in `tools/picker.py`, update `TESTING.md`, run `python tools/picker.py export-web`.
- **New passive after a game patch:** add it to `CATALOG` in `tools/picker.py`, then run `export-web`.
- **New preset:** add `presets/NN-name.ini`, then run `export-web`.
- **Web UI:** `docs/app.js` / `docs/index.html`. Build logic belongs in `docs/core.js`, and it must stay a port of `picker.py`.
- Before a PR (CI runs the same checks):
  ```
  pip install lupa pillow ruff
  python tools/picker.py export-web --check
  ruff check tools tests
  python tests/run_all.py
  ```
  Preview the site locally with `cd docs && python -m http.server`.
- **Releasing:** bump `VERSION` in `tools/picker.py` and add a `CHANGELOG.md` entry. Then run `export-web`, commit, and push a tag (`git tag v5.4 && git push origin v5.4`). GitHub Actions runs every test, builds both editions, and publishes the release with notes taken from `CHANGELOG.md`.

## Credits

- **mostlycloudy**: Passive Picker v3, where this started: memory-patching engine, archive format, passive data ([AyakaMods](https://ayakamods.com/mods/modular-armor-passives.4350/))
- **SHODAN**: engine credit, as noted in v3; the panel's drawing, input and font handling are adapted from [SHODAN Stat Editor](https://github.com/SHODAN-HORAI/SHODAN-Stat-Editor) v1.4.1 (public domain)
- **Bingus Shared Loader**: the loader this runs on
- **hd2modpj**: the Simplified Chinese (简体中文) translation of the panel, from their *Super Earth Armory Forge 简体中文* addon
- **FileDiver** by xypwn (BSD-3-Clause): the armor kit record layout behind *Armor weight* ([GitHub](https://github.com/xypwn/filediver))
- **JSZip** (MIT): zip writing in the web builder
- **Hung1510**: Super Earth Armory Forge: armory terminal, loadouts, config layer, web builder

Not affiliated with Arrowhead Game Studios.
