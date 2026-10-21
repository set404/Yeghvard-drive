# Rebuilds the supermarket (world/supermarket.scn) from tools/build_supermarket.gd:
# its signs, the pharmacy cross, the shop, the guard's booth and the parking lot.
#
# Right-click this file > "Run with PowerShell", or in a terminal in the project folder:
#     powershell -ExecutionPolicy Bypass -File tools\rebuild_supermarket.ps1
#
# It finds Godot by itself: set GODOT to the path of Godot's .exe if it does not.
# Close the project in the Godot editor while this runs.

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# Godot: $env:GODOT, else on the PATH, else the usual places for its .exe.
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

Write-Host "Building the supermarket..."
Run-Tool "res://tools/build_supermarket.gd"
Write-Host "Done: world/supermarket.scn is rebuilt."
Read-Host "Press Enter to close"
