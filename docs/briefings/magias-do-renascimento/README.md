# Magias do Renascimento - briefing de arte

`gerar/` monta o pacote para o designer (`Magias do Renascimento - briefing v1.zip`,
que não fica no repositório: `*.zip` está no `.gitignore`): as magias de
chefe (estilo Path of Exile, avisadas no chão) dos monstros Pale, Ashen, Obsidian e
Lord of Death, com o dano pela XP do monstro que renasceu.

Dentro do zip: `LEIA-ME.pdf`/`.html`, `lista_de_arquivos.csv` (114 arquivos),
`diagramas/` (os sqm de perigo de cada magia), `referencias/`, `fundos_de_teste/` e
`entrega/` (as pastas com os nomes que a arte deve ter).

Para gerar (de novo depois de mudar uma magia; `gerar/spec.py` é a fonte única):

    python3 gerar/build.py <pasta de saída>
    node gerar/pdf.js "<pasta de saída>/Magias do Renascimento - briefing v1"
    cd <pasta de saída> && zip -qr "Magias do Renascimento - briefing v1.zip" "Magias do Renascimento - briefing v1"

O gerador lê a arte atual do renascimento e dos skillshots em `modules/` deste
repositório (ou em `CLIENT_MODULES`).
