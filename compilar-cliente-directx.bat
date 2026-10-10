@echo off
rem Mythos - versao DirectX (teste). Sincroniza com a branch de teste,
rem compila o client desenhando com Direct3D 11 (via ANGLE) e empacota em
rem dist\Mythos DirectX\, sem mexer no client normal.
rem Pode abrir com dois cliques ou de qualquer cmd: o ambiente do Visual
rem Studio e carregado aqui mesmo.
rem   compilar-cliente-directx.bat         sincroniza, compila e empacota
rem   compilar-cliente-directx.bat limpo   apaga a configuracao do CMake antes
setlocal

rem roda uma copia de si mesmo a partir da pasta temporaria: assim o git
rem pode trocar de branch e substituir este .bat sem quebrar o cmd
if /i not "%~1"=="--rodando" (
    copy /y "%~f0" "%TEMP%\baiak-directx.bat" >nul
    call "%TEMP%\baiak-directx.bat" --rodando "%~dp0." %1
    exit /b
)
cd /d "%~2"
set "OPCAO=%~3"
set "PASTA=%CD%"

if not defined VCPKG_ROOT set "VCPKG_ROOT=C:\vcpkg"

echo == sincronizando com a branch de teste claude/funny-maxwell-kpy7sn
git fetch origin claude/funny-maxwell-kpy7sn
if errorlevel 1 goto :falhou
rem uma copia solta deste .bat (baixada a parte) travaria a troca de branch
git ls-files --error-unmatch compilar-cliente-directx.bat >nul 2>&1
if errorlevel 1 if exist compilar-cliente-directx.bat del compilar-cliente-directx.bat
git checkout claude/funny-maxwell-kpy7sn
if errorlevel 1 goto :falhou
git pull --ff-only origin claude/funny-maxwell-kpy7sn
if errorlevel 1 (
    echo A pasta tem mudancas locais que nao estao no GitHub.
    goto :falhou
)
echo versao:
git log -1 --oneline

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERRO: Visual Studio nao encontrado.
    goto :falhou
)
set "VSPATH="
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if not defined VSPATH (
    echo ERRO: Visual Studio sem o "Desenvolvimento para desktop com C++".
    goto :falhou
)

echo == carregando o ambiente do Visual Studio
call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 goto :falhou

if /i "%OPCAO%"=="limpo" (
    echo == apagando a configuracao antiga
    if exist "build\windows-release-directx\CMakeCache.txt" del "build\windows-release-directx\CMakeCache.txt"
)

echo == configurando
cmake --preset windows-release-directx
if errorlevel 1 goto :falhou

echo == compilando (pode demorar)
cmake --build --preset windows-release-directx
if errorlevel 1 goto :falhou

echo == empacotando
powershell -NoProfile -ExecutionPolicy Bypass -File "%PASTA%\tools\empacotar-cliente.ps1" -Exe "%PASTA%\build\windows-release-directx\bin\otclient.exe" -Nome "Mythos DirectX" -ZipNome "Mythos-DirectX.zip"
if errorlevel 1 goto :falhou

echo.
echo Pronto. O client DirectX esta em dist\Mythos DirectX\
echo Para voltar ao client normal, rode o compilar-cliente.bat (ele volta para o main).
pause
exit /b 0

:falhou
echo.
echo Parou com erro. Copie as ultimas linhas acima e mande.
pause
exit /b 1
