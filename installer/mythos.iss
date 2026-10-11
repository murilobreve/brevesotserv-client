; Mythos - instalador (Inno Setup 6, https://jrsoftware.org/isinfo.php)
;
; Montado pelo tools\montar-instalador.ps1, que passa:
;   /DFonte=<pasta pronta do client>  /DExe=<nome do .exe>  /DCanal=directx|opengl
;   /DVersao=<numero da versao>       /DSaida=<nome do instalador, sem .exe>
;
; Instala na pasta do usuario (%LOCALAPPDATA%\Programs), sem pedir
; administrador: o client grava as atualizacoes na propria pasta.

#ifndef Fonte
  #define Fonte "..\dist\Mythos"
#endif
#ifndef Exe
  #define Exe "Mythos.exe"
#endif
#ifndef Canal
  #define Canal "opengl"
#endif
#ifndef Versao
  #define Versao "1"
#endif
#ifndef Saida
  #define Saida "Mythos-Setup"
#endif

#if Canal == "directx"
  #define Nome "Mythos"
  #define Pasta "Mythos"
  #define Id "8B0F6C1E-3D4A-4E7B-9C21-6A5D0F2B7E11"
#else
  #define Nome "Mythos (OpenGL)"
  #define Pasta "Mythos OpenGL"
  #define Id "C4E2A7D9-1B3F-4A6C-8E05-2D7F9B1A3C64"
#endif

[Setup]
AppId={{{#Id}}
AppName={#Nome}
AppVersion={#Versao}
AppVerName={#Nome}
AppPublisher=Mythos
AppPublisherURL=https://mythosot.com.br
AppSupportURL=https://mythosot.com.br
DefaultDirName={localappdata}\Programs\{#Pasta}
DisableProgramGroupPage=yes
; sempre a pasta do usuario: em "Arquivos de Programas" o client nao consegue
; gravar as atualizacoes (e o Windows nega criar a pasta sem administrador)
DisableDirPage=yes
UsePreviousAppDir=no
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename={#Saida}
SetupIconFile=..\cmake\icon\otcicon.ico
UninstallDisplayIcon={app}\{#Exe}
UninstallDisplayName={#Nome}
WizardStyle=modern
WizardImageFile=wizard.bmp,wizard@2x.bmp
WizardSmallImageFile=wizard-small.bmp,wizard-small@2x.bmp
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "atalho"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Fonte}\*"; DestDir: "{app}"; Excludes: "desktop.ini,*.log,*.pdb"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#Nome}"; Filename: "{app}\{#Exe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#Nome}"; Filename: "{app}\{#Exe}"; WorkingDir: "{app}"; Tasks: atalho

[Run]
Filename: "{app}\{#Exe}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#Nome}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; o client baixa os arquivos do jogo e as atualizacoes para dentro da pasta
Type: filesandordirs; Name: "{app}"
