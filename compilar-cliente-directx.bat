@echo off
rem Baiak Breves - versao DirectX (teste). Sincroniza com a branch de teste,
rem compila o client desenhando com Direct3D 11 (via ANGLE) e empacota em
rem dist\Baiak Breves DirectX\, sem mexer no client normal.
rem Pode abrir com dois cliques ou de qualquer cmd: o ambiente do Visual
rem Studio e carregado aqui mesmo.
rem   compilar-cliente-directx.bat         sincroniza, compila e empacota
rem   compilar-cliente-directx.bat limpo   apaga a configuracao do CMake antes
setlocal
cd /d "%~dp0"

if not defined VCPKG_ROOT set "VCPKG_ROOT=C:\vcpkg"

echo == sincronizando com a branch de teste claude/funny-maxwell-kpy7sn
git fetch origin claude/funny-maxwell-kpy7sn
if errorlevel 1 goto :falhou
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

if /i "%~1"=="limpo" (
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
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\empacotar-cliente.ps1" -Exe "%~dp0build\windows-release-directx\bin\otclient.exe" -Nome "Baiak Breves DirectX" -ZipNome "BaiakBreves-DirectX.zip"
if errorlevel 1 goto :falhou

echo.
echo Pronto. O client DirectX esta em dist\Baiak Breves DirectX\
echo Para voltar ao client normal, rode o compilar-cliente.bat (ele volta para o main).
pause
exit /b 0

:falhou
echo.
echo Parou com erro. Copie as ultimas linhas acima e mande.
pause
exit /b 1
