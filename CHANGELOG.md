# Changelog

## 6.2 (unreleased)
Both editions (full and Passive Swap):
- **简体中文:** the in-game panel in Simplified Chinese. Keys tab → *Language / 语言* → 简体中文. Passive and armor names are the game's own Chinese names. The translation is hd2modpj's, from their *Super Earth Armory Forge 简体中文* addon (now built in; the separate addon isn't needed). Your loadout file, share codes and the problem report stay in English, so loadouts move between languages unchanged.
- The panel draws Chinese with the game's own font: set the game's *text language* to Chinese (简体 or 繁體) and the characters are there. If the font can't draw them, the panel stays English and the Keys tab says so.

## 6.1 (2026-10-01)
Both editions (full and Passive Swap):
- **What you're wearing, at the top of the panel:** the armor's name and how its passive's tab stands: how many passives it stacks (or, in Passive Swap, what it's swapped to), "nothing ticked yet", or, when there's no tab for it, "click to add its tab". Click the box to jump to your armor's tab or add it. Most "my stack doesn't work" reports were an armor whose passive had no tab.
- **Guide tab** in the panel: how to use it step by step, and every key, mouse and controller control. The web builder has a matching **Guide** tab (or press G).

## 6.0 (2026-10-01)
Both editions (full and Passive Swap):
- **The game ignores your keyboard and mouse while the panel is open:** typing a value no longer moves your Helldiver, clicks don't shoot or press the armory behind the panel, and the mouse doesn't turn the camera. The mouse wheel still scrolls the panel's lists. Close the panel and everything works as before. The Keys tab has *Blocked / Let through* if you'd rather keep the game live. Thanks anmayvuong9x for the idea, and SHODAN Stat Editor, whose *Block game input* showed how the game reads its input.
- **It knows what you're wearing:** a few seconds after the scan, the mod finds the armor you have equipped and follows it when you change. The panel opens on its passive's tab, and *+ Armor* lists your armor's passive first, marked *YOUR ARMOR*. Thanks Triwxys.
- **Real armor names** from the game's own data; armors that share a name are numbered (*B-01 Tactical #2*).

Full edition:
- **Weight for one armor:** the *Armor weight* row has a second line, *Only the armor you're wearing* (As above / Light / Medium / Heavy). It overrides the passive-wide weight from 5.7, so you can make just your Cinderblock light.
- **Web builder:** a new *Armor weight* card sets the same for any armor. In the loadout it's an `[armor: SR-64 Cinderblock]` section with `weight = light`; names or ids both work.

Tried and dropped: colour schemes from other armors (6.0 test builds). The game unloads the other armor's textures a second or two later and the armor turns black, so it's out.

Under the hood: the equipped loadout is a helmet, cape and armor id stored back to back, found by a 5.7 research build that diffed two full memory scans. A one-time background pass finds it, and after that it's re-read every second. The game reads mouse movement as Windows raw input and keys, buttons and the wheel as window messages. While the panel is open, its raw mouse and keyboard registrations are taken (once the panel key is let go) and registered again exactly as they were when the panel closes or the game loses focus; a 173-byte window filter (`tools/window_filter.py`, tested on an x64 emulator in `tests/test_window_filter.py`) drops key presses and clicks and keeps the wheel for the panel. Releases always pass, so no key or button sticks. The panel reads keys, buttons and the cursor straight from Windows. Armor names come from FileDiver's armor dump through the new `tools/armor_names.py`. `tests/test_wearing.py` covers all of it. 600+ checks.

## 5.7 (2026-10-01)
Full edition:
- **Armor weight:** a new *Armor weight* row on every armor tab. Pick *Light*, *Medium*, *Heavy* or *Game*, and every armor with that passive moves like that class: speed, stamina regen and base armor rating. The look doesn't change, so a heavy armor can run like a light one. Also `weight = light` in a `[profile]`, and in the web builder. It's saved with your loadout, carried in share codes, undone by Undo, and put back by *Game* or *Remove armor*. Confirmed in game: a heavy SR-64 Cinderblock set to Light shows 50 / 550 / 125 and runs like light armor. Thanks nomu1116 for asking.
  - It applies per passive, like the tabs: Siege-Ready → Light changes all four Siege-Ready armors.

Both editions (full and Passive Swap):
- **Every armor tab is reachable:** with more armors than fit (7+, or fewer at a big panel size), the tab row gets `<` `>` arrows, and the tab you're on always scrolls into view. LB / RB step through every tab, not just the ones on screen. Before, the extra tabs weren't drawn, so those armors couldn't be edited. Thanks BONHakyla.
- **Undo stays on the tab you're on** instead of jumping back to the first one.

