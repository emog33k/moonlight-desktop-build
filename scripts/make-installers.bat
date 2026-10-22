@echo off
rem Builds both installers into <project>\dist (version from moonlight-qt\app\desktop-version.txt):
rem   MoonlightDesktop-Setup-<version>.exe       - the client
rem   MoonlightDesktopAgent-Setup-<version>.exe  - the host with Sunshine (the agent)
rem By default runs the tests and a full release build first (make-bundle.bat, which
rem also makes the portable zip) and builds the agent.
rem   make-installers.bat nobuild   - package the builds that are already there
setlocal
call "%~dp0env.bat" || exit /b 1

set "MAKENSIS=%ProgramFiles(x86)%\NSIS\makensis.exe"
rem (no parentheses around these: the path has "(x86)" in it)
if not exist "%MAKENSIS%" echo NSIS not found: "%MAKENSIS%"
if not exist "%MAKENSIS%" exit /b 1

if /I "%~1"=="nobuild" goto package
call "%~dp0make-bundle.bat" || exit /b 1
call "%~dp0build-agent.bat" || exit /b 1

:package
rem One version for the app (update check) and the installers
set /p VERSION=<L:\moonlight-qt\app\desktop-version.txt
set "DEPLOY=L:\moonlight-qt\build\deploy-x64-release"
set "AGENT=L:\moonlight-qt\build\agent-deploy"
if not exist "%DEPLOY%\Moonlight.exe" (echo Missing %DEPLOY%\Moonlight.exe & exit /b 1)
if not exist "%AGENT%\MoonlightDesktopAgent.exe" (echo Missing %AGENT%\MoonlightDesktopAgent.exe & exit /b 1)
if not exist L:\dist mkdir L:\dist

"%MAKENSIS%" /V2 /INPUTCHARSET UTF8 /DVERSION=%VERSION% "/DDEPLOY=%DEPLOY%" ^
    "/DICON=L:\moonlight-qt\app\moonlight.ico" "/DLICENSE=L:\moonlight-qt\LICENSE" ^
    "/DOUT=L:\dist\MoonlightDesktop-Setup-%VERSION%.exe" "%~dp0installer\moonlight-desktop.nsi" || exit /b 1

"%MAKENSIS%" /V2 /INPUTCHARSET UTF8 /DVERSION=%VERSION% "/DAGENT_DIR=%AGENT%" "/DSCRIPTS=L:\scripts" ^
    "/DICON=L:\moonlight-qt\app\moonlight.ico" ^
    "/DOUT=L:\dist\MoonlightDesktopAgent-Setup-%VERSION%.exe" "%~dp0installer\moonlight-desktop-agent.nsi" || exit /b 1

echo Installers:
echo   %LOCALRDP_ROOT%\dist\MoonlightDesktop-Setup-%VERSION%.exe
echo   %LOCALRDP_ROOT%\dist\MoonlightDesktopAgent-Setup-%VERSION%.exe
exit /b 0
