# SeekOS full-image installer. Run on a PC on the same Wi-Fi as Vector.
# Vector cannot pull GitHub OTAs (stuck at 0%) — this downloads on the PC, then copies over LAN.
#
# One command (Windows, typical IP + key in Downloads):
#   powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/install-ota.ps1 | iex"
#
# Other robot / other key:
#   powershell -ExecutionPolicy Bypass -Command "$SeekIp='192.168.42.209'; $SeekKey='C:\Users\You\Downloads\ssh_root_key.txt'; irm https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/install-ota.ps1 | iex"

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $SeekIp) {
    if ($args.Count -ge 1 -and $args[0]) { $SeekIp = [string]$args[0] }
    else { $SeekIp = '192.168.42.209' }
}
if (-not $SeekKey) {
    if ($args.Count -ge 2 -and $args[1]) { $SeekKey = [string]$args[1] }
    else { $SeekKey = Join-Path $env:USERPROFILE 'Downloads\ssh_root_key.txt' }
}

function Find-OpenSsh([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
            (Join-Path $env:WINDIR "System32\OpenSSH\$name.exe"),
            (Join-Path ${env:ProgramFiles} "Git\usr\bin\$name.exe")
        )) {
        if (Test-Path $p) { return $p }
    }
    throw "Need $name (Windows OpenSSH). Install 'OpenSSH Client' in Optional Features."
}

if (-not (Test-Path -LiteralPath $SeekKey)) {
    throw "SSH key not found: $SeekKey"
}

$ssh = Find-OpenSsh 'ssh'
$scp = Find-OpenSsh 'scp'
$sshOpts = @('-i', $SeekKey, '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=15', '-o', 'BatchMode=yes')

Write-Host "Finding latest SeekOS .ota on GitHub..."
$asset = $null
try {
    $rels = Invoke-RestMethod -Headers @{ 'User-Agent' = 'seek-install-ota' } -Uri 'https://api.github.com/repos/loganstorm1254-sudo/seek-cfw/releases?per_page=15'
    foreach ($rel in $rels) {
        $asset = $rel.assets | Where-Object { $_.name -match '^vicos-.*\.ota$' } | Select-Object -First 1
        if ($asset) { break }
    }
} catch {
    Write-Host "GitHub API lookup failed: $($_.Exception.Message)"
}
if (-not $asset) {
    $asset = [pscustomobject]@{
        name                  = 'vicos-3.0.1.38d.ota'
        browser_download_url  = 'https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.38d/vicos-3.0.1.38d.ota'
    }
}

$name = $asset.name
$url = $asset.browser_download_url
$local = Join-Path $env:TEMP $name

Write-Host "Downloading $name on this PC (not the robot)..."
Write-Host $url
$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($curl) {
    & curl.exe -fL --progress-bar -o $local $url
    if ($LASTEXITCODE -ne 0) { throw "Download failed" }
} else {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $local
}
$sizeMb = [math]::Round((Get-Item -LiteralPath $local).Length / 1MB, 1)
Write-Host "Downloaded $sizeMb MB."

Write-Host "Preparing Vector $SeekIp ..."
& $ssh @sshOpts "root@$SeekIp" 'mkdir -p /data/ota; systemctl stop update-engine || true'
if ($LASTEXITCODE -ne 0) { throw "SSH to $SeekIp failed. Check IP and key." }

Write-Host "Copying over Wi-Fi (this is the slow part, then flash is local)..."
& $scp @sshOpts $local "root@${SeekIp}:/data/ota/$name"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

$remote = @"
set -e
mkdir -p /data/ota
if grep -q serve_local_ota /usr/sbin/update-os 2>/dev/null; then
  update-os /data/ota/$name
elif curl -sI --max-time 3 http://127.0.0.1:8765/$name 2>/dev/null | grep -qi content-length; then
  systemctl stop update-engine || true
  update-os http://127.0.0.1:8765/$name
elif busybox httpd -p 127.0.0.1:8765 -h /data/ota 2>/dev/null; then
  systemctl stop update-engine || true
  update-os http://127.0.0.1:8765/$name
else
  ln -sf /data/ota/$name /etc/wired/webroot/vicos.ota
  systemctl stop update-engine || true
  update-os http://127.0.0.1:8080/vicos.ota
fi
"@

Write-Host "Flashing from localhost. Eyes will go dark; Vector reboots when done."
& $ssh @sshOpts "root@$SeekIp" $remote
if ($LASTEXITCODE -ne 0) { throw "update-os failed" }
Write-Host "Done. Wait for Vector to boot."
