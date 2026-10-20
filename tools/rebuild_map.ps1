# Rebuilds the world (world/yeghvard.scn and the minimap) from the editable map
# world/map/map.tscn, then the sidewalks along it (world/sidewalks.scn).
#
# Right-click this file > "Run with PowerShell", or in a terminal in the project folder:
#     powershell -ExecutionPolicy Bypass -File tools\rebuild_map.ps1
#
# It downloads the map data first if it is not there (tools/fetch_data.ps1), and
# finds Godot by itself: set GODOT to the path of Godot's .exe if it does not.
# Close the project in the Godot editor while this runs.

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# 1. The map data (OpenStreetMap roads and land use, elevation), if missing.
$data = Join-Path $root "data"
$haveData = (Test-Path (Join-Path $data "osm.json")) -and
    ((Get-ChildItem (Join-Path $data "elev") -Filter "13_*.png" -ErrorAction SilentlyContinue).Count -ge 16)
if (-not $haveData) {
    Write-Host "Downloading the map data..."
    & (Join-Path $PSScriptRoot "fetch_data.ps1")
}

# 2. Godot: $env:GODOT, else on the PATH, else the usual places for its .exe.
$godot = $env:GODOT
if (-not $godot) {
    $cmd = Get-Command "godot*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $godot = $cmd.Source }
}
if (-not $godot) {
    $places = @(
        (Join-Path $HOME "Desktop"), (Join-Path $HOME "Downloads"), (Join-Path $HOME "Documents"),
        $env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}, "C:\Godot", "D:\", "C:\Tools"
    ) | Where-Object { $_ -and (Test-Path $_) }
    $found = foreach ($p in $places) {
        Get-ChildItem $p -Filter "Godot_v4*.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue
    }
    # The console build shows the progress in this window; otherwise the newest.
    $pick = $found | Sort-Object @{ Expression = { $_.Name -like "*console*" }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $true } |
        Select-Object -First 1
    if ($pick) { $godot = $pick.FullName }
}
if (-not $godot) {
    throw "Godot not found. Set its path first, e.g.:  `$env:GODOT = 'C:\path\to\Godot_v4.7-stable_win64.exe'"
}
Write-Host "Using $godot"

# Runs one of the build scripts and waits for it (Godot's window opens meanwhile).
function Run-Tool($script) {
    $proc = Start-Process -FilePath $godot -ArgumentList @("--path", "`"$root`"", "--script", $script) `
        -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) { throw "$script failed (exit code $($proc.ExitCode))" }
}

# 3. The world (not --headless: the trees need the renderer), then the sidewalks.
Write-Host "Moving walls and buildings back off the sidewalks..."
Run-Tool "res://tools/clear_sidewalks.gd"
Write-Host "Building the world from world/map/map.tscn (a few minutes)..."
Run-Tool "res://tools/build_world.gd"
Write-Host "Building the sidewalks..."
Run-Tool "res://tools/build_sidewalks.gd"
Write-Host "Done: world/yeghvard.scn, world/minimap.res and world/sidewalks.scn are rebuilt."
