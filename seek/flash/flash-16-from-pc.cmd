@echo off
REM Download 1.6-rebuild OTA on THIS PC, then upload+flash Vector.
REM Stay on charger. Run from CMD (not PowerShell).
REM
REM   flash-16-from-pc.cmd
REM   flash-16-from-pc.cmd 192.168.42.111

setlocal
set IP=%1
if "%IP%"=="" set IP=192.168.42.111
set KEY=%TEMP%\vector_dev_key
set OTA=%TEMP%\vicos-1.6.1.0079d.ota
set FLASH=%TEMP%\unlock-manual-flash-v2.sh
set BRANCH=cursor/16-rebuild-errorsafe-7a4a
set OTA_URL=https://github.com/Victor-Rebuild/1.6-rebuild-historical-releases/releases/download/1.6.1.007X/vicos-1.6.1.0079d.ota
set RAW=https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/%BRANCH%/seek/flash
set SSH_OPTS=-i %KEY% -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no

if not exist "%KEY%" (
  echo ERROR: missing %KEY%
  exit /b 1
)

echo === PC download 1.6-rebuild OTA ===
echo IP=%IP%
echo OTA=%OTA%

curl -L --http1.1 -f -o "%OTA%" "%OTA_URL%"
if errorlevel 1 (
  echo ERROR: OTA download failed
  exit /b 1
)

for %%A in ("%OTA%") do set SZ=%%~zA
echo OTA size=%SZ%
if %SZ% LSS 150000000 (
  echo ERROR: OTA too small — download incomplete
  exit /b 1
)

echo Downloading flash helper...
curl -L -f -o "%FLASH%" "%RAW%/unlock-manual-flash-v2.sh"
if errorlevel 1 (
  echo ERROR: flash helper download failed
  exit /b 1
)

echo Preparing /ota on robot...
ssh %SSH_OPTS% root@%IP% "mount -o remount,rw /; mkdir -p /ota /data/ota /data/seek; rm -f /ota/v.ota"

echo Uploading OTA to robot /ota/v.ota (several minutes)...
scp %SSH_OPTS% -O "%OTA%" root@%IP%:/ota/v.ota
if errorlevel 1 (
  echo scp -O failed, trying without -O...
  scp %SSH_OPTS% "%OTA%" root@%IP%:/ota/v.ota
)
if errorlevel 1 (
  echo ERROR: scp upload failed
  exit /b 1
)

echo Uploading flash helper...
scp %SSH_OPTS% -O "%FLASH%" root@%IP%:/data/unlock-manual-flash-v2.sh
if errorlevel 1 scp %SSH_OPTS% "%FLASH%" root@%IP%:/data/unlock-manual-flash-v2.sh

echo Flashing inactive slot (robot will reboot)...
ssh %SSH_OPTS% root@%IP% "chmod 755 /data/unlock-manual-flash-v2.sh; sh /data/unlock-manual-flash-v2.sh /ota/v.ota"

echo Done. Vector should reboot onto 1.6-rebuild.
endlocal
