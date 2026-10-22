; Moonlight Desktop installer (the client).
; Built by scripts\make-installers.bat:
;   makensis /DVERSION=x.y.z /DDEPLOY=<deploy folder> /DICON=<ico> /DLICENSE=<file> /DOUT=<file> moonlight-desktop.nsi
;
; Installs for the current Windows user into %LOCALAPPDATA%\Programs\Moonlight Desktop
; (no administrator rights). It keeps its settings and pairing keys next to the
; program (portable.dat), so it never touches a regular Moonlight on the same PC,
; and only this user can read them (the folder is in their profile). The folder is
; fixed on purpose: a folder picked elsewhere (e.g. C:\Moonlight) could be readable
; and writable by other users.
; An install under the earlier name (Moonlight LocalRDP) is moved here: settings
; and pairing come along, the rest of it is removed.

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user
ManifestDPIAware true

!include MUI2.nsh
!include LogicLib.nsh

!define PRODUCT "Moonlight Desktop"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\MoonlightDesktop"
; Where Moonlight keeps its settings in portable mode (QSettings: organization\application.ini)
!define SETTINGS_DIR "Moonlight Game Streaming Project"
; The earlier name
!define OLD_PRODUCT "Moonlight LocalRDP"
!define OLD_DIR "$LOCALAPPDATA\Programs\Moonlight LocalRDP"
!define OLD_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\MoonlightLocalRDP"

Name "${PRODUCT}"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\Moonlight Desktop"
ShowInstDetails show
ShowUninstDetails show
BrandingText "${PRODUCT} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT} setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "GPLv3, based on Moonlight by the Moonlight Game Streaming Project"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "$(WelcomeText)"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "$(RunText)"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchMoonlight
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; The system's language when it is one of these, English otherwise
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Russian"

LangString WelcomeText ${LANG_ENGLISH} "Moonlight for remote desktop: in-stream toolbar, two-way clipboard and files, host displays, sound, host lock.$\r$\n$\r$\nInstalled for you only, no administrator rights needed. A regular Moonlight, if any, is not touched.$\r$\n$\r$\nUpdates keep your settings and pairing."
LangString WelcomeText ${LANG_RUSSIAN} "Moonlight для удалённого рабочего стола: панель в окне стрима, общий буфер обмена и файлы, мониторы, звук, блокировка ПК.$\r$\n$\r$\nУстанавливается только для вас, права администратора не нужны. Обычный Moonlight (если он есть) не затрагивается.$\r$\n$\r$\nПри обновлении настройки и спаривание сохраняются."
LangString RunText ${LANG_ENGLISH} "Start ${PRODUCT}"
LangString RunText ${LANG_RUSSIAN} "Запустить ${PRODUCT}"
LangString RunningAsk ${LANG_ENGLISH} "${PRODUCT} is running. Close it and continue?"
LangString RunningAsk ${LANG_RUSSIAN} "${PRODUCT} сейчас запущен. Закрыть его и продолжить?"
LangString Closing ${LANG_ENGLISH} "Closing the running ${PRODUCT}..."
LangString Closing ${LANG_RUSSIAN} "Закрываю запущенный ${PRODUCT}..."
LangString CloseFailed ${LANG_ENGLISH} "Could not close ${PRODUCT}. Close it and run the setup again."
LangString CloseFailed ${LANG_RUSSIAN} "Не удалось закрыть ${PRODUCT}. Закройте его и запустите установку снова."
LangString Moving ${LANG_ENGLISH} "Moving settings and pairing from ${OLD_PRODUCT}..."
LangString Moving ${LANG_RUSSIAN} "Переношу настройки и спаривание из ${OLD_PRODUCT}..."
LangString RemoveSettingsAsk ${LANG_ENGLISH} "Also remove settings and pairing with your hosts?$\r$\n$\r$\nKeep them and a later install needs no setup again."
LangString RemoveSettingsAsk ${LANG_RUSSIAN} "Удалить также настройки и спаривание с ПК?$\r$\n$\r$\nЕсли оставить, при повторной установке ничего не придётся настраивать заново."

!define POWERSHELL "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

; Closes the Moonlight started from $R9 (a full path to Moonlight.exe), never another
; Moonlight. A running program can't be replaced, so asks first; Cancel stops the
; (un)install.
!macro CloseMoonlightAt un
Function ${un}CloseMoonlightAt
    ${IfNot} ${FileExists} "$R9"
        Return
    ${EndIf}
    ClearErrors
    FileOpen $0 "$R9" a
    ${IfNot} ${Errors}
        FileClose $0
        Return ; not running
    ${EndIf}
    MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION "$(RunningAsk)" /SD IDOK IDOK close
    Abort
close:
    DetailPrint "$(Closing)"
    ; The path goes in through an environment variable: no quoting problems with any user name
    System::Call 'kernel32::SetEnvironmentVariable(t "MOONLIGHT_DESKTOP_EXE", t "$R9")'
    nsExec::Exec '"${POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -Command "Get-Process Moonlight -ErrorAction SilentlyContinue | Where-Object { $$_.Path -ieq $$env:MOONLIGHT_DESKTOP_EXE } | ForEach-Object { Stop-Process -Id $$_.Id -Force; Wait-Process -Id $$_.Id -Timeout 10 -ErrorAction SilentlyContinue }"'
    Pop $0
    ClearErrors
    FileOpen $0 "$R9" a
    ${If} ${Errors}
        MessageBox MB_OK|MB_ICONSTOP "$(CloseFailed)" /SD IDOK
        Abort
    ${EndIf}
    FileClose $0
