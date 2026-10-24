; Instalador de Windows (Inno Setup 6). Lo compila el workflow de release:
;   iscc /DAppVersion=1.2.3 installer\windows.iss
; Empaqueta build\windows\x64\runner\Release (exe, DLLs de Flutter y libmpv, datos)
; y vc_redist.x64.exe, que el workflow descarga a installer\ antes de compilar.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F3B8B0E-5C2D-4E7A-9A61-2B7F0E9C4D11}
AppName=Ghostlime IPTV
AppVersion={#AppVersion}
AppPublisher=guimo-dev
DefaultDirName={autopf}\Ghostlime IPTV
DefaultGroupName=Ghostlime IPTV
UninstallDisplayIcon={app}\iptv_player.exe
OutputDir=..\build\installer
OutputBaseFilename=Ghostlime-IPTV-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ runtime; installed only when missing.
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: VCRedistNeeded

[Icons]
Name: "{group}\Ghostlime IPTV"; Filename: "{app}\iptv_player.exe"
Name: "{autodesktop}\Ghostlime IPTV"; Filename: "{app}\iptv_player.exe"; Tasks: desktopicon

[Registry]
; Esquema ghostlime:// para volver del navegador tras "Continuar con Google"
; (ghostlime://login-callback). HKA = HKCU\Software\Classes en una instalación
; para el usuario (sin admin) y HKLM\Software\Classes en una para todos. Se borra
; al desinstalar. La versión portable (zip) no lo registra: ahí Google no vuelve.
Root: HKA; Subkey: "Software\Classes\ghostlime"; ValueType: string; ValueName: ""; ValueData: "URL:Ghostlime IPTV"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\ghostlime"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\ghostlime\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\iptv_player.exe"",0"
Root: HKA; Subkey: "Software\Classes\ghostlime\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\iptv_player.exe"" ""%1"""

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Instalando Visual C++ Runtime..."; Check: VCRedistNeeded; Flags: waituntilterminated
Filename: "{app}\iptv_player.exe"; Description: "{cm:LaunchProgram,Ghostlime IPTV}"; Flags: nowait postinstall skipifsilent

[Code]
// The Flutter runner and libmpv need the VC++ 2015-2022 x64 runtime.
function VCRedistNeeded: Boolean;
var
  Installed: Cardinal;
begin
  Result := not (RegQueryDWordValue(HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed)
    and (Installed = 1));
end;

// Offers to delete the app data folder (lists, settings) once uninstall is done.
// Silent uninstalls never prompt and never delete user data.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and not UninstallSilent then
  begin
    if MsgBox('¿Borrar también tus listas, ajustes y datos guardados?',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DelTree(ExpandConstant('{userappdata}\dev.guimo\iptv_player'), True, True, True);
  end;
end;
