<p align="center"><img src="docs/icon.png" width="96" alt=""></p>

# Passive Picker v4: HD2 armor passive stacker

[![tests](https://github.com/Hung1510/HD2-Armor-Transmog/actions/workflows/tests.yml/badge.svg)](https://github.com/Hung1510/HD2-Armor-Transmog/actions/workflows/tests.yml)
[![latest release](https://img.shields.io/github/v/release/Hung1510/HD2-Armor-Transmog)](https://github.com/Hung1510/HD2-Armor-Transmog/releases/latest)

Stack any of the 31 Helldivers 2 armor passives onto your armor and tune every value.

**Press F7 in game** to open the panel: tick passives, change any value, and it applies at once. Or build before you play with the **[web builder](https://hung1510.github.io/HD2-Armor-Transmog/)**. No Python, nothing to install.

<p align="center"><img src="docs/img/panel-preview.png" width="640" alt="In-game panel"><br>
<sub>The F7 panel, drawn by the offline test harness (the game uses its own UI font).</sub></p>

Built on **[Modular Armor Passives / Passive Picker v3](https://ayakamods.com/mods/modular-armor-passives.4350/) by mostlycloudy**. The memory-patching engine, archive format and passive data are mostlycloudy's work (engine credit also to SHODAN); v4 adds the config layer, presets and builder. See [CREDITS.txt](CREDITS.txt).

- **Requires:** [Bingus Shared Loader](https://ayakamods.com/mods/bingus-shared-loader.3861/)
- **Single-player / private lobbies only.** Don't use it in public matchmaking.
- AyakaMods page: https://ayakamods.com/mods/passive-picker-v4.4359/

## Ways to use it

| You want | Do this |
|---|---|
| Change things while playing | Install any build, then press **F7** in game (see below) |
| A ready-made build | Download **[Passive-Picker-v4.zip](https://github.com/Hung1510/HD2-Armor-Transmog/releases/latest)**, add it to your mod manager, pick a preset: *Kitchen Sink, Tank, Stealth, Survivor, Demolitionist, Gunner* |
| Your own build, no setup | **[Web builder](https://hung1510.github.io/HD2-Armor-Transmog/)**, then *Download mod (.zip)* |
| Scripting / version control | `python tools\picker.py build loadout.ini --zip "My Stack.zip"` (below) |

<p align="center"><img src="docs/img/web-builder.png" width="720" alt="Web builder"></p>

Then:
1. Remove Passive Picker v3 and any older v4 build.
2. Deploy, **fully restart the game**, and wear armor with the passive the stack is on (Med-Kit by default; use Armor Transmog if you want a different look).
3. Check `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\PassivePickerV4-STATUS.txt`. It should say `OK - perk stacked`.

## The in-game panel (F7)

- **Left:** every armor passive with a tick box. Ticked = stacked onto your armor. Click a name to see its values.
- **Right:** the chosen passive's values, in plain terms (`75%` resist, `+30%`, `+50` armor). `--` `-` `+` `++` change them, `R` resets, or click a value and type one, e.g. `75` for 75% (Enter to set, Esc to cancel). The armor's own passive (e.g. Med-Kit) is listed first; its values **replace** the originals.
- **Tabs:** one per armor passive you stack onto. **+ Armor** adds another (e.g. a separate Siege-Ready stack), **Remove this armor** puts the game's own values back.
- **When two passives change the same thing:** *Stack all* or *Strongest only*.
- Every change applies at once and is saved to `%LOCALAPPDATA%\CowboyBingus\Helldivers2\PassivePicker\loadout.ini`, the same format as the web builder, so you can import it there to share. Installing a different build starts fresh from that build.
- **Presets tab:** load the installed build, a built-in preset or one of yours. **+ Save current stack** saves what you have; rename, overwrite or delete your own. Saved in `PassivePicker\my-presets.txt`.
- **Quick-swap (F9):** cycles your presets in game without opening the panel (built-ins if you have none saved). Set `swap_hotkey = F9` or `OFF` in `[settings]`.
- **Undo / Ctrl+Z** takes back the last change (up to 30).
- **Copy code / Paste code:** your build as one line of text for Discord etc. Web-builder share links paste too.

- The key is set with `hotkey = F7` in `[settings]` (the web builder has a dropdown). SHODAN Stat Editor uses F8, and its panel sits on the right while this one sits on the left.
- If a change doesn't show, re-equip the armor or start a mission.

<p align="center"><img src="docs/img/panel-presets.png" width="560" alt="Presets tab"></p>

## What v4 adds over v3

| v3 | v4 |
|---|---|
| comment out hex rows in a 1,000-line Lua | web builder, or `Democracy Protects = on` in `loadout.ini` |
| one trigger armor | one stack per armor passive, several at once |
| base perk can't be changed | `Med-Kit.stims = 6` **replaces** the base value |
| hex values | named effects: `Democracy Protects.death_save = 2.0` |
| conflicts always multiply | `conflicts = stack` or `strongest` |
| rebuild and reinstall for every change | F7 in-game panel, live |
| one build per zip | six presets in one zip, chosen in the mod manager |

## What's confirmed in game

Effect names are **inferred** from the passive descriptions; the game only stores hashes. The mod itself is confirmed to load and patch in game. Most individual effects are still **untested**. See **[TESTING.md](TESTING.md)** for the status of each one and how to test it. Report results with an [Effect test result](https://github.com/Hung1510/HD2-Armor-Transmog/issues/new?template=effect_report.yml) issue.

Known limits:
- `death_save = 2.0` = 100% is a best guess.
- Adreno-Defibrillator's revive is probably tied to the perk ID, so it likely won't work when stacked.
- Some passives store their effect in both lists (Epaulettes, Unflinching, Siege-Ready, Gunslinger, Hazmat, True Grit): a normal effect and a `(stat)` effect. Change both.

## Command line (Python 3.8+)

```powershell
git clone https://github.com/Hung1510/HD2-Armor-Transmog.git
cd HD2-Armor-Transmog
pip install lupa                                   # optional: Lua syntax check

python tools\picker.py list                        # every passive, effect, default
python tools\picker.py build loadout.ini           # preview
python tools\picker.py build loadout.ini --zip "My Stack.zip"
python tools\picker.py release --zip dist\Passive-Picker-v4.zip   # presets zip
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
tools/main.lua             per-frame tick and startup
docs/                      web builder (GitHub Pages): index.html, app.js (UI), core.js (build logic)
docs/data.json             generated by `picker.py export-web`, never hand-edited
presets/*.ini              the presets shipped in the release zip
tests/harness.py           fake game for LuaJIT: memory, engine GUI, keyboard, mouse
tests/test_ingame.py       real mod vs fake game: rows match picker.py, panel flows, save/restore
tests/test_web_parity.js   web builder output must be byte-identical to Python
TESTING.md                 in-game verification status per effect
```

## When the game updates

Nothing to do for new armor that uses an existing passive; stacks are per passive, not per armor.

On patch day:
1. Start the game once with the mod. Check `PassivePickerV4-STATUS.txt`:
   - `found=31 of 31`: all good.
   - `NOT in the catalog=N`: new passives exist.
   - `found=0`: the game's data layout changed. The mod safely does nothing; disable it until it's updated.
2. The mod has written every armor passive the game has, with the game's own values, to `%LOCALAPPDATA%\CowboyBingus\Helldivers2\PassivePicker\passives-dump.txt`. Compare it with the catalog:
   ```
   python tools\picker.py check-dump
   ```
   It prints **NEW** passives and **CHANGED** values as ready-to-paste `CATALOG` lines, **MISSING** passives, and new effect IDs for `EFFECTS`. It exits 0 when nothing changed.
3. Paste the lines into `tools/picker.py`, give new passives and effects real names, then run `python tools\picker.py export-web` and `python tests\test_ingame.py`. Commit, tag and release.

## Contributing

- **Effect name confirmed or wrong:** edit `EFFECTS` / `STAT_EFFECTS` in `tools/picker.py`, update `TESTING.md`, run `python tools/picker.py export-web`.
- **New passive after a game patch:** add it to `CATALOG` in `tools/picker.py`, then run `export-web`.
- **New preset:** add `presets/NN-name.ini`, then run `export-web`.
- **Web UI:** `docs/app.js` / `docs/index.html`. Build logic belongs in `docs/core.js`, and it must stay a port of `picker.py`.
- Before a PR (CI runs the same checks):
  ```
  pip install lupa
  python tools/picker.py export-web --check
  python tests/test_ingame.py
  node tests/test_web_parity.js
  ```
  Preview the site locally with `cd docs && python -m http.server`.
- **Releasing:** bump `VERSION` in `tools/picker.py` and add a `CHANGELOG.md` entry. Then run `export-web`, commit, and push a tag (`git tag v4.2 && git push --tags`). GitHub Actions builds the presets zip and attaches it to the release.

## Credits

- **mostlycloudy**: original mod, engine, passive data ([AyakaMods](https://ayakamods.com/mods/modular-armor-passives.4350/))
- **SHODAN**: engine credit, as noted in v3; the panel's drawing, input and font handling are adapted from [SHODAN Stat Editor](https://github.com/SHODAN-HORAI/SHODAN-Stat-Editor) v1.4.1 (public domain)
- **Bingus Shared Loader**: the loader this runs on
- **JSZip** (MIT): zip writing in the web builder
- **Hung1510**: v4 config layer, presets, web builder, in-game panel

Not affiliated with Arrowhead Game Studios.
