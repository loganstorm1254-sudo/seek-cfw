@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================
echo  Minecraft rd-132211 - oak planks standalone
echo ============================================
echo.
echo Folder: %CD%
echo.

if not exist "lib\minecraft-client.jar" goto missing
if not exist "lib\lwjgl.jar" goto missing
if not exist "lib\lwjgl_util.jar" goto missing
if not exist "lib\jinput.jar" goto missing
if not exist "natives\lwjgl64.dll" goto missing

set "JAVA="
if exist "%APPDATA%\PrismLauncher\java\jre-legacy\bin\java.exe" set "JAVA=%APPDATA%\PrismLauncher\java\jre-legacy\bin\java.exe"
if not defined JAVA if exist "%JAVA_HOME%\bin\java.exe" set "JAVA=%JAVA_HOME%\bin\java.exe"

if not defined JAVA (
  where java >nul 2>nul
  if not errorlevel 1 for /f "delims=" %%J in ('where java') do (
    echo %%J | find /i "WindowsApps" >nul
    if errorlevel 1 (
      set "JAVA=%%J"
      goto havejava
    )
  )
)

:havejava
if not defined JAVA goto nojava

echo Using Java:
echo   %JAVA%
echo.

if not exist "gamedata" mkdir "gamedata"

echo Starting game...
echo.
"%JAVA%" -Xms512M -Xmx1024M -Djava.library.path="%CD%\natives" -cp "%CD%\lib\minecraft-client.jar;%CD%\lib\lwjgl.jar;%CD%\lib\lwjgl_util.jar;%CD%\lib\jinput.jar" com.mojang.rubydung.RubyDung
set "ERR=%ERRORLEVEL%"
echo.
echo Game exited with code %ERR%
echo.
pause
exit /b %ERR%

:missing
echo ERROR: Missing game files.
echo Extract the FULL zip so you have:
echo   START-HERE.bat
echo   lib\
echo   natives\
echo.
echo Do not run a single downloaded .exe by itself.
echo.
pause
exit /b 1

:nojava
echo ERROR: No Java 8 found.
echo.
echo Easiest fix: keep Prism Launcher installed so this exists:
echo   %APPDATA%\PrismLauncher\java\jre-legacy\bin\java.exe
echo.
echo Or install Temurin Java 8 x64, then run this bat again.
echo.
pause
exit /b 1
