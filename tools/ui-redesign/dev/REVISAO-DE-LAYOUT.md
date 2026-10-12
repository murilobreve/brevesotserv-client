# Revisão de layout do cliente Mythos

Base: os 12 prints, os 59 arquivos de imagem e o estilo OTUI recebidos. Nenhum comportamento do cliente foi executado. O objetivo é melhorar leitura, identificação das funções e coerência entre as janelas, preservando a linguagem compacta do Tibia.

## Mudanças que já entram pela troca dos PNGs

Todas as janelas que usam o tema ganham superfícies lisas, bordas mais discretas, campos escuros separados dos cartões, botões com estados consistentes e seleção violeta. Os ícones 16×16 têm o mesmo enquadramento e nomes; os botões da barra mantêm os dois quadros.

A marca Mythos na barra foi redesenhada como uma espada alada em pixels. Não substitui automaticamente o logotipo grande do login: esse arquivo não veio no kit.

## Mudanças que exigem editar o layout

| Janela / print | Observação | Proposta concreta |
| --- | --- | --- |
| Painel Mythos — panel/pinfo | Muitas funções comprimidas; valores e ON têm pouco espaço. | Ícone em coluna fixa de 16 px, nome alinhado, valor à direita, categorias com título discreto; manter todos os atalhos. Evitar que nomes e contadores se sobreponham. |
| Hunt Board | Nome, XP, HP, dano, spawns e duas barras disputam a mesma linha. | Uma linha de nome, uma de metadados, XP/loot em coluna própria e XP calculado à direita. Usar violeta para XP, dourado para loot e vermelho somente para perigo/erro real. |
| Ranking | Duas caixas grandes vazias dominam a janela. | Estado vazio compacto e acionável; mostrar seu resultado perto do período. Últimos vencedores em lista menor. Não inventar dados quando o período ainda está vazio. |
| Task diária | Estado “nenhuma task” ocupa quase o mesmo espaço de uma task preenchida. | Ação “Pegar task” próxima da mensagem vazia; recompensa e prazo logo abaixo. Na trilha, progresso junto ao monstro e ação junto ao bloco. |
| Trilha do Caçador | Muitas linhas bloqueadas e regras em parágrafos pequenos. | Destacar a etapa atual, próximos dois destinos e marcos; preservar a lista completa com rolagem. Resumir as regras em ajuda expansível. |
| Loja de Tasks | Preço, quantidade e texto de falta de pontos não ficam agrupados. | Colocar saldo no topo, preço junto ao Comprar e explicitar unidade/duração. Desabilitar compra com motivo textual. Confirmar valores usando dados atuais. |
| Rarity Bonuses — bonus | Bônus, fontes e máximos se repetem numa composição larga. | À esquerda os itens; à direita total e limite agrupados. Mostrar origem sob cada valor e diferenciar bônus individual do total. Manter cores dos elementos. |
| Rarity Market | A lista é densa; o estado inicial dos detalhes é vazio. | Instrução inicial curta, item selecionado evidente, atributos em linhas e preço dominante. Confirmar compra pelo fluxo existente; limpar detalhes quando a seleção desaparecer. |
| Wiki | Navegação corta títulos; muito texto seguido e tabela pequena. | Painel lateral de largura suficiente ou redimensionável, busca persistente, breadcrumbs e seções curtas. Preservar as cores de tier/elemento e os sprites reais. |
| Heal Bot | Comboboxes e percentuais pequenos; prioridade depende de leitura de um aviso. | Destacar prioridade e regra ativa; alinhar magia/tipo/limiar. Rotular os percentuais e tornar ON/OFF explícito. Não remover campos essenciais que a proposta visual simplificou. |
| Auto Loot | Botões X e setas cruzadas se parecem; três painéis estreitos. | X para remover, bolsa com confirmação para escolher; labels claras para destino/obtidos. A busca de item e o painel de escolha precisam de mais largura. Preservar todas as categorias. |

O print `bonus.png` mostra “Rarity Bonuses”; não havia uma captura independente de uma roleta aleatória. Os ícones change/improve/reroll foram tratados como ações genéricas conforme seu LEIA-ME. Não foram inventadas regras de sorteio.

## Sugestão de espaçamento

- Margem interna da janela: manter 16 px, como no estilo recebido.
- Espaço entre controles: 6–8 px; entre grandes blocos: 10–12 px.
- Ícones funcionais: 16×16, sem aumentar o sprite de produção.
- Linhas simples: 22–26 px; linhas com nome/metadados: 40–56 px conforme a janela.
- Botões: manter altura 22 px e largura conforme o texto real, usando 9-slice.
- Rodapé: uma linha de explicação e ações à direita, sem colidir com a paginação.
- Título: Cinzel já existente; informações: fonte nativa atual. Os previews usam uma substituta, por isso não validam métricas da fonte real.

## Cores com função

Violeta: foco/seleção; dourado: moeda e recompensa; pérola: ação principal; verde: ligado/sucesso; vermelho: erro/perigo. Não recolorir graus de raridade, tipos elementais, sprites de itens ou monstros para combinar com o tema.

## Cuidados nas propostas visuais

A coluna “Dificuldade” do Hunt Board é opcional e ilustrativa. Deve ser calculada a partir de uma regra transparente, ligada a level, dano e resistência, ou ficar fora da implementação. Bônus alto sozinho não define a dificuldade de uma hunt.

O botão “Confirmar” do Heal Bot é uma proposta de rótulo; mantenha a semântica real do botão original. Não altere a aplicação imediata/persistência das regras sem revisar o módulo.

O Rarity Market mantém informações exemplificadas no print. Não há promessa de local de entrega, saldo atualizado ou transação funcional no preview.

## Conferência do dev no jogo

1. Abrir todas as janelas nos tamanhos reais e alternar PT/EN.
2. Testar normal, hover, pressed/on, disabled e focus, verificando ausência de salto da moldura.
3. Abrir combobox, rolar listas, arrastar sliders e expandir categorias.
4. Conferir o alinhamento dos 20×20 da barra e os estados ligados após fechar a janela.
5. Verificar tooltips, textos cortados, teclas e máscaras de raridade, sem alterar suas cores.
6. Comparar antes/depois com a mesma escala da UI e renderer do cliente. As propostas são orientação visual, não prova de funcionamento.
