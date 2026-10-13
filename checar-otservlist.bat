@echo off
rem Mythos - confere tudo que o otservlist.org precisa: status na porta 7171,
rem porta do jogo, site, login.php, instalador e, na VPS, firewall e config.
rem A saida aparece aqui e fica salva em checar-otservlist.txt.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0checar-otservlist.ps1" > "%~dp0checar-otservlist.txt" 2>&1
type "%~dp0checar-otservlist.txt"
echo.
echo == salvo em %~dp0checar-otservlist.txt
pause
