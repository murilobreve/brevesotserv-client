@echo off
rem Mythos - deixa outra pessoa entrar na VPS com uma chave dela, sem usar a
rem sua: a chave publica vai para o authorized_keys do root com um nome,
rem para tirar depois.
rem   A, so atualizar: a chave so roda a atualizacao do servidor
rem      (tools/deploy/update-server.sh): sem terminal, sem tunel, sem compilar
rem   T, acesso total: entra na VPS como voce
rem Arraste o arquivo .pub para cima deste bat, ou abra e cole a chave
rem publica (a linha "ssh-ed25519 AAAA...", a do painel da VPS tambem serve),
rem de um nome e escolha A ou T.
rem   autorizar-amigo.bat listar          quem entra, e como
rem   autorizar-amigo.bat remover NOME    tira o acesso desse nome
setlocal EnableDelayedExpansion
set "CHAVE=%USERPROFILE%\.ssh\baiak"
set "AK=/root/.ssh/authorized_keys"

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)
rem o endereco da VPS fica neste PC, fora do git (vps-endereco.bat)
call "%~dp0vps-endereco.bat" usar || goto :fim

if /i "%~1"=="listar" goto :listar
if /i "%~1"=="remover" goto :remover

rem the key: its text pasted, or its .pub file (dropped, given or pasted).
rem What is read only goes through delayed expansion, so a quote or an &
rem in it is never cmd syntax
set "ENTRADA=%~1"
if not defined ENTRADA set /p "ENTRADA=Arraste aqui o arquivo .pub, ou cole a chave publica, e aperte Enter: "
if not defined ENTRADA goto :fim
set "ENTRADA=!ENTRADA:"=!"
set "TIPO="
set "BLOB="
for /f "tokens=1,2" %%a in ("!ENTRADA!") do (
    set "TIPO=%%a"
    set "BLOB=%%b"
)
call :valida
if defined VALIDO goto :chaveOk
set "TIPO="
set "BLOB="
if exist "!ENTRADA!" goto :arquivo
echo ERRO: isso nao e uma chave publica, nem um arquivo que exista.
goto :fim
:arquivo
findstr /c:"PRIVATE" "!ENTRADA!" >nul
if errorlevel 1 goto :publica
echo ERRO: esse e o arquivo PRIVADO da chave. Use o .pub, ou a chave publica
echo que o painel mostra; a privada fica so com quem vai entrar.
goto :fim
:publica
for /f "usebackq tokens=1,2" %%a in ("!ENTRADA!") do if not defined TIPO (
    set "TIPO=%%a"
    set "BLOB=%%b"
)
call :valida
if not defined VALIDO goto :invalido
:chaveOk

set "NOME="
set /p "NOME=Nome de quem vai entrar, so letras e numeros: "
if not defined NOME goto :fim
call :nomeValido
if not defined NOMEOK goto :nomeRuim

echo.
echo   A = so atualizar o servidor
echo   T = acesso total, como voce
choice /c AT /m "Que acesso"
set "ESCOLHA=%errorlevel%"
set "LINHA=%TEMP%\mythos-amigo-%RANDOM%.txt"
if "%ESCOLHA%"=="2" goto :total
rem "restrict" takes away the shell and the tunnels: whatever the key asks,
rem sshd runs this command= and nothing else. An "echo ..." (the test of
rem instalar-chave.bat) only gets an answer; anything else updates
set "MODO=so atualiza"
> "%LINHA%" echo restrict,pty,command="case x$SSH_ORIGINAL_COMMAND in xecho*) echo OK: esta chave entra, so para atualizar o servidor;; *) cd /opt/brevesot && bash tools/deploy/update-server.sh && git log -1 --oneline;; esac" !TIPO! !BLOB! mythos-amigo-!NOME!
goto :enviar
:total
set "MODO=acesso total"
> "%LINHA%" echo !TIPO! !BLOB! mythos-amigo-!NOME!
:enviar
echo == autorizando !NOME! na VPS: !MODO!
rem the line goes by stdin, with no quotes to escape on the way. The file
rem must end with a newline before the append (or the last key, yours,
rem would be cut); the name's old key goes; a key that already gets in is
rem not touched
ssh -i "%CHAVE%" %VPS% "sed -i -e '$a\' %AK% && sed -i '/ mythos-amigo-!NOME!$/d' %AK% && if grep -qF '!BLOB!' %AK%; then echo 'ERRO: essa chave ja entra na VPS - nao e a sua?'; exit 1; fi && tr -d '\r' >> %AK% && echo OK" < "%LINHA%"
if errorlevel 1 goto :falhouEnvio
del "%LINHA%" >nul 2>&1
echo.
echo Pronto: !NOME! entra na VPS com a chave dele: !MODO!.
echo No PC dele, a chave privada vai para a pasta .ssh com o nome baiak:
echo o instalar-chave.bat faz isso, arrastando o arquivo para cima dele.
echo Para tirar o acesso: autorizar-amigo.bat remover !NOME!
goto :fim

:falhouEnvio
del "%LINHA%" >nul 2>&1
echo.
echo Parou com erro. Copie as linhas acima e mande.
goto :fim

:invalido
echo ERRO: !ENTRADA! nao parece uma chave publica SSH. Use o .pub ou a linha
echo que comeca com ssh-ed25519 ou ssh-rsa, no formato OpenSSH.
goto :fim

:nomeRuim
echo ERRO: use so letras, numeros ou _ no nome.
goto :fim

:listar
ssh -i "%CHAVE%" %VPS% "echo '== quem entra na VPS com chave propria:'; grep 'mythos-amigo-' %AK% | sed -e 's/^restrict.* mythos-amigo-\([A-Za-z0-9_]*\)$/   \1: so atualiza/' -e 's/^[^ ]* [^ ]* mythos-amigo-\([A-Za-z0-9_]*\)$/   \1: acesso total/'; true"
goto :fim

:remover
set "NOME=%~2"
if not defined NOME (
    echo Uso: autorizar-amigo.bat remover NOME
    goto :fim
)
call :nomeValido
if not defined NOMEOK goto :nomeRuim
ssh -i "%CHAVE%" %VPS% "if grep -q ' mythos-amigo-!NOME!$' %AK%; then sed -i '/ mythos-amigo-!NOME!$/d' %AK% && echo 'acesso de !NOME! removido'; else echo '!NOME! nao estava autorizado'; fi"
goto :fim

rem ---------------------------------------------------------------- checks
rem a known key type and a base64 key (the letters spelled out: findstr's
rem ranges also take accented letters)
:valida
set "VALIDO="
for %%t in (ssh-ed25519 ssh-rsa ecdsa-sha2-nistp256 ecdsa-sha2-nistp384 ecdsa-sha2-nistp521) do if "!TIPO!"=="%%t" set "VALIDO=1"
if not defined VALIDO exit /b
> "%TEMP%\mythos-chave.txt" echo(!BLOB!
findstr /r /x "AAAA[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=]*" "%TEMP%\mythos-chave.txt" >nul
if errorlevel 1 set "VALIDO="
del "%TEMP%\mythos-chave.txt" >nul 2>&1
exit /b

:nomeValido
set "NOMEOK="
> "%TEMP%\mythos-nome.txt" echo(!NOME!
findstr /r /x "[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*" "%TEMP%\mythos-nome.txt" >nul && set "NOMEOK=1"
del "%TEMP%\mythos-nome.txt" >nul 2>&1
exit /b

:fim
echo.
pause
