@echo off
rem Mythos - para quem ajuda a manter o jogo: baixa o main do GitHub,
rem compila o client DirectX (o que o site da aos jogadores), empacota e,
rem se voce confirmar, publica: os jogadores recebem a versao nova ao abrir
rem o jogo, e o instalador do site e trocado.
rem Na primeira vez prepara o PC: instala o Git, o Visual Studio 2026 com
rem C++, o Inno Setup e o vcpkg (pede permissao de administrador; o Visual
rem Studio baixa varios GB) e baixa o codigo em C:\Mythos\brevesotserv-client.
rem A primeira compilacao demora bastante (compila todas as bibliotecas); as
rem outras sao rapidas.
rem Precisa de uma conta do GitHub colaboradora de murilobreve/brevesotserv-client
rem e de murilobreve/mythos-client: o Git pede o login no navegador na
rem primeira vez.
rem   atualizar-jogadores.bat          baixa, compila e publica
rem   atualizar-jogadores.bat limpo    apaga a configuracao do CMake antes
setlocal

rem roda uma copia de si mesmo a partir da pasta temporaria: o git pode
rem trocar este .bat no meio sem quebrar o cmd
if /i not "%~1"=="--rodando" (
    copy /y "%~f0" "%TEMP%\mythos-jogadores.bat" >nul
    call "%TEMP%\mythos-jogadores.bat" --rodando "%~dp0." %1
    exit /b
)
set "AQUI=%~2"
set "OPCAO=%~3"
set "REPO_URL=https://github.com/murilobreve/brevesotserv-client.git"
if not defined VCPKG_ROOT set "VCPKG_ROOT=C:\vcpkg"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
rem dentro de uma copia do codigo, usa ela; senao, uma pasta sem espacos
rem no caminho (algumas bibliotecas nao compilam com espaco)
set "PASTA=C:\Mythos\brevesotserv-client"
if exist "%AQUI%\.git" set "PASTA=%AQUI%"
set "WINGET="
where winget >nul 2>&1 && set "WINGET=1"

echo == conferindo o que este PC precisa

rem ---------------------------------------------------------------- Git
call :acharGit
if defined GITOK goto :gitPronto
echo == instalando o Git
if defined WINGET winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
call :acharGit
if defined GITOK goto :gitPronto
echo ERRO: falta o Git. Instale de https://git-scm.com/download/win e rode este bat de novo.
start "" https://git-scm.com/download/win
goto :falhou
:gitPronto
rem caminhos longos das bibliotecas; e o publicar faz um commit, que pede um nome
git config --global core.longpaths true
git config --global user.email >nul 2>&1
if not errorlevel 1 goto :nomePronto
git config --global user.name "%USERNAME%"
git config --global user.email "%USERNAME%@users.noreply.github.com"
:nomePronto

rem ---------------------------------------------------------------- Visual Studio
call :acharVS
if defined VSOK goto :vsPronto
echo == instalando o Visual Studio 2026 Community com o C++
echo    sao varios GB e demora; aceite o pedido de administrador
if defined WINGET winget install -e --id Microsoft.VisualStudio.Community --accept-package-agreements --accept-source-agreements --override "--passive --wait --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended"
call :acharVS
if defined VSOK goto :vsPronto
echo.
echo ERRO: falta o Visual Studio 2026 com C++. Abrindo a pagina de download:
echo instale o Visual Studio Community 2026 e marque a opcao
echo    Desenvolvimento para desktop com C++
echo Se ele ja estiver instalado, abra o Visual Studio Installer, clique em
echo Modificar e marque essa opcao. Depois rode este bat de novo.
start "" https://visualstudio.microsoft.com/pt-br/downloads/
goto :falhou
:vsPronto

rem ---------------------------------------------------------------- Inno Setup
call :acharInno
if defined INNOOK goto :innoPronto
echo == instalando o Inno Setup 6, que monta o instalador do site
if defined WINGET winget install -e --id JRSoftware.InnoSetup --accept-package-agreements --accept-source-agreements
call :acharInno
if defined INNOOK goto :innoPronto
echo ERRO: falta o Inno Setup 6. Instale de https://jrsoftware.org/isdl.php e rode este bat de novo.
start "" https://jrsoftware.org/isdl.php
goto :falhou
:innoPronto

rem ---------------------------------------------------------------- vcpkg
if exist "%VCPKG_ROOT%\vcpkg.exe" goto :vcpkgPronto
echo == baixando o vcpkg, que compila as bibliotecas do client, em %VCPKG_ROOT%
if exist "%VCPKG_ROOT%\.git" goto :vcpkgBootstrap
git clone https://github.com/microsoft/vcpkg.git "%VCPKG_ROOT%"
if errorlevel 1 goto :falhou
:vcpkgBootstrap
call "%VCPKG_ROOT%\bootstrap-vcpkg.bat" -disableMetrics
if errorlevel 1 goto :falhou
:vcpkgPronto

rem ---------------------------------------------------------------- codigo
if exist "%PASTA%\.git" goto :codigoPronto
echo == baixando o codigo do client em %PASTA%
echo    na primeira vez o Git abre o navegador para o login do GitHub
if not exist "C:\Mythos" mkdir "C:\Mythos"
git clone %REPO_URL% "%PASTA%"
if not errorlevel 1 goto :codigoPronto
echo.
echo ERRO: nao consegui baixar o codigo. A sua conta do GitHub precisa ser
echo colaboradora de murilobreve/brevesotserv-client e de
echo murilobreve/mythos-client: peca ao dono do servidor e aceite o convite
echo que chega no e-mail.
goto :falhou
:codigoPronto

rem ---------------------------------------------------------------- compila e publica
rem o mesmo bat do dono, no main: sincroniza, compila, empacota e pergunta
rem antes de publicar
echo == compilando o main
call "%PASTA%\compilar-cliente-directx.bat" main %OPCAO%
exit /b

:falhou
echo.
echo Parou com erro. Copie as ultimas linhas acima e mande.
pause
exit /b 1

rem ---------------------------------------------------------------- funcoes
:acharGit
set "GITOK="
where git >nul 2>&1 && (set "GITOK=1" & exit /b)
if exist "%ProgramFiles%\Git\cmd\git.exe" set "PATH=%PATH%;%ProgramFiles%\Git\cmd"
if exist "%LOCALAPPDATA%\Programs\Git\cmd\git.exe" set "PATH=%PATH%;%LOCALAPPDATA%\Programs\Git\cmd"
where git >nul 2>&1 && set "GITOK=1"
exit /b

:acharVS
set "VSOK="
if not exist "%VSWHERE%" exit /b
set "VSVER="
for /f "usebackq tokens=1 delims=." %%v in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion`) do set "VSVER=%%v"
if not defined VSVER exit /b
rem o projeto compila com as ferramentas v145, do Visual Studio 2026 (versao 18)
if %VSVER% GEQ 18 set "VSOK=1"
exit /b

:acharInno
set "INNOOK="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "INNOOK=1"
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "INNOOK=1"
if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "INNOOK=1"
exit /b
