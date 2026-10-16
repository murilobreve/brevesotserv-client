# Pisos escolhidos para Ventera

Do pacote "Mythos, pisos de templo e cidade" (16 variações por tipo) entraram dois tipos. Só eles estão nesta pasta,
com o LEIA-ME, o manifesto e os catálogos do pacote.

| Tipo do pacote | Item | Pasta da arte | Onde fica |
| --- | --- | --- | --- |
| `templo/01_placas_pretas` | 60001 (obsidian floor) | `art/obsidian_floor` | o salão do templo de Ventera, 561 quadrados |
| `cidade/04_pedra_grafite` | 60004 (obsidian paving) | `art/obsidian_city_paving` | as ruas de Ventera, 2.468 quadrados |

## Por que estes

- **Templo, placas pretas:** preto calmo com facetas suaves e pontos dourados, sem moldura de placa. O caminho roxo
  (60002, obsidiana incrustada) e a runa de chegada (60003) continuam sendo o que se destaca. As placas roxas mostravam
  as juntas dos blocos de 4x4 quadrados, as mistas ficavam agitadas demais, e o pavimento retangular parecia calçada de
  rua, não piso de templo.
- **Cidade, pedra grafite:** escura como o calçamento irregular de obsidiana (60005, 412 quadrados) que fica nas
  mesmas ruas, então as duas se encontram sem emenda, e combina com o templo. Pedra envelhecida e terracota, claras,
  faziam uma borda dura contra o 60005; o arenito se confundia com o chão das casas.

As prévias foram montadas com o mapa `Baiak.otbm` do servidor, com os itens de verdade em volta.

## Como as 16 peças entram

O cliente desenha um chão 4x4 pela posição do quadrado (x % 4, y % 4): as 16 peças se repetem a cada 4 quadrados, sem
sorteio. Os pesos do `pesos.csv` não se aplicam: cada peça aparece uma vez a cada 16 quadrados. Para as peças mais
marcadas não se tocarem, `import_floor_pack.py` põe 13 a 16 em quadrados a duas casas um do outro e 9 a 12 na
diagonal entre eles, também através da repetição.

Os itens e os ids de sprite não mudam: o mapa e o servidor seguem iguais, só a arte da folha de chãos muda.

## Faltou do pacote

O ZIP recebido estava cortado no fim. Os PNGs dos dois tipos escolhidos chegaram inteiros. O tipo 05 do templo
(pavimento irregular) e as prévias de mistura do tipo 04 se perderam, então o 05 não foi avaliado.

## Refazer

```
python3 import_floor_pack.py
protoc --python_out=. -I ../../src/protobuf appearances.proto
python3 build_mounts.py ../../data/things/custom <servidor>/data/items/appearances.dat
```
