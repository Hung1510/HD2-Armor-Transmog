Armor names for Super Earth Armory Forge
========================================
Double-click Run-me.bat. It finds your Helldivers 2 install, READS its data files
(nothing in the game folder is changed), and writes next to it:
  armors.json      every armor, helmet and cape with its id, name and passive (English)
  armors-ja.json   the same in Japanese
  armors-zh.json   the same in Chinese (Simplified)
Send them back, or turn them into the mod's name tables with:
  python tools/armor_names.py armors.json --lang ja armors-ja.json --lang zh armors-zh.json

armor-set-json-dumper.exe is FileDiver's armor-set-json-dumper tool from
https://github.com/xypwn/filediver (commit @COMMIT@), built for Windows x64 by
tools/armor-names/build.sh in the Super Earth Armory Forge repository with one change:
the language comes from ARMOR_NAMES_LANG instead of always English.
FileDiver is BSD-3-Clause licensed (LICENSE-filediver.txt), by xypwn and contributors.

Windows SmartScreen may warn because the exe isn't signed: More info > Run anyway.
