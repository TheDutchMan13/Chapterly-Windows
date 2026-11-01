; Builds Chapterly-Setup-<version>.exe from the release build.
; GitHub Actions runs:  ISCC.exe /DMyAppVersion=1.1.0 installer\chapterly.iss
; Installs for the current user only, so no admin rights are needed. Your
; library lives in AppData and is kept when Chapterly is uninstalled.

#ifndef MyAppVersion
  #define MyAppVersion "1.1.0"
#endif

[Setup]
AppId={{B22021BF-108E-4F7A-A9C4-4A326D2D9D6A}
AppName=Chapterly
AppVersion={#MyAppVersion}
AppVerName=Chapterly {#MyAppVersion}
AppPublisher=Hans De Kryger
AppPublisherURL=https://github.com/TheDutchMan13/Chapterly-Windows
AppSupportURL=https://github.com/TheDutchMan13/Chapterly-Windows/issues
DefaultDirName={autopf}\Chapterly
DefaultGroupName=Chapterly
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=Chapterly-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\chapterly.exe
UninstallDisplayName=Chapterly
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Chapterly"; Filename: "{app}\chapterly.exe"; AppUserModelID: "HansDeKryger.Chapterly"
Name: "{autodesktop}\Chapterly"; Filename: "{app}\chapterly.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\chapterly.exe"; Description: "{cm:LaunchProgram,Chapterly}"; Flags: nowait postinstall
