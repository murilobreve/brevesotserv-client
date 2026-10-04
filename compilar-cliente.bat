@echo off
rem Baiak Breves - sincroniza com o main do GitHub, compila e empacota o client.
rem Pode abrir com dois cliques ou de qualquer cmd: o ambiente do Visual
rem Studio e carregado aqui mesmo.
rem   compilar-cliente.bat         sincroniza, compila e empacota
rem   compilar-cliente.bat limpo   apaga a configuracao do CMake antes
setlocal
cd /d "%~dp0"

if not defined VCPKG_ROOT set "VCPKG_ROOT=C:\vcpkg"

echo == sincronizando com o main do GitHub
git fetch origin main
if errorlevel 1 goto :falhou
git checkout main
if errorlevel 1 goto :falhou
git pull --ff-only origin main
if errorlevel 1 (
    echo A pasta tem mudancas locais que nao estao no GitHub.
    goto :falhou
)
for /f "usebackq tokens=*" %%c in (`git log -1 --format^="%%h %%s"`) do echo versao: %%c

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
    if exist "build\windows-release\CMakeCache.txt" del "build\windows-release\CMakeCache.txt"
)

echo == configurando
cmake --preset windows-release
if errorlevel 1 goto :falhou

echo == compilando (pode demorar)
cmake --build --preset windows-release
if errorlevel 1 goto :falhou

echo == empacotando
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\empacotar-cliente.ps1"
if errorlevel 1 goto :falhou

echo.
echo Pronto. O client esta em dist\Baiak Breves\ e o zip em dist\BaiakBreves.zip
pause
exit /b 0

:falhou
echo.
echo Parou com erro. Copie as ultimas linhas acima e mande.
pause
exit /b 1
