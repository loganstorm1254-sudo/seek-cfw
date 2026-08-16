@echo off
cd /d "%~dp0"
where node >nul 2>&1
if errorlevel 1 (
  echo Install Node.js from https://nodejs.org then run this again.
  pause
  exit /b 1
)
echo Syncing OTAs from files.anki.org.uk ...
node bin\seek-web-setup.js ota-sync
if errorlevel 1 (
  echo ota-sync failed — serving anyway ^(will proxy /ota/latest^).
)
echo.
echo Open Chrome at http://localhost:8000/
node bin\seek-web-setup.js serve
pause
