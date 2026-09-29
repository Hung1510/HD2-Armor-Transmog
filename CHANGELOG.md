# Changelog

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
