; Moonlight Desktop Agent installer (the host with Sunshine).
; Built by scripts\make-installers.bat:
;   makensis /DVERSION=x.y.z /DAGENT_DIR=<agent-deploy> /DSCRIPTS=<scripts> /DICON=<ico> /DOUT=<file> moonlight-desktop-agent.nsi
;
; The work is done by scripts\install-agent.ps1 (the same, tested script as for a
; manual install): it asks for administrator rights itself, copies the agent to
; "C:\Program Files\Moonlight Desktop Agent", gives it its own certificate signed with
; Sunshine's key (key encrypted for the current Windows user), opens TCP 48100 for
; the local subnet only, starts the agent at sign-in and removes an install under
; the earlier name (LocalRDP Agent). So the installer runs as the signed-in user:
; the agent's key must belong to that user.

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user
ManifestDPIAware true

!include MUI2.nsh
!include LogicLib.nsh

!define PRODUCT "Moonlight Desktop Agent"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\MoonlightDesktopAgent"

Name "${PRODUCT}"
OutFile "${OUT}"
; Fixed by install-agent.ps1; only used for the uninstall entry
InstallDir "$PROGRAMFILES64\Moonlight Desktop Agent"
ShowInstDetails show
ShowUninstDetails show
BrandingText "${PRODUCT} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT} setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "GPLv3"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "$(WelcomeText)"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TEXT "$(FinishText)"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; The system's language when it is one of these, English otherwise
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Russian"

LangString WelcomeText ${LANG_ENGLISH} "The agent runs on the host next to Sunshine: two-way clipboard and files, host lock and power actions, display list, cursor shapes.$\r$\n$\r$\nSunshine must be installed. Windows asks for administrator rights once.$\r$\n$\r$\nInstall as the Windows user you work as: the agent's key is encrypted for that user."
LangString WelcomeText ${LANG_RUSSIAN} "Агент работает на ПК рядом с Sunshine: общий буфер обмена и файлы, блокировка и питание ПК, список мониторов, форма курсора.$\r$\n$\r$\nНужен установленный Sunshine. Windows один раз спросит права администратора.$\r$\n$\r$\nУстанавливайте под той учётной записью, в которой работаете: ключ агента шифруется для неё."
LangString FinishText ${LANG_ENGLISH} "The agent is running and starts when you sign in to Windows."
LangString FinishText ${LANG_RUSSIAN} "Агент запущен и будет запускаться при входе в Windows."
LangString Installing ${LANG_ENGLISH} "Installing the agent (Windows asks for administrator rights)..."
LangString Installing ${LANG_RUSSIAN} "Установка агента (Windows спросит права администратора)..."
LangString InstallFailed ${LANG_ENGLISH} "The agent was not installed (code $0). See the details in the setup window.$\r$\n$\r$\nCommon causes: Sunshine is not installed, administrator rights were refused."
LangString InstallFailed ${LANG_RUSSIAN} "Агент не установлен (код $0). Подробности в окне установки.$\r$\n$\r$\nЧастые причины: Sunshine не установлен, отказ в запросе прав администратора."
LangString Removing ${LANG_ENGLISH} "Removing the agent (Windows asks for administrator rights)..."
LangString Removing ${LANG_RUSSIAN} "Удаление агента (Windows спросит права администратора)..."
LangString RemoveFailed ${LANG_ENGLISH} "The agent was not removed (code $0). See the details in the window."
LangString RemoveFailed ${LANG_RUSSIAN} "Агент не удалён (код $0). Подробности в окне удаления."

; 64-bit PowerShell: this installer is a 32-bit program, and a 32-bit PowerShell
; would see "C:\Program Files (x86)" as Program Files.
!define POWERSHELL "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

Section "Install"
    ; The wizard's pages create $PLUGINSDIR; a silent install (/S) shows none
    InitPluginsDir
    SetOutPath "$PLUGINSDIR\agent"
    File /r "${AGENT_DIR}\*"
    ; The uninstaller goes with the agent into its folder
    WriteUninstaller "$PLUGINSDIR\agent\Uninstall.exe"
    SetOutPath "$PLUGINSDIR"
    File "${SCRIPTS}\install-agent.ps1"

    DetailPrint "$(Installing)"
    nsExec::ExecToLog '"${POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\install-agent.ps1" -Source "$PLUGINSDIR\agent"'
    Pop $0
    ${If} $0 != 0
        MessageBox MB_ICONSTOP|MB_OK "$(InstallFailed)" /SD IDOK
        SetOutPath "$TEMP"
        Abort
    ${EndIf}

    WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${PRODUCT}"
    WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "emog33k"
    WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "https://github.com/emog33k/moonlight-desktop"
    WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\MoonlightDesktopAgent.exe"
    WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
    WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
    WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
    WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" 30000
    ; Leave the temporary folder so it can be deleted
    SetOutPath "$TEMP"
SectionEnd

Section "Uninstall"
    InitPluginsDir
    SetOutPath "$PLUGINSDIR"
    File "${SCRIPTS}\uninstall-agent.ps1"
    DetailPrint "$(Removing)"
    nsExec::ExecToLog '"${POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\uninstall-agent.ps1"'
    Pop $0
    SetOutPath "$TEMP"
    ${If} $0 != 0
        MessageBox MB_ICONSTOP|MB_OK "$(RemoveFailed)" /SD IDOK
        Abort
    ${EndIf}
    DeleteRegKey HKCU "${UNINST_KEY}"
SectionEnd
