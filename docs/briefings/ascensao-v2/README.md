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
