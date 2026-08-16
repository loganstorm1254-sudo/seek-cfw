@echo off
cd /d "%~dp0"
where node >nul 2>&1
if errorlevel 1 (
  echo Install Node.js from https://nodejs.org then run this again.
  pause
  exit /b 1
)
echo.
echo FAST OTA: this PC downloads Seek OS, Vector pulls over hotspot Wi-Fi.
echo Keep Vector + this PC on the SAME phone hotspot.
echo.
node bin\seek-web-setup.js fast-ota
pause
