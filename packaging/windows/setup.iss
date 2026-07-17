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
SetupIconFile=..\wypas.ico
UninstallDisplayIcon={app}\wypas.exe
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[InstallDelete]
; Clean install: stale pack files from a previous install (or a poisoned
; updater state) must never shadow the freshly downloaded bootstrap — a
; leftover init.lua/modules tree boots instead of the new pack and can fatal
; at module discovery with the updater gated off. User state (config.otml,
; minimap, bot\, screenshots) is deliberately kept, and so are Tibia.dat/.spr
; (~150MB): the updater checksum-verifies and replaces them when stale.
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\modules"
Type: filesandordirs; Name: "{app}\mods"
Type: filesandordirs; Name: "{app}\layouts"
Type: files; Name: "{app}\init.lua"
; stale self-update binaries — the freshly installed wypas.exe is the truth now
Type: files; Name: "{app}\wypas-*.exe"
Type: files; Name: "{app}\update.exe"

[Files]
Source: "..\..\dist\wypas.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Wypas"; Filename: "{app}\wypas.exe"
Name: "{autodesktop}\Wypas"; Filename: "{app}\wypas.exe"

[Run]
Filename: "{app}\wypas.exe"; Description: "Launch Wypas"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Assets are downloaded into {app} after install, so Inno's default uninstall
; (which only removes tracked-installed files) leaves the whole asset tree behind.
; Remove the entire install folder on uninstall.
Type: filesandordirs; Name: "{app}"

[Code]
// Assets are downloaded verbatim from prod, where the deploy pipeline serves them
// ENC3-encrypted and regenerates manifest.json over the encrypted bytes. This
// installer stores each file byte-for-byte and does NOT verify checksums (the
// manifest is parsed only to enumerate filenames), so encrypted assets install
// fine; the WITH_ENCRYPTION client decrypts them transparently at runtime, and the
// downloaded init.lua already has the updater enabled. Do not add a plaintext or
// checksum-verifying step here — it would reject the encrypted files.
const
  ManifestURL = 'https://wypas.eu/assets/manifest.json';
  AssetsBaseURL = 'https://wypas.eu/assets/';

var
  DownloadPage: TOutputProgressWizardPage;

// The installer only bootstraps: init.lua + the updater's module set + data/
// (fonts, UI resources the updater screen needs). Everything else — game
// modules, layouts, Tibia.dat/.spr — is synced checksum-verified by the
// in-game updater on first boot, so installs always run the newest remote
// pack and never ship a stale or partially-downloaded game tree. Mirrors the
// thin macOS DMG bundle (see wypas/packaging/macos/package-dmg.sh).
function IsBootstrapFile(const FileName: String): Boolean;
begin
  Result := (FileName = 'init.lua')
    or (Pos('data/', FileName) = 1)
    or (Pos('modules/corelib/', FileName) = 1)
    or (Pos('modules/updater/', FileName) = 1)
    or (Pos('modules/client_locales/', FileName) = 1)
    or (Pos('modules/client_styles/', FileName) = 1)
    or (Pos('modules/client_background/', FileName) = 1);
end;

function GetManifestJSON(out JSON: AnsiString): Boolean;
var
  WinHttpReq: Variant;
begin
  Result := False;
  try
    WinHttpReq := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    WinHttpReq.Open('GET', ManifestURL, False);
    WinHttpReq.Send('');
    if WinHttpReq.Status = 200 then
    begin
      JSON := WinHttpReq.ResponseText;
      Result := True;
    end;
  except
  end;
end;

function DownloadFile(const URL, DestPath: String): Boolean;
var
  TmpPath: String;
  Attempt: Integer;
begin
  Result := False;
  TmpPath := ExpandConstant('{tmp}') + '\' + ExtractFileName(DestPath);
  for Attempt := 1 to 3 do
  begin
    try
      // A stale tmp file left by an earlier download with the same basename
      // must not mask a failure — FileCopy would install the wrong bytes.
      DeleteFile(TmpPath);
      DownloadTemporaryFile(URL, ExtractFileName(DestPath), '', nil);
      if FileCopy(TmpPath, DestPath, False) then
      begin
        Result := True;
        Exit;
      end;
    except
    end;
  end;
end;

procedure ParseAndDownloadAssets;
var
  JSON: AnsiString;
  FilesStr: AnsiString;
  P, BraceDepth, FilesStart: Integer;
  FileName, DestPath, DirPart, URL, HashStr: String;
  FileCount, FileIndex, TotalFiles: Integer;
  InKey: Boolean;
  KeyStart, KeyEnd, ValStart: Integer;
  FailedFiles: Integer;