FunctionEnd
!macroend
!insertmacro CloseMoonlightAt ""
!insertmacro CloseMoonlightAt "un."

; The program's own files (everything except settings, pairing keys, logs and cache)
!macro RemoveProgramFiles
    Delete "$INSTDIR\Moonlight.exe"
    Delete "$INSTDIR\*.dll"
    Delete "$INSTDIR\gamecontrollerdb.txt"
    Delete "$INSTDIR\portable.dat"
    Delete "$INSTDIR\LICENSE.txt"
    RMDir /r "$INSTDIR\qml"
    RMDir /r "$INSTDIR\platforms"
    RMDir /r "$INSTDIR\imageformats"
    RMDir /r "$INSTDIR\iconengines"
    RMDir /r "$INSTDIR\networkinformation"
    RMDir /r "$INSTDIR\tls"
    RMDir /r "$INSTDIR\translations"
    RMDir /r "$INSTDIR\styles"
    RMDir /r "$INSTDIR\generic"
    ; Compiled QML of the old version
    RMDir /r "$INSTDIR\qmlcache"
!macroend

Function LaunchMoonlight
    ; Portable mode looks for portable.dat in the current folder
    SetOutPath "$INSTDIR"
    Exec '"$INSTDIR\Moonlight.exe"'
FunctionEnd

; An install under the earlier name: its settings and pairing move here (unless this
; install already has its own), then it is removed
Function MoveOldInstall
    ${IfNot} ${FileExists} "${OLD_DIR}\*.*"
        Return
    ${EndIf}
    ${If} "${OLD_DIR}" == "$INSTDIR"
        Return
    ${EndIf}
    StrCpy $R9 "${OLD_DIR}\Moonlight.exe"
    Call CloseMoonlightAt
    ${If} ${FileExists} "${OLD_DIR}\${SETTINGS_DIR}\*.*"
    ${AndIfNot} ${FileExists} "$INSTDIR\${SETTINGS_DIR}\*.*"
        DetailPrint "$(Moving)"
        CreateDirectory "$INSTDIR"
        Rename "${OLD_DIR}\${SETTINGS_DIR}" "$INSTDIR\${SETTINGS_DIR}"
    ${EndIf}
    RMDir /r "${OLD_DIR}"
    Delete "$SMPROGRAMS\${OLD_PRODUCT}.lnk"
    Delete "$DESKTOP\${OLD_PRODUCT}.lnk"
    DeleteRegKey HKCU "${OLD_UNINST_KEY}"
FunctionEnd

Section "Install"
    StrCpy $R9 "$INSTDIR\Moonlight.exe"
    Call CloseMoonlightAt
    Call MoveOldInstall
    ; An update: old program files go (a file the new version no longer has must
    ; not stay behind); settings and pairing stay
    !insertmacro RemoveProgramFiles

    SetOutPath "$INSTDIR"
    File /r /x portable.dat /x portable.dat.inactive "${DEPLOY}\*"
    File "/oname=LICENSE.txt" "${LICENSE}"
    ; Settings and pairing keys next to the program, in this user's profile
    FileOpen $0 "$INSTDIR\portable.dat" w
    FileClose $0

    WriteUninstaller "$INSTDIR\Uninstall.exe"

    ; Shortcuts start in the program folder (portable mode needs it)
    CreateShortcut "$SMPROGRAMS\${PRODUCT}.lnk" "$INSTDIR\Moonlight.exe" "" "$INSTDIR\Moonlight.exe" 0
    CreateShortcut "$DESKTOP\${PRODUCT}.lnk" "$INSTDIR\Moonlight.exe" "" "$INSTDIR\Moonlight.exe" 0

    WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${PRODUCT}"
    WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "emog33k"
    WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "https://github.com/emog33k/moonlight-desktop"
    WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\Moonlight.exe"
    WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
    WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
    WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
    WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" 150000
SectionEnd

Section "Uninstall"
    StrCpy $R9 "$INSTDIR\Moonlight.exe"
    Call un.CloseMoonlightAt
    !insertmacro RemoveProgramFiles
    Delete "$INSTDIR\Uninstall.exe"
    Delete "$SMPROGRAMS\${PRODUCT}.lnk"
    Delete "$DESKTOP\${PRODUCT}.lnk"
    DeleteRegKey HKCU "${UNINST_KEY}"

    ; Settings, pairing keys, logs, cache: only if the user says so (kept when silent)
    MessageBox MB_YESNO|MB_ICONQUESTION "$(RemoveSettingsAsk)" /SD IDNO IDNO keep
    RMDir /r "$INSTDIR\${SETTINGS_DIR}"
    RMDir /r "$INSTDIR\cache"
    RMDir /r "$INSTDIR\boxart"
    Delete "$INSTDIR\*.log"
keep:
    ; Only removed when empty
    RMDir "$INSTDIR"
SectionEnd
