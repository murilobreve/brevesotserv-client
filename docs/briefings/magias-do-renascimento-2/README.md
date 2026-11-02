# Magias do Renascimento, parte 2 - briefing de arte

`gerar/` monta o pacote para o designer (`Magias do Renascimento - parte 2 - briefing v1.zip`,
que não fica no repositório: `*.zip` está no `.gitignore`): mais 2 magias de chefe por tier
(Pale, Ashen, Obsidian e Lord of Death), no mesmo estilo da parte 1 (avisadas no chão,
quem lê desvia), cada uma com uma ideia de desvio que o kit ainda não tinha.

| tier | magias novas |
|---|---|
| Pale | Maré de Bruma (onda com fresta), Sopro do Véu (abrigos de vidro-do-mar) |
| Ashen | Ciranda de Brasa (varredura que gira), Pavio de Cobre (o pavio é o relógio) |
| Obsidian | Persiana de Vidro (fileiras, depois colunas), Redoma de Vidro (gaiola com porta) |
| Lord of Death | Dobre de Finados (anéis no compasso de um sino), Pesagem das Almas (metade e metade, o fiel é seguro) |

Dentro do zip: `LEIA-ME.pdf`/`.html`, `lista_de_arquivos.csv` (51 arquivos), `diagramas/`,
`referencias/` (com a etapa 1 da parte 1 como está no jogo), `fundos_de_teste/` e `entrega/`.

Para gerar (de novo depois de mudar uma magia; `gerar/spec2.py` é a fonte única, e os tiers,
o motor dos diagramas e o CSS vêm da parte 1, em `../magias-do-renascimento/gerar/`):

    /usr/bin/python3 gerar/montar.py <pasta de saída>
    node ../magias-do-renascimento/gerar/pdf.js "<pasta de saída>/Magias do Renascimento - parte 2 - briefing v1"
    cd <pasta de saída> && zip -qr "Magias do Renascimento - parte 2 - briefing v1.zip" "Magias do Renascimento - parte 2 - briefing v1"

Precisa do Pillow e da fonte Inter. O gerador lê a arte atual em `modules/` deste repositório
(ou em `CLIENT_MODULES`).
