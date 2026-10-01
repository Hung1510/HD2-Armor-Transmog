@echo off
rem Reads your Helldivers 2 install (read-only) and writes armors.json next to this file.
cd /d "%~dp0"
echo Reading the game files, this can take a minute...
armor-set-json-dumper.exe > armors.json
if errorlevel 1 (echo Something went wrong. Send the text above to the mod author.) else (echo Done: armors.json was written next to this file. Send it to the mod author.)
pause
