# Seek: install BLE OTA fix on a Vector from Windows (PowerShell).
# Fixes: ssh-rsa algo mismatch, robot curl CA (77), bot IP changes on hotspot.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File fix-ble-ota.ps1
#   powershell -ExecutionPolicy Bypass -File fix-ble-ota.ps1 -Key C:\Users\Logan\Downloads\ssh_root_key.txt -Ip 192.168.43.130
#   powershell -ExecutionPolicy Bypass -File fix-ble-ota.ps1 -Scan

param(
  [string]$Key = "$env:USERPROFILE\Downloads\ssh_root_key.txt",
  [string]$Ip = "",
  [string]$ScriptUrl = "https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/scripts/fix-ble-ota.sh",
  [switch]$Scan
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Key)) {
  Write-Host "SSH key not found: $Key"
  Write-Host "Pass -Key path\to\ssh_root_key.txt"
  exit 1
}

$sshOpts = @(
  "-i", $Key,
  "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
  "-o", "HostkeyAlgorithms=+ssh-rsa",
  "-o", "StrictHostKeyChecking=no",
  "-o", "UserKnownHostsFile=NUL",
  "-o", "IdentitiesOnly=yes",
  "-o", "ConnectTimeout=6",
  "-o", "BatchMode=yes"
)

function Test-Robot([string]$addr) {
  & ssh @sshOpts "root@$addr" "echo OK" 2>$null
  return ($LASTEXITCODE -eq 0)
}

function Install-On([string]$addr) {
  Write-Host "=== Installing BLE OTA fix on $addr ==="
  $local = Join-Path $env:TEMP "fix-ble-ota.sh"
  Write-Host "Downloading script to $local ..."
  Invoke-WebRequest -Uri $ScriptUrl -OutFile $local -UseBasicParsing

  Write-Host "Copying via scp..."
  & scp @sshOpts $local "root@${addr}:/tmp/f.sh"
  if ($LASTEXITCODE -ne 0) { throw "scp failed to $addr" }

  Write-Host "Running fix on robot..."
  & ssh @sshOpts "root@$addr" "chmod +x /tmp/f.sh && sh /tmp/f.sh"
  if ($LASTEXITCODE -ne 0) { throw "fix script failed on $addr" }
  Write-Host "DONE on $addr"
}

$candidates = @()
if ($Ip) { $candidates += $Ip }
$candidates += @("192.168.43.130", "192.168.43.3", "192.168.43.2", "192.168.43.4")

if ($Scan -or -not $Ip) {
  Write-Host "Probing known IPs (and quick scan of .2-.40 if needed)..."
  $found = @()
  foreach ($c in ($candidates | Select-Object -Unique)) {
    Write-Host -NoNewline "  ssh $c ... "
    if (Test-Robot $c) {
      Write-Host "UP"
      $found += $c
    } else {
      Write-Host "down"
    }
  }
  if ($found.Count -eq 0 -and $Scan) {
    for ($i = 2; $i -le 40; $i++) {
      $c = "192.168.43.$i"
      if ($candidates -contains $c) { continue }
      Write-Host -NoNewline "  ssh $c ... "
      if (Test-Robot $c) {
        Write-Host "UP"
        $found += $c
      } else {
        Write-Host "down"
      }
    }
  }
  if ($found.Count -eq 0) {
    Write-Host ""
    Write-Host "No robot answered SSH on this hotspot."
    Write-Host "1) Put Vector on the charger, wait for eyes."
    Write-Host "2) Confirm it rejoined the phone hotspot (IP on face / BLE websetup)."
    Write-Host "3) Re-run this script with the new IP:  -Ip 192.168.43.XX"
    Write-Host "Or skip SSH: open http://ROBOT_IP in Chrome → Install OTA (file upload)."
    exit 2
  }
  foreach ($f in $found) {
    Install-On $f
  }
} else {
  if (-not (Test-Robot $Ip)) {
    Write-Host "SSH timeout to $Ip — robot is offline on this network."
    exit 2
  }
  Install-On $Ip
}

Write-Host ""
Write-Host "Next: websetup → Install with https://files.anki.org.uk/ota/latest"
