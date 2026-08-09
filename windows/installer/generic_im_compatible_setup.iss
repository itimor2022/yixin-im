#ifndef MyAppName
  #define MyAppName "通用IM"
#endif

#ifndef MyAppVersion
  #define MyAppVersion "5.0.0"
#endif

#ifndef MyAppPublisher
  #define MyAppPublisher "通用IM"
#endif

#ifndef MyAppExeName
  #define MyAppExeName "genericim.exe"
#endif

#ifndef MyAppId
  #define MyAppId "{{89A2F9B1-0F59-4D9A-8D55-E7E2E35A1B25}"
#endif

#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\dist\windows-compatible-installer"
#endif

#ifndef VCRedistPath
  #error VCRedistPath must point to Microsoft's signed vc_redist.x64.exe
#endif

#ifndef WebView2BootstrapperPath
  #error WebView2BootstrapperPath must point to Microsoft's signed Evergreen Bootstrapper
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://app.example.com
AppSupportURL=https://app.example.com
AppUpdatesURL=https://app.example.com
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\runner\resources\app_icon.ico
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=yes
OutputDir={#OutputDir}
OutputBaseFilename=GenericIM-Windows-Compatible-Setup-{#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Windows compatible installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项："; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#VCRedistPath}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: deleteafterinstall
Source: "{#WebView2BootstrapperPath}"; DestDir: "{tmp}"; DestName: "MicrosoftEdgeWebview2Setup.exe"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCR; Subkey: "genericim"; ValueType: string; ValueName: ""; ValueData: "URL:OneChat Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "genericim"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "genericim\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "genericim\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "正在安装 Microsoft Visual C++ 运行库..."; Flags: runhidden waituntilterminated; Check: NeedsVCRuntime
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "正在安装 Microsoft Edge WebView2 Runtime..."; Flags: runhidden waituntilterminated; Check: NeedsWebView2Runtime
Filename: "{app}\{#MyAppExeName}"; Description: "立即启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function NeedsVCRuntime: Boolean;
var
  Installed: Cardinal;
begin
  Result := not (
    RegQueryDWordValue(
      HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Installed',
      Installed
    ) and (Installed = 1)
  );
end;

function HasWebView2RuntimeAt(RootKey: Integer): Boolean;
var
  Version: String;
begin
  Result :=
    RegQueryStringValue(
      RootKey,
      'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'pv',
      Version
    ) and (Version <> '') and (Version <> '0.0.0.0');
end;

function NeedsWebView2Runtime: Boolean;
begin
  Result := not (HasWebView2RuntimeAt(HKLM32) or HasWebView2RuntimeAt(HKCU32));
end;