Under the hood: the scan also looks around the armor kit records once, then stops as before (0.4 MB read in the test). `tests/test_weight.py` covers weight end to end, including the Passive Swap edition never touching weights. The fake game now has armor kit records. 530+ checks.

## 5.6 (2026-10-01)
Both editions (full and Passive Swap):
- **Copy problem report** (Keys tab): puts a short report on the clipboard to paste in a bug report. It includes the version, edition, screen size, panel key, how many times the key was pressed (and how many of those presses came while the game wasn't the active window), whether the panel opened and drew, the last panel error, other mods sharing the update loop, and the end of the log. The same report is also written to `Logs\ArmoryForge-STATUS.txt`, so it's there even when the panel never opens.

Full edition:
- **Short share codes:** *Copy code* and the web builder's *Copy share link* now hold only what you changed: the passives that are on (by number), changed values, and no keys or panel settings. A kitchen-sink build went from about 2,200 characters to about 260, so it fits in a Discord message. Old long codes and links still paste, and new codes also load in 5.2 to 5.5.
- **Panel off** (web builder, *In-game panel: Off*, or `panel = off` in `[settings]`): the build applies its loadout and nothing else. No panel, hotkeys or controller are read. It's for anyone who only uses the web builder, or who wants to rule the panel out while chasing a crash or a key clash. Thanks lemuro.
- **Values are editable, and now it says so:** the header reads *Tick passives to stack them. Click a name to edit its values.* Thanks BONHakyla.

Under the hood: `tests/test_report_share.py` covers panel off (it checks that no key or controller is read), code length, and that a code copied in game loads to the same loadout in picker.py. The web parity suite checks that every preset's share link loads to the same loadout in Python. 480+ checks.

## 5.5 (2026-09-30)
Both editions (full and Passive Swap):
- **Controller support.** **Back + Start** opens and closes the panel. The D-pad or left stick moves a yellow focus box to the nearest button, and long lists scroll under it. **A** presses, **B** goes back (and closes), **LB / RB** switch tabs, **X** undoes, **Y** ticks the chosen passive, and the right stick scrolls. The prompt bar shows the controller buttons while you use it; moving the mouse hands control back.
- **What each passive does**, in one plain line, e.g. *+2 stims; stims last 2 s longer*. Shown when you pick a passive, in *+ Armor* when you point at one, and in the swap view.
- **Which armors carry it:** *Wear any of: CM-09 Bonesnapper, CM-14 Physician, …* for your armor's passive, and the full list when you point at a passive in *+ Armor*. 110 armors from the Helldivers wiki; corrections welcome in `tools/passives.json`.
- **Clearer remove button:** *Remove armor* is now a real button next to the tabs (click it twice). *+ Armor* also explains how to undo a wrong pick. Thanks Shatterdive.

Full edition:
- **Stack summary:** a new *Stack summary* entry at the top of the list shows everything on the armor together, e.g. *Armor rating +150 · Fire damage taken 87.5% · Stims +4*. Additive values add up and resists multiply. It's marked as an estimate, because how the game combines stacked values isn't confirmed yet.
- **Confirmed in game or not:** each value card says *UNTESTED*, *CONFIRMED IN GAME* or *NO EFFECT SEEN*, straight from TESTING.md. Report your tests and they show up in the next version.

Under the hood: `tests/test_controller.py` drives the whole panel with a fake controller. `tests/test_passive_info.py` covers the new info, summary and remove flows. The harness scrolls to a row before clicking it, like a player. 450+ checks.

## 5.4 (2026-09-30)
Both editions (full and Passive Swap):
- **Keys tab:** pick the panel key (F1–F12) and the quick-swap key (F1–F12 or off) in the panel, no file editing needed. The two can't clash, and choosing the quick-swap key as the panel key turns quick-swap off. Saved with your loadout; not an undo step. The tab also lists the fixed shortcuts and has size/position controls.
- **A bad key can't lock you out:** a key in `loadout.ini` that isn't F1–F12 (e.g. `hotkey = G`) now falls back to F7 / F9, so the panel always opens.
- **Search:** **Ctrl+F**, or click the field above a list, and type part of a passive's name or effect (`reload`, `grit`). Works in the passive list, *+ Armor* and the swap list. Esc clears it.
- **Every armor tab stays reachable:** with several stacks on armors with long names, the tabs share the row and long names are cut (`CONCUSSIVE PADD..`). Before, the tabs after the second or third weren't drawn at all.
- **Undo leaves your keys and panel size alone.** It only takes back loadout changes.

Under the hood:
- `docs/ARCHITECTURE.md`: how the engine, its safety rules, the panel, the two editions and the tests work, with diagrams.
- `tests/run_all.py` runs every suite with one summary: 360+ checks. New `tests/test_panel_keys_search.py`, and `test_ingame.py` now checks that records another mod changed are left alone.
- Lint (ruff) in CI. GitHub releases now carry notes taken from this changelog (`tools/release_notes.py`).

## 5.3.2 (2026-09-30)
- **New: Passive Swap edition** (`Super-Earth-Armory-Forge-Passive-Swap.zip`, the Nexus Mods build). Each armor gets **one** other armor passive, copied from the game's own record for that passive, so the values are always the game's. No stacking and no value editing. The engine enforces this, so no save file, preset or code can get around it. Its saves are its own (`loadout-swap.ini`, `my-swaps.txt`), so the full edition's builds are left alone. Both editions share one mod ID, so the mod manager keeps one or the other.
- The full edition is unchanged.
- New `tests/test_swap_edition.py`; the layout check covers the swap views.

## 5.3.1 (2026-09-30)
- Same mod as 5.3. The release zip no longer includes developer scripts (a PowerShell badge updater had slipped into `tools/`), which made Nexus quarantine the 5.3 file. The zip now holds only the mod, its readme files, presets and the plain-text sources of the mod and builder, and a test checks that.

## 5.3 (2026-09-30)
- **Every passive can be picked again:** the *+ Armor* list stopped at Kinetic Displacement Mitigation on smaller screens, so Blunt-Force Mitigation and True Grit could not be chosen as a base armor. Long lists (+ Armor, a stack's passives, your presets) now scroll: mouse wheel over the list, the bar on its right (arrows, click the track to page), or PageUp / PageDown. The bar only appears when a list doesn't fit.
- **Drag the panel:** grab the top strip (it says *Drag to move*) and put the panel anywhere, so it doesn't cover what you want to see when it's zoomed in. It always stays on screen, the spot is remembered (`ArmoryForge\panel-position.txt`, as a share of the screen so it survives a resolution change), and **Ctrl 0** puts it back.
- Support link: the mod stays free; there's now a [Ko-fi](https://ko-fi.com/phamtrangiahung) link in the README and the web builder if you'd like to tip.
- New `tests/test_panel_scroll_drag.py`.

## 5.2 (2026-09-30)
- **Sharper text on 1440p / 4K:** the F7 panel is drawn at your screen's own resolution with every edge, text position and font size on a whole pixel. Fractional positions were what made text soft on bigger screens.
- **Panel size:** `[-] 100% [+]` at the top of the panel, or **Ctrl +** / **Ctrl -** (**Ctrl 0** resets), from 80% to 150%. It is saved, kept when you load a preset, and not an undo step. Also `panel_scale = 0.8 .. 1.5` in `[settings]` and a *Panel size* dropdown in the web builder. The panel always fits the screen.
- Shrink-to-fit text now works in whole pixels, so small sizes (720p, 80%) don't overlap either.
- The log records the panel's font, resolution and size (`panel font: ...`) to help with display reports.
- New `tests/test_panel_scale.py`. The layout check now runs at 720p, 1080p, 1440p and 4K and at 80 to 150%, and also checks whole pixels and that the panel fits the screen.

## 5.1 (2026-09-30)
- **The F7 panel matches the web builder:** the Helldivers 2 armory look, with near-black panels, yellow for what is on, boxed tabs with a hatched stripe under the active one, uppercase passive names and a key-prompt bar (F7 close, F9 swap, Ctrl+Z undo).
- **Fixed overlapping text:** values like `+30%` could run into the `--` button, `++` was wider than its button, and long *Reset ...* labels ran past their click area. Buttons are now sized from their label's measured width. When the game can't measure text, the panel estimates widths per character on the wide side.
- New `tests/test_panel_layout.py` checks every panel view for overlapping or clipped text, with real font measurement and with the estimate.

## 5.0 (2026-09-30): Super Earth Armory Forge
Passive Picker v4 has a new name and its own identity. Includes everything listed under 4.4 (never released on its own).
- **New name: Super Earth Armory Forge.** It has a new icon, a new in-game terminal look (navy and Super Earth gold, ember marks on values you change, numbered requisition boxes) and a matching web builder.
- **One install, no mod-manager options.** The release zip no longer asks you to pick a preset. You build in game with F7, and the six presets are in the Presets tab and on F9. A fresh install shows a *Press F7 to forge your armor* card once the game is ready.
- **The release keeps what you make in the panel,** even your edits from 4.x made under another preset. Web-builder zips still install their own build.
- Files moved to `%LOCALAPPDATA%\CowboyBingus\Helldivers2\ArmoryForge\` (`loadout.ini`, `my-presets.txt`, `passives-dump.txt`). Saves in the old `PassivePicker` folder are read until the first new save. The status file is now `Logs\ArmoryForge-STATUS.txt`.
- Same mod GUID, so the mod manager updates it in place.
- The repository and web builder moved to `github.com/Hung1510/Super-Earth-Armory-Forge` and `hung1510.github.io/Super-Earth-Armory-Forge`. Share links from the old address still paste into the panel.
- README badges show AyakaMods downloads, views and rating, refreshed every 6 hours.

## 4.4 (2026-09-30, shipped as part of 5.0)
- **Presets in the panel:** a Presets tab with the installed build, the 6 built-in presets and your own. Save the current stacks, rename, overwrite or delete. Your presets live in `PassivePicker\my-presets.txt`.
- **Quick-swap (F9):** cycles your presets (or the built-ins if you have none) without opening the panel; a small card at the top of the screen shows which one is on. `swap_hotkey = F1..F12 | OFF` in `[settings]`, also a dropdown in the web builder.
- **Undo:** Undo button and Ctrl+Z (last 30 changes).
- **Share codes:** Copy code puts your whole build on the clipboard as one line; Paste code loads one. Codes are the same as web-builder share links, so a link works too.
- **Plain values:** values show and are typed as the game means them: `75%` resist, `+30%`, `+50` armor, `+2` stims, with the game's raw number shown underneath.
- *Back to installed build* moved into the Presets tab.
- 4.3 panel saves carry over unchanged.

## 4.3 (2026-09-30)
- **Much lighter start-up:** the memory scan stops once the armor-passive table and the area around it are checked, instead of reading all of the game's memory (in the test, 0.4 MB read instead of all 64 MB). It reads into one reused buffer, so there's no garbage-collector stutter, and it gives itself a share of each frame measured from your frame rate (~3 ms at 60 fps, ~1.5 ms at 144 fps). A passive removed by a game patch no longer triggers 12 full rescans.
- **Patch-day tooling:** the mod writes every armor passive in the game (IDs and the game's own values, read before any change) to `PassivePicker\passives-dump.txt`. `python tools/picker.py check-dump` compares it with the catalog and prints new passives, changed values and new effect IDs as ready-to-paste lines.
- The STATUS file flags armor passives that aren't in the catalog.
- In-game panel redesign: yellow header with hazard stripe, toggle switches, underlined armor tabs, value cards.
- The mod manager description shows the version and the panel key.

## 4.2 (2026-09-30)
- **In-game panel (F7)**: every armor passive with a tick box, values with `-- - + ++ R` or typed in, one tab per armor stack, Stack all / Strongest only. Changes apply live and are saved to `%LOCALAPPDATA%\CowboyBingus\Helldivers2\PassivePicker\loadout.ini` (web-builder format).
- The engine now finds all 31 armor passives and can add, change or remove a stack at any time; removing one restores the game's original data exactly. Updates go through two alternating buffers so the game never sees a half-written array.
- `hotkey = F1..F12` in `[settings]`; the web builder has a dropdown for it.
- New offline test harness: the real mod runs in LuaJIT against a fake game (memory, GUI, keyboard, mouse). `tests/test_ingame.py` replaces `tests/test_engine.py`.
- Panel drawing/input technique adapted from SHODAN Stat Editor v1.4.1 (public domain).

## 4.1 (2026-09-30)
- **Web builder** (https://hung1510.github.io/Super-Earth-Armory-Forge/): pick passives, tune values, download a ready-to-install zip in the browser. No Python. Share builds with a link, import/export `loadout.ini`.
- **Presets in one zip**: Kitchen Sink, Tank, Stealth, Survivor, Demolitionist, Gunner. Pick one in your mod manager.
- Mod icon in the mod manager.
- `picker.py release` (presets zip) and `picker.py export-web` (builder data).
- GitHub Actions: tests on every push; pushing a `v*` tag builds and attaches the release zip.
- Issue templates for bugs and in-game effect test results; `TESTING.md` tracks what's confirmed.

## 4.0 (2026-09-30)
- First release. Built on mostlycloudy's Passive Picker v3 engine.
- `loadout.ini` config: passives on/off by name, per-effect value tweaks, base-perk overrides, multiple armor profiles, `conflicts = stack | strongest`, typo suggestions.
- Offline engine test against a fake perk table.
