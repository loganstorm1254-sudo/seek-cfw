# Seek Fast OTA — PC downloads ~217MB, Vector pulls over LAN Wi-Fi (fast).
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/fast-ota.ps1 | iex"
$ErrorActionPreference = "Stop"
$Port = 8765
$OtaUrl = "https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/vicos-3.0.1.64d.ota"
$OtaUrlAlt = "http://files.anki.org.uk/ota/latest"
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
    throw "No LAN IP found. Join this PC to the SAME Wi-Fi as Vector, then run again."
  }
  $pref = $candidates | Where-Object { $_ -like "192.168.*" } | Select-Object -First 1
  if ($pref) { return $pref }
  return $candidates[0]
}

function Start-PythonServer([string]$root, [int]$port) {
  $py = $null
  foreach ($c in @("python", "py", "python3")) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { $py = $cmd.Source; break }
  }
  if (-not $py) { return $null }
  Write-Host "Serving with Python (no admin needed)..."
  $p = Start-Process -FilePath $py -ArgumentList @("-m", "http.server", "$port", "--bind", "0.0.0.0") `
    -WorkingDirectory $root -PassThru -WindowStyle Hidden
  return $p
}

# Minimal HTTP file server — no HttpListener URL ACL / admin required.
function Start-TcpOtaServer([string]$otaPath, [string]$bindIp, [int]$port) {
  $endpoint = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, $port)
  $listener = New-Object System.Net.Sockets.TcpListener $endpoint
  $listener.Start()
  Write-Host "Serving with TcpListener on 0.0.0.0:$port (no admin)..."
  $otaLen = (Get-Item $otaPath).Length
  $run = $true
  while ($run) {
    try {
      $client = $listener.AcceptTcpClient()
    } catch {
      break
    }
    try {
      $stream = $client.GetStream()
      $reader = New-Object System.IO.StreamReader($stream)
      $reqLine = $reader.ReadLine()
      if (-not $reqLine) { $client.Close(); continue }
      $headers = @{}
      while ($true) {
        $h = $reader.ReadLine()
        if ($null -eq $h -or $h -eq "") { break }
        $i = $h.IndexOf(":")
        if ($i -gt 0) {
          $headers[$h.Substring(0, $i).Trim().ToLower()] = $h.Substring($i + 1).Trim()
        }
      }
      $parts = $reqLine.Split(" ")
      $method = $parts[0]
      $path = if ($parts.Length -gt 1) { $parts[1].Split("?")[0] } else { "/" }
      $ok = @("/", "/latest.ota", "/v.ota", "/firmware/latest.ota", "/ota/latest") -contains $path
      if (-not $ok) {
        $body = [Text.Encoding]::ASCII.GetBytes("not found`n")
        $hdr = "HTTP/1.1 404 Not Found`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
        $hb = [Text.Encoding]::ASCII.GetBytes($hdr)
        $stream.Write($hb, 0, $hb.Length)
        $stream.Write($body, 0, $body.Length)
        $client.Close()
        continue
      }

      $start = [int64]0
      $end = $otaLen - 1
      $code = 200
      $status = "OK"
      if ($headers.ContainsKey("range") -and $headers["range"] -match "^bytes=(\d*)-(\d*)$") {
        if ($Matches[1] -ne "") { $start = [int64]$Matches[1] }
        if ($Matches[2] -ne "") { $end = [int64]$Matches[2] }
        if ($end -ge $otaLen) { $end = $otaLen - 1 }
        $code = 206
        $status = "Partial Content"
      }
      $len = $end - $start + 1
      $resp = "HTTP/1.1 $code $status`r`n"
      $resp += "Content-Type: application/octet-stream`r`n"
      $resp += "Accept-Ranges: bytes`r`n"
      $resp += "Content-Length: $len`r`n"
      $resp += "Access-Control-Allow-Origin: *`r`n"
      $resp += "Connection: close`r`n"
      if ($code -eq 206) {
        $resp += "Content-Range: bytes $start-$end/$otaLen`r`n"
      }
      $resp += "`r`n"
      $hb = [Text.Encoding]::ASCII.GetBytes($resp)
      $stream.Write($hb, 0, $hb.Length)
      if ($method -ne "HEAD") {
        $fs = [System.IO.File]::OpenRead($otaPath)
        try {
          $null = $fs.Seek($start, "Begin")
          $buf = New-Object byte[] 65536
          $left = $len
          while ($left -gt 0) {
            $n = [Math]::Min($buf.Length, $left)
            $r = $fs.Read($buf, 0, $n)
            if ($r -le 0) { break }
            $stream.Write($buf, 0, $r)
            $left -= $r
          }
        } finally { $fs.Close() }
      }
      Write-Host ("{0} {1} -> {2} bytes" -f (Get-Date -Format "HH:mm:ss"), $client.Client.RemoteEndPoint, $len)
    } catch {
      # ignore single-request errors
    } finally {
      try { $client.Close() } catch {}
    }
  }
  try { $listener.Stop() } catch {}
}

