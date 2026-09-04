# Unbrick Vector when both slots show unbootable.
param([string]$Ip = "192.168.0.105", [string]$Key = "$env:TEMP\vector_dev_key")
$Branch = "cursor/head-only-ignore-body-7a4a"
$Base = "https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/$Branch/seek/flash"
$Ssh = @("-i", $Key, "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa", "-o", "HostKeyAlgorithms=+ssh-rsa")
$Scp = $Ssh + @("-O")

Write-Host "=== Vector unbrick (both slots) ==="
curl.exe -L -f -o "$env:TEMP\bootctl-anki" "$Base/bin/bootctl-anki-arm"
curl.exe -L -f -o "$env:TEMP\unbrick.sh" "$Base/recovery-unbrick.sh"
& scp @Scp "$env:TEMP\bootctl-anki" "root@${Ip}:/data/bootctl-anki"
& scp @Scp "$env:TEMP\unbrick.sh" "root@${Ip}:/data/recovery-unbrick.sh"
ssh @Ssh "root@$Ip" "chmod 755 /data/bootctl-anki /data/recovery-unbrick.sh; sh /data/recovery-unbrick.sh"
