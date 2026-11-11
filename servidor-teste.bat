@echo off
rem Mythos - roda na VPS o servidor de uma branch de teste, ou volta ao main.
rem Entra por SSH, troca a pasta /opt/brevesot de branch e reinicia o servidor
rem (com aviso no jogo).
rem   servidor-teste.bat NOME-DA-BRANCH   liga essa branch (pergunta se faltar)
rem   servidor-teste.bat main             volta para o main (o servidor normal)
rem Os jogadores entram no mesmo servidor: enquanto a branch de teste estiver
rem ligada, TODO MUNDO joga nela. Depois do lancamento, teste num servidor
rem separado, nunca no de producao.
setlocal
set "CHAVE=%USERPROFILE%\.ssh\baiak"
set "BRANCH="
set "MODO=teste"
if /i "%~1"=="main" (set "MODO=main") else (set "BRANCH=%~1")

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)
rem o endereco da VPS fica neste PC, fora do git (vps-endereco.bat)
call "%~dp0vps-endereco.bat" usar || goto :fim

if "%MODO%"=="main" (
    echo == voltando o servidor para o main
    goto :rodar
)
if not defined BRANCH set /p "BRANCH=Nome da branch de teste no GitHub: "
if not defined BRANCH goto :fim
rem only the characters of a branch name: nothing that is cmd or shell syntax,
rem and no "-" at the start. Written with delayed expansion and outside a ( )
rem block, so nothing typed runs before the check (resetar-servidor.bat does
rem the same). The lines after it may expand the name: it passed.
rem PowerShell reads it from the environment (findstr ran out of memory on
rem the long character classes this check used before)
powershell -NoProfile -Command "if ($env:BRANCH -cmatch '^[A-Za-z0-9_][A-Za-z0-9_./-]*$') { exit 0 } else { exit 1 }"
if errorlevel 1 (
    echo ERRO: nome de branch invalido.
    goto :fim
)
echo ATENCAO: todos os jogadores passam a jogar na branch %BRANCH%.
echo O servidor reinicia com aviso de 5 minutos no jogo.
set "RESP="
set /p "RESP=Para continuar digite TESTE e Enter: "
if not "%RESP%"=="TESTE" (
    echo Cancelado, nada mudou.
    goto :fim
)
echo == ligando a branch de teste %BRANCH%
:rodar
ssh -t -i "%CHAVE%" %VPS% "cd /opt/brevesot && git fetch -q origin main && git show origin/main:tools/deploy/test-branch.sh | bash -s %MODO% %BRANCH%"
if errorlevel 1 (
    echo.
    echo Parou com erro. Copie as linhas acima e mande.
)

:fim
echo.
pause
