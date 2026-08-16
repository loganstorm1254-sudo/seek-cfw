@echo off
REM Seek update-os from Windows CMD — no website.
REM Needs: OpenSSH Client + ssh_root_key.txt (usually in Downloads)
REM
REM Usage:
REM   update-os.bat
REM   update-os.bat 192.168.1.50
REM   update-os.bat 192.168.1.50 C:\path\to\ssh_root_key.txt

setlocal
set IP=%~1
set KEY=%~2
if "%KEY%"=="" set KEY=%USERPROFILE%\Downloads\ssh_root_key.txt

echo.
echo Seek update-os (SSH) — no browser
echo.

if not "%IP%"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/update-os.ps1 -OutFile $env:TEMP\seek-update-os.ps1; & $env:TEMP\seek-update-os.ps1 -Ip '%IP%' -Key '%KEY%'"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/update-os.ps1 -OutFile $env:TEMP\seek-update-os.ps1; & $env:TEMP\seek-update-os.ps1 -Key '%KEY%'"
)

echo.
pause
