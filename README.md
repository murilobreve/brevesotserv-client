# Baiak Reborn - Client

Client baseado no [OTClient - Redemption](https://github.com/mehah/otclient), enxugado para conectar direto no servidor Baiak Reborn (versao 15.25).

## Trocar o IP do servidor

Edite apenas o bloco no topo do `init.lua`:

```lua
local SERVER_HOST     = "http://25.18.172.192/login.php" -- URL do login.php
local SERVER_PORT     = 80                                -- porta HTTP do login
local CLIENT_VERSION  = 1525                              -- versao do client (15.25)
```

Com um unico servidor configurado, a tela de login abre ja apontando para ele (os campos de IP/porta/versao ficam ocultos).

## Assets (sprites/sons)

Os arquivos da versao 15.25 sao baixados automaticamente na primeira execucao (modulo `client_assets`) para `data/things/1525/` e `data/sounds/1525/`.
Se preferir distribuir junto, coloque os assets do Tibia 15.25 nessas pastas.

## Compilar (Windows)

```
cmake --preset windows-release
cmake --build --preset windows-release
```

Distribua o executavel junto com: `init.lua`, `config.ini`, `otclientrc.lua`, `cacert.pem`, `data/`, `modules/` e `mods/`.
