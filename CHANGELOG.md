# Changelog

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
