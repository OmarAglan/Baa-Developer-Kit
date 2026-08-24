; Offline bootstrapper for the Baa development ecosystem.
; It owns no component files: each embedded installer keeps its own AppId,
; files, environment entries, upgrade behavior, and uninstaller.

#define MyAppId "{{713E6720-D44C-4B1E-BFAB-43274018264F}"
#define MyAppName "عدة تطوير باء"
#ifndef MyAppVersion
  #define MyAppVersion "0.2.0"
#endif
#ifndef NazmInstallerPath
  #error NazmInstallerPath is required
#endif
#ifndef BaaInstallerPath
  #error BaaInstallerPath is required
#endif
#ifndef TakweenInstallerPath
  #error TakweenInstallerPath is required
#endif
#ifndef QalamInstallerPath
  #error QalamInstallerPath is required
#endif
#ifndef InstallerManifestPath
  #error InstallerManifestPath is required
#endif
#ifndef NazmSha256
  #error NazmSha256 is required
#endif
#ifndef BaaSha256
  #error BaaSha256 is required
#endif
#ifndef TakweenSha256
  #error TakweenSha256 is required
#endif
#ifndef QalamSha256
  #error QalamSha256 is required
#endif

#define NazmInstallerName ExtractFileName(NazmInstallerPath)
#define BaaInstallerName ExtractFileName(BaaInstallerPath)
#define TakweenInstallerName ExtractFileName(TakweenInstallerPath)
#define QalamInstallerName ExtractFileName(QalamInstallerPath)
#define InstallerManifestName ExtractFileName(InstallerManifestPath)

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Omar Aglan
AppPublisherURL=https://github.com/OmarAglan/Baa-Developer-Kit
AppSupportURL=https://github.com/OmarAglan/Baa-Developer-Kit
DefaultDirName={tmp}\BaaDeveloperKit
CreateAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir=dist\installer
OutputBaseFilename=baa-developer-kit-setup-{#MyAppVersion}-x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
SetupLogging=yes
Uninstallable=no
CreateUninstallRegKey=no
UsePreviousLanguage=yes
#ifdef InstallerSignTool
SignTool={#InstallerSignTool}
#endif

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#NazmInstallerPath}"; Flags: dontcopy
Source: "{#BaaInstallerPath}"; Flags: dontcopy
Source: "{#TakweenInstallerPath}"; Flags: dontcopy
Source: "{#QalamInstallerPath}"; Flags: dontcopy
Source: "{#InstallerManifestPath}"; Flags: dontcopy

[Code]
const
  NazmHash = '{#NazmSha256}';
  BaaHash = '{#BaaSha256}';
  TakweenHash = '{#TakweenSha256}';
  QalamHash = '{#QalamSha256}';
  NazmUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8D3D57AE-41CF-4B8A-95E9-270E4564E2A1}_is1';
  BaaUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{E4B6D77C-6C22-4E2D-8F9D-61D34A26B0D1}_is1';
  TakweenUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{9D321DC1-69B3-44F0-A52A-86DB6A6E0C97}_is1';
  QalamUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{1A6F6714-2C14-4DBD-BACB-B26CBABE36EE}_is1';

var
  ReceiptDirectory: string;
  ReceiptStem: string;
  ReceiptPath: string;

function InstallerRoot: Integer;
begin
  if IsAdminInstallMode then
    Result := HKLM
  else
    Result := HKCU;
end;

procedure WriteReceipt(const Message: string);
begin
  Log(Message);
  if ReceiptPath <> '' then
    SaveStringToFile(ReceiptPath,
      GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':') + ' ' + Message + #13#10,
      True);
end;

procedure InitializeReceipt;
begin
  if IsAdminInstallMode then
    ReceiptDirectory := ExpandConstant('{commonappdata}\BaaEcosystem\InstallerLogs')
  else
    ReceiptDirectory := ExpandConstant('{localappdata}\BaaEcosystem\InstallerLogs');
  ForceDirectories(ReceiptDirectory);
  ReceiptStem := GetDateTimeString('yyyymmdd-hhnnss', '-', ':') +
    '-baa-developer-kit-{#MyAppVersion}';
  ReceiptPath := AddBackslash(ReceiptDirectory) + ReceiptStem + '.log';
  WriteReceipt('Starting Baa Developer Kit installation.');
end;

function VerifyInstaller(const FileName, ExpectedHash: string): Boolean;
var
  FullPath, ActualHash: string;
