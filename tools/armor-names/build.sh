#!/usr/bin/env bash
# Builds the armor names tool: FileDiver's armor-set-json-dumper for Windows, plus a
# double-click runner, packed as dist/armor-names-tool.zip. Run by
# .github/workflows/armor-names-tool.yml; works locally too (Go 1.24+, git, zip).
#
#   tools/armor-names/build.sh              # pinned FileDiver commit
#   FILEDIVER_REF=master tools/armor-names/build.sh
#   MIRRORS=1 tools/armor-names/build.sh    # no proxy.golang.org: golang.org/x from GitHub mirrors
#
# The dumper itself is FileDiver's (https://github.com/xypwn/filediver, BSD-3-Clause,
# by xypwn and contributors), with one change: the text language comes from the
# ARMOR_NAMES_LANG environment variable (default English (US)) instead of always English,
# so the same exe also writes the Japanese and Chinese names and passive text. It reads
# the game install (read-only) and prints every armor, helmet and cape with its id and name.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REF="${FILEDIVER_REF:-6d66a9c}"          # FileDiver master, 2026-09-30
WORK="$(mktemp -d)"
OUT="${OUT:-$HERE/dist}"
trap 'rm -rf "$WORK"' EXIT

git clone -q https://github.com/xypwn/filediver "$WORK/filediver"
git -C "$WORK/filediver" checkout -q "$REF"
COMMIT="$(git -C "$WORK/filediver" rev-parse --short HEAD)"
cd "$WORK/filediver"

export GOOS=windows GOARCH=amd64 CGO_ENABLED=0
if [ "${MIRRORS:-0}" = "1" ]; then
    # Build hosts without proxy.golang.org: fetch golang.org/x/* from github.com/golang/*
    # at the versions go.sum pins, and let a local Go toolchain build it.
    for m in sys term text image mod sync tools exp; do
        ver="$(awk -v p="golang.org/x/$m" '$1==p && $2 !~ /go.mod$/ {print $2; exit}' go.sum)"
        [ -n "$ver" ] || continue
        rev="${ver##*-}"; case "$ver" in v0.0.0-*) ;; *) rev="$ver" ;; esac
        git clone -q https://github.com/golang/$m "$WORK/x/$m"
        git -C "$WORK/x/$m" checkout -q "$rev"
        sed -i -E 's/^go 1\.(2[5-9])(\.[0-9]+)?$/go 1.24/; /^toolchain/d' "$WORK/x/$m/go.mod"
        echo "replace golang.org/x/$m => $WORK/x/$m" >> go.mod
    done
    sed -i -E 's/^go 1\.(2[5-9])(\.[0-9]+)?$/go 1.24/; /^toolchain/d' go.mod
    export GOTOOLCHAIN=local GOPROXY=direct GOSUMDB=off GOFLAGS=-mod=mod
fi

# the one change: language from ARMOR_NAMES_LANG (FileDiver's friendly names, e.g. "Japanese")
MAIN=cmd/tools/components/armor-set-json-dumper/main.go
grep -q 'LanguageFriendlyNameToHash\["English (US)"\]' "$MAIN"
sed -i 's/LanguageFriendlyNameToHash\["English (US)"\]/LanguageFriendlyNameToHash[armorNamesLang()]/' "$MAIN"
cat >> "$MAIN" <<'GO'

// Super Earth Armory Forge: the text language, from ARMOR_NAMES_LANG (default English (US))
func armorNamesLang() string {
	if l := os.Getenv("ARMOR_NAMES_LANG"); l != "" {
		if _, ok := stingray_strings.LanguageFriendlyNameToHash[l]; ok {
			return l
		}
	}
	return "English (US)"
}
GO

mkdir -p "$WORK/pkg" "$OUT"
go build -trimpath -o "$WORK/pkg/armor-set-json-dumper.exe" ./cmd/tools/components/armor-set-json-dumper
cp LICENSE "$WORK/pkg/LICENSE-filediver.txt"
cp "$HERE/Run-me.bat" "$WORK/pkg/"
sed "s/@COMMIT@/$COMMIT/" "$HERE/README.txt" > "$WORK/pkg/README.txt"
(cd "$WORK/pkg" && rm -f "$OUT/armor-names-tool.zip" && zip -q -9 "$OUT/armor-names-tool.zip" ./*)
sha256sum "$WORK/pkg/armor-set-json-dumper.exe" | tee "$OUT/armor-set-json-dumper.exe.sha256"
echo "built $OUT/armor-names-tool.zip from FileDiver $COMMIT"
