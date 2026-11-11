# Mythos Voz no client Windows (DirectX)

O client do Windows agora tem a voz completa, com áudio, igual à do
navegador: microfone, alto-falantes, push-to-talk, ativação por voz, teste de
microfone, volumes por jogador e por sala. Até aqui o Windows só tinha o modo
"presença" (via quem está na sala, sem som).

Como funciona por dentro, em uma linha: o Opus (libopus) codifica a voz, o
OpenAL capta o microfone e toca a voz num dispositivo próprio (o som do jogo
não é mexido), e o ixwebsocket conversa com o relay de voz. Tudo roda numa
thread só, chamada `voz`, que só nasce quando a voz é usada. Detalhes para
programador: `src/framework/voice/voiceengine_native.h`.

## 1. Compilar

Na pasta do client, no Windows:

```
compilar-cliente-directx.bat claude/exciting-cannon-uceou6
```

(ou `compilar-cliente-directx.bat main`, depois que esta branch entrar no
main).

- **O vcpkg baixa e compila o Opus sozinho.** O `vcpkg.json` ganhou a
  dependência `opus` (versão 1.5.2, licença BSD, uns 400 KB no `.exe`). A
  primeira compilação demora uns minutos a mais por isso; as seguintes não.
- **Não precisa do `limpo`.** Uma pasta de build antiga guardava a voz
  desligada no Windows; o CMake liga uma vez sozinho. Se algo der errado,
  rode de novo com `limpo` no fim:
  `compilar-cliente-directx.bat claude/exciting-cannon-uceou6 limpo`.
- **Como saber que a voz entrou:** na parte "configurando" aparece a linha
  `Enabled: Voice: native engine (libopus, OpenAL, ixwebsocket)`.
- **Se o vcpkg reclamar de "baseline"** (versão do vcpkg muito velha para o
  `builtin-baseline` do projeto): `git -C C:\vcpkg pull` e compile de novo.
- **Para compilar sem voz** (só se a compilação da voz falhar e você
  precisar do `.exe` hoje). O `.bat` não aceita opções do CMake, então é um
  passo à mão, uma vez só:
  1. Abra o **"x64 Native Tools Command Prompt for VS"** (menu Iniciar,
     pasta do Visual Studio).
  2. Rode, trocando o caminho pela pasta do client:
     ```
     cd /d C:\caminho\do\client
     set VCPKG_ROOT=C:\vcpkg
     cmake --preset windows-release-directx -DTOGGLE_FRAMEWORK_VOICE=OFF
     ```
  3. Rode o `compilar-cliente-directx.bat <branch>` de novo, normalmente,
     **sem** `limpo`. A escolha fica guardada na pasta de build e o client
     sai igual ao de antes (modo presença).

  Para a voz voltar: o mesmo comando com `-DTOGGLE_FRAMEWORK_VOICE=ON`, ou
  rode o `.bat` uma vez com `limpo` no fim. Se o erro for só na parte do
  áudio, `-DVOICE_NATIVE=OFF` no lugar do `TOGGLE_FRAMEWORK_VOICE` também
  serve (o client fica sem áudio da voz, como com `OFF`).

  Isso vale para erro na parte "compilando". Se o erro vier na parte
  "configurando", com `vcpkg install failed` ao compilar o `opus`, o
  comando do passo 2 falha do mesmo jeito (o vcpkg roda antes de o CMake
  ler a opção). Nesse caso, no passo 2 rode:
  ```
  cmake --preset windows-release-directx -DTOGGLE_FRAMEWORK_VOICE=OFF -DVCPKG_MANIFEST_INSTALL=OFF
  ```
  Ele usa as bibliotecas que o vcpkg já tinha na pasta de build (as do
  build anterior continuam lá, se o Visual Studio e o vcpkg não foram
  atualizados desde aquele build; se foram, o vcpkg apaga as bibliotecas
  para compilar de novo, e esse comando para com erro de biblioteca não
  encontrada: me avise). Depois o passo 3 igual, **sem** `limpo`.
  Para a voz voltar, aí só o `.bat` com `limpo` no fim (o
  `-DTOGGLE_FRAMEWORK_VOICE=ON` não serve nesse caso). Se o PC tiver a
  variável `CANARY_SHARED_CACHE_ROOT`, esse comando para com erro na hora:
  me avise.

