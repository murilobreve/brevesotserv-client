@echo off
rem Mythos - testa a LivePix na VPS do jeito que o site usa (como www-data):
rem credenciais, token, criar um checkout de R$ 1 (ninguem paga, ele expira)
rem e listar pagamentos. Rode depois do atualizar-servidor.bat.
rem A saida fica em testar-livepix.txt: mande para o Claude.
setlocal
set "VPS=root@82.38.28.137"
set "CHAVE=%USERPROFILE%\.ssh\baiak"
set "SAIDA=%~dp0testar-livepix.txt"

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)

echo == testando, aguarde...
ssh -i "%CHAVE%" %VPS% "cd /opt/brevesot && git log -1 --oneline && runuser -u www-data -- php tools/deploy/livepix-test.php; echo; echo '== erros do site (php-fpm)'; grep -h LivePix /var/log/php*-fpm.log 2>/dev/null | tail -5; journalctl -u 'php*-fpm' --no-pager -n 200 2>/dev/null | grep LivePix | tail -5; echo; echo '== cron (ultimas linhas)'; tail -5 /var/log/brevesot-livepix.log 2>/dev/null; ls -la /etc/brevesot-livepix.env /var/lib/brevesot" > "%SAIDA%" 2>&1

type "%SAIDA%"
echo.
echo == salvo em %SAIDA%
echo    mande esse arquivo (ou copie o texto acima) para o Claude.

:fim
echo.
pause
