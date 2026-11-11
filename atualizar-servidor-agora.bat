@echo off
rem Mythos - atualiza o servidor e reinicia o jogo NA HORA, sem os 5 minutos
rem de aviso. Quem estiver online cai e volta em menos de um minuto: o
rem progresso de todos e salvo antes do jogo fechar.
rem E o mesmo que "atualizar-servidor.bat agora", em dois cliques.
echo Quem estiver online cai na hora (o progresso e salvo) e volta em ~1 minuto.
choice /c SN /m "Atualizar e reiniciar agora"
if errorlevel 2 goto :eof
call "%~dp0atualizar-servidor.bat" agora
