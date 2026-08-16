@echo off
REM Seek Fast OTA — paste this whole line into CMD:
REM   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://files.anki.org.uk/fast-ota.ps1 | iex"
REM Or double-click this .bat after saving it.
echo.
echo Seek Fast OTA — PC downloads CFW, Vector installs over LAN Wi-Fi...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { irm https://files.anki.org.uk/fast-ota.ps1 | iex } catch { irm https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/websetup-pages/fast-ota.ps1 | iex }"
echo.
pause
