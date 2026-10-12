# Mythos — revisão visual do cliente

58 PNGs redesenhados, todos com o **mesmo nome, tamanho, borda fixa e ordem dos quadros** do kit recebido. A pasta `3-janelas-extras/frames.png` não foi incluída: continue usando a original. As cores das raridades foram preservadas.

## O que mudou

- Fundos em obsidiana escura mais neutra, com o miolo liso para leitura e esticamento.
- Molduras finas, luz no topo/esquerda e pequenos detalhes de ouro antigo.
- Violeta concentrado no foco, seleção e estado ligado.
- Botão principal em pérola quente, compatível com o texto escuro atual.
- Ícones funcionais com contorno e facetas; marca Mythos de espada alada na barra.
- Auto Loot: a escolha da bolsa fica representada por uma bolsa com confirmação, em vez das setas cruzadas pouco claras; remoção continua sendo X.

**As peças de produção foram desenhadas diretamente no tamanho final.** Não foram reduzidas de imagens grandes. São PNGs RGBA com alpha 0 ou 255, sem suavização ou texto. A ampliação do catálogo e das folhas de comparação usa nearest-neighbor apenas para visualização.

## Instalação das imagens

1. Faça backup das imagens atuais.
2. Troque somente os arquivos correspondentes das pastas `1-tema`, `2-icones-painel` e `3-janelas-extras`.
3. Em `1-tema`, as referências do estilo recebido apontam para `/images/mythos/<nome>`.
4. Os arquivos `2-icones-painel/botao-barra-*.png` correspondem a `modules/game_<nome>/images/button.png`, conforme seu LEIA-ME. Confira o nome real de cada módulo antes de copiar. `2-icones-painel/button.png` é a marca do painel Mythos. Os ícones das linhas devem substituir suas referências atuais; seus caminhos não aparecem no estilo fornecido.
5. Em `3-janelas-extras`, substitua os seis arquivos pelo caminho usado no módulo atual. Mantenha `frames.png` original.
6. Reabra o cliente ou use o procedimento de recarga de imagens do projeto para evitar textura antiga em cache.

Não há alteração de tamanho nem de `image-border`. Para aplicar apenas as imagens, **não é necessário trocar o OTUI**.

## Estilo opcional

`dev/estilos-50-breves-proposta.otui` é uma cópia do estilo enviado com ajustes somente de cores: títulos mais quentes, texto secundário mais legível e halo coerente com a nova paleta. Mantém tamanhos, padding, clips, estados, classes e fontes.

Compare com a versão atual do projeto antes de integrar. Ele é opcional e não muda a posição dos widgets. Não carregue duas definições concorrentes das mesmas classes.

## Layouts propostos

Os arquivos de `previews/` são **composições de proposta**, construídas sobre seus prints com as peças novas e um simulador 9-slice. Não são capturas do cliente rodando com as alterações. Textos e alguns campos são ilustrativos.

- `01-hunt-board-proposta.png`: dados agrupados, seleção mais evidente e XP/loot sem cores de erro. A coluna de dificuldade é uma sugestão que exige uma regra real do servidor; os níveis mostrados são exemplos, não uma avaliação dos monstros.
- `02-rarity-market-proposta.png`: preço e atributos bem separados, detalhes do item e ação de compra clara. O mecanismo real de entrega e confirmação deve seguir o servidor.
- `03-heal-bot-proposta.png`: prioridade, regras, valor percentual e estado ligado legíveis. Preserve o momento real em que as mudanças são aplicadas e os controles de magia/tipo existentes.
- `04-icones-antes-depois.png`: comparação dos ícones, ampliada apenas para inspeção.
- `05-teste-9-slice.png`: demonstração dos cantos e campos em diferentes tamanhos.
- `06-painel-mythos-proposta.png`: mini painel com marca, funções e indicadores. É um recorte de proposta; conserve todas as categorias e funções do painel completo.

Para aplicar a **reorganização dos layouts**, o dev precisa editar os OTUI/Lua de cada janela. Esses arquivos não vieram no ZIP; por isso o pacote inclui orientações, não substituições inventadas das janelas.

## Bordas e quadros — sem alterações

| Peça | Dimensões | Borda / quadros |
| --- | --- | --- |
| Window | 256×256 | laterais/base 6; topo 30 |
| Section | 64×64 | laterais/base 4; topo 21 |
| Panel, panel_on, notice | 32×32 | 4 |
| Well / popup | 32×32 | 3 / 2 |
| Input / input_focus | 32×22 | 3 |
| Botões escuros e pérola | 64×22 | 4; quatro arquivos de estado |
| Abas | 64×24 | 2; base 2 |
| Combobox | 91×60 | 3; direita 20; três estados 91×20 empilhados |
| Scroll track vertical/horizontal | 10×32 / 32×10 | 2 |
| Scroll thumb vertical/horizontal | 10×24 / 24×10 | 4 |
| Scroll arrows | 20×20 | quatro quadros 10×10 na ordem original |
| Fold | 8×8 | sem borda |
| Gemas | 12×12 | sem borda |
| Marca / botões da barra | 40×20 | normal e ligado 20×20, lado a lado |
| Ícones do painel | 16×16 | sem borda |
| Change, improve, reroll | 14×14 | sem borda |
| Choose, remove | 20×40 | normal e hover 20×20, empilhados |
| Container | 7×9 | sem borda |

`dev/manifesto.json` registra dimensões, bordas, estados e SHA-256 de cada imagem. Não modifica o contrato original.

## Validação feita

- 58 nomes e dimensões comparados com o ZIP recebido.
- PNG RGBA, sem pixels de transparência intermediária.
- Silhuetas idênticas entre estados de botão e entre os quadros de cada atlas.
- Miolos dos fundos e controles conferidos como lisos; ornamentos dentro das faixas fixas.
- Teste local de renderização 9-slice, com exemplos visuais e verificação de cantos.
- Dimensões, clips e bordas do OTUI opcional comparados ao arquivo original.
- **Não testado dentro do OTClient.** O renderer real, cache, fontes e textos traduzidos precisam de uma conferência no jogo.

## Paleta

| Uso | Cor |
| --- | --- |
| Corpo obsidiana | #191821 |
| Título / listas | #101018 |
| Cartão | #21202B |
| Seleção | #2C2540 |
| Aro discreto | #5E5261 |
| Ouro antigo | #B69A60 |
| Luz dourada | #EBD7A1 |
| Halo | #B296F5 |
| Botão pérola | #DFD5BE |
| Texto principal proposto | #EBE7EF |
| Texto secundário proposto | #B4AFC3 |

## Regeneração

O fonte `dev/redesenhar.py` acompanha o pacote. Usa Pillow e os arquivos extraídos do ZIP original; DejaVu é usado apenas para textos dos catálogos/propostas. As imagens de produção não precisam de fonte.

```bash
python dev/redesenhar.py --reference /caminho/mythos-ui-kit --output /caminho/saida
```

O script usa a pasta DejaVu padrão do Linux para gerar os previews. Em outro sistema, ajuste `F` para a pasta equivalente. Ele exige Pillow com `get_flattened_data()`; ou adapte essa chamada para `getdata()` numa versão anterior. Guarde o ZIP original como referência e backup.
