@echo off
rem Mythos - prepara a pasta remeres-cliente\ para o editor de mapa
rem (Canary Map Editor / Remere's). Rode de novo sempre que o cliente
rem ganhar sprites ou itens novos (depois de um git pull).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0preparar-remeres.ps1"
if errorlevel 1 (
    echo.
    echo Parou com erro. Copie as linhas acima e mande.
)
echo.
pause
