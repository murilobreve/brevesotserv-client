@echo off
rem Mythos - junta num arquivo tudo que precisa para ver por que o jogo nao
rem entra: CPU (avx2), estado do servidor, ultimas linhas do log, memoria,
rem portas e qual binario esta rodando. Nao muda nada na VPS.
rem A saida aparece aqui e fica salva em diagnostico-vps.txt, nesta pasta:
rem mande esse arquivo (ou copie o texto) para o Claude.
setlocal
set "CHAVE=%USERPROFILE%\.ssh\baiak"
set "SAIDA=%~dp0diagnostico-vps.txt"

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)
rem o endereco da VPS fica neste PC, fora do git (vps-endereco.bat)
call "%~dp0vps-endereco.bat" usar || goto :fim

echo == coletando, aguarde...
ssh -i "%CHAVE%" %VPS% "cd /opt/brevesot; echo '== CPU'; grep -m1 'model name' /proc/cpuinfo; echo -n 'avx2: '; grep -o -m1 avx2 /proc/cpuinfo || echo NAO; nproc; echo; echo '== binario'; ls -la canary; git log -1 --oneline; md5sum canary; echo; echo '== servico'; systemctl --no-pager status canary | head -12; echo; echo '== log do servidor (ultimas 40 linhas)'; journalctl -u canary -n 40 --no-pager; echo; echo '== portas do jogo (7171 login, 7172 jogo)'; ss -ltnp | grep -E ':717[12] ' || echo 'NENHUMA PORTA ABERTA'; echo; echo '== memoria'; free -m; echo; echo '== carga e processos'; uptime; top -bn1 | head -15; echo; echo '== lag e erros do servidor (ultima hora)'; journalctl -u canary --since '-60min' --no-pager | grep -E 'Lag|rror|took' | tail -80; echo; echo '== MariaDB'; systemctl --no-pager status mariadb | head -5" > "%SAIDA%" 2>&1

type "%SAIDA%"
echo.
echo == salvo em %SAIDA%
echo    mande esse arquivo (ou copie o texto acima) para o Claude.

:fim
echo.
pause
