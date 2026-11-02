@echo off
rem Mythos - poe neste PC a chave da VPS que o dono do servidor mandou (o
rem arquivo baiak), para os bats que entram na VPS funcionarem aqui:
rem atualizar-servidor.bat, servidor-teste.bat e os outros.
rem Arraste o arquivo da chave para cima deste bat.
setlocal
set "VPS=root@82.38.28.137"
set "CHAVE=%USERPROFILE%\.ssh\baiak"

set "ARQ=%~1"
if not defined ARQ set /p "ARQ=Arraste aqui o arquivo da chave e aperte Enter: "
if not defined ARQ goto :fim
set "ARQ=%ARQ:"=%"
rem (no echo of the file name inside a block: "baiak (1)" would close it)
if exist "%ARQ%" goto :temArquivo
echo ERRO: arquivo nao encontrado: %ARQ%
goto :fim
:temArquivo
findstr /c:"PRIVATE KEY" "%ARQ%" >nul
if not errorlevel 1 goto :ehChave
echo ERRO: esse arquivo nao e a chave. O certo e o arquivo baiak, sem .pub,
echo que comeca com -----BEGIN OPENSSH PRIVATE KEY-----
goto :fim
:ehChave
if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"
if not exist "%CHAVE%" goto :copiar
choice /c SN /m "Este PC ja tem uma chave baiak. Trocar pela nova"
if errorlevel 2 goto :fim
icacls "%CHAVE%" /grant:r "%USERNAME%":F >nul 2>&1
:copiar
copy /y "%ARQ%" "%CHAVE%" >nul
if errorlevel 1 goto :erro
rem a chave de amigo que o atualizar-servidor.bat cria deixa um .pub, que
rem nao e o desta
if exist "%CHAVE%.pub" del "%CHAVE%.pub"
rem o ssh do Windows recusa uma chave que outros usuarios do PC podem ler
icacls "%CHAVE%" /inheritance:r /grant:r "%USERNAME%":F >nul
if errorlevel 1 goto :erro

echo == testando a entrada na VPS
ssh -i "%CHAVE%" -o StrictHostKeyChecking=accept-new %VPS% "echo OK: entrou na VPS $(hostname)"
if errorlevel 1 goto :erro
echo.
echo Pronto. Os bats que entram na VPS ja funcionam neste PC.
echo Pode apagar o arquivo que voce recebeu: a chave ficou em %CHAVE%
goto :fim

:erro
echo.
echo Parou com erro. Copie as linhas acima e mande.

:fim
echo.
pause
