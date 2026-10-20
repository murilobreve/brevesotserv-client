@echo off
rem Mythos - liga o jogo no navegador: https://mythosot.com.br/jogar
rem Entra na VPS por SSH, atualiza o servidor (como o atualizar-servidor.bat,
rem que reinicia o jogo) e roda o tools/deploy/ativar-navegador.sh:
rem   - baixa a versao do cliente para navegador (release "navegador" do
rem     GitHub, feita sozinha pelo GitHub Actions a cada mudanca no cliente)
rem   - coloca a pagina /jogar no site (precisa do site em https)
rem   - liga a ponte do navegador para o jogo (porta 7180) e libera no firewall
rem Basta rodar uma vez: depois o atualizar-servidor.bat mantem tudo em dia.
rem Rodar de novo nao estraga nada.
setlocal
set "VPS=root@82.38.28.137"
set "CHAVE=%USERPROFILE%\.ssh\baiak"

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)

echo == ligando o jogo no navegador (a primeira vez baixa uns 270 MB na VPS)
ssh -t -i "%CHAVE%" %VPS% "cd /opt/brevesot && bash tools/deploy/update-server.sh && bash tools/deploy/ativar-navegador.sh"
if errorlevel 1 (
    echo.
    echo Parou com erro. Copie as linhas acima e mande.
    goto :fim
)

echo.
echo Pronto. Abra https://mythosot.com.br/jogar no Chrome, Edge ou Firefox.

:fim
echo.
pause
