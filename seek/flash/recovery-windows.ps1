# Seek recovery flash from Windows (PowerShell). Version: 3
param(
    [string]$Ip = "192.168.0.105",
    [string]$Key = "$env:TEMP\vector_dev_key",
    [switch]$SkipDownload
)

$ScriptVersion = 3
$ErrorActionPreference = "Stop"
$Branch = "cursor/head-only-ignore-body-7a4a"
$Flash = Join-Path $env:TEMP "unlock-manual-flash-v2.sh"
$Ota = Join-Path $env:TEMP "vicos-3.0.1.33d.ota"
$OtaOnRobot = "/data/ota/v.ota"
$Remote = "root@$Ip"
$SshOpts = @(
    "-i", $Key,
    "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
    "-o", "HostKeyAlgorithms=+ssh-rsa",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=120"
)
# -O = legacy scp (recovery has no sftp-server; Windows OpenSSH defaults to SFTP)
$ScpOpts = $SshOpts + @("-O")

function Invoke-ScpFile([string]$Local, [string]$RemotePath) {
    $dest = "${Remote}:${RemotePath}"
    & scp @ScpOpts $Local $dest
    return $LASTEXITCODE
}

function Invoke-SshStreamUpload([string]$Local, [string]$RemotePath) {
    Write-Host "  streaming over ssh (legacy scp unavailable)..."
    $q = '"'
    $sshLine = "ssh -i $q$Key$q -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -o ServerAliveInterval=15 -o ServerAliveCountMax=120 $Remote"
    & cmd.exe /c "type $q$Local$q | $sshLine `"cat > $RemotePath`""
    return $LASTEXITCODE
}

function Send-RobotOta([string]$Local, [string]$RemotePath) {
    if (-not (Test-Path $Local)) { throw "Missing local file: $Local" }
    $size = (Get-Item $Local).Length
    if ($size -lt 50MB) {
        if ((Invoke-ScpFile $Local $RemotePath) -eq 0) { return }
        if ((Invoke-SshStreamUpload $Local $RemotePath) -eq 0) { return }
        throw "Upload failed for $RemotePath"
    }

    Write-Host "  large OTA ($([math]::Round($size/1MB)) MB) — chunked upload..."
    $chunkScript = Join-Path $env:TEMP "recovery-chunk-upload.ps1"
    curl.exe -L -f -o $chunkScript "https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/$Branch/seek/flash/recovery-chunk-upload.ps1?v=1"
    & $chunkScript -Ip $Ip -Key $Key -Ota $Local
    if ($LASTEXITCODE -ne 0) { throw "Chunked OTA upload failed" }
}

Write-Host "=== Seek recovery flash v$ScriptVersion (3.0.1.33d) ==="
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
    Write-Host "[1-2/4] Using existing files in TEMP"
}

Write-Host "[3/4] Upload to Vector (/data/ota only — /ota is read-only in recovery)..."
ssh @SshOpts $Remote "mkdir -p /data/ota && df -h /data /cache 2>/dev/null; rm -f $OtaOnRobot"
Write-Host "  flash script..."
if ((Invoke-ScpFile $Flash "/data/unlock-manual-flash-v2.sh") -ne 0) {
    if ((Invoke-SshStreamUpload $Flash "/data/unlock-manual-flash-v2.sh") -ne 0) {
        throw "Upload failed for flash script"
    }
}
Write-Host "  OTA (~204MB, several minutes)..."
Send-RobotOta $Ota $OtaOnRobot

Write-Host "[4/4] Flashing inactive slot (several minutes, then reboot)..."
ssh @SshOpts $Remote "rm -f /data/unbrick; mount -o remount,rw /; chmod 755 /data/unlock-manual-flash-v2.sh; sh /data/unlock-manual-flash-v2.sh $OtaOnRobot"
if ($LASTEXITCODE -ne 0) { throw "Flash command failed" }

Write-Host "DONE - Vector should reboot into Seek."
