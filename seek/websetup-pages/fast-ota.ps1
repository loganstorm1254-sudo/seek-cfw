# Seek Fast OTA — run on the PC (same hotspot as Vector). No Node, no git clone.
# Windows one-liner:
#   irm https://files.anki.org.uk/fast-ota.ps1 | iex
$ErrorActionPreference = "Stop"
$Port = 8765
$OtaUrl = "http://files.anki.org.uk/ota/latest"
$Dir = Join-Path $env:TEMP "seek-fast-ota"
$Ota = Join-Path $Dir "latest.ota"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

function Get-LanIPv4 {
  $candidates = @()
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -notlike "127.*" -and
      $_.PrefixOrigin -ne "WellKnown" -and
      (
        $_.IPAddress -like "192.168.*" -or
        $_.IPAddress -like "10.*" -or
        $_.IPAddress -match '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
      )
    } |
    ForEach-Object { $candidates += $_.IPAddress }

  if (-not $candidates.Count) {
    $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
      Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq "Up" }
    foreach ($c in $cfg) {
      $ip = $c.IPv4Address.IPAddress
      if ($ip -and $ip -notlike "127.*") { $candidates += $ip }
    }
  }
  if (-not $candidates.Count) {
    throw "No LAN IP found. Join this PC to the same phone hotspot as Vector, then run again."
  }
  # Prefer 192.168 (typical phone hotspot)
  $pref = $candidates | Where-Object { $_ -like "192.168.*" } | Select-Object -First 1
  if ($pref) { return $pref }
  return $candidates[0]
}

Write-Host ""
Write-Host "=== Seek Fast OTA ===" -ForegroundColor Green
Write-Host "PC downloads the OS image; Vector pulls it over hotspot Wi-Fi (fast)."
Write-Host ""

$need = $true
if (Test-Path $Ota) {
  $len = (Get-Item $Ota).Length
  if ($len -gt 80MB) {
    $need = $false
    Write-Host ("Using cached file: {0:N1} MB" -f ($len / 1MB))
  }
}
if ($need) {
  Write-Host "Downloading Seek OS (~217 MB) to this PC…"
  Write-Host "  $OtaUrl"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $OtaUrl -OutFile $Ota -UseBasicParsing
  Write-Host ("Saved {0:N1} MB" -f ((Get-Item $Ota).Length / 1MB))
}

$ip = Get-LanIPv4
$robotUrl = "http://${ip}:${Port}/latest.ota"
try { Set-Clipboard -Value $robotUrl } catch {}

# Allow non-admin bind to this IP:port when possible
$prefix = "http://${ip}:${Port}/"
$listener = New-Object System.Net.HttpListener
$bound = $false
foreach ($p in @($prefix, "http://+:${Port}/", "http://*:${Port}/")) {
  try {
    $listener.Prefixes.Clear()
    [void]$listener.Prefixes.Add($p)
    $listener.Start()
    $bound = $true
    break
  } catch {
    try { $listener.Close() } catch {}
    $listener = New-Object System.Net.HttpListener
  }
}
if (-not $bound) {
  throw @"
Could not listen on port $Port.
Fix: open PowerShell as Administrator once and run:
  netsh http add urlacl url=http://+:$Port/ user=Everyone
Then run this script again.
"@
}

# Best-effort firewall allow (may prompt / need admin)
try {
  $rule = "Seek Fast OTA $Port"
  if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
  }
} catch {}

Write-Host ""
Write-Host "READY — leave this window open." -ForegroundColor Green
Write-Host "1. Chrome:  https://files.anki.org.uk/setup"
Write-Host "2. Pair Vector (same hotspot as this PC)"
Write-Host "3. Paste this into Fast install (copied to clipboard if possible):"
Write-Host ""
Write-Host "   $robotUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Serving $Ota … Ctrl+C to stop."
Write-Host ""

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  $fs = $null
  try {
    $path = $req.Url.AbsolutePath
    if ($req.HttpMethod -eq "OPTIONS") {
      $res.StatusCode = 204
      $res.Close()
      continue
    }
    $ok =
      $path -eq "/" -or
      $path -eq "/latest.ota" -or
      $path -eq "/firmware/latest.ota" -or
      $path -eq "/ota/latest"
    if (-not $ok) {
      $msg = [Text.Encoding]::UTF8.GetBytes("Seek Fast OTA`n$robotUrl`n")
      $res.StatusCode = 404
      $res.ContentType = "text/plain"
      $res.OutputStream.Write($msg, 0, $msg.Length)
      $res.Close()
      continue
    }

    $fs = [System.IO.File]::OpenRead($Ota)
    $otaLen = $fs.Length
    $res.Headers.Add("Accept-Ranges", "bytes")
    $res.Headers.Add("Access-Control-Allow-Origin", "*")
    $res.ContentType = "application/octet-stream"

    $range = $req.Headers["Range"]
    $start = [int64]0
    $end = $otaLen - 1
    if ($range -match "^bytes=(\d*)-(\d*)$") {
      if ($Matches[1] -ne "") { $start = [int64]$Matches[1] }
      if ($Matches[2] -ne "") { $end = [int64]$Matches[2] }
      if ($end -ge $otaLen) { $end = $otaLen - 1 }
      if ($start -lt 0 -or $start -gt $end) {
        $res.StatusCode = 416
        $res.Close()
        continue
      }
      $res.StatusCode = 206
      $res.Headers.Add("Content-Range", "bytes $start-$end/$otaLen")
    } else {
      $res.StatusCode = 200
    }

    $len = $end - $start + 1
    $res.ContentLength64 = $len
    if ($req.HttpMethod -ne "HEAD") {
      $null = $fs.Seek($start, "Begin")
      $buffer = New-Object byte[] 65536
      $remaining = $len
      while ($remaining -gt 0) {
        $toRead = [Math]::Min($buffer.Length, $remaining)
        $read = $fs.Read($buffer, 0, $toRead)
        if ($read -le 0) { break }
        $res.OutputStream.Write($buffer, 0, $read)
        $remaining -= $read
      }
    }
  } catch {
    try { $res.StatusCode = 500 } catch {}
  } finally {
    if ($fs) { try { $fs.Close() } catch {} }
    try { $res.Close() } catch {}
  }
}
