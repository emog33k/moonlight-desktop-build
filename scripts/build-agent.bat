@echo off
rem Builds Moonlight Desktop Agent (release) with everything it needs to run:
rem   L:\moonlight-qt\build\agent-deploy\MoonlightDesktopAgent.exe + Qt + OpenSSL DLLs
setlocal
call "%~dp0env.bat" || exit /b 1
for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath`) do set "VSDIR=%%i"
call "%VSDIR%\VC\Auxiliary\Build\vcvarsall.bat" amd64 >nul || exit /b 1

set JOM=nmake /nologo
where /q jom.exe && set JOM=jom

set "OUT=L:\moonlight-qt\build\agent"
set "DEPLOY=L:\moonlight-qt\build\agent-deploy"
rem Always a clean build: it is small, and a stale object file with an older class
rem layout once made the agent crash at random.
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
pushd "%OUT%"
qmake L:\moonlight-qt\localrdp\agent\localrdp-agent.pro || (popd & exit /b 1)
%JOM% release || (popd & exit /b 1)
popd

if exist "%DEPLOY%" rmdir /s /q "%DEPLOY%"
mkdir "%DEPLOY%"
copy /y "%OUT%\release\MoonlightDesktopAgent.exe" "%DEPLOY%\" >nul || exit /b 1
windeployqt --release --no-translations --no-system-d3d-compiler --no-opengl-sw --no-compiler-runtime --force-openssl "%DEPLOY%\MoonlightDesktopAgent.exe" >nul || exit /b 1
rem OpenSSL for Qt's TLS backend, and the VC runtime
copy /y L:\moonlight-qt\libs\windows\lib\x64\libssl-3-x64.dll "%DEPLOY%\" >nul || exit /b 1
copy /y L:\moonlight-qt\libs\windows\lib\x64\libcrypto-3-x64.dll "%DEPLOY%\" >nul || exit /b 1
for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -find VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT`) do set "CRT=%%i"
copy /y "%CRT%\*.dll" "%DEPLOY%\" >nul || exit /b 1
echo Agent build OK: %DEPLOY%
exit /b 0
