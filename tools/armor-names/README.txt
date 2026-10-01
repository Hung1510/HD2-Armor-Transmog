Armor names for Super Earth Armory Forge
========================================
Double-click Run-me.bat. It finds your Helldivers 2 install, READS its data files
(nothing in the game folder is changed), and writes armors.json next to it:
every armor, helmet and cape with its id and English name. Send armors.json back,
or turn it into the mod's name table with:  python tools/armor_names.py armors.json

armor-set-json-dumper.exe is FileDiver's armor-set-json-dumper tool, built unmodified
from https://github.com/xypwn/filediver (commit @COMMIT@) for Windows x64 by
tools/armor-names/build.sh in the Super Earth Armory Forge repository.
FileDiver is BSD-3-Clause licensed (LICENSE-filediver.txt), by xypwn and contributors.

Windows SmartScreen may warn because the exe isn't signed: More info > Run anyway.
