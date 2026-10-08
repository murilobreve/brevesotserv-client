@echo off
rem Baiak Mythicum - gera dist\Baiak Mythicum\ e dist\BaiakMythicum.zip
rem Rode depois de compilar o client (precisa do otclient.exe nesta pasta).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\empacotar-cliente.ps1" %*
echo.
pause
