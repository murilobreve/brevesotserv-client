# Ascensão — artes v2 · briefing

`gerar/` monta o pacote para o designer (`Ascensao - artes v2 - briefing v1.zip`,
que não fica no repositório: `*.zip` está no `.gitignore`): as 15 magias que a
Ascensão ensina e a Translocação, refeitas para ficarem mais grandiosas e
suaves a 60 fps com poucas imagens — camadas paradas que o jogo anima por
curvas, flipbooks curtos com mistura de frames, partículas e luz. Inclui a
Flecha do Crepúsculo com a puxada do arco (mudança de jogo).

Para gerar (`gerar/asc_spec.py` é a fonte única; o estilo e as referências vêm
de `../magias-do-renascimento/gerar/`):

    python3 gerar/demo60.py ../magias-do-renascimento/<fundo 448x448>.png conceito.mp4 <pasta temporária>
    python3 gerar/asc_build.py <pasta de saída> conceito.mp4
    node ../magias-do-renascimento/gerar/pdf.js "<pasta de saída>/Ascensao - artes v2 - briefing v1"
    cd <pasta de saída> && zip -qr "Ascensao - artes v2 - briefing v1.zip" "Ascensao - artes v2 - briefing v1"

O vídeo conceito precisa de numpy e ffmpeg; um fundo de teste sai do gerador
das Magias do Renascimento (`fundos_de_teste/terra.png`).

## Etapa 1 no jogo

A Etapa 1 (Salto do Titã, Flecha do Crepúsculo, Meteoro, Muralha Glacial e
Chute do Dragão) está em `modules/game_skillshot/images/<magia>/`, com o
`curvas.csv` e o `particulas.csv` do designer como vieram. O cliente lê as
curvas (`modules/game_skillshot/layers.lua`) e o motor as anima no
`draw()` do `AttachedEffect` (curvas, âncora, giro, espelho, brilho aditivo,
quadros pelo tempo, partículas) e treme o mapa (`UIMap:shake`). Uma
entrega nova da mesma magia é só trocar os arquivos da pasta. A Flecha
ganhou a puxada do arco (0,4 s) e o voo de 30 ms por sqm em
`scripts/skillshot/paladin.lua` do servidor.

## Etapa 2 no jogo

As outras dez magias e a Translocação estão em
`modules/game_skillshot/images/<magia>/`, também com o `curvas.csv` e o
`particulas.csv` como vieram. O que a Etapa 2 pediu além da Etapa 1 está em
`layers.lua`: o projétil que o servidor move sqm a sqm (`set.flight`: a
cabeça, os ecos e o rastro seguem os passos), o rastro e o feixe esticados
(curva `estica`), a carga que cresce até cheia e fica cheia até soltar
(`set.held`) e a cor da luz do mapa tirada do `cor_luz` do designer
(`layerLight`). A Translocação ganhou o fx `transloc` (servidor:
`scripts/ascensao/06_sorcerer.lua`). As prévias estáticas da janela
(`modules/game_ascensao/images/previas/`) são as do designer, com o nome da
magia.

O Meteoro saiu da arte v2: o dono do servidor quis uma magia com a cara do
Tibia e leve para a placa de vídeo. O servidor o desenha com os efeitos do
próprio Tibia (fumaça vermelha na área 3x3, a rocha grande caindo com bolas
de fogo, a explosão da Great Fireball e as chamas no chão) e a prévia da
janela da Ascensão é um quadro desses sprites.
