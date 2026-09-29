# Changelog

## 4.2 (2026-09-30)
- **In-game panel (F7)**: every armor passive with a tick box, values with `-- - + ++ R` or typed in, one tab per armor stack, Stack all / Strongest only. Changes apply live and are saved to `%LOCALAPPDATA%\CowboyBingus\Helldivers2\PassivePicker\loadout.ini` (web-builder format).
- The engine now finds all 31 armor passives and can add, change or remove a stack at any time; removing one restores the game's original data exactly. Updates go through two alternating buffers so the game never sees a half-written array.
- `hotkey = F1..F12` in `[settings]`; the web builder has a dropdown for it.
- New offline test harness: the real mod runs in LuaJIT against a fake game (memory, GUI, keyboard, mouse). `tests/test_ingame.py` replaces `tests/test_engine.py`.
- Panel drawing/input technique adapted from SHODAN Stat Editor v1.4.1 (public domain).

## 4.1 (2026-09-30)
- **Web builder** (https://hung1510.github.io/HD2-Armor-Transmog/): pick passives, tune values, download a ready-to-install zip in the browser. No Python. Share builds with a link, import/export `loadout.ini`.
- **Presets in one zip**: Kitchen Sink, Tank, Stealth, Survivor, Demolitionist, Gunner. Pick one in your mod manager.
- Mod icon in the mod manager.
- `picker.py release` (presets zip) and `picker.py export-web` (builder data).
- GitHub Actions: tests on every push; pushing a `v*` tag builds and attaches the release zip.
- Issue templates for bugs and in-game effect test results; `TESTING.md` tracks what's confirmed.

## 4.0 (2026-09-30)
- First release. Built on mostlycloudy's Passive Picker v3 engine.
- `loadout.ini` config: passives on/off by name, per-effect value tweaks, base-perk overrides, multiple armor profiles, `conflicts = stack | strongest`, typo suggestions.
- Offline engine test against a fake perk table.
