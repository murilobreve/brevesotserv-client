# Repositório de atualização (murilobreve/mythos-client)

O atualizador do client (`modules/client_updater`) baixa tudo do repositório
público `murilobreve/mythos-client`, que o `tools/publicar-atualizacao.ps1`
monta a cada versão:

```
objects/<sha256>          o conteúdo de cada arquivo publicado, pelo SHA-256
<canal>/manifest.json     caminho -> sha256 e tamanho, o número da versão e os arquivos que saíram
<canal>/versao.json       só o número da versão (o client aberto lê só ele a cada meia hora)
```

Os canais são `directx` (o client do site) e `opengl`.

## Como ele cresce

- Cada publicação copia para `objects/` todo arquivo que mudou. Nada é
  apagado: o `objects/` guarda todas as versões já publicadas, e o histórico
  do git também.
- O que pesa é o `.exe`: cerca de 41 MB por publicação que muda o C++
  (DirectX; o OpenGL tem uns 32 MB). Uma versão que só muda Lua, OTUI ou
  imagens soma poucos KB.
- Medido na cópia de 01/11 (directx v81, opengl v2): 4.277 objetos, 592 MB
  em `objects/`, 12 cópias do `.exe`. 450 MB desses objetos não são usados
  por nenhum dos dois manifests atuais. O pack do git tinha 172 MB.

Limites do GitHub a acompanhar:

| Limite | Valor | Situação |
|---|---|---|
| Tamanho recomendado do repositório | 1 GB (5 GB no máximo) | longe: cada `.exe` novo soma ~10-15 MB ao pack |
| Aviso por arquivo | 50 MB | o `.exe` tem ~41 MB e cresce (o chat de voz soma bibliotecas) |
| Bloqueio por arquivo | 100 MB | um push com um arquivo maior é recusado |

Para os jogadores o tamanho do repositório não importa: o client baixa só os
objetos que mudaram entre a versão dele e a nova. Quem sente é quem publica:
o `publicar-atualizacao.ps1` (e o `atualizar-jogadores.bat`, no PC de quem
ajuda) clonam o repositório inteiro, e os pushes ficam mais lentos.

## Por que apagar objetos do main é seguro

O client nunca baixa de `main/` quando a API do GitHub responde: ele pega o
commit do main e baixa os arquivos daquele commit
(`raw.githubusercontent.com/<sha>/...`). Um objeto apagado do main continua
existindo nos commits antigos, então um client que estava no meio de uma
atualização termina normalmente. Só as tentativas finais de cada arquivo (a
4ª em diante, depois de três falhas) vão por `main/` e deixariam de achar um
objeto apagado. Numa falha comum a 4ª é a última; quando o GitHub responde
429 ou 5xx o client tenta até 6 vezes, então até 3 tentativas de um arquivo
passam por `main/`. Um 404 ali encerra o download na hora: a tela de login
mostra "Atualizar agora" e o client tenta de novo na próxima vez que abrir.

Reescrever o histórico (squash) é diferente: os commits antigos deixam de
existir no main e, depois que o GitHub limpa os commits soltos, um client
preso a um deles recebe 404 até reabrir. Por isso o squash é raro e feito
longe de uma publicação.

## Política

1. **A cada 5 publicações (ou quando `objects/` passar de 800 MB): podar.**
   Apagar de `objects/` todo arquivo que não está no `manifest.json` atual de
   nenhum canal nem nos manifests das 2 versões anteriores de cada canal.
   Os commits que mudaram um manifest saem de
   `git log --format=%H -- <canal>/manifest.json`, e cada versão antiga de
   `git show <sha>:<canal>/manifest.json`. Isso precisa do histórico: podar
   num clone completo, ou primeiro buscar commits suficientes
   (`git fetch --deepen=20`, ou `git fetch --unshallow`). Commitar como
   `podar objects (versao N)` e dar push. Não precisa esperar nada: os commits
   antigos continuam com os arquivos, e as 2 versões anteriores cobrem um
   client que leu um manifest de `main/` ainda no cache (até 5 minutos).
2. **Quando o pack passar de 600 MB: recomeçar o histórico.** Depois de podar,
   criar um commit órfão com a árvore atual (`git checkout --orphan novo`,
   `git add -A`, `git commit`, `git branch -M novo main`,
   `git push --force origin main`). Fazer de madrugada e pelo menos 30 minutos
   depois da última publicação. Avisar quem publica para apagar o clone local
   (`%USERPROFILE%\mythos-client`) e deixar o script clonar de novo.
3. **Se o `.exe` passar de 45 MB:** antes do aviso de 50 MB do GitHub,
   publicar o `.exe` compactado com LZMA. O C++ já descompacta
   (`ResourceManager::writeDownloadedFile` com `decompressLzma`), mas o
   atualizador ainda não usa: é preciso marcar o arquivo no manifest
   (por exemplo `"lzma": true`) e ligar a descompactação no
   `installDownloadedFileInWorkDir` antes de publicar assim.
4. **Clone raso só para publicar.** Um `git clone --depth 1` basta para o
   `publicar-atualizacao.ps1` (ele só lê o manifest atual e acrescenta
   objetos), e evita baixar o histórico inteiro no PC de quem publica. Para
   podar (passo 1) esse clone não serve como está: ele não tem os manifests
   antigos. Busque o histórico antes (`git fetch --deepen=20`) ou pode num
   clone completo.

## Conferir depois de podar ou recomeçar

- `git count-objects -vH` no clone: `size-pack` deve cair.
- Abrir um client da versão anterior com `MYTHOS_UPDATE_URL` vazio: ele deve
  atualizar normalmente para a versão atual.
- Abrir um client já atualizado e clicar em "Verificar" na tela de login: o
  log deve dizer `file check (full): 0 to repair`.
