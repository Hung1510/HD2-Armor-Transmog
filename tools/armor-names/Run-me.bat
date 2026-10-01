@echo off
rem Reads your Helldivers 2 install (read-only) and writes the armor names next to this file:
rem armors.json (English), armors-ja.json (Japanese), armors-zh.json (Chinese, Simplified).
cd /d "%~dp0"
echo Reading the game files in English, this can take a minute...
set ARMOR_NAMES_LANG=English (US)
armor-set-json-dumper.exe > armors.json
if errorlevel 1 goto failed
echo Japanese...
set ARMOR_NAMES_LANG=Japanese
armor-set-json-dumper.exe > armors-ja.json
if errorlevel 1 goto failed
echo Chinese (Simplified)...
set ARMOR_NAMES_LANG=Chinese (Simplified)
armor-set-json-dumper.exe > armors-zh.json
if errorlevel 1 goto failed
echo Done: armors.json, armors-ja.json and armors-zh.json are next to this file. Send all three to the mod author.
goto end
:failed
echo Something went wrong. Send the text above to the mod author.
:end
pause
