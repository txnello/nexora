; NEXORA - Inno Setup script. Compiled by Build\Build-Nexora.ps1 (parameters: AppVersion, StageDir, RepoRoot, OutDir).
; To compile manually:  ISCC.exe /DAppVersion=1.0.0 /DStageDir=<stage> /DRepoRoot=<repo> /DOutDir=<release> Nexora.iss

#define AppName "NEXORA"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef StageDir
  #define StageDir "..\out\stage"
#endif
#ifndef RepoRoot
  #define RepoRoot "..\.."
#endif
#ifndef OutDir
  #define OutDir "..\..\Release"
#endif

[Setup]
; AppId identifies the application for updates and uninstallation: DO NOT change it between versions
AppId={{C8FF24EB-3A56-4B5E-B53B-88253B0920B2}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Manuel Tonello
AppCopyright=Copyright (C) Manuel Tonello
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoCompany=Manuel Tonello
VersionInfoDescription={#AppName} Setup
DefaultDirName={autopf}\NEXORA
DefaultGroupName=NEXORA
DisableProgramGroupPage=yes
; per-user installation (no administrator); the wizard allows choosing "all users"
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile={#RepoRoot}\LICENSE.txt
OutputDir={#OutDir}
OutputBaseFilename=Nexora-Setup
SetupIconFile={#RepoRoot}\Assets\Branding\nexora-icon.ico
UninstallDisplayIcon={app}\Nexora.exe
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardImageFile={#RepoRoot}\Build\Installer\wizard-large.bmp,{#RepoRoot}\Build\Installer\wizard-large@2x.bmp
WizardSmallImageFile={#RepoRoot}\Build\Installer\wizard-small.bmp,{#RepoRoot}\Build\Installer\wizard-small@2x.bmp
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; if NEXORA is running it asks to close it (mutex created by Nexora.exe)
AppMutex=NEXORA.SingleInstance
CloseApplications=yes
RestartApplications=no
SetupMutex=NEXORA.Setup

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; cleanup of the previous version's application files. Personal data is in %LOCALAPPDATA%\Nexora: it is not touched.
Type: filesandordirs; Name: "{app}\app"

[Files]
Source: "{#StageDir}\Nexora.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\app\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\README.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; AppUserModelID equal to the one set by the process: the taskbar groups the windows and shows the NEXORA icon
Name: "{autoprograms}\NEXORA"; Filename: "{app}\Nexora.exe"; AppUserModelID: "Nexora.App"
Name: "{autodesktop}\NEXORA"; Filename: "{app}\Nexora.exe"; Tasks: desktopicon; AppUserModelID: "Nexora.App"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "NEXORA"; ValueData: """{app}\Nexora.exe"""; Flags: uninsdeletevalue; Check: IsStartupEnabled

[Run]
Filename: "{app}\Nexora.exe"; Description: "{cm:LaunchProgram,NEXORA}"; Flags: nowait postinstall skipifsilent

[CustomMessages]
en.DeleteDataPrompt=Do you also want to delete your personal NEXORA data (tasks, settings, history and backups) from:%n%n%1%n%nChoose No to keep your data, for example to reinstall NEXORA later.
it.DeleteDataPrompt=Vuoi eliminare anche i tuoi dati personali di NEXORA (task, impostazioni, cronologia e backup) da:%n%n%1%n%nScegli No per conservare i dati, ad esempio per reinstallare NEXORA in seguito.

[Code]
function DefaultUserDataDir: string;
begin
  Result := ExpandConstant('{localappdata}\Nexora');
end;

function IsAbsoluteDataPath(const Path: string): Boolean;
begin
  Result := ((Length(Path) >= 3) and (Path[2] = ':') and ((Path[3] = '\') or (Path[3] = '/'))) or
    (Copy(Path, 1, 2) = '\\');
end;

function IsNexoraDataDir(const Path: string): Boolean;
begin
  Result := DirExists(Path) and
    (FileExists(AddBackslash(Path) + 'tasks.json') or
     FileExists(AddBackslash(Path) + 'settings.json') or
     FileExists(AddBackslash(Path) + 'history.json'));
end;

function UserDataDir: string;
var
  SavedLines: TArrayOfString;
  SavedPath: string;
begin
  Result := DefaultUserDataDir;
  { current versions remember the chosen data folder in the registry (HKCU\Software\Nexora, value DataPath) }
  if RegQueryStringValue(HKCU, 'Software\Nexora', 'DataPath', SavedPath) then
  begin
    SavedPath := Trim(SavedPath);
    if IsAbsoluteDataPath(SavedPath) and
       (CompareText(AddBackslash(SavedPath), AddBackslash(ExtractFileDrive(SavedPath))) <> 0) and
       IsNexoraDataDir(SavedPath) then
    begin
      Result := SavedPath;
      Exit;
    end;
  end;
  { versions up to 1.0.4 used a pointer file inside the default folder: still honoured as a fallback }
  if LoadStringsFromFile(AddBackslash(Result) + 'data-path.txt', SavedLines) and
     (GetArrayLength(SavedLines) > 0) then
  begin
    SavedPath := Trim(SavedLines[0]);
    if (Length(SavedPath) > 0) and (SavedPath[1] = #$FEFF) then
      Delete(SavedPath, 1, 1);
    if IsAbsoluteDataPath(SavedPath) and
       (CompareText(AddBackslash(SavedPath), AddBackslash(ExtractFileDrive(SavedPath))) <> 0) and
       IsNexoraDataDir(SavedPath) then
      Result := SavedPath;
  end;
end;

function IsStartupEnabled: Boolean;
var
  SettingsRaw: AnsiString;
  SettingsText: string;
begin
  Result := True;
  if LoadStringFromFile(AddBackslash(UserDataDir) + 'settings.json', SettingsRaw) then
  begin
    SettingsText := string(SettingsRaw);
    SettingsText := Lowercase(SettingsText);
    StringChangeEx(SettingsText, ' ', '', True);
    StringChangeEx(SettingsText, #9, '', True);
    StringChangeEx(SettingsText, #10, '', True);
    StringChangeEx(SettingsText, #13, '', True);
    Result := Pos('"openonstartup":false', SettingsText) = 0;
  end;
end;

function UserDataDirsForPrompt: string;
var
  SelectedDir, DefaultDir: string;
begin
  SelectedDir := UserDataDir;
  DefaultDir := DefaultUserDataDir;
  Result := SelectedDir;
  if CompareText(AddBackslash(SelectedDir), AddBackslash(DefaultDir)) <> 0 then
    Result := Result + #13#10 + DefaultDir;
end;

procedure DeleteNexoraDataAt(const DataDir: string);
var
  FindRec: TFindRec;
  Entry: string;
begin
  if not DirExists(DataDir) then
    Exit;

  DeleteFile(AddBackslash(DataDir) + 'tasks.json');
  DeleteFile(AddBackslash(DataDir) + 'tasks.json.bak');
  DeleteFile(AddBackslash(DataDir) + 'settings.json');
  DeleteFile(AddBackslash(DataDir) + 'settings.json.bak');
  DeleteFile(AddBackslash(DataDir) + 'history.json');
  DeleteFile(AddBackslash(DataDir) + 'history.json.bak');
  DeleteFile(AddBackslash(DataDir) + 'data-path.txt');
  DeleteFile(AddBackslash(DataDir) + 'data-path.txt.bak');
  DelTree(AddBackslash(DataDir) + 'Backups', True, True, True);
  DelTree(AddBackslash(DataDir) + 'Logs', True, True, True);

  if FindFirst(AddBackslash(DataDir) + 'Nexora-data-backup-*', FindRec) then
  try
    repeat
      Entry := AddBackslash(DataDir) + FindRec.Name;
      if DirExists(Entry) then
      begin
        DelTree(Entry, True, True, True);
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;

  RemoveDir(DataDir);
end;

procedure DeleteUserData;
var
  SelectedDir, DefaultDir: string;
begin
  SelectedDir := UserDataDir;
  DefaultDir := DefaultUserDataDir;
  DeleteNexoraDataAt(SelectedDir);
  if CompareText(AddBackslash(SelectedDir), AddBackslash(DefaultDir)) <> 0 then
    DeleteNexoraDataAt(DefaultDir);
  { the pointer to the chosen folder is removed together with the data (kept when the user keeps the data) }
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Nexora');
end;

{ I dati personali NON si trovano nella cartella di installazione e non vengono mai toccati da installazione o aggiornamento.
  In disinstallazione interattiva si chiede se eliminarli (predefinito: No). In disinstallazione silenziosa vengono
  conservati, salvo il parametro esplicito /DELETEDATA=1. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if DirExists(UserDataDir) or DirExists(DefaultUserDataDir) then
    begin
      if UninstallSilent then
      begin
        if ExpandConstant('{param:DELETEDATA|0}') = '1' then
          DeleteUserData;
      end
      else if MsgBox(FmtMessage(CustomMessage('DeleteDataPrompt'), [UserDataDirsForPrompt]), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DeleteUserData;
    end;
  end;
end;
