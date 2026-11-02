@echo off
rem Mythos - versao DirectX, a que o site da aos jogadores. Sincroniza com a
rem branch de teste (ou com o main), compila o client desenhando com Direct3D
rem 11 (via ANGLE) e empacota em dist\Mythos DirectX\, sem mexer no client
rem normal. Pode abrir com dois cliques ou de qualquer cmd: o ambiente do
rem Visual Studio e carregado aqui mesmo.
rem   compilar-cliente-directx.bat         sincroniza, compila e empacota
rem   compilar-cliente-directx.bat limpo   apaga a configuracao do CMake antes
rem   compilar-cliente-directx.bat main    do main em vez da branch de teste
rem                                        (o atualizar-jogadores.bat usa)
setlocal

rem roda uma copia de si mesmo a partir da pasta temporaria: assim o git
rem pode trocar de branch e substituir este .bat sem quebrar o cmd
if /i not "%~1"=="--rodando" (
    copy /y "%~f0" "%TEMP%\baiak-directx.bat" >nul
    call "%TEMP%\baiak-directx.bat" --rodando "%~dp0." %1 %2
    exit /b
)
cd /d "%~2"
set "PASTA=%CD%"
set "BRANCH=claude/funny-maxwell-kpy7sn"
set "LIMPO="
if /i "%~3"=="main" set "BRANCH=main"
if /i "%~4"=="main" set "BRANCH=main"
if /i "%~3"=="limpo" set "LIMPO=1"
if /i "%~4"=="limpo" set "LIMPO=1"

if not defined VCPKG_ROOT set "VCPKG_ROOT=C:\vcpkg"

echo == sincronizando com %BRANCH%
git fetch origin %BRANCH%
if errorlevel 1 goto :falhou
rem uma copia solta deste .bat (baixada a parte) travaria a troca de branch
git ls-files --error-unmatch compilar-cliente-directx.bat >nul 2>&1
if errorlevel 1 if exist compilar-cliente-directx.bat del compilar-cliente-directx.bat
rem uma copia deste .bat baixada por cima da do git (mandada pelo chat, por
rem exemplo) travaria a troca de branch: volta para a do git, que e a mesma
git checkout -- compilar-cliente.bat compilar-cliente-directx.bat >nul 2>&1
git checkout %BRANCH%
if errorlevel 1 goto :falhou
git pull --ff-only origin %BRANCH%
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

if defined LIMPO (
    echo == apagando a configuracao antiga
    if exist "build\windows-release-directx\CMakeCache.txt" del "build\windows-release-directx\CMakeCache.txt"
)

echo == configurando
cmake --preset windows-release-directx
if errorlevel 1 goto :falhou

echo == compilando (pode demorar)
cmake --build --preset windows-release-directx
rem sem memoria, erro C1060 do compilador: de novo com 2 tarefas por vez.
rem O que ja compilou fica pronto, so falta o resto.
if errorlevel 1 (
    echo.
    echo == faltou memoria? compilando o resto com 2 tarefas por vez
    cmake --build --preset windows-release-directx -j 2
)
if errorlevel 1 goto :falhou

echo == empacotando
powershell -NoProfile -ExecutionPolicy Bypass -File "%PASTA%\tools\empacotar-cliente.ps1" -Exe "%PASTA%\build\windows-release-directx\bin\otclient.exe" -Nome "Mythos DirectX" -ZipNome "Mythos-DirectX.zip"
if errorlevel 1 goto :falhou

echo.
rem S publica: os jogadores recebem a versao nova ao abrir o client, e o
rem instalador do site e trocado. N so deixa o client pronto em dist\ para testar.
choice /c SN /m "Publicar esta versao para os jogadores"
if errorlevel 2 goto :naoPublicar
echo == publicando a atualizacao
powershell -NoProfile -ExecutionPolicy Bypass -File "%PASTA%\tools\publicar-atualizacao.ps1" -Canal directx -Pasta "%PASTA%\dist\Mythos DirectX"
if errorlevel 1 goto :falhou
echo == montando o instalador
rem o antivirus as vezes tira o script da pasta: volta com o do git
if not exist "%PASTA%\tools\montar-instalador.ps1" git checkout -- tools/montar-instalador.ps1 >nul 2>&1
if not exist "%PASTA%\tools\montar-instalador.ps1" (
    echo O tools\montar-instalador.ps1 sumiu da pasta ^(antivirus?^). A atualizacao ja foi publicada;
    echo veja a quarentena do antivirus e depois rode o montar-instalador.bat.
    goto :naoPublicar
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PASTA%\tools\montar-instalador.ps1" -Canal directx -Pasta "%PASTA%\dist\Mythos DirectX"
if errorlevel 1 goto :falhou
:naoPublicar

echo.
echo Pronto. O client DirectX esta em dist\Mythos DirectX\
if not "%BRANCH%"=="main" echo Para voltar ao client normal, rode o compilar-cliente.bat (ele volta para o main).
pause
exit /b 0

:falhou
echo.
echo Parou com erro. Copie as ultimas linhas acima e mande.
pause
exit /b 1
