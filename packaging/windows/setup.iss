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

[Files]
Source: "..\..\dist\wypas.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Wypas"; Filename: "{app}\wypas.exe"
Name: "{autodesktop}\Wypas"; Filename: "{app}\wypas.exe"

[Run]
Filename: "{app}\wypas.exe"; Description: "Launch Wypas"; Flags: nowait postinstall skipifsilent

[Code]
const
  ManifestURL = 'https://wypas.pl/assets/manifest.json';
  AssetsBaseURL = 'https://wypas.pl/assets/';

var
  DownloadPage: TOutputProgressWizardPage;

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
begin
  Result := False;
  try
    DownloadTemporaryFile(URL, ExtractFileName(DestPath), '', nil);
    FileCopy(ExpandConstant('{tmp}') + '\' + ExtractFileName(DestPath), DestPath, False);
    Result := True;
  except
  end;
end;

procedure ParseAndDownloadAssets;
var
  JSON: AnsiString;
  FilesStr: AnsiString;
  P, BraceDepth, FilesStart: Integer;
  FileName, DestPath, DirPart, URL: String;
  FileCount, FileIndex, TotalFiles: Integer;
  InKey: Boolean;
  KeyStart, KeyEnd: Integer;
begin
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

          // Skip the value (the hash string after colon)
          P := P + 1;
          while (P <= Length(FilesStr)) and (FilesStr[P] <> '"') do
            P := P + 1;
          if P < Length(FilesStr) then
          begin
            P := P + 1;
            while (P <= Length(FilesStr)) and (FilesStr[P] <> '"') do
              P := P + 1;
          end;

          // Download this file
          FileIndex := FileIndex + 1;
          DownloadPage.SetText('Downloading game assets...', FileName);
          DownloadPage.SetProgress(FileIndex, TotalFiles);

          URL := AssetsBaseURL + FileName;
          DestPath := ExpandConstant('{app}') + '\' + FileName;

          DirPart := ExtractFileDir(DestPath);
          if not DirExists(DirPart) then
            ForceDirectories(DirPart);

          if not DownloadFile(URL, DestPath) then
            Log('Failed to download: ' + URL);
        end;
      end;
      P := P + 1;
    end;
  finally
    DownloadPage.Hide;
  end;
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
