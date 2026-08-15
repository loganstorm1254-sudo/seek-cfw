# Run in PowerShell AFTER quitting Prism.
# 1) Unlocks the jar  2) Installs modded client  3) Pins meta sha1 so Prism won't restore vanilla

$ErrorActionPreference = "Stop"
$lib = "$env:APPDATA\Roaming\PrismLauncher\libraries\com\mojang\minecraft\rd-132211\minecraft-rd-132211-client.jar"
$meta = "$env:APPDATA\Roaming\PrismLauncher\meta\net.minecraft\rd-132211.json"
$src = Join-Path $PSScriptRoot "minecraft-rd-132211-client-oakplanks.jar"
$sha1 = "e3524029afa856c4a5a17006ee6b23da0703b9f8"
$size = 24997

if (-not (Test-Path $src)) { throw "Missing $src — put this script next to the modded jar." }

attrib -R $lib 2>$null
New-Item -ItemType Directory -Force -Path (Split-Path $lib) | Out-Null
Copy-Item -Force $src $lib

if (-not (Test-Path $meta)) { throw "Missing $meta — launch the rd-132211 instance once in Prism first, then re-run." }

$json = Get-Content -Raw $meta | ConvertFrom-Json
$json.mainJar.downloads.artifact.sha1 = $sha1
$json.mainJar.downloads.artifact.size = $size
if ($json.mainJar.downloads.artifact.PSObject.Properties['url']) {
  $json.mainJar.downloads.artifact.PSObject.Properties.Remove('url')
}
($json | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 $meta

$hash = (Get-FileHash $lib -Algorithm SHA1).Hash.ToLower()
if ($hash -ne $sha1) { throw "Jar hash $hash != expected $sha1" }
Write-Host "OK: modded jar installed and meta pinned."
Write-Host "Launch the instance (offline first is fine)."
