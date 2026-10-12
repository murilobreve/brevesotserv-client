# Muros e balcões — obsidiana nativa

Um PNG RGBA por peça, na pasta `pecas/`. As peças foram recoloridas diretamente nos pixels das referências, sem ampliar, reduzir, girar, recortar ou mudar a geometria. A máscara alfa de cada peça é idêntica à referência: somente 0 e 255, sem pixels semitransparentes e sem borda suavizada. A luz de cima à esquerda e os planos de topo, frente e lateral das referências foram preservados.

A paleta usa preto/ grafite, roxo escuro e reflexos dourados pontuais. As variações 02 usam menos roxo; as 03 usam mais roxo. Todas mantêm exatamente a mesma forma e tamanho.

## Peças e referências

| PNG | Medida | Referência do ZIP |
| --- | --- | --- |
| horizontal_01.png | 64 × 64 | 01_horizontal_49282 |
| vertical_01.png | 64 × 64 | 02_vertical_49288 |
| canto.png | 64 × 64 | 03_canto_49294 |
| ponta.png | 64 × 64 | 04_ponta_49297 |
| horizontal_baixo.png | 64 × 64 | 05_horizontal_baixo_49298 |
| vertical_baixo.png | 64 × 64 | 06_vertical_baixo_49299 |
| janela_horizontal.png | 64 × 64 | 07_janela_49655 |
| balcao_vertical.png | 64 × 32 | 08_balcao_vertical_2317 |
| balcao_horizontal.png | 64 × 32 | 09_balcao_horizontal_2318 |
| balcao_ponta_a.png | 32 × 64 | 10_balcao_ponta_a_2320 |
| balcao_ponta_b.png | 32 × 64 | 11_balcao_ponta_b_2321 |
| horizontal_02.png / horizontal_03.png | 64 × 64 | Variações de 01_horizontal_49282 |
| vertical_02.png / vertical_03.png | 64 × 64 | Variações de 02_vertical_49288 |

O balcão vertical também tem 64 × 32, conforme a tabela e o PNG original fornecidos. As pontas são 32 × 64. A orientação visual da peça não deve ser confundida com a orientação do canvas; não girar as imagens para mudar as medidas.

## Tile dono e colocação

O tile dono é sempre o quadrado de 32 × 32 no canto inferior direito:

| Canvas | Origem do tile dono dentro do PNG |
| --- | --- |
| 64 × 64 | x=32, y=32 |
| 64 × 32 | x=32, y=0 |
| 32 × 64 | x=0, y=32 |

Preserve o canvas e os espaços transparentes originais. Não centralize nem faça trim automático. Use o posicionamento das peças de referência para os novos itens. Os IDs no quadro identificam as referências; não são IDs novos atribuídos às artes entregues.

Para visualizar numa montagem, se `(X,Y)` for o canto superior esquerdo do tile dono no mapa e `(W,H)` forem as medidas do PNG, desenhe a imagem em `(X - (W - 32), Y - (H - 32))`. Vizinhos no eixo X ou Y ficam a 32 pixels de distância. Esta fórmula segue o tile dono descrito nas referências e serve para reproduzir as prévias; a importação usa o sistema de posicionamento do seu cliente.

## Conferência de encaixe

`previews/sala_5x4_novo_1x.png` monta um interior de 5 × 4 tiles com o canto, os muros horizontal e vertical e suas pontas. O canto tem tile dono (1,1); os horizontais ficam em (2,1) a (6,1), com ponta em (7,1); os verticais ficam em (1,2) a (1,5), com ponta em (1,6). É uma montagem em L, seguindo o exemplo enviado.

A mesma montagem foi feita com os sprites originais em `sala_5x4_referencia_1x.png`. As duas máscaras alfa são idênticas pixel a pixel: a troca de arte não acrescenta nem remove vãos ou sobreposições em relação às referências. Há também uma prévia com o piso aprovado.

Os arquivos `*_zoom.png` são apenas prévias ampliadas por vizinho mais próximo. Os sprites importáveis estão exclusivamente em `pecas/` e nunca foram redimensionados.

`manifesto.json` registra medidas, referência, coordenadas do tile dono, paleta, contagem dos reflexos dourados e verificações. As referências originais e a máscara de encaixe orientaram esta entrega; não foi realizada importação no cliente do jogo.
