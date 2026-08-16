@echo off
REM Double-click this after downloading from https://files.anki.org.uk/fast-ota.bat
REM Or save this file and run it — no git clone, no Node.
echo.
echo Seek Fast OTA — downloading helper…
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://files.anki.org.uk/fast-ota.ps1 | iex"
echo.
pause
