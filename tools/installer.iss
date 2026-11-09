; Installateur Windows de Pazulu Reader (Inno Setup 6)
; Appele automatiquement par tools\build.ps1 si Inno Setup est installe.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\PazuluReader-1.0.0-windows"
#endif

[Setup]
AppId={{8C5B7E2A-4F1D-4B8E-9A61-3D2F7A0C5E11}
AppName=Pazulu Reader
AppVersion={#AppVersion}
AppPublisher=Pazulu
DefaultDirName={localappdata}\Programs\Pazulu Reader
DefaultGroupName=Pazulu Reader
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=PazuluReader-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\pazulu_reader.exe
SetupIconFile=..\assets\icon\app_icon.ico

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Pazulu Reader"; Filename: "{app}\pazulu_reader.exe"
Name: "{group}\Désinstaller Pazulu Reader"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Pazulu Reader"; Filename: "{app}\pazulu_reader.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pazulu_reader.exe"; Description: "Lancer Pazulu Reader"; Flags: nowait postinstall skipifsilent
