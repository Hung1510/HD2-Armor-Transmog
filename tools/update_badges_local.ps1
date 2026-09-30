# Refresh the AyakaMods badges from this PC and push them to a GitHub Gist.
#
# Why: AyakaMods sits behind a Cloudflare JavaScript challenge, so plain HTTP
# (the GitHub workflow, curl, urllib) gets a 403. This reads the page through
# your installed Edge via Playwright (python -m pip install playwright), which
# passes the challenge. Run it by hand or from Task Scheduler (README,
# "AyakaMods badges"). Set $env:AYAKAMODS_BROWSER = "chrome" to use Chrome.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\update_badges_local.ps1
#
# The Gist's id is in tools\badges-gist.txt. Badges live in a Gist (not a branch of
# this repo) so pushes don't show "recent pushes / Compare & pull request" on GitHub.
# It keeps its own clone of the Gist in %LOCALAPPDATA%\ArmoryForgeBadges,
# merges what it reads over the last numbers (a partly-read page never drops a
# stat), and only commits when something changed. Log: last-run.log next to it.

$ErrorActionPreference = "Stop"
$repoDir = Split-Path -Parent $PSScriptRoot
$home_   = Join-Path $env:LOCALAPPDATA "ArmoryForgeBadges"
$clone   = Join-Path $home_ "gist"
$log     = Join-Path $home_ "last-run.log"
$gistId  = (Get-Content (Join-Path $PSScriptRoot "badges-gist.txt") -Raw).Trim()
if ($gistId -notmatch '^[0-9a-f]{20,40}$') { throw "put the Gist id in tools\badges-gist.txt (see README, AyakaMods badges)" }
$remote  = "https://gist.github.com/$gistId.git"
New-Item -ItemType Directory -Force -Path $home_ | Out-Null
Start-Transcript -Path $log -Force | Out-Null

try {
    # 1. an up-to-date copy of the Gist
    if (-not (Test-Path (Join-Path $clone ".git"))) {
        git clone -q $remote $clone
    }
    git -C $clone fetch -q origin
    git -C $clone reset -q --hard "@{u}"

    # 2. read AyakaMods into a scratch folder
    $out = Join-Path $home_ "out"
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    $python = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $python) { $python = (Get-Command py -ErrorAction Stop).Source }
    $ErrorActionPreference = "Continue"   # PS 5.1 turns redirected native stderr into errors
    & $python -c "import playwright" 2>$null
    $ErrorActionPreference = "Stop"
    if ($LASTEXITCODE -ne 0) { throw "Playwright is missing: run  `"$python`" -m pip install playwright" }
    if (-not $env:AYAKAMODS_BROWSER) { $env:AYAKAMODS_BROWSER = "msedge" }
    & $python (Join-Path $repoDir "tools\ayakamods_stats.py") $out
    $newJson = Join-Path $out "ayakamods.json"
    if (-not (Test-Path $newJson)) { Write-Output "could not read AyakaMods; badges unchanged"; return }

    # 3. merge over the old numbers; never go backwards
    $oldPath = Join-Path $clone "ayakamods.json"
    $merged = @{}
    if (Test-Path $oldPath) {
        (Get-Content $oldPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $merged[$_.Name] = $_.Value }
    }
    $fresh = Get-Content $newJson -Raw | ConvertFrom-Json
    foreach ($p in $fresh.PSObject.Properties) {
        $isCount = $p.Name -in @("downloads", "views")
        if (-not $isCount -or -not $merged.ContainsKey($p.Name) -or [double]$p.Value -ge [double]$merged[$p.Name]) {
            $merged[$p.Name] = $p.Value
            $badge = Join-Path $out ("ayakamods-{0}.json" -f $p.Name)
            if (Test-Path $badge) { Copy-Item $badge $clone -Force }
        }
    }
    $ordered = [ordered]@{}
    foreach ($k in @("downloads", "views", "rating")) { if ($merged.ContainsKey($k)) { $ordered[$k] = $merged[$k] } }
    # no BOM, one line, same shape the workflow writes
    [IO.File]::WriteAllText($oldPath, ($ordered | ConvertTo-Json -Compress))

    # 4. commit + push only if something changed
    git -C $clone add -A
    git -C $clone diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { Write-Output "no change: $(Get-Content $oldPath -Raw)"; return }
    git -C $clone commit -q -m "AyakaMods stats (local)"
    git -C $clone push -q origin HEAD
    Write-Output "pushed: $(Get-Content $oldPath -Raw)"
}
finally {
    Stop-Transcript | Out-Null
}
