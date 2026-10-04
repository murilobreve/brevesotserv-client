@echo off
rem Baiak Breves - atualiza o servidor na VPS a partir deste PC.
rem Entra por SSH, baixa do GitHub (main) os scripts, o site e o binario ja
rem compilado, e reinicia o servidor. Dois cliques e pronto.
rem   atualizar-servidor.bat           atualiza (o normal)
rem   atualizar-servidor.bat compilar  compila o servidor na propria VPS
setlocal
set "VPS=root@82.38.28.137"
set "CHAVE=%USERPROFILE%\.ssh\baiak"

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)

if /i "%~1"=="compilar" (
    echo == compilando o servidor na VPS, pode levar ate 30 minutos
    echo    nao feche esta janela
    ssh -t -i "%CHAVE%" %VPS% "cd /opt/brevesot && bash tools/deploy/update-server.sh && bash tools/deploy/compilar-servidor.sh"
) else (
    echo == atualizando o servidor na VPS
    ssh -t -i "%CHAVE%" %VPS% "cd /opt/brevesot && bash tools/deploy/update-server.sh && git log -1 --oneline"
)
if errorlevel 1 (
    echo.
    echo Parou com erro. Copie as linhas acima e mande.
)

:fim
echo.
pause
