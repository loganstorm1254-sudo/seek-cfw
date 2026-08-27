# Upload large OTA in small chunks (recovery SSH often drops ~60MB+ single scp).
param(
    [string]$Ip = "192.168.0.105",
    [string]$Key = "$env:TEMP\vector_dev_key",
    [string]$Ota = "$env:TEMP\vicos-3.0.1.33d.ota",
    [int]$ChunkMb = 15
)

$ErrorActionPreference = "Stop"
$ChunkBytes = $ChunkMb * 1MB
$ChunkDir = Join-Path $env:TEMP "ota-chunks"
$RemoteDir = "/data/ota/chunks"
$RemoteOta = "/data/ota/v.ota"
$Remote = "root@$Ip"
$SshOpts = @(
    "-i", $Key,
    "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
    "-o", "HostKeyAlgorithms=+ssh-rsa",
    "-o", "ServerAliveInterval=10",
    "-o", "ServerAliveCountMax=360"
)
$ScpOpts = $SshOpts + @("-O")

if (-not (Test-Path $Key)) { throw "SSH key not found: $Key" }
if (-not (Test-Path $Ota)) { throw "OTA not found: $Ota" }

Write-Host "=== Chunked OTA upload ($ChunkMb MB chunks) ==="
Write-Host "OTA: $Ota"
Write-Host "Robot: $Ip"
Write-Host ""

Write-Host "Preparing robot..."
ssh @SshOpts $Remote "rm -rf $RemoteDir $RemoteOta; mkdir -p $RemoteDir; df -h /data /cache 2>/dev/null"

Write-Host "Splitting locally..."
if (Test-Path $ChunkDir) { Remove-Item -Recurse -Force $ChunkDir }
New-Item -ItemType Directory -Path $ChunkDir | Out-Null

$input = [System.IO.File]::OpenRead($Ota)
$buf = New-Object byte[] $ChunkBytes
$idx = 0
while (($read = $input.Read($buf, 0, $ChunkBytes)) -gt 0) {
    $name = "part{0:D3}" -f $idx
    $path = Join-Path $ChunkDir $name
    $out = [System.IO.File]::OpenWrite($path)
    $out.Write($buf, 0, $read)
    $out.Close()
    $mb = [math]::Round($read / 1MB, 1)
    Write-Host "  $name ($mb MB)"
    $idx++
}
$input.Close()
$total = $idx
Write-Host "Chunks: $total"
Write-Host ""

for ($i = 0; $i -lt $total; $i++) {
    $name = "part{0:D3}" -f $i
    $local = Join-Path $ChunkDir $name
    $remote = "${Remote}:${RemoteDir}/${name}"
    $n = $i + 1
    Write-Host "[$n/$total] Upload $name ..."
    & scp @ScpOpts $local $remote
    if ($LASTEXITCODE -ne 0) { throw "scp failed on $name — rerun this script (chunks are cached in TEMP)" }
}

Write-Host ""
Write-Host "Assembling on robot..."
ssh @SshOpts $Remote "cat ${RemoteDir}/part* > ${RemoteOta}; SZ=`$(wc -c <${RemoteOta}); echo assembled `$SZ bytes; rm -rf ${RemoteDir}"
if ($LASTEXITCODE -ne 0) { throw "assemble failed" }

$localSz = (Get-Item $Ota).Length
Write-Host "Local size:  $localSz"
Write-Host "DONE - OTA at $RemoteOta"
Write-Host ""
Write-Host "Flash with:"
Write-Host "ssh -i `$env:TEMP\vector_dev_key -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa root@${Ip} `"rm -f /data/unbrick; sh /data/unlock-manual-flash-v2.sh /data/ota/v.ota`""
