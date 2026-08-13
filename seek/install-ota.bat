@echo off
REM SeekOS full-image installer. Run on a PC on the same Wi-Fi as Vector.
REM   install-ota.bat
REM   install-ota.bat 192.168.42.209 C:\Users\You\Downloads\ssh_root_key.txt
setlocal
set "SEEK_IP=%~1"
set "SEEK_KEY=%~2"
if "%SEEK_IP%"=="" set "SEEK_IP=192.168.42.209"
if "%SEEK_KEY%"=="" set "SEEK_KEY=%USERPROFILE%\Downloads\ssh_root_key.txt"
if exist "%~dp0install-ota.ps1" (
  powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0install-ota.ps1" "%SEEK_IP%" "%SEEK_KEY%"
) else (
  powershell -ExecutionPolicy Bypass -NoProfile -Command "$SeekIp='%SEEK_IP%'; $SeekKey='%SEEK_KEY%'; irm https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/install-ota.ps1 | iex"
)
endlocal
