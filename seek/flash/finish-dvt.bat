@echo off
REM Flash authentic Anki DVT OTA (BusyBox-safe unlock script)
REM Usage: finish-dvt.bat
REM        finish-dvt.bat 192.168.43.130
setlocal
set IP=%~1
if "%IP%"=="" set IP=192.168.43.130
set KEY=%~2
if "%KEY%"=="" set KEY=%USERPROFILE%\Downloads\ssh_root_key.txt
set OTA_URL=https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.4d-dvt/vicos-3.0.1.4d-dvt.ota
set FLASH=https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.4d-dvt/unlock-manual-flash.sh
set EXPECT=161832960

echo.
echo Authentic Anki DVT — local flash
echo Robot: %IP%
echo.

ssh -i "%KEY%" -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostkeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -t root@%IP% "set -e; mount -o remount,rw /; mkdir -p /data/ota /run/update-engine /cache; umount /usr/bin/curl 2>/dev/null||true; if [ ! -x /usr/bin/curl.anki ]; then cp -L /usr/bin/curl /usr/bin/curl.anki 2>/dev/null||cp /usr/bin/curl /usr/bin/curl.anki; chmod 755 /usr/bin/curl.anki; fi; if [ -f /data/ota/v.ota ]; then SZ=$(wc -c ^< /data/ota/v.ota); echo existing /data/ota/v.ota size=$SZ; else SZ=0; fi; if [ \"$SZ\" != \"%EXPECT%\" ]; then echo Downloading OTA to /data/ota/v.ota ...; /usr/bin/curl.anki -k -L --http1.1 -4 --fail -o /data/ota/v.ota '%OTA_URL%'; SZ=$(wc -c ^< /data/ota/v.ota); echo downloaded size=$SZ; fi; [ \"$SZ\" = \"%EXPECT%\" ]||{ echo size mismatch; exit 1; }; /usr/bin/curl.anki -k -fsSL -4 --http1.1 '%FLASH%' -o /data/unlock-manual-flash.sh; chmod 755 /data/unlock-manual-flash.sh; sh /data/unlock-manual-flash.sh /data/ota/v.ota"

echo.
pause
