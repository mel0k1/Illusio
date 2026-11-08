Unicode True

!include "MUI2.nsh"
!include "FileFunc.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif

!ifndef SRCDIR
  !define SRCDIR "build\windows\x64\runner\Release"
!endif

!ifndef OUTDIR
  !define OUTDIR "."
!endif

!ifndef ICONDIR
  !define ICONDIR "installer"
!endif

!ifndef LICENSE
  !define LICENSE "..\..\LICENSE"
!endif

!define APPNAME "Illusio"
!define PUBLISHER "mel0k1"
!define APPMAIN "illusio.exe"
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Illusio"

Name "${APPNAME}"
OutFile "${OUTDIR}\Illusio-${VERSION}-windows-x64-setup.exe"
InstallDir "$LOCALAPPDATA\${APPNAME}"
InstallDirRegKey HKCU "Software\${APPNAME}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma

!define MUI_ABORTWARNING
!define MUI_ICON "${ICONDIR}\app_icon.ico"
!define MUI_UNICON "${ICONDIR}\app_icon.ico"
!define MUI_FINISHPAGE_RUN "${APPMAIN}"
!define MUI_FINISHPAGE_RUN_TEXT "Run ${APPNAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Russian"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${SRCDIR}\*.*"

  WriteUninstaller "$INSTDIR\uninstall.exe"

  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortCut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\${APPMAIN}"
  CreateShortCut "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk" "$INSTDIR\uninstall.exe"
  CreateShortCut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\${APPMAIN}"

  WriteRegStr HKCU "Software\${APPNAME}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${REGKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${REGKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${REGKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${REGKEY}" "DisplayIcon" "$INSTDIR\${APPMAIN}"
  WriteRegStr HKCU "${REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${REGKEY}" "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "${REGKEY}" "QuietUninstallString" "$INSTDIR\uninstall.exe /S"
  WriteRegDWORD HKCU "${REGKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${REGKEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0B" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${REGKEY}" "EstimatedSize" $0

  WriteRegStr HKCR "ss14" "" "URL:Space Station 14"
  WriteRegStr HKCR "ss14" "URL Protocol" ""
  WriteRegStr HKCR "ss14\DefaultIcon" "" "$INSTDIR\${APPMAIN},0"
  WriteRegStr HKCR "ss14\shell\open\command" "" '"$INSTDIR\${APPMAIN}" "%1"'
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk"
  RMDir "$SMPROGRAMS\${APPNAME}"

  RMDir /r "$INSTDIR"

  DeleteRegKey HKCR "ss14\shell\open\command"
  DeleteRegKey HKCR "ss14\shell\open"
  DeleteRegKey HKCR "ss14\shell"
  DeleteRegKey HKCR "ss14\DefaultIcon"
  DeleteRegKey HKCR "ss14"
  DeleteRegKey HKCU "${REGKEY}"
  DeleteRegKey HKCU "Software\${APPNAME}"
SectionEnd