begin
  FailedFiles := 0;
  if not GetManifestJSON(JSON) then
  begin
    MsgBox('Could not download asset manifest. Assets will be downloaded on first launch by the in-game updater.', mbInformation, MB_OK);
    Exit;
  end;

  // Find "files": { in JSON
  P := Pos('"files"', JSON);
  if P = 0 then
  begin
    MsgBox('Invalid manifest format. Assets will be downloaded on first launch.', mbInformation, MB_OK);
    Exit;
  end;

  // Find opening brace of files object
  P := Pos('{', Copy(JSON, P, Length(JSON)));
  if P = 0 then Exit;
  FilesStart := Pos('"files"', JSON) + P;
  FilesStr := Copy(JSON, FilesStart - 1, Length(JSON));

  // Count files (number of colons inside the files object = number of entries)
  TotalFiles := 0;
  BraceDepth := 1;
  P := 2; // skip opening brace
  while (P <= Length(FilesStr)) and (BraceDepth > 0) do
  begin
    if FilesStr[P] = '{' then BraceDepth := BraceDepth + 1
    else if FilesStr[P] = '}' then BraceDepth := BraceDepth - 1
    else if (FilesStr[P] = ':') and (BraceDepth = 1) then
      TotalFiles := TotalFiles + 1;
    P := P + 1;
  end;

  if TotalFiles = 0 then
  begin
    MsgBox('No files found in manifest. Assets will be downloaded on first launch.', mbInformation, MB_OK);
    Exit;
  end;

  DownloadPage.SetText('Downloading game assets...', '');
  DownloadPage.SetProgress(0, TotalFiles);
  DownloadPage.Show;

  try
    // Parse keys from the files object
    FileIndex := 0;
    BraceDepth := 1;
    P := 2;
    InKey := False;
    KeyStart := 0;
    while (P <= Length(FilesStr)) and (BraceDepth > 0) do
    begin
      if FilesStr[P] = '{' then
        BraceDepth := BraceDepth + 1
      else if FilesStr[P] = '}' then
        BraceDepth := BraceDepth - 1
      else if (FilesStr[P] = '"') and (BraceDepth = 1) then
      begin
        if not InKey then
        begin
          InKey := True;
          KeyStart := P + 1;
        end
        else
        begin
          InKey := False;
          KeyEnd := P;
          FileName := Copy(FilesStr, KeyStart, KeyEnd - KeyStart);

          // Capture the value (CRC32 hash) after the colon, used as a
          // cache-busting ?v= so Cloudflare can't serve a stale (e.g.
          // pre-encryption plaintext) copy on the bare URL.
          P := P + 1;
          while (P <= Length(FilesStr)) and (FilesStr[P] <> '"') do
            P := P + 1;
          HashStr := '';
          if P < Length(FilesStr) then
          begin
            P := P + 1;
            ValStart := P;
            while (P <= Length(FilesStr)) and (FilesStr[P] <> '"') do
              P := P + 1;
            HashStr := Copy(FilesStr, ValStart, P - ValStart);
          end;

          // Download this file (bootstrap set only — see IsBootstrapFile)
          FileIndex := FileIndex + 1;
          DownloadPage.SetProgress(FileIndex, TotalFiles);
          if IsBootstrapFile(FileName) then
          begin
            DownloadPage.SetText('Downloading game assets...', FileName);

            URL := AssetsBaseURL + FileName;
            if HashStr <> '' then
              URL := URL + '?v=' + HashStr;
            DestPath := ExpandConstant('{app}') + '\' + FileName;

            DirPart := ExtractFileDir(DestPath);
            if not DirExists(DirPart) then
              ForceDirectories(DirPart);

            if not DownloadFile(URL, DestPath) then
            begin
              Log('Failed to download: ' + URL);
              FailedFiles := FailedFiles + 1;
            end;
          end;
        end;
      end;
      P := P + 1;
    end;
  finally
    DownloadPage.Hide;
  end;

  // A partial bootstrap does not start (module discovery fatals) — say so
  // loudly instead of leaving a broken install behind.
  if FailedFiles > 0 then
    MsgBox(Format('%d game asset files failed to download.' + #13#10 +
      'The game will not start with an incomplete pack — please check your ' +
      'connection and run this installer again.', [FailedFiles]),
      mbError, MB_OK);
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateOutputProgressPage('Downloading Assets', 'Please wait while game assets are downloaded...');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    ParseAndDownloadAssets;
end;