Write-Host ""
Write-Host "=== Seek Fast OTA ===" -ForegroundColor Green
Write-Host "This PC downloads the CFW once; Vector installs over local Wi-Fi."
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
  Write-Host "Downloading Seek OS (~217 MB) to this PC (one time)..."
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try {
    Write-Host "  $OtaUrl"
    Invoke-WebRequest -Uri $OtaUrl -OutFile $Ota -UseBasicParsing
  } catch {
    Write-Host "GitHub download failed, trying files.anki.org.uk..."
    Invoke-WebRequest -Uri $OtaUrlAlt -OutFile $Ota -UseBasicParsing
  }
  Write-Host ("Saved {0:N1} MB" -f ((Get-Item $Ota).Length / 1MB))
}

# Ensure filename Vector will request
Copy-Item -Force $Ota (Join-Path $Dir "v.ota") -ErrorAction SilentlyContinue

$ip = Get-LanIPv4
$robotUrl = "http://${ip}:${Port}/latest.ota"
try { Set-Clipboard -Value $robotUrl } catch {}

try {
  $rule = "Seek Fast OTA $Port"
  if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
  }
} catch {}

Write-Host ""
Write-Host "READY — leave this window OPEN." -ForegroundColor Green
Write-Host ""
Write-Host "1. PC + Vector on the SAME Wi-Fi"
Write-Host "2. On Vector (SSH), run:"
Write-Host ""
Write-Host "   UPDATE_ENGINE_DEBUG=true UPDATE_ENGINE_ALLOW_DOWNGRADE=True UPDATE_ENGINE_ENABLED=True UPDATE_ENGINE_URL='$robotUrl' /anki/bin/update-engine" -ForegroundColor Cyan
Write-Host ""
Write-Host "(URL also copied to clipboard if possible)"
Write-Host "Serving $Ota ... Ctrl+C to stop."
Write-Host ""

# Prefer TcpListener — no admin URL ACL needed (HttpListener often fails on Win10/11).
try {
  Start-TcpOtaServer -otaPath $Ota -bindIp $ip -port $Port
} catch {
  Write-Host "TcpListener failed: $_"
  Write-Host "Trying Python fallback..."
  $proc = Start-PythonServer -root $Dir -port $Port
  if (-not $proc) {
    throw @"
Could not start a local HTTP server on port $Port.

Option A (Admin PowerShell, once):
  netsh http add urlacl url=http://+:$Port/ user=Everyone
  netsh advfirewall firewall add rule name=`"Seek Fast OTA`" dir=in action=allow protocol=TCP localport=$Port

Then re-run the fast-ota command.

Option B: install Python from python.org, re-run this script.
"@
  }
  Write-Host "Python PID $($proc.Id). Press Ctrl+C to stop."
  try {
    Wait-Process -Id $proc.Id
  } finally {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
}
