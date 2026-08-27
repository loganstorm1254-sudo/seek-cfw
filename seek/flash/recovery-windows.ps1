# Seek recovery flash from Windows (PowerShell). More reliable than .cmd on modern Windows.
param(
    [string]$Ip = "192.168.0.105",
    [string]$Key = "$env:TEMP\vector_dev_key",
    [switch]$SkipDownload
)

$ErrorActionPreference = "Stop"
$Branch = "cursor/head-only-ignore-body-7a4a"
$Flash = Join-Path $env:TEMP "unlock-manual-flash-v2.sh"
$Ota = Join-Path $env:TEMP "vicos-3.0.1.33d.ota"
$SshOpts = @(
    "-i", $Key,
    "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
    "-o", "HostKeyAlgorithms=+ssh-rsa"
)
$ScpOpts = $SshOpts + @("-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=120")
$Remote = "root@$Ip"

Write-Host "=== Seek recovery flash (3.0.1.33d) ==="
Write-Host "Charger must stay connected. IP=$Ip"
Write-Host ""

if (-not (Test-Path $Key)) {
    throw "SSH key not found: $Key"
}

if (-not $SkipDownload) {
    Write-Host "[1/4] Download flash script..."
    curl.exe -L -f -o $Flash "https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/$Branch/seek/flash/unlock-manual-flash-v2.sh"

    Write-Host "[2/4] Download OTA (~204MB)..."
    curl.exe -L -f -o $Ota "https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.33d-recovery/vicos-3.0.1.33d.ota"
} else {
    if (-not (Test-Path $Flash)) { throw "Missing flash script: $Flash" }
    if (-not (Test-Path $Ota)) { throw "Missing OTA: $Ota" }
    Write-Host "[1-2/4] Using existing files in %TEMP%"
}

Write-Host "[3/4] Upload to Vector..."
ssh @SshOpts $Remote "mkdir -p /data/ota /ota && df -h /data /ota /cache 2>/dev/null; rm -f /data/ota/v.ota /ota/v.ota"
scp @ScpOpts $Flash "${Remote}:/data/unlock-manual-flash-v2.sh"

$otaOnRobot = "/ota/v.ota"
scp @ScpOpts $Ota "${Remote}:/ota/v.ota"
if ($LASTEXITCODE -ne 0) {
    Write-Host "/ota failed, trying /data/ota/v.ota ..."
    scp @ScpOpts $Ota "${Remote}:/data/ota/v.ota"
    if ($LASTEXITCODE -ne 0) { throw "scp failed for OTA" }
    $otaOnRobot = "/data/ota/v.ota"
}

Write-Host "[4/4] Flashing inactive slot (several minutes, then reboot)..."
ssh @SshOpts $Remote "rm -f /data/unbrick; mount -o remount,rw /; chmod 755 /data/unlock-manual-flash-v2.sh; sh /data/unlock-manual-flash-v2.sh $otaOnRobot"
if ($LASTEXITCODE -ne 0) { throw "Flash command failed" }

Write-Host "DONE - Vector should reboot into Seek."
