@echo off
rem Mythos - atualiza o servidor na VPS a partir deste PC.
rem Entra por SSH, baixa do GitHub (main) os scripts, o site e o binario ja
rem compilado, e reinicia o servidor. Dois cliques e pronto.
rem   atualizar-servidor.bat           atualiza (o normal)
rem   atualizar-servidor.bat compilar  compila o servidor na propria VPS
rem No PC de um amigo, sem a chave: este bat cria uma e mostra o arquivo
rem baiak.pub para ele mandar ao dono do servidor, que autoriza com o
rem autorizar-amigo.bat. A chave do amigo so atualiza.
setlocal
set "VPS=root@82.38.28.137"
set "CHAVE=%USERPROFILE%\.ssh\baiak"

if not exist "%CHAVE%" goto :semchave

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
goto :fim

:semchave
echo Este PC ainda nao tem a chave que entra na VPS: %CHAVE%
echo Se o dono do servidor te mandou a chave dele, o arquivo baiak, feche e
echo arraste esse arquivo para cima do instalar-chave.bat.
echo Se ele vai autorizar uma chave sua, crie a sua agora.
choice /c SN /m "Criar a chave"
if errorlevel 2 goto :fim
where ssh-keygen >nul 2>&1
if errorlevel 1 (
    echo ERRO: falta o Cliente OpenSSH do Windows. Instale em Configuracoes,
    echo Aplicativos, Recursos opcionais, Cliente OpenSSH, e rode de novo.
    goto :fim
)
if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"
ssh-keygen -q -t ed25519 -N "" -C "mythos-%USERNAME%" -f "%CHAVE%"
if errorlevel 1 goto :fim
echo.
echo Pronto. Mande este arquivo para o dono do servidor:
echo    %CHAVE%.pub
echo Esse pode mandar, e a parte publica. O outro, baiak sem .pub, nunca mande.
echo Depois que ele autorizar, rode este bat de novo para atualizar.
explorer /select,"%CHAVE%.pub"

:fim
echo.
pause
