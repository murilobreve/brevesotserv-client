@echo off
rem Mythos - liga a voz (Mythos Voz): o botao "Voz" no jogo, salas da party,
rem guild e publicas. Entra na VPS por SSH, atualiza o servidor (como o
rem atualizar-servidor.bat) e roda o tools/deploy/ativar-voz.sh:
rem   - compila o relay da voz e o liga como servico (porta 7190, wss com o
rem     certificado do site)
rem   - cria a chave da voz, o endereco e o usuario do banco so para a voz
rem   - libera a porta 7190 no firewall
rem O jogo le a chave quando inicia: no fim ele pergunta se pode reiniciar
rem (quem estiver online recebe aviso de 5 minutos).
rem Basta rodar uma vez: depois o atualizar-servidor.bat mantem o relay em
rem dia. Rodar de novo nao estraga nada.
rem No jogo, como GM: /voz status mostra como esta; no comeco so a staff ve
rem a voz, e /voz acesso all libera para todos.
setlocal
set "CHAVE=%USERPROFILE%\.ssh\baiak"

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)
rem o endereco da VPS fica neste PC, fora do git (vps-endereco.bat)
call "%~dp0vps-endereco.bat" usar || goto :fim

echo == ligando a voz (a primeira vez instala o Go e compila o relay na VPS)
ssh -t -i "%CHAVE%" %VPS% "cd /opt/brevesot && bash tools/deploy/update-server.sh && bash tools/deploy/ativar-voz.sh --perguntar"
if errorlevel 1 (
    echo.
    echo Parou com erro. Copie as linhas acima e mande.
    goto :fim
)

echo.
echo Pronto. No jogo (depois do reinicio), o botao "Voz" aparece no canto
echo superior direito para a staff. Para liberar para todos: /voz acesso all

:fim
echo.
pause
