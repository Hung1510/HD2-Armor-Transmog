# Refresh the AyakaMods badges from this PC and push them to the "badges" branch.
#
# Why: AyakaMods answers GitHub's servers with a 403, so the hourly workflow
# often can't read the page. A home connection gets through. Run this by hand
# or from Task Scheduler (see README, "AyakaMods badges").
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\update_badges_local.ps1
#
# It keeps its own clone of the badges branch in %LOCALAPPDATA%\ArmoryForgeBadges,
# merges what it reads over the last numbers (a partly-read page never drops a
# stat), and only commits when something changed. Log: last-run.log next to it.

$ErrorActionPreference = "Stop"
$repoDir = Split-Path -Parent $PSScriptRoot
$home_   = Join-Path $env:LOCALAPPDATA "ArmoryForgeBadges"
$clone   = Join-Path $home_ "badges"
$log     = Join-Path $home_ "last-run.log"
$remote  = "https://github.com/Hung1510/Super-Earth-Armory-Forge.git"
New-Item -ItemType Directory -Force -Path $home_ | Out-Null
Start-Transcript -Path $log -Force | Out-Null

try {
    # 1. an up-to-date copy of the badges branch (the workflow force-pushes it)
    if (-not (Test-Path (Join-Path $clone ".git"))) {
        git clone -q --single-branch -b badges $remote $clone
    }
    git -C $clone fetch -q origin badges
    git -C $clone reset -q --hard origin/badges

    # 2. read AyakaMods into a scratch folder
    $out = Join-Path $home_ "out"
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    $python = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $python) { $python = (Get-Command py -ErrorAction Stop).Source }
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
    git -C $clone push -q origin badges
    Write-Output "pushed: $(Get-Content $oldPath -Raw)"
}
finally {
    Stop-Transcript | Out-Null
}