Mandar o `.exe` para os jogadores é o mesmo de sempre (o `.bat` pergunta se
publica). Enquanto a voz estiver liberada só para a staff no servidor (item
2), os jogadores não veem nada de novo.

## 2. Ligar a voz para a staff no servidor

A voz fica **desligada no servidor até existirem a chave e o endereço do
relay**. Sem os dois, o canary responde "voz desligada" e não toca no banco.

| O quê | Onde fica na VPS |
|---|---|
| chave (64 caracteres hexadecimais, a mesma do relay) | `/etc/mythos/voz.key` |
| endereço do relay | `/etc/mythos/voz.url`, por exemplo `wss://mythosot.com.br:7190/voz` |

O relay é o programa `mythos-voz` (`tools/voz` no repositório do servidor;
como compilar, rodar e as portas estão no `tools/voz/README.md` de lá). Ele usa
a mesma chave e o certificado do site (Let's Encrypt) na porta 7190, que
precisa estar liberada no firewall da VPS (TCP de entrada).

Com o relay rodando e os dois arquivos no lugar:

1. `/reload scripts` no jogo (ou reinicie o servidor). O log do canary deve
   mostrar `[Voz] voice ready: relay wss://...`. Se mostrar
   `[Voz] voice is off: ...`, o motivo vem escrito na mesma linha.
2. No jogo, com um personagem da staff: `/voz status` mostra se a voz está
   ligada, quem está usando e os números do relay.
3. **Quem pode usar:** `/voz acesso staff` (o padrão) libera só para a staff
   (tutor para cima). `/voz acesso all` libera para todos. A escolha fica
   salva e sobrevive a reinícios.
4. `/voz off` desliga tudo na hora (todos saem da voz); `/voz on` liga de
   novo.

Os outros comandos (`mute`, `kick`, `ban`, `falar`, `calar`) estão no
`data-otservbr-global/scripts/voice/README.md` do servidor.

## 3. Roteiro de teste no Windows

Faça com um personagem da staff, com fone de ouvido. Se puder, tenha uma
segunda pessoa (ou o client do navegador em `/play`) na mesma party.

1. **Testar microfone**, no painel de voz: fale e ouça a própria voz
   (local, sem passar pelo servidor). Depois o **Teste de eco**: a voz volta
   pelo relay depois de 1,5 s.
2. **Listas de dispositivos** (engrenagem do painel): o microfone e a
   "Saída de som" mostram os dispositivos do Windows. Troque para outro
   (um fone USB, por exemplo) e confirme que a voz vai para ele enquanto o
   som do jogo continua nas caixas. Tirar o fone USB com a voz ligada não
   pode travar nada: a voz volta no dispositivo padrão.
3. **Push-to-talk:** segure a tecla de "Falar na party" e fale; a outra
   pessoa ouve, e o ícone de quem fala acende para os dois. Solte: para na
   hora.
4. **Ativação por voz** (configurações da voz): fale sem apertar nada; o
   microfone abre sozinho e fecha uns 0,3 s depois que você para. Fora de
   qualquer sala, ela não abre o microfone.
5. **Alt+Tab solta o push-to-talk:** segure a tecla, aperte Alt+Tab e veja
   que parou de transmitir.
6. **Falar com o jogo minimizado** (opção "Falar com o jogo minimizado" nas
   teclas): com ela ligada, a tecla de "Falar na party" funciona até com o
   jogo minimizado ou com outra janela na frente. Funciona com letras,
   números, F1 a F24 e Espaço. Segurar mais de 60 s solta sozinho.
   - Com a janela do jogo na frente vale a tecla normal do jogo (que
     respeita o modo de chat: digitar a letra no chat do jogo não abre o
     microfone).
   - Com **outro programa** na frente, a tecla vale sempre: se for uma letra,
     digitar essa letra no Discord ou no navegador abre o microfone na party.
     Por isso, para essa opção, prefira uma tecla que não se digita (F9 a
     F12, por exemplo).
   - Com **outro client do jogo** na frente (dois personagens abertos), vale
     a tecla daquele client: o de trás não transmite junto.
   - Trocou a tecla nas opções? A nova passa a valer no minimizado depois
     de apertá-la uma vez dentro do jogo (ou na próxima conexão da voz).
   - Teste: com outra janela na frente, segure a tecla e fale; com o chat
     do jogo aberto, digite a letra: não pode transmitir.
7. **Client minimizado continua com áudio:** minimize o jogo e peça para a
   outra pessoa falar; você continua ouvindo.
8. **Queda e volta:** `/voz off` (e depois `/voz on`), ou pare o relay na
   VPS por um minuto: o painel mostra que caiu, tenta de novo sozinho com
   espera crescente e volta quando o relay volta.
9. **Gerenciador de Tarefas**, aba Detalhes, `otclient.exe`: falando, a
   memória sobe no máximo uns 5 MB em relação a antes de ligar a voz, e a
   CPU fica em até uns 2%.
10. **Indicador de microfone do Windows** (ícone na barra de tarefas): no
    push-to-talk, ele aparece ao apertar a tecla e some uns 10 s depois de
    soltar. Na ativação por voz, ele fica enquanto você está conectado numa
    sala e sem o microfone silenciado. Com o painel de configurações aberto o
    medidor de nível também usa o microfone.
11. **Firewall:** o Windows não pode pedir permissão de firewall (o client só
    abre conexão de saída).
12. **Fone ligado depois:** sem entrar na voz, abra as configurações da voz
    com o fone USB desligado (o microfone mostra que não há dispositivo).
    Ligue o fone: em uns 3 s ele aparece na lista e o medidor de nível
    mexe quando você fala. O mesmo vale com o "Testar microfone" ligado.
13. **Trocar a qualidade falando** (configurações, "Qualidade": Normal ou Alta): segure a
    tecla, troque e continue falando. A outra pessoa não pode ouvir corte ou
    estalo; a nova qualidade vale a partir da próxima vez que você apertar a
    tecla.
14. **Abrir dispositivo demorado:** depois de testar, procure no log do
    client linhas `voice: opening the microphone took ... ms`,
    `voice: opening the output device took ... ms` ou
    `voice: listing the devices took ... ms`. Elas só aparecem quando passam
    de 100 ms (o Windows pode demorar com fone Bluetooth). Se aparecerem com
    mais de uns 200 ms, mande para mim: nessa hora a voz dos outros pode
    falhar por um instante, e dá para mudar isso.
15. **Perto de você (voz por proximidade):** com duas pessoas com fone, cada
    uma com o personagem na tela da outra (a poucos passos, no mesmo andar),
    as duas entram em "Perto de você" no painel e escolhem uma tecla para
    "Falar perto" (ela não tem tecla padrão). Fale com essa tecla: a outra
    pessoa ouve do lado em que o seu personagem está na tela dela (à
    esquerda, no lado esquerdo do fone) e mais baixo quanto mais longe. Ande
    de um lado para o outro falando: o som passa de um lado para o outro
    aos poucos, sem estalo. Ao mesmo tempo, a party e a guild continuam no
    meio e com o volume de sempre. Fora da tela um do outro (outro andar, ou
    longe), não se ouvem pela "Perto de você". Com fone, o OpenAL pode ligar
    o som 3D (HRTF) sozinho: o lado fica mais natural e não some de todo do
    outro ouvido; nas caixas de som, quem está bem ao lado sai só de uma.

Se algo falhar, mande: o que fez, o que esperava, e o arquivo de log do
client (as linhas que começam com `voice:`).

### Problemas comuns

- **"Voz: o microfone foi bloqueado"**: o Windows está bloqueando o
  microfone para programas. Configurações > Privacidade e segurança >
  Microfone > ligar "Permitir que aplicativos da área de trabalho acessem
  o microfone". Também acontece quando outro programa usa o microfone em
  modo exclusivo. A voz tenta de novo sozinha a cada poucos segundos; dá para
  continuar ouvindo enquanto isso.
- **Push-to-talk com o jogo minimizado não funciona** quando a janela da
  frente é de um programa aberto como administrador e o jogo não: o Windows
  esconde as teclas dessa janela. Abra os dois do mesmo jeito.
- **Eco para os outros**: é o som das caixas entrando no microfone. Use
  fone (a ativação por voz avisa isso no painel).
- **"connection failed: ... handshake" de vez em quando, logo no login**:
  no Windows o TLS do ixwebsocket é o mbedTLS do vcpkg, que desliga uma
  parte global do TLS sempre que qualquer conexão HTTPS do client fecha
  (atualizador, site). Se isso coincidir com a conexão da voz, ela falha uma
  vez e tenta de novo sozinha (na segunda tentativa usa a outra lista de
  certificados; a voz só passa a preferir uma lista depois que ela
  funcionou). Se acontecer sempre, me avise: a correção é trocar o TLS do
  ixwebsocket para OpenSSL no `vcpkg.json`, uma decisão sua porque muda
  também o HTTP do client.
- **Modo presença no Windows**: se a voz completa não puder rodar no PC
  (nenhuma saída de som que o OpenAL abra), o painel cai no modo presença,
  que hoje não conecta no relay no Windows (o relay recusa o cabeçalho
  `Origin` que o HTTP do client manda). Só acontece num PC sem áudio; ver
  com o programador se aparecer.

## 4. O que foi testado aqui, sem Windows

Num Linux, com o mesmo código da voz (`tools/voz-native-test`, que compila
os arquivos da voz sozinhos, com AddressSanitizer e UBSan):

- testes de unidade do protocolo, do buffer de jitter (ordem trocada,
  perda com ocultação, teto de 400 ms, recomeço a cada fala, volta do número
  de sequência, a sala de cada pacote) e do Opus: 45 de 45; ao todo, 28 de
  28 testes do roteiro automático;
- client nativo para `vozbot` e de volta, nativo para nativo, e nativo com o
  client do navegador (Chromium) nos dois sentidos, todos pelo relay local:
  todos os pacotes chegaram, sem buracos, e o volume da voz tocada pelo
  OpenAL ficou a menos de 1,3 dB do arquivo original;
- 5% de perda e atraso variável injetados: a ocultação cobriu as falhas;
  travadas de 0,7 s: o atraso acumulado foi descartado (nunca passou de
  160 ms no buffer);
- ativação por voz, sala vazia, limite de tamanho do relay e o teste de
  microfone com o medidor de nível;
- microfone ligado depois, sem conexão com o relay (só o medidor, ou o
  teste de microfone): abre e aparece na lista 1,5 s depois de ligado;
- trocar a qualidade falando: o mesmo codificador até o fim da fala, o novo
  na fala seguinte, sem erro de decodificação do outro lado;
- TLS com o `cacert.pem` do client e com a lista do sistema como reserva;
- fechar o jogo falando e ouvindo ao mesmo tempo: fecha em cerca de 10 ms,
  sem travar;
- "Perto de você" (sala 3), com o OpenAL de verdade gravando em estéreo: a
  voz de quem ainda não tem posição sai no meio, igual às outras salas; na
  posição -1 sai só na esquerda (mais de 80 dB de diferença), na +1 só na
  direita, com ganho 0,5 cai 6 dB; a mesma pessoa falando na party continua
  no meio; mudar a posição com a pessoa falando leva uns 50 ms, sem estalo;
  e, quando a mesma fala passa da sala 3 para a party, o lado muda junto com
  o som (não antes). Pelo relay com a sala "near": dois clients nativos que
  se veem se ouvem (com a posição), e um terceiro que o outro não vê não
  ouve nada;
- memória e CPU: +2,3 MB e 1,3% de um núcleo falando; +3,9 MB e 1,4%
  ouvindo (nesta máquina, dividida com outros programas; antes da "Perto de
  você", na mesma máquina: +2,1 MB e 1,35%, +3,8 MB e 1,36%); ouvir alguém
  na "Perto de você" com posição custa o mesmo que ouvir na party (1,26% e
  1,33% de um núcleo, +3,4 MB nos dois);
- os arquivos da voz compilam com o compilador MinGW para Windows, com os
  cabeçalhos do Windows na frente (como no build do Visual Studio).

**O que só dá para ver no Windows:** a compilação no Visual Studio de
verdade, os dispositivos reais (WASAPI), o TLS do ixwebsocket do vcpkg (que
no Windows usa mbedTLS), a tecla com o jogo minimizado (`GetAsyncKeyState`) e
o indicador de microfone. O roteiro do item 3 cobre tudo isso.
