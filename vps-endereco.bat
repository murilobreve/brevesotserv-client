@echo off
rem Mythos - o endereco da VPS (usuario@IP) que os bats usam no SSH.
rem Fica so neste PC, fora do git, ao lado da chave baiak:
rem    %USERPROFILE%\.ssh\mythos-vps.txt
rem   vps-endereco.bat          mostra o endereco guardado e deixa trocar
rem Os outros bats chamam  call vps-endereco.bat usar  e usam o %VPS%: na
rem primeira vez ele pergunta o endereco (peca ao dono do servidor).
set "VPSFILE=%USERPROFILE%\.ssh\mythos-vps.txt"
set "VPS="
if exist "%VPSFILE%" set /p VPS=<"%VPSFILE%"
if /i "%~1"=="usar" (
    if defined VPS exit /b 0
    goto :perguntar
)
if defined VPS (
    echo Endereco da VPS guardado neste PC: %VPS%
    choice /c SN /m "Trocar"
    if errorlevel 2 goto :fim
)
:perguntar
echo.
echo Digite o endereco da VPS no formato usuario@IP, por exemplo root@203.0.113.10
echo (o dono do servidor sabe; ele fica guardado em %VPSFILE%).
set "VPS="
set /p "VPS=Endereco da VPS: "
if not defined VPS goto :vazio
rem only letters, numbers, . - _ and one @: nothing that is cmd syntax
> "%TEMP%\mythos-vps.txt" echo(%VPS%
findstr /r /x "[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-]*@[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.:-][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.:-]*" "%TEMP%\mythos-vps.txt" >nul
if errorlevel 1 goto :invalido
del "%TEMP%\mythos-vps.txt" >nul 2>&1
if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"
> "%VPSFILE%" echo %VPS%
echo Guardado: %VPS%
if /i "%~1"=="usar" exit /b 0
goto :fim

:invalido
del "%TEMP%\mythos-vps.txt" >nul 2>&1
echo ERRO: use usuario@IP, so letras, numeros, ponto, hifen e um @.
set "VPS="
if /i "%~1"=="usar" exit /b 1
goto :fim

:vazio
echo Nada digitado.
if /i "%~1"=="usar" exit /b 1

:fim
if /i not "%~1"=="usar" pause
exit /b 0
