#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppName=Wypas
AppVersion={#AppVersion}
AppPublisher=Wypas
DefaultDirName={localappdata}\Wypas
DefaultGroupName=Wypas
OutputDir=..\..\output
OutputBaseFilename=wypas-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=packaging\windows\favicon.ico
UninstallDisplayIcon={app}\wypas.exe
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Files]
Source: "..\..\dist\wypas.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\dist\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Wypas"; Filename: "{app}\wypas.exe"
Name: "{autodesktop}\Wypas"; Filename: "{app}\wypas.exe"

[Run]
Filename: "{app}\wypas.exe"; Description: "Launch Wypas"; Flags: nowait postinstall skipifsilent
