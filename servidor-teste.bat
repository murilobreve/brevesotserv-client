@echo off
rem Baiak Breves - roda na VPS o servidor da branch de teste, ou volta ao main.
rem Entra por SSH, troca a pasta /opt/brevesot de branch e reinicia o servidor.
rem   servidor-teste.bat         liga a branch de teste
rem   servidor-teste.bat main    volta para o main (o servidor normal)
rem Os jogadores entram no mesmo servidor: enquanto a branch de teste estiver
rem ligada, todo mundo joga nela.
setlocal
set "VPS=root@82.38.28.137"
set "CHAVE=%USERPROFILE%\.ssh\baiak"
set "BRANCH=claude/funny-maxwell-kpy7sn"
set "MODO=teste"
if /i "%~1"=="main" set "MODO=main"

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)

if "%MODO%"=="main" (
    echo == voltando o servidor para o main
) else (
    echo == ligando a branch de teste %BRANCH%
)
ssh -t -i "%CHAVE%" %VPS% "cd /opt/brevesot && git fetch -q origin main && git show origin/main:tools/deploy/test-branch.sh | bash -s %MODO% %BRANCH%"
if errorlevel 1 (
    echo.
    echo Parou com erro. Copie as linhas acima e mande.
)

:fim
echo.
pause
