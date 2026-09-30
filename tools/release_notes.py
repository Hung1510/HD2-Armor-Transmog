#!/usr/bin/env python3
"""
Release notes for a tag, from CHANGELOG.md (used by .github/workflows/release.yml).

    python tools/release_notes.py v5.4 > notes.md
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FOOTER = """
### Downloads
| File | Where it's for | What it does |
|---|---|---|
| `Super-Earth-Armory-Forge.zip` | GitHub, AyakaMods | **Full edition:** stack any armor passives onto your armor and set every value, live in game (F7) |
| `Super-Earth-Armory-Forge-Passive-Swap.zip` | Nexus Mods | **Passive Swap edition:** give any armor one other passive at the game's own values; no stacking, no value editing |

Install one of them with Arsenal (or any HD2 mod manager); both need **Bingus Shared Loader**. Start the game and press **F7**.
Single-player / private lobbies only.
"""


def notes(tag):
    version = tag.lstrip("vV")
    text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    m = re.search(r"^## %s\b[^\n]*\n(.*?)(?=^## |\Z)" % re.escape(version), text, re.S | re.M)
    body = m.group(1).strip() if m else "See CHANGELOG.md."
    return "## What's new in %s\n\n%s\n%s" % (version, body, FOOTER)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.stdout.write(notes(sys.argv[1]))
