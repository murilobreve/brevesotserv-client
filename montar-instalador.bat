@echo off
rem Mythos - refaz so o instalador (Mythos-Setup.exe e o .zip) e manda para
rem o GitHub, sem compilar de novo. Usa o client que ja esta em dist\.
rem   montar-instalador.bat            versao DirectX (dist\Mythos DirectX)
rem   montar-instalador.bat opengl     versao OpenGL (dist\Mythos)
setlocal
cd /d "%~dp0"

rem o antivirus as vezes tira o script da pasta: volta com o do git
if not exist "tools\montar-instalador.ps1" git checkout -- tools/montar-instalador.ps1
if not exist "tools\montar-instalador.ps1" (
    echo ERRO: o tools\montar-instalador.ps1 nao esta na pasta.
    echo Veja se o antivirus colocou ele em quarentena e restaure, ou rode:
    echo   git checkout -- tools/montar-instalador.ps1
    goto :falhou
)

if /i "%~1"=="opengl" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\tools\montar-instalador.ps1" -Canal opengl
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\tools\montar-instalador.ps1" -Canal directx -Pasta "%CD%\dist\Mythos DirectX"
)
if errorlevel 1 goto :falhou

echo.
echo Pronto.
pause
exit /b 0

:falhou
echo.
echo Parou com erro. Copie as ultimas linhas acima e mande.
pause
exit /b 1
