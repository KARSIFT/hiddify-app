#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef ReleaseDir
  #error ReleaseDir is required
#endif

[Setup]
AppId={{A2C752D2-A140-4E02-A85B-52255B3F19C4}
AppName=Hiddify Karsift
AppVersion={#AppVersion}
AppPublisher=KARSIFT
AppPublisherURL=https://github.com/KARSIFT/hiddify-app
DefaultDirName={localappdata}\Programs\Hiddify-Karsift
DefaultGroupName=Hiddify Karsift
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#ReleaseDir}
OutputBaseFilename=Hiddify-Karsift-{#AppVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Hiddify.exe
; The portable build stores data in this writable per-user install directory.
; User-created hiddify_portable_data is deliberately retained on uninstall.
CloseApplications=yes

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Hiddify Karsift"; Filename: "{app}\Hiddify.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\Hiddify Karsift"; Filename: "{app}\Hiddify.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Hiddify.exe"; Description: "Launch Hiddify Karsift"; Flags: nowait postinstall skipifsilent
