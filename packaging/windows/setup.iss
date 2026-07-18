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
; freshly downloaded bootstrap. Tibia.dat/.spr (~150MB) are kept: the
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
  // WinHttpRequestOption_SecureProtocols (9) = TLS1.0|TLS1.1|TLS1.2 (128+512+2048).
  // Stock Windows 7 WinHTTP negotiates only TLS 1.0 by default, but wypas.eu
  // (Cloudflare) is TLS 1.2-only — without forcing 1.2 every download here is
  // rejected, the bootstrap never lands, and the client fatals with no pack.
  SecureProtocolsTLS12 = 2688;

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
    WinHttpReq.Option(9) := SecureProtocolsTLS12; // TLS 1.2 — see the const
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

// Downloads via WinHttpRequest (not Inno's DownloadTemporaryFile) so we can
// force TLS 1.2 on Windows 7 — the built-in downloader's TLS floor depends on
// the Inno/OS version and silently fails against the TLS 1.2-only origin.
// The response body (a byte array) is written verbatim through ADODB.Stream,
// present on every Windows 7+.
function DownloadFile(const URL, DestPath: String): Boolean;
var
  WinHttpReq, Stream: Variant;
  Attempt: Integer;
begin
  Result := False;
  for Attempt := 1 to 3 do
  begin
    try
      WinHttpReq := CreateOleObject('WinHttp.WinHttpRequest.5.1');
      WinHttpReq.Option(9) := SecureProtocolsTLS12;
      WinHttpReq.SetTimeouts(0, 60000, 60000, 120000);
      WinHttpReq.Open('GET', URL, False);
      WinHttpReq.Send('');
      if WinHttpReq.Status = 200 then
      begin
        Stream := CreateOleObject('ADODB.Stream');
        Stream.Type := 1; // adTypeBinary
        Stream.Open;
        Stream.Write(WinHttpReq.ResponseBody);
        Stream.SaveToFile(DestPath, 2); // adSaveCreateOverWrite
        Stream.Close;
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
  // No bundled fallback pack ships on Windows — the bootstrap downloaded here
  // is the ONLY way the client gets a runnable pack, so a failure must read as
  // fatal (the in-game updater cannot run without this bootstrap).
  if not GetManifestJSON(JSON) then
  begin
    MsgBox('Could not download game assets. Please check your internet connection and run this installer again.'#13#10#13#10'The game will not start without them.', mbError, MB_OK);
    Exit;
  end;

  // Find "files": { in JSON
  P := Pos('"files"', JSON);
  if P = 0 then
  begin
    MsgBox('The asset manifest was invalid. Please run this installer again.'#13#10#13#10'The game will not start without a complete pack.', mbError, MB_OK);
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
