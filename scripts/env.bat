@echo off
rem Build environment for the localrdp forks.
rem Maps the project folder to drive L: (upstream build scripts break on paths with
rem spaces or Cyrillic), then puts Qt and 7-Zip on PATH. Run from any cmd window:
rem     call "<project>\scripts\env.bat"
rem Afterwards work from L:\moonlight-qt (or other forks under L:\).

set "LOCALRDP_ROOT=%~dp0.."
for %%I in ("%LOCALRDP_ROOT%") do set "LOCALRDP_ROOT=%%~fI"

if not exist L:\ (
    subst L: "%LOCALRDP_ROOT%"
)
if not exist L:\scripts\env.bat (
    echo Drive L: is mapped to a different folder. Run "subst L: /D" and try again.
    exit /b 1
)

set "PATH=L:\tools\Qt\6.11.3\msvc2022_64\bin;C:\Program Files\7-Zip;%PATH%"
rem Optional: parallel builds with jom (set JOM_DIR to the folder with jom.exe)
if defined JOM_DIR if exist "%JOM_DIR%\jom.exe" set "PATH=%PATH%;%JOM_DIR%"
set VSLANG=1033
exit /b 0
