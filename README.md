# Passive Picker v4: HD2 armor passive stacker

A configurable Helldivers 2 mod that stacks any of the 31 armor passives onto armor with a chosen base passive, and lets you tune every value.

Built on **[Modular Armor Passives / Passive Picker v3](https://ayakamods.com/mods/modular-armor-passives.4350/) by mostlycloudy**. The memory-patching engine, archive format and passive data are mostlycloudy's work (engine credit also to SHODAN). v4 adds the config layer on top. See [CREDITS.txt](CREDITS.txt).

- **Download:** [Releases](https://github.com/Hung1510/HD2-Armor-Transmog/releases) · AyakaMods page *(link here once posted)*
- **Requires:** [Bingus Shared Loader](https://ayakamods.com/mods/bingus-shared-loader.3861/)
- **Single-player / private lobbies only.** Don't use it in public matchmaking.

## What v4 adds over v3

| v3 | v4 |
|---|---|
| comment out hex rows in a 1,000-line Lua | `Democracy Protects = on` in `loadout.ini` |
| one trigger armor | one `[profile: <passive>]` per armor, each with its own stack |
| base perk can't be changed | `Med-Kit.stims = 6` **replaces** the base value |
| hex values | named effects: `Democracy Protects.death_save = 2.0` |
| conflicts always multiply | `conflicts = stack` or `strongest` |
| typos fail silently | typos rejected with "did you mean" |

## Install (no Python needed)

1. Download `Passive Picker v4.zip` from [Releases](https://github.com/Hung1510/HD2-Armor-Transmog/releases).
2. Remove Passive Picker v3 if you have it installed.
3. Add the zip to your mod manager and deploy. Wear armor with the **Med-Kit** passive; use Armor Transmog if you want a different look.
4. Check `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\PassivePickerV4-STATUS.txt`. It should say `OK - perk stacked`.

## Build your own stack (Python 3.8+)

```powershell
git clone https://github.com/Hung1510/HD2-Armor-Transmog.git
cd HD2-Armor-Transmog
pip install lupa                                   # optional: Lua syntax check

python tools\picker.py list                        # every passive, effect, default
notepad loadout.ini                                # turn passives on, tweak values
python tools\picker.py build loadout.ini           # preview
python tools\picker.py build loadout.ini --zip "My Stack.zip"
```

Replace the mod in your mod manager, then **fully restart the game**. The mod patches once at load.

### loadout.ini

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
Siege-Ready.ammo_capacity        = 1.5    ; stat-array passives: set both lines
Siege-Ready.stat_ammo_capacity   = 1.5

[profile: Siege-Ready]           ; a second, independent stack
Scout = on
```

Advanced: `raw = 0xHEXID type value, ...` and `raw_stats = stat unk1 unk2, ...` append arbitrary rows. Types are 0 set, 1 add, 2 multiply, 3 time.

## Known limits

- Effect names are **inferred** from the passive descriptions; the game only stores hashes. Names marked `?` in `list` are guesses. PRs with confirmed names are welcome.
- `death_save = 2.0` = 100% is a best guess, not confirmed.
- Adreno-Defibrillator's revive is probably tied to the perk ID, so it likely won't work when stacked.
- Passives stored in both lists (Epaulettes, Unflinching, Siege-Ready, Gunslinger, Hazmat, True Grit) have a normal effect and a `stat_*` effect. Change both.

## Project layout

```
tools/picker.py      config parser, catalog (CATALOG / EFFECTS), Lua generator, archive + zip writer
tools/engine.lua     runtime engine (mostlycloudy's v3 engine + v4 profiles/overrides)
tests/test_engine.py runs the real engine in LuaJIT against a fake perk table
loadout.ini          default loadout (the one shipped in the release zip)
examples/            sample loadouts
```

### Contributing

- **New or renamed effect:** edit `EFFECTS` / `STAT_EFFECTS` in `tools/picker.py`.
- **New passive after a game patch:** add it to `CATALOG`: `perk_id: (name, [(modifier_id, type, value)], [(stat, unk1, unk2)])`.
- **Engine changes:** run the offline test before opening a PR:
  ```
  pip install lupa
  python tools/picker.py build examples/two-profiles.ini --dump-lua build/test.lua
  python tests/test_engine.py build/test.lua
  ```
  The test proves the engine logic. Only an in-game test proves the game's memory layout still matches.

## Credits

- **mostlycloudy**: original mod, engine, passive data ([AyakaMods](https://ayakamods.com/mods/modular-armor-passives.4350/))
- **SHODAN**: engine credit, as noted in v3
- **Bingus Shared Loader**: the loader this runs on
- **Hung1510**: v4 config layer, profiles, overrides
