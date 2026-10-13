# Downloads the map data that tools/build_world.gd turns into world/yeghvard.scn.
#   data/osm.json          OpenStreetMap features (c) OpenStreetMap contributors, ODbL
#   data/elev/13_X_Y.png   Terrarium elevation tiles (Mapzen / AWS Terrain Tiles)
# The bounding box and tile range must match the constants in build_world.gd.

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$data = Join-Path $root "data"
New-Item -ItemType Directory -Force (Join-Path $data "elev") | Out-Null
# Keep Godot from importing the raw data.
if (-not (Test-Path (Join-Path $data ".gdignore"))) { New-Item -ItemType File (Join-Path $data ".gdignore") | Out-Null }

$query = @'
[out:json][timeout:120][bbox:40.302,44.455,40.342,44.508];
(
  way["highway"];
  way["building"];
  relation["building"];
  way["landuse"];
  way["natural"];
  way["leisure"];
  way["waterway"];
  way["railway"];
  node["natural"="tree"];
  node["place"];
);
out body geom;
'@
$queryFile = Join-Path $env:TEMP "yeghvard_overpass.txt"
Set-Content -Path $queryFile -Value $query -Encoding ascii

# The public Overpass servers are often busy, so retry.
curl.exe -sS -f -m 200 --retry 5 --retry-delay 20 --retry-all-errors `
    -A "yeghvard-drive-godot/0.1" -H "Accept: */*" `
    -o (Join-Path $data "osm.json") --data-urlencode "data@$queryFile" `
    https://overpass-api.de/api/interpreter
if ($LASTEXITCODE -ne 0) { throw "Overpass download failed" }

foreach ($x in 5106..5109) {
    foreach ($y in 3090..3093) {
        curl.exe -sS -f -m 60 -o (Join-Path $data "elev\13_${x}_${y}.png") `
            "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/13/$x/$y.png"
        if ($LASTEXITCODE -ne 0) { throw "Elevation tile $x/$y failed" }
    }
}
Write-Host "Done. Now run: godot --path . --script res://tools/build_world.gd"
