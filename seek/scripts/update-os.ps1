# Seek: WireOS-style update-os from Windows CMD — no website.
# Needs OpenSSH Client + Vector root SSH key (ssh_root_key.txt).
#
# Easiest — CMD (auto-finds Vector on your Wi-Fi):
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/update-os.ps1 | iex"
#
# With IP:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/update-os.ps1 -OutFile $env:TEMP\u.ps1; & $env:TEMP\u.ps1 -Ip 192.168.1.50"

param(
  [string]$Ip = "",
  [string]$Key = "$env:USERPROFILE\Downloads\ssh_root_key.txt",
  [string]$OtaUrl = "http://files.anki.org.uk/ota/latest",
  [switch]$Scan
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $Key)) {
  Write-Host "SSH key not found: $Key"
  Write-Host "Put ssh_root_key.txt in Downloads, or pass -Key path\to\key"
  exit 1
}
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  Write-Host "OpenSSH client missing. Install: Settings → Apps → Optional features → OpenSSH Client"
  exit 1
}

$sshOpts = @(
  "-i", $Key,
  "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
  "-o", "HostkeyAlgorithms=+ssh-rsa",
  "-o", "StrictHostKeyChecking=no",
  "-o", "UserKnownHostsFile=NUL",
  "-o", "LogLevel=ERROR",
  "-o", "IdentitiesOnly=yes",
  "-o", "ConnectTimeout=6",
  "-o", "BatchMode=yes"
)

function Invoke-Ssh([string]$addr, [string]$remoteCmd) {
  $output = & ssh @sshOpts "root@$addr" $remoteCmd 2>&1
  return @{ Code = $LASTEXITCODE; Output = $output }
}

function Test-Robot([string]$addr) {
  $r = Invoke-Ssh $addr "echo OK"
  return ($r.Code -eq 0)
}

function Find-RobotIp {
  $guess = @(
    "192.168.43.130", "192.168.43.3", "192.168.43.2", "192.168.43.4",
    "192.168.1.130", "192.168.0.130", "192.168.1.50", "192.168.0.50"
  )
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" } |
    ForEach-Object {
      $parts = $_.IPAddress.Split(".")
      if ($parts.Count -eq 4) {
        $base = "$($parts[0]).$($parts[1]).$($parts[2])"
        $guess += @("$base.130", "$base.2", "$base.3", "$base.4", "$base.50", "$base.100")
      }
    }

  Write-Host "Looking for Vector over SSH..."
  foreach ($c in ($guess | Select-Object -Unique)) {
    Write-Host -NoNewline "  $c ... "
    if (Test-Robot $c) {
      Write-Host "FOUND"
      return $c
    }
    Write-Host "no"
  }
  return $null
}

$addr = $Ip
if (-not $addr -or $Scan) {
  $found = Find-RobotIp
  if ($found) { $addr = $found }
}
if (-not $addr) {
  Write-Host ""
  Write-Host "Could not find Vector on SSH."
  Write-Host "1) Vector + PC on same Wi-Fi"
  Write-Host "2) SSH unlocked (root key in Downloads\ssh_root_key.txt)"
  Write-Host "3) Re-run with:  -Ip 192.168.x.x"
  exit 1
}

$install = "https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/scripts/install-ota.sh"
# Keep remote command simple for BusyBox ash
$remote = "curl -k -fsSL -4 --http1.1 '$install' | sh -s -- '$OtaUrl'"

Write-Host ""
Write-Host "=== update-os on $addr (no browser) ===" -ForegroundColor Green
Write-Host "OTA: $OtaUrl"
Write-Host ""

& ssh @sshOpts -t "root@$addr" $remote
$code = $LASTEXITCODE
Write-Host ""
if ($code -eq 0) {
  Write-Host "Done — Vector should reboot into Seek." -ForegroundColor Green
} else {
  Write-Host "Exit code: $code (if flash started, wait for reboot)" -ForegroundColor Yellow
}
exit $code
