@echo off
rem Mythos - deixa um amigo atualizar o servidor com o atualizar-servidor.bat
rem dele, sem dar a ele a sua chave nem acesso root: a chave dele so roda a
rem atualizacao (tools/deploy/update-server.sh), mais nada.
rem   1. o amigo roda o atualizar-servidor.bat no PC dele: sem chave, ele
rem      cria uma e mostra o arquivo baiak.pub para mandar para voce
rem   2. voce arrasta esse baiak.pub para cima deste bat e da um nome ao amigo
rem   autorizar-amigo.bat listar          quem pode atualizar
rem   autorizar-amigo.bat remover NOME    tira o acesso desse amigo
setlocal
set "VPS=root@82.38.28.137"
set "CHAVE=%USERPROFILE%\.ssh\baiak"
set "AK=/root/.ssh/authorized_keys"

if not exist "%CHAVE%" (
    echo ERRO: chave SSH nao encontrada em %CHAVE%
    goto :fim
)

if /i "%~1"=="listar" goto :listar
if /i "%~1"=="remover" goto :remover

rem the friend's public key: dropped on this bat, given as an argument or asked
set "PUB=%~1"
if not defined PUB set /p "PUB=Arraste aqui o arquivo .pub do amigo e aperte Enter: "
if not defined PUB goto :fim
set "PUB=%PUB:"=%"
rem (no echo of the file name inside a block: "baiak (1).pub" would close it)
if exist "%PUB%" goto :temArquivo
echo ERRO: arquivo nao encontrado: %PUB%
goto :fim
:temArquivo
findstr /c:"PRIVATE" "%PUB%" >nul
if errorlevel 1 goto :publica
echo ERRO: esse e o arquivo PRIVADO da chave. Peca ao amigo o baiak.pub,
echo a parte publica, e diga a ele para nao mandar o outro para ninguem.
goto :fim
:publica
set "TIPO="
set "BLOB="
for /f "usebackq tokens=1,2" %%a in ("%PUB%") do if not defined TIPO (
    set "TIPO=%%a"
    set "BLOB=%%b"
)
set "VALIDO="
for %%t in (ssh-ed25519 ssh-rsa ecdsa-sha2-nistp256 ecdsa-sha2-nistp384 ecdsa-sha2-nistp521) do if "%TIPO%"=="%%t" set "VALIDO=1"
if not defined VALIDO goto :invalido
echo %BLOB%| findstr /r /x "AAAA[A-Za-z0-9+/=]*" >nul
if errorlevel 1 goto :invalido

set "NOME="
set /p "NOME=Nome do amigo, so letras e numeros: "
if not defined NOME goto :fim
echo %NOME%| findstr /r /x "[A-Za-z0-9_]*" >nul
if not errorlevel 1 goto :nomeOk
echo ERRO: use so letras, numeros ou _ no nome.
goto :fim
:nomeOk

rem the line goes by stdin: no quotes to escape on the way. "restrict"
rem takes away the shell and forwarding; whatever the friend asks, sshd
rem runs the command= (the bat's update) and nothing else
set "LINHA=%TEMP%\mythos-amigo-%RANDOM%.txt"
> "%LINHA%" echo restrict,pty,command="cd /opt/brevesot && bash tools/deploy/update-server.sh && git log -1 --oneline" %TIPO% %BLOB% mythos-amigo-%NOME%
echo == autorizando %NOME% na VPS
rem the file must end with a newline before the append (or the last key,
rem yours, would be cut); the name's old key goes; a key that already gets
rem in is not touched
ssh -i "%CHAVE%" %VPS% "sed -i -e '$a\' %AK% && sed -i '/ mythos-amigo-%NOME%$/d' %AK% && if grep -qF '%BLOB%' %AK%; then echo 'ERRO: essa chave ja entra na VPS - nao e a sua?'; exit 1; fi && tr -d '\r' >> %AK% && echo OK" < "%LINHA%"
if errorlevel 1 (
    del "%LINHA%" >nul 2>&1
    echo.
    echo Parou com erro. Copie as linhas acima e mande.
    goto :fim
)
del "%LINHA%" >nul 2>&1
echo.
echo Pronto: %NOME% ja pode rodar o atualizar-servidor.bat no PC dele.
echo A chave dele so atualiza o servidor; nao entra na VPS nem compila.
echo Para tirar o acesso: autorizar-amigo.bat remover %NOME%
goto :fim

:invalido
echo ERRO: %PUB% nao parece uma chave publica SSH. Peca ao amigo o baiak.pub
echo que o atualizar-servidor.bat criou na pasta .ssh dele.
goto :fim

:listar
ssh -i "%CHAVE%" %VPS% "echo '== amigos que podem atualizar o servidor:'; grep -o 'mythos-amigo-[A-Za-z0-9_]*' %AK% | sed 's/^mythos-amigo-/   /'; true"
goto :fim

:remover
set "NOME=%~2"
if not defined NOME (
    echo Uso: autorizar-amigo.bat remover NOME
    goto :fim
)
echo %NOME%| findstr /r /x "[A-Za-z0-9_]*" >nul
if not errorlevel 1 goto :removerOk
echo ERRO: nome invalido: %NOME%
goto :fim
:removerOk
ssh -i "%CHAVE%" %VPS% "if grep -q ' mythos-amigo-%NOME%$' %AK%; then sed -i '/ mythos-amigo-%NOME%$/d' %AK% && echo 'acesso de %NOME% removido'; else echo '%NOME% nao estava autorizado'; fi"

:fim
echo.
pause
