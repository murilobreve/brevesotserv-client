# Baiak Mythicum - Client

Client baseado no [OTClient - Redemption](https://github.com/mehah/otclient), enxugado para conectar direto no servidor Baiak Mythicum (versao 15.25).

## Trocar o IP do servidor

Edite apenas o bloco no topo do `init.lua`:

```lua
local SERVER_NAME     = "Baiak Mythicum"                    -- nome exibido na janela e no client
local SERVER_HOST     = "http://25.18.172.192/login.php" -- URL do login.php
local SERVER_PORT     = 80                                -- porta HTTP do login
local CLIENT_VERSION  = 1525                              -- versao do client (15.25)
```

Com um unico servidor configurado, a tela de login abre ja apontando para ele (os campos de IP/porta/versao ficam ocultos).

## Configuracoes do jogador

Opcoes, hotkeys, action bars e minimapa ficam em `%APPDATA%\baiakreborn` e sao salvos automaticamente
(a cada alteracao na action bar, ao fechar as Opcoes, ao deslogar e a cada 1 minuto).

## Rarity Market

Janela propria para comprar e vender os itens de raridade (Uncommon, Rare, Epic, Legendary, Mythic) que caem dos monstros.
Abre pelo botao com o diamante no painel lateral ou com `!market` no jogo. Tem tres abas: **Navegar** (busca, filtros por tipo/raridade, ordenacao e paginas),
**Vender** (lista os itens de raridade que voce carrega; digite o preco e clique em *List for sale*) e **Minhas ofertas** (cancelar anuncios e ver o que ja vendeu).
O modulo e `modules/game_raritymarket`; ele conversa com o script `custom_market.lua` do servidor pelo extended opcode 120.

## Assets (sprites/sons)

Os arquivos da versao 15.25 sao baixados automaticamente na primeira execucao (modulo `client_assets`) para `data/things/1525/` e `data/sounds/1525/`.
Se preferir distribuir junto, coloque os assets do Tibia 15.25 nessas pastas.

## Compilar (Windows)

```
cmake --preset windows-release
cmake --build --preset windows-release
```

Distribua o executavel junto com: `init.lua`, `config.ini`, `cacert.pem`, `data/`, `modules/` e `mods/`.