begin
  ExtractTemporaryFile(FileName);
  FullPath := ExpandConstant('{tmp}\') + FileName;
  ActualHash := Lowercase(GetSHA256OfFile(FullPath));
  Result := ActualHash = Lowercase(ExpectedHash);
  if Result then
    WriteReceipt('Verified SHA-256: ' + FileName)
  else
    WriteReceipt('SHA-256 mismatch: ' + FileName + ' expected=' +
      ExpectedHash + ' actual=' + ActualHash);
end;

function VerifyAllInstallers: Boolean;
var
  ManifestContent: AnsiString;
begin
  Result :=
    VerifyInstaller('{#NazmInstallerName}', NazmHash) and
    VerifyInstaller('{#BaaInstallerName}', BaaHash) and
    VerifyInstaller('{#TakweenInstallerName}', TakweenHash) and
    VerifyInstaller('{#QalamInstallerName}', QalamHash);
  if Result then
  begin
    ExtractTemporaryFile('{#InstallerManifestName}');
    if not LoadStringFromFile(ExpandConstant('{tmp}\{#InstallerManifestName}'),
      ManifestContent) then
      RaiseException('Unable to read the embedded installer manifest.');
    if not SaveStringToFile(
      AddBackslash(ReceiptDirectory) + ReceiptStem + '-manifest.json',
      ManifestContent, False) then
      RaiseException('Unable to preserve the installer manifest receipt.');
  end;
end;

function ComponentDirectoryArgument(const ComponentId: string): string;
var
  Root: string;
begin
  Root := Trim(ExpandConstant('{param:COMPONENTROOT|}'));
  if Root = '' then
    Result := ''
  else
  begin
    Root := RemoveQuotes(Root);
    Result := ' /DIR="' + AddBackslash(Root) + ComponentId + '"';
  end;
end;

function RunComponent(const ComponentId, FileName: string): Boolean;
var
  Arguments, ScopeArgument, ChildLog: string;
  ExitCode: Integer;
begin
  if IsAdminInstallMode then
    ScopeArgument := '/ALLUSERS'
  else
    ScopeArgument := '/CURRENTUSER';
  ChildLog := AddBackslash(ReceiptDirectory) + ReceiptStem + '-' +
    ComponentId + '.log';
  Arguments := '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- ' +
    ScopeArgument + ComponentDirectoryArgument(ComponentId) +
    ' /LOG="' + ChildLog + '"';
  WriteReceipt('Installing ' + ComponentId + '.');
  Result := Exec(ExpandConstant('{tmp}\') + FileName, Arguments,
    ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ExitCode) and
    (ExitCode = 0);
  if Result then
    WriteReceipt('Installed ' + ComponentId + ' successfully.')
  else
    WriteReceipt('Component failed: ' + ComponentId +
      ' exit_code=' + IntToStr(ExitCode));
end;

function InstalledLocation(const UninstallKey: string; var Location: string): Boolean;
begin
  Result := RegQueryStringValue(InstallerRoot, UninstallKey,
    'InstallLocation', Location) and (Location <> '');
end;

function RunVersionProbe(const ComponentId, UninstallKey, RelativeProgram,
  Arguments: string): Boolean;
var
  Location, ProgramPath: string;
  ExitCode: Integer;
begin
  Result := InstalledLocation(UninstallKey, Location);
  if not Result then
  begin
    WriteReceipt('Missing uninstall registration for ' + ComponentId + '.');
    Exit;
  end;
  ProgramPath := AddBackslash(Location) + RelativeProgram;
  Result := FileExists(ProgramPath) and
    Exec(ProgramPath, Arguments, Location, SW_HIDE,
      ewWaitUntilTerminated, ExitCode) and (ExitCode = 0);
  if Result then
    WriteReceipt('Health check passed: ' + ComponentId + '.')
  else
    WriteReceipt('Health check failed: ' + ComponentId + '.');
end;

function RunAllHealthChecks: Boolean;
var
  QalamLocation: string;
begin
  Result :=
    RunVersionProbe('nazm', NazmUninstallKey, 'bin\نظم.exe', '--إصدار') and
    RunVersionProbe('baa', BaaUninstallKey, 'baa.exe', '--version') and
    RunVersionProbe('takween', TakweenUninstallKey, 'bin\تكوين.exe', '--إصدار') and
    RunVersionProbe('qalam', QalamUninstallKey,
      'baa-lsp\baa-lsp.exe', '--version');
  if Result then
    Result := InstalledLocation(QalamUninstallKey, QalamLocation) and
      FileExists(AddBackslash(QalamLocation) + 'Qalam.exe');
  if Result then
    WriteReceipt('All ecosystem health checks passed.')
  else
    WriteReceipt('Ecosystem health checks failed.');
end;

function PrepareToInstall(var NeedsRestart: Boolean): string;
begin
  Result := '';
  InitializeReceipt;
  try
    if not VerifyAllInstallers then
      Result := 'فشل التحقق من SHA-256 لأحد المثبتات. لم يبدأ أي تثبيت.';
  except
    Result := 'تعذر التحقق من المثبتات: ' + GetExceptionMessage;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if not RunComponent('nazm', '{#NazmInstallerName}') then
      RaiseException('فشل تثبيت نظم. راجع سجل المثبت.');
    if not RunComponent('baa', '{#BaaInstallerName}') then
      RaiseException('فشل تثبيت باء. راجع سجل المثبت.');
    if not RunComponent('takween', '{#TakweenInstallerName}') then
      RaiseException('فشل تثبيت تكوين. راجع سجل المثبت.');
    if not RunComponent('qalam', '{#QalamInstallerName}') then
      RaiseException('فشل تثبيت قلم. راجع سجل المثبت.');
    if not RunAllHealthChecks then
      RaiseException('فشل فحص صحة عدة تطوير باء بعد التثبيت.');
    WriteReceipt('Baa Developer Kit installation completed successfully.');
  end;
end;
