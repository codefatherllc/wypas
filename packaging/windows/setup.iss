#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppName=Wypas
AppVersion={#AppVersion}
AppPublisher=Wypas
; v0.3.0 storage split: {app} (%APPDATA%\Wypas) is the PACK dir — exe, game
; pack and self-update binaries; wiped wholesale on fresh install/uninstall.
; User state (config, minimap, settings, logs) lives in %LOCALAPPDATA%\Wypas
; and is NEVER touched by this installer.
DefaultDirName={userappdata}\Wypas
DefaultGroupName=Wypas
OutputDir=..\..\output
OutputBaseFilename=wypas-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\wypas.ico
UninstallDisplayIcon={app}\wypas.exe
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[InstallDelete]
; Clean install: {app} is the disposable pack dir — stale pack files from a
; previous install (or a poisoned updater state) must never shadow the
; freshly bundled bootstrap. Tibia.dat/.spr (~150MB) are kept: the
; updater checksum-verifies and replaces them when stale.
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\modules"
Type: filesandordirs; Name: "{app}\mods"
Type: filesandordirs; Name: "{app}\layouts"
Type: files; Name: "{app}\init.lua"
Type: files; Name: "{app}\boot-failure"
; stale self-update binaries — the freshly installed wypas.exe is the truth now
Type: files; Name: "{app}\wypas-*.exe"
Type: files; Name: "{app}\update.exe"
; ==========================================================================
; TEMPORARY MIGRATION (v0.2.x unified layout -> v0.3.0 storage split).
; v0.2.x installed everything into %LOCALAPPDATA%\Wypas, which is now the
; user-state dir. Remove the pack/binary leftovers from there — the client
; itself migrates pack entries at boot, but a reinstall must also clear the
; old exe so stale shortcuts can't resurrect a pre-split client. User state
; (config.otml, hotkeys_*.otml, settings\, minimap*, user_dir\, records\,
; logs, dumps) is deliberately NOT listed. Remove this block once the
; pre-v0.3.0 fleet is gone.
; ==========================================================================
Type: filesandordirs; Name: "{localappdata}\Wypas\data"
Type: filesandordirs; Name: "{localappdata}\Wypas\modules"
Type: filesandordirs; Name: "{localappdata}\Wypas\mods"
Type: filesandordirs; Name: "{localappdata}\Wypas\layouts"
Type: files; Name: "{localappdata}\Wypas\init.lua"
Type: files; Name: "{localappdata}\Wypas\Tibia.dat"
Type: files; Name: "{localappdata}\Wypas\Tibia.spr"
Type: files; Name: "{localappdata}\Wypas\boot-failure"
Type: files; Name: "{localappdata}\Wypas\data.zip"
Type: files; Name: "{localappdata}\Wypas\wypas.exe"
Type: files; Name: "{localappdata}\Wypas\wypas-*.exe"
Type: files; Name: "{localappdata}\Wypas\update.exe"
Type: files; Name: "{localappdata}\Wypas\*.dll"
; ==========================================================================

[Files]
Source: "..\..\dist\wypas.exe"; DestDir: "{app}"; Flags: ignoreversion
; Thin ENC3-encrypted bootstrap staged by stage-bootstrap.sh at build time —
; the same bundle the DMG/AppImage carry (data/ + corelib/updater + UI deps +
; rendered updater-ON init.lua). The installer must do NO network I/O: the
; previous install-time WinHTTP + ADODB.Stream download loop is the classic
; malware-dropper fingerprint, and AV behavior blockers killed the installer
; mid-download, leaving packless installs that fataled at boot. The in-game
; updater — guaranteed present in this bundle — syncs the rest of the pack
; checksum-verified on first boot.
Source: "bootstrap\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Wypas"; Filename: "{app}\wypas.exe"
Name: "{autodesktop}\Wypas"; Filename: "{app}\wypas.exe"

[Run]
Filename: "{app}\wypas.exe"; Description: "Launch Wypas"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The updater syncs the rest of the pack into {app} after install, so Inno's
; default uninstall (which only removes tracked-installed files) would leave
; the synced tree behind. Remove the entire install folder on uninstall.
Type: filesandordirs; Name: "{app}"
