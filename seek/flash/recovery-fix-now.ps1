# One-command Vector recovery unbrick. Usage: .\recovery-fix-now.ps1 -Ip 192.168.0.105
param(
    [string]$Ip = "192.168.0.105",
    [string]$Key = "$env:TEMP\vector_dev_key"
)

$ErrorActionPreference = "Stop"
$Commit = "7913ac1a95e1197d58d6e9ceb60096b2421b8739"
$Bootctl = "$env:TEMP\bootctl-static-arm"
$BootctlUrl = "https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/$Commit/seek/flash/bin/bootctl-static-arm"
$SshOpts = @("-i", $Key, "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa", "-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "ConnectTimeout=10")
$ScpOpts = $SshOpts + @("-O")

Write-Host "=== Vector recovery fix ==="
Write-Host "IP: $Ip (use -Ip if different)"
Write-Host ""

if (-not (Test-Path $Key)) { throw "SSH key missing: $Key" }

Write-Host "[1/4] Download static bootctl (must be ~600KB)..."
curl.exe -L -f -o $Bootctl $BootctlUrl
$sz = (Get-Item $Bootctl).Length
Write-Host "  downloaded $sz bytes"
if ($sz -lt 500000) {
    throw "Wrong bootctl file ($sz bytes). Need ~628000. Retry in 1 min or check network."
}

Write-Host "[2/4] Test SSH..."
ssh @SshOpts "root@$Ip" "echo ok"
if ($LASTEXITCODE -ne 0) {
    throw "Cannot reach Vector at $Ip. Check: charger on, recovery screen up, same WiFi, try -Ip with screen IP."
}

Write-Host "[3/4] Free /data + upload bootctl..."
ssh @SshOpts "root@$Ip" "rm -f /data/ota/v.ota; rm -rf /data/ota/chunks; df -h /data"
& scp @ScpOpts $Bootctl "root@${Ip}:/data/bootctl-anki"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

Write-Host "[4/4] Unbrick slots + reboot..."
$cmd = @'
chmod 755 /data/bootctl-anki
echo "slot A:"; /data/bootctl-anki f status a
echo "---"
echo "slot B:"; /data/bootctl-anki f status b
/data/bootctl-anki f set_bootable a
/data/bootctl-anki f set_bootable b
rm -f /data/unbrick
/data/bootctl-anki f set_active b
sync
echo REBOOTING...
reboot
'@
ssh @SshOpts "root@$Ip" $cmd
Write-Host ""
Write-Host "Done. Wait 2 min. If still recovery, run again with: -Ip <ip from screen>"
