@echo off
setlocal EnableDelayedExpansion
set IP=192.168.0.105
set KEY=%TEMP%\vector_dev_key
set SSH=ssh -i %KEY% -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa root@%IP%
set FLASH=%TEMP%\unlock-manual-flash-v2.sh
set OTA=%TEMP%\vicos-3.0.1.33d.ota

echo === Seek recovery flash (3.0.1.33d) ===
echo Charger must stay connected. IP=%IP%
echo.

echo [1/4] Download flash script...
curl -L -f -o "%FLASH%" https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/head-only-ignore-body-7a4a/seek/flash/unlock-manual-flash-v2.sh
if errorlevel 1 goto fail

echo [2/4] Download OTA (~204MB)...
curl -L -f -o "%OTA%" https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.33d-recovery/vicos-3.0.1.33d.ota
if errorlevel 1 goto fail

echo [3/4] Upload to Vector (scp - more reliable than pipe for 204MB)...
%SSH% "mkdir -p /data/ota /ota && df -h /data /ota /cache 2>/dev/null; rm -f /data/ota/v.ota /ota/v.ota"
scp -i "%KEY%" -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -o ServerAliveInterval=15 -o ServerAliveCountMax=120 "%FLASH%" root@%IP%:/data/unlock-manual-flash-v2.sh
if errorlevel 1 goto fail
scp -i "%KEY%" -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -o ServerAliveInterval=15 -o ServerAliveCountMax=120 "%OTA%" root@%IP%:/ota/v.ota
if errorlevel 1 (
  echo /ota failed, trying /data/ota/v.ota ...
  scp -i "%KEY%" -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -o ServerAliveInterval=15 -o ServerAliveCountMax=120 "%OTA%" root@%IP%:/data/ota/v.ota
  if errorlevel 1 goto fail
  set OTA_ON_ROBOT=/data/ota/v.ota
) else (
  set OTA_ON_ROBOT=/ota/v.ota
)

echo [4/4] Flashing inactive slot (several minutes, then reboot)...
%SSH% "rm -f /data/unbrick; mount -o remount,rw /; chmod 755 /data/unlock-manual-flash-v2.sh; sh /data/unlock-manual-flash-v2.sh !OTA_ON_ROBOT!"
if errorlevel 1 goto fail

echo DONE - Vector should reboot into Seek.
exit /b 0

:fail
echo FAILED - check charger, WiFi, IP (%IP%), and SSH key.
exit /b 1
