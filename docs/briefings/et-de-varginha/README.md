# ET de Varginha - briefing de arte

`gerar/` monta o pacote para o designer (`ET de Varginha - briefing v1.zip`,
que não fica no repositório: `*.zip` está no `.gitignore`): o chefe do meme,
com sprites, arena, loot e as 7 magias (o golpe final é BUSQUEM CONHECIMENTO),
no mesmo formato das Magias do Renascimento.

Para gerar (`gerar/et_spec.py` é a fonte única; diagramas, referências e
estilo vêm de `../magias-do-renascimento/gerar/`):

    python3 gerar/et_build.py <pasta de saída>
    node ../magias-do-renascimento/gerar/pdf.js "<pasta de saída>/ET de Varginha - briefing v1"
    cd <pasta de saída> && zip -qr "ET de Varginha - briefing v1.zip" "ET de Varginha - briefing v1"
