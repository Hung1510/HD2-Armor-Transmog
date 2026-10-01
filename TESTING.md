# Testing effects in game

Effect names come from the passive descriptions; the game only stores hashes. This page tracks what has actually been **confirmed in game**. If you test one, open an [Effect test result](https://github.com/Hung1510/Super-Earth-Armory-Forge/issues/new?template=effect_report.yml) issue and it gets marked here.

## How to test

1. Build a stack with **only the passive you're testing** (web builder: *Start over*, switch one passive on). Use a big value so the difference is obvious.
2. Test in a **solo, trivial-difficulty** mission, once with the mod and once without, same weapon, same spot.
3. Check `ArmoryForge-STATUS.txt` says `OK - perk stacked` before judging anything.

Status: ✅ confirmed · ⚠️ works but name/meaning wrong · ❌ no effect · ❔ untested

## Mod as a whole

| Check | Status | Notes |
|---|---|---|
| Loads with Bingus Shared Loader, patches the Med-Kit record | ✅ | STATUS `OK - perk stacked`, `rows_appended=39 passive, 8 stat` (v4.0, 2026-09-30) |
| Release zip installs with no options (5.0) | ❔ | manifest has no Options; patch at the zip root |
| Fresh install shows the *Press F7* card | ❔ | 5.0; offline test passes |
| Updating from Passive Picker 4.x keeps panel edits and presets | ❔ | 5.0; offline test passes |
| Two armor profiles at once | ❔ | offline engine test passes; untested in game |
| F7 opens the panel and text is readable | ✅ | v4.2, confirmed in game 2026-09-30 |
| Mouse clicks and typing work in the panel | ❔ | v4.2 |
| A change applies without re-equipping the armor | ❔ | v4.2; unknown when the game re-reads passives |
| Panel save survives a game restart | ❔ | v4.2; offline test passes |
| Presets tab: load / save / rename / delete | ❔ | v4.4; offline test passes |
| F9 quick-swap changes build and shows the card | ❔ | v4.4; offline test passes |
| Undo and Ctrl+Z | ❔ | v4.4; offline test passes |
| Copy code / Paste code use the Windows clipboard | ❔ | v4.4; clipboard mocked offline |
| `%` and `+` signs show in the panel font | ❔ | v4.4 |
| Panel text is sharp on 1440p / 4K | ❔ | v5.2; whole-pixel drawing checked offline |
| Ctrl + / Ctrl - resize the panel in game | ❔ | v5.2; offline test passes |
| Mouse wheel scrolls the passive lists | ❔ | v5.3; arrows / PageUp / PageDown work if the wheel doesn't |
| Dragging the top strip moves the panel | ❔ | v5.3; offline test passes |
| Keys tab: changing F7 / F9 works in game | ❔ | v5.4; offline test passes |
| Ctrl+F search in the panel | ❔ | v5.4; offline test passes |
| Controller: Back + Start opens the panel, D-pad / A / B work | ❔ | v5.5; XInput, offline test with a fake pad |
| Stack summary numbers match what you feel in game | ❔ | v5.5; an estimate by design |
| Copy problem report reaches the clipboard; STATUS file has the panel section | ❔ | v5.6; offline test passes |
| A `panel = off` build applies its loadout with no panel | ❔ | v5.6; offline test passes |
| Armor weight: a heavy armor set to Light shows 50 / 550 / 125 and runs like light | ✅ | 5.6 research build (SR-64 Cinderblock, BFM-220 Ironclad), confirmed in a mission |
| Armor weight also changes damage taken (armor rating) in a mission | ❔ | v5.7; the armory card changes, damage not measured yet |
| Colours: another armor's colour texture on an armor | ❌ | dropped in 6.0: shows for 1-2 s, then the game unloads the texture and the armor turns black |
| The equipped armor is found (WEARING) and followed | ✅ | 5.7 research build: helmet, cape, armor ids back to back; v6.0 offline test passes |
| Weight for only the worn armor, saved and reloaded | ❔ | v6.0; offline test passes |
| Cursor on the panel: no shooting, turning or armory clicks behind it | ❔ | v6.0 test 3 (raw input); test 2's Lua-only block didn't stop it in the armory |
| Mouse wheel still scrolls the panel's lists while the game's mouse is blocked | ❔ | v6.0 test 3; PgUp / PgDn and the scrollbar work either way |
| Works alongside SHODAN Stat Editor (F8) | ❔ | if SHODAN changes the same passive first, Armory Forge leaves that passive alone |

## Effects

| Effect | Status | Used by (default value) | How to test |
|---|---|---|---|
| `armor_rating` | ❔ | Extra Padding (1), Unflinching (0.5), Supplemental Adrenaline (0.5), Concussive Padding, Reinforced (0.6), Blunt-Force Mitigation (0.5) | Stand in fire or take a fixed enemy hit with and without the mod; compare damage taken. |
| `radar_ping` | ❔ | Scout (2), Unflinching (2) | Watch the minimap: enemies should pop up on radar every N seconds. |
| `detection_radius` | ❔ | Scout (0.7), Reduced Signature (0.6) | Sneak toward a patrol; count how close you get before they aggro. |
| `crouch_prone_recoil` | ❔ | Fortified (0.7), Engineering Kit (0.7) | Crouch and fire a full mag at a wall; compare spread/climb to standing. |
| `explosive_damage_taken` | ❔ | Fortified (0.5), Ballistic Padding (0.75), Concussive Padding, Reinforced (0.5), Concussive Padding, Grenadier (0.5), Concussive Padding, Hazmat (0.5) | Throw a grenade at your feet (or stand near a barrel) and compare damage. |
| `arc_damage_taken` | ❔ | Electrical Conduit (0.05), Adreno-Defibrillator (0.5) | Take arc damage (e.g. a teammate's Arc Thrower); compare damage. |
| `arc_secondary` | ❔ | Electrical Conduit (0.05), Acclimated (0.05), Adreno-Defibrillator (0.05), Desert Stormer (0.06) | Unknown arc effect. Compare arc stun/ragdoll with and without. |
| `throwables` | ❔ | Engineering Kit (2), Integrated Explosives (2), Concussive Padding, Grenadier (2) | Count grenades at mission start. |
| `stims` | ❔ | Med-Kit (2) | Count stims at mission start (base is 4; Med-Kit's default +2). |
| `stim_duration` | ❔ | Med-Kit (2), Adreno-Defibrillator (2) | Time the stim heal/stamina effect with a stopwatch. |
| `throw_range` | ❔ | Servo-Assisted (1.3), Desert Stormer (1.2) | Throw a grenade/stratagem at max distance from a fixed spot; compare landing point. |
| `limb_health` | ❔ | Servo-Assisted (1.5) | Count hits a limb takes before it's injured. |
| `death_save` | ❔ | Democracy Protects (1.5) | Set 2.0, take ~10 lethal hits. Survive every time = 100%. About half = still 50%. |
| `chest_bleed` | ❔ | Democracy Protects (0), Ballistic Padding (0) | Take a chest hit that normally causes bleeding; check for the bleed icon. |
| `primary_reload_speed` | ❔ | Reinforced Epaulettes (1.3), Siege-Ready (1.3) | Time a primary reload (tactical and empty). |
| `limb_injury_avoid` | ❔ | Reinforced Epaulettes (1.5), Kinetic Displacement Mitigation (1.5) | Count how often a limb hit causes an injury over ~20 hits. |
| `melee_damage` | ❔ | Reinforced Epaulettes (1.2), Peak Physique (1.4), Rock-Solid (1.4) | Count melee hits to kill a small enemy. |
| `stat_primary_reload` | ❔ | Reinforced Epaulettes (1.3), Siege-Ready (1.3) | Stat-list copy of primary reload. |
| `fire_damage_taken` | ❔ | Inflammable (0.25), Kinetic Displacement Mitigation (0.5) | Stand in fire for 2 s; compare damage. |
| `ergonomics` | ❔ | Peak Physique (30), True Grit (20) | Compare aim-sway/turn speed with a heavy weapon. |
| `melee_flag` | ❔ | Peak Physique (1), Rock-Solid (1) | Unknown flag from Peak Physique / Rock-Solid. Note anything that changes. |
| `gas_damage_taken` | ❔ | Advanced Filtration (0.2), Concussive Padding, Hazmat (0.75) | Stand in a gas cloud for 2 s; compare damage. |
| `flinch` | ❔ | Unflinching (0) | Get shot while aiming; the crosshair should barely move. |
| `stat_flinch` | ❔ | Unflinching (0.05) | Stat-list copy of flinch. Test with and without to see if both are needed. |
| `elemental_damage_taken` | ❔ | Acclimated (0.5), Desert Stormer (0.6) | Compare fire/gas/acid/arc damage together. |
| `ammo_capacity` | ❔ | Siege-Ready (1.2) | Count spare magazines for your primary. |
| `stat_ammo_capacity` | ❔ | Siege-Ready (1.2) | Stat-list copy of ammo capacity. |
| `death_explosion_delay` | ❔ | Integrated Explosives (1.5) | Die and time the delay before the explosion. |
| `sidearm_reload_speed` | ❔ | Gunslinger (1.4) | Time a sidearm reload. |
| `sidearm_draw_speed` | ❔ | Gunslinger (1.5) | Time swapping to your sidearm. |
| `sidearm_recoil` | ❔ | Gunslinger (0.3), Concussive Padding, Hazmat (0.7) | Fire a sidearm mag at a wall; compare spread. |
| `stat_sidearm_reload` | ❔ | Gunslinger (1.6) | Stat-list copy of sidearm reload. |
| `stat_sidearm_draw` | ❔ | Gunslinger (1.5) | Stat-list copy of sidearm draw. |
| `stat_sidearm_recoil` | ❔ | Gunslinger (0.3), Concussive Padding, Hazmat (0.7) | Stat-list copy of sidearm recoil. |
| `revive_marker` | ❔ | Adreno-Defibrillator (0) | Adreno-Defibrillator's revive. Die once and see if you get revived (probably not when stacked). |
| `chest_damage_taken` | ❔ | Ballistic Padding (0.75) | Take chest hits from a fixed enemy; compare damage. |
| `movement_noise` | ❔ | Feet First (0.5), Reduced Signature (0.5) | Walk past sleeping/unaware enemies; compare how often they notice. |
| `poi_range` | ❔ | Feet First (1.3) | Walk toward a point of interest; note the distance where it's identified. |
| `leg_injury_immunity` | ❔ | Feet First (1) | Fall from a height / take leg hits; legs should never be injured. |
| `stagger` | ❔ | Rock-Solid (0.7), Blunt-Force Mitigation (0.7) | Get hit by a charger/berserker; compare stagger and ragdoll. |
| `stamina_on_damage` | ❔ | Supplemental Adrenaline (2) | Drain stamina, take a hit, and watch the stamina bar jump. |
| `move_speed_a` | ❔ | Oxygenator (1.1) | Time a fixed distance walking vs running. Which one changed tells us what this is. |
| `move_speed_b` | ❔ | Oxygenator (1.1) | Same as move_speed_a. Tells us which is walk and which is run. |
| `slide_flag` | ❔ | Oxygenator (0) | Dive/slide and compare the distance. |
| `impact_damage_taken` | ❔ | Kinetic Displacement Mitigation (0.7), Blunt-Force Mitigation (0.7) | Take impact hits (charger ram, ragdoll into a wall); compare damage. |
| `support_reload_speed` | ❔ | True Grit (1.3) | Time a support weapon reload. |
| `stat_support_reload` | ❔ | True Grit (1.3) | Stat-list copy of support reload. |
