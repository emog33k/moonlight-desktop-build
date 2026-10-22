@echo off
rem Full release build of Moonlight Desktop and the portable client package.
rem Result: <project>\dist\MoonlightDesktop-Portable-<yyyymmdd>.zip (unzip anywhere and run
rem Moonlight.exe; settings stay next to the exe, the regular Moonlight is not touched).
setlocal
call "%~dp0env.bat" || exit /b 1

rem Run the tests first; never package a build that fails them.
call "%~dp0test.bat" || (echo Tests failed, not packaging. & exit /b 1)

pushd L:\moonlight-qt
call scripts\build-arch.bat release
if errorlevel 1 (popd & echo Build failed. & exit /b 1)
popd

for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set STAMP=%%d
set /p VERSION=<L:\moonlight-qt\app\version.txt
set "SRC=L:\moonlight-qt\build\installer-x64-release\MoonlightPortable-x64-%VERSION%.zip"
if not exist "%SRC%" (echo Missing %SRC% & exit /b 1)

"C:\Program Files\7-Zip\7z.exe" l "%SRC%" | findstr /c:"portable.dat" >nul || (echo portable.dat missing from package & exit /b 1)

if not exist L:\dist mkdir L:\dist
copy /y "%SRC%" "L:\dist\MoonlightDesktop-Portable-%STAMP%.zip" >nul || exit /b 1
echo Package: %LOCALRDP_ROOT%\dist\MoonlightDesktop-Portable-%STAMP%.zip
exit /b 0
