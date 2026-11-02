# -*- coding: utf-8 -*-
# Magias do Renascimento, parte 2: mais 2 magias de chefe por tier (fonte
# unica: o HTML, o CSV, os diagramas e a pasta de entrega saem daqui). Os
# tiers, as pecas comuns e as regras sao as do v1
# (../magias-do-renascimento/gerar/spec.py), que este arquivo importa.
import copy
import os
import sys

V1 = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "magias-do-renascimento", "gerar")
sys.path.insert(0, os.path.abspath(V1))

import spec as v1  # noqa: E402

F, seg, ORIENT, ref_hit, EXAMPLES = v1.F, v1.seg, v1.ORIENT, v1.ref_hit, v1.EXAMPLES

# o jogo hoje (RarityConfig.tierSpells, 00_config.lua): Pale, Ashen e Obsidian
# batem 50% mais forte que no v1 e avisam 3 s, como o Lord of Death
TIERS = copy.deepcopy(v1.TIERS)
for _t in TIERS:
    _t["mult"] = {"pale": 1.5, "ashen": 2.025, "obsidian": 2.7, "deathlord": 2.2}[_t["key"]]

# o que o kit do tier ja tem (v1) e o que as duas novas trazem
KIT = {
    "pale": {
        "ja_tem": ["Pluma do Véu (linha)", "Lágrimas de Pérola (chuva de marcas)", "Véu que se Fecha (anel)"],
        "novas": "Duas lições clássicas de chefe, ainda no ritmo calmo do Pale: achar a passagem numa onda "
                 "(Maré de Bruma) e se esconder atrás de um obstáculo (Sopro do Véu).",
    },
    "ashen": {
        "ja_tem": ["Brasa Rastejante (leque de linhas)", "Flor de Cinza (área + estrela)", "Investida Incandescente (avanço)"],
        "novas": "O Ashen continua tomando o chão: uma varredura que gira em volta dele e deixa um anel de brasa "
                 "(Ciranda de Brasa) e três cargas com pavio, em que o próprio pavio é o relógio (Pavio de Cobre).",
    },
    "obsidian": {
        "ja_tem": ["Feixe Refratado (mira que trava)", "Coroa Partida (xadrez)", "Reflexos (estátuas em cruz)"],
        "novas": "Mais dois quebra-cabeças de posição: faixas de vidro em duas fases, em que um passo na diagonal "
                 "resolve tudo (Persiana de Vidro), e uma gaiola com uma porta só (Redoma de Vidro).",
    },
    "deathlord": {
        "ja_tem": ["Garra do Eclipse (leque)", "Sol Negro (persegue)", "Colapso (puxão + círculo)", "Eclipse Total (golpe final)"],
        "novas": "O Lord ganha ritmo: um sino que dobra três vezes, cada vez mais rápido, com anéis alternados "
                 "(Dobre de Finados), e uma balança que esmaga metade do chão e depois a outra (Pesagem das Almas).",
    },
}

SPELLS = []


def spell(**kw):
    SPELLS.append(kw)


# ---------------------------------------------------------------- PALE
spell(tier="pale", key="mare", nome="Maré de Bruma", tipo="onda que varre, com uma fresta",
      conceito="O véu se ergue como uma maré de névoa e varre o chão na frente do monstro. Só uma fresta de luz "
               "de pérola fica limpa — é por ali que se passa.",
      mecanica=[
          "O monstro vira para o jogador (4 direções). Na frente dele, uma faixa de 9 sqm de largura e 8 sqm de "
          "comprimento é tomada pela névoa (forma no diagrama).",
          "Dentro dela corre de ponta a ponta uma FRESTA de 2 sqm de largura, sempre a 1–3 sqm de lado do jogador "
          "(nunca em cima dele).",
          "Aviso de 3,0 s. Então a onda rola do monstro para longe, fileira por fileira (120 ms por sqm, 1 s para "
          "cruzar), e atinge quem estiver fora da fresta quando ela passa.",
          "A onda passa por cima de tudo que não é parede. A fresta nunca fica atrás de uma parede.",
      ],
      esquiva="Andar de lado até a fresta (1 a 3 passos) e esperar a onda passar dentro dela.",
      dano="1,2 × R de gelo + Frio 3 s",
      timeline=[("aviso", 3000), ("onda", 1000), ("frio no atingido", 3000)],
      files=[
          F("aviso", 64, 64, 12, 3000, "chão", "sqm", "centro",
            "O chão tomado pela névoa, 1 sqm (a faixa inteira é essa peça repetida: emenda com as vizinhas dos 4 "
            "lados, sem costura). Relógio: começa rala, rente ao chão, e fica mais densa e mais alta; no último "
            "quarto fica cor de pérola = 'agora'. Miolo translúcido."),
          F("fresta", 64, 64, 4, "loop", "chão", "sqm", "centro",
            "O caminho seguro: chão LIMPO, um brilho calmo de pérola e 1–2 estrelinhas de 4 pontas paradas. Sem "
            "relógio e sem névoa por cima. A fresta tem 2 sqm de largura: as duas colunas usam a mesma peça, e a "
            "borda aparece sozinha pelo contraste com a névoa em volta."),
          F("onda_h", 64, 128, 6, 300, "ar", "sqm", "base",
            "A crista da maré passando pelo sqm: uma parede de névoa e plumas que sobe ~1 sqm e tomba para a frente. "
            "O jogo toca a peça na fileira inteira ao mesmo tempo e na próxima fileira 120 ms depois — tem que "
            "parecer UMA onda andando. _h = a onda anda na horizontal (para leste ou oeste). Simétrica: serve para "
            "os dois sentidos."),
          F("onda_v", 64, 128, 6, 300, "ar", "sqm", "base",
            "↑ a onda andando na vertical (para norte ou sul): a crista é uma parede deitada na horizontal."),
      ])

spell(tier="pale", key="sopro", nome="Sopro do Véu", tipo="área em volta + abrigos",
      conceito="O monstro ergue colunas de vidro-do-mar, puxa o ar e sopra um inverno em volta de si. Só a sombra "
               "das colunas fica calma.",
      mecanica=[
          "3 colunas de vidro-do-mar sobem a 2 sqm do monstro, em 3 das 8 direções (uma sempre do lado do jogador).",
          "O sopro cobre o círculo de 4 sqm em volta do monstro (9×9 arredondado).",
          "Seguros: o sqm de cada coluna e os 2 sqm logo atrás dela, na mesma direção, para longe do monstro (a "
          "'sombra'), e tudo fora do círculo.",
          "Aviso de 3,0 s. Depois o sopro (0,6 s) e as colunas derretem em névoa.",
      ],
      esquiva="Entrar na sombra de uma coluna (atrás dela, olhando do monstro) ou sair do círculo.",
      dano="1,4 × R de gelo + Frio 3 s",
      timeline=[("aviso", 3000), ("sopro", 600), ("frio no atingido", 3000)],
      files=[
          F("coluna_surge", 64, 192, 6, 400, "ar", "sqm", "base",
            "Uma coluna de vidro-do-mar sobe do chão até ~2 sqm de altura: verde-água leitoso, arestas gastas pelo "
            "mar, névoa presa por dentro. Elegante, nada de pedra bruta."),
          F("coluna_loop", 64, 192, 4, "loop", "ar", "sqm", "base",
            "A coluna parada: luz de pérola subindo devagar por dentro dela."),
          F("coluna_derrete", 64, 192, 6, 500, "ar", "sqm", "base",
            "Depois do sopro a coluna se desfaz em névoa e plumas que sobem."),
          F("sombra", 64, 64, 4, "loop", "chão", "sqm", "centro",
            "O chão protegido atrás da coluna: limpo, com um halo calmo cor de pérola. SEM relógio — é o 'aqui "
            "não'. Tem que se destacar no meio da geada (é o que o jogador procura com os olhos)."),
          F("geada_aviso", 64, 64, 12, 3000, "chão", "sqm", "centro",
            "A geada chegando ao sqm: cristais de gelo crescendo dos cantos até cobrir o sqm (relógio); os últimos "
            "0,25 s mais claros. Emenda com as vizinhas: o círculo inteiro é essa peça repetida (o jogo deixa as "
            "sombras de fora)."),
          F("sopro", 64, 64, 6, 400, "ar", "sqm", "centro",
            "O golpe em cada sqm: estouro de cristais de gelo e plumas, rajada fria. Sem direção (serve para "
            "qualquer lado do monstro)."),
      ])

# ---------------------------------------------------------------- ASHEN
spell(tier="ashen", key="ciranda", nome="Ciranda de Brasa", tipo="varredura que gira + anel de brasa",
      conceito="O monstro roda no lugar como numa ciranda, com um jato de fogo saindo do corpo, e varre o "
               "círculo inteiro em volta dele. Na borda, o chão fica em brasa.",
      mecanica=[
          "Círculo de 4 sqm em volta do monstro (9×9 arredondado), dividido em 8 fatias — as 8 direções da "
          "rosa-dos-ventos (diagrama).",
          "Aviso de 3,0 s: o chão de todas as fatias racha de leve; a fatia onde a ciranda COMEÇA acende forte, e "
          "uma seta curva no chão mostra para que lado ela gira (horário ou anti-horário, sorteado). A primeira "
          "fatia nunca é a do jogador.",
          "Depois o jato varre uma fatia a cada 250 ms (2 s a volta inteira). Cada fatia acende forte 250 ms "
          "antes de o jato chegar.",
          "Os sqm da borda de cada fatia (a 4 sqm do monstro) ficam em brasa 3 s depois que o jato passa.",
      ],
      esquiva="Andar em volta do monstro ATRÁS do jato (entrar na fatia que acabou de queimar), ou sair do "
              "círculo logo no começo, antes de a borda pegar fogo.",
      dano="Jato 1,3 × R de fogo + Queimando; borda: 0,15 × R por segundo",
      timeline=[("aviso", 3000), ("volta do jato", 2000), ("brasa na borda", 3000)],
      files=[
          F("giro_horario", 576, 576, 12, 3000, "chão", "monstro (sqm)", "centro",
            "Seta curva no chão em volta do monstro mostrando o sentido da volta (horário): rachaduras de cobre e "
            "folhas de cinza correndo em círculo, com a ponta da seta acesa. Relógio: a seta se completa e acende "
            "no fim. Vai até a borda do círculo (4 sqm, arquivo 9×9 sqm), mas fina: não pode esconder as fatias."),
          F("giro_anti", 576, 576, 12, 3000, "chão", "monstro (sqm)", "centro", "↑ o mesmo, no sentido anti-horário."),
          F("fatia_aviso", 64, 64, 12, 3000, "chão", "sqm", "centro",
            "O chão de todas as fatias rachando de leve: carvão com veios de cobre ainda apagados, acendendo devagar "
            "(relógio). É o perigo 'geral', mais fraco que a fatia da vez."),
          F("fatia_inicio", 64, 64, 4, "loop", "chão", "sqm", "centro",
            "Os sqm da primeira fatia durante o aviso: as rachaduras já em âmbar vivo, faíscas subindo. É por aqui "
            "que a ciranda começa."),
          F("fatia_vez", 64, 64, 4, 250, "chão", "sqm", "centro",
            "A fatia que o jato vai varrer em seguida: as rachaduras acendem âmbar de uma vez (relógio curto, 250 ms)."),
          F("jato", 64, 128, 6, 300, "ar", "sqm", "base",
            "O jato passando pelo sqm: labareda baixa de cobre saindo das rachaduras, cinza e faíscas girando. O jogo "
            "toca em todos os sqm da fatia ao mesmo tempo."),
          F("redemoinho", 192, 192, 8, "loop", "ar", "monstro", "centro",
            "O monstro girando durante a volta: redemoinho de cinza e faíscas em volta dele (o jato em si é o "
            "'jato' no chão)."),
      ])

spell(tier="ashen", key="pavio", nome="Pavio de Cobre", tipo="cargas em sequência (o pavio é o relógio)",
      conceito="O monstro arremessa três carvões em brasa em volta do jogador e acende um pavio de cobre até cada "
               "um. Quando a faísca chega, o carvão estoura.",
      mecanica=[
          "3 cargas: uma no sqm do jogador e duas a 2 sqm dele, em sqm livres e em direções diferentes.",
          "Cada carga estoura num 3×3 em volta dela e deixa brasa 3 s.",
          "Um pavio liga o monstro a cada carga em linha reta pela grade. Depois de 1 s acendendo, a faísca corre "
          "o pavio a 300 ms por sqm: o pavio mais curto estoura primeiro. Nenhuma estoura antes de 3,0 s.",
      ],
      esquiva="Sair do 3×3 da carga embaixo de você sem entrar no 3×3 das outras. Olhe as faíscas: a mais "
              "adiantada estoura primeiro.",
      dano="1,2 × R de fogo + Queimando por carga; brasa: 0,15 × R por segundo",
      timeline=[("arremesso", 500), ("aviso (faíscas correndo)", 2500), ("1º estouro", 450), ("2º", 450),
                ("3º", 450), ("brasa no chão", 3000)],
      files=[
          F("carga_arremesso", 64, 192, 6, 500, "ar", "sqm", "base",
            "O carvão em brasa caindo do alto e quicando no sqm: pedra de carvão com rachaduras de cobre e rastro de "
            "faíscas."),
          F("carga_loop", 64, 96, 4, "loop", "ar", "sqm", "base",
            "O carvão no chão: as rachaduras de cobre pulsando, uma faísca sobe a cada pulso. (O jogo acelera o "
            "pulso perto do estouro.)"),
          F("area_aviso", 192, 192, 12, 3000, "chão", "sqm", "centro",
            "O 3×3 de perigo em volta da carga: cinza escura com um anel de rachaduras de cobre na borda. Relógio: o "
            "anel acende no sentido horário e fecha no estouro. O jogo estica ou encurta conforme o pavio, por isso "
            "o relógio tem que ser uniforme, sem pausas."),
      ] + seg("pavio", 4, "loop", "chão",
              "O pavio: fio de cobre trançado com cinza, saindo de uma rachadura no chão. Apagado e discreto, mas "
              "visível de longe. O jogo apaga o pedaço que a faísca já passou.")
        + [F(f"faisca_{i}", 64, 64, 1, "parado", "ar", "sqm", "centro",
             "A faísca correndo o pavio: frames PARADOS que o jogo troca a cada sqm (como a pétala da Flor). Chispa "
             "âmbar com estrelinhas; tem que ser o ponto mais claro do pavio." if i == 1 else "↑")
           for i in range(1, 5)]
        + [F("estouro", 192, 192, 8, 500, "ar", "sqm", "centro",
             "O carvão estoura: pedaços de carvão, labareda de cobre no 3×3, folhas de cinza girando. Fica dentro "
             "do 3×3.")])

# ---------------------------------------------------------------- OBSIDIAN
spell(tier="obsidian", key="persiana", nome="Persiana de Vidro", tipo="faixas em 2 fases (fileiras, depois colunas)",
      conceito="Lâminas de vidro sobem do chão em faixas paralelas, como uma persiana se fechando: primeiro as "
               "fileiras, depois as colunas. Quem acha o xadrez entre elas não é cortado.",
      mecanica=[
          "Quadrado de 9×9 sqm centrado no jogador.",
          "Fase 1: as fileiras pares — a do jogador e de 2 em 2 — racham e as lâminas sobem. Aviso de 3,0 s.",
          "Fase 2, logo em seguida: as colunas pares (a do jogador e de 2 em 2). Aviso de 2,0 s. Durante a fase 1 "
          "as faixas da fase 2 já aparecem fracas.",
          "Os sqm fora de qualquer faixa (fileira ímpar e coluna ímpar) são seguros nas duas fases.",
      ],
      esquiva="Um passo na diagonal: sai da sua fileira e da sua coluna de uma vez e fica seguro nas duas fases.",
      dano="1,2 × R físico + Cortes, por fase",
      timeline=[("fase 1", 3000), ("lâminas", 450), ("fase 2", 2000), ("lâminas", 450)],
      files=[
          F("faixa_h", 64, 64, 12, 3000, "chão", "sqm", "seg",
            "A faixa de perigo na fileira: um risco de vidro rachando de ponta a ponta do sqm, luz violeta subindo "
            "pela rachadura (relógio: acende até a borda no fim). Emenda com a vizinha numa linha contínua. A "
            "faixa é o sqm inteiro (o perigo é o sqm todo, não só o risco). Na fase 2 o jogo toca em 2,0 s, e as "
            "faixas da próxima fase aparecem com 30% de opacidade."),
          F("faixa_v", 64, 64, 12, 3000, "chão", "sqm", "seg", "↑ na coluna (vertical)."),
          F("lamina_h", 64, 128, 6, 450, "ar", "sqm", "base",
            "Uma lâmina de vidro fina como uma tábua de persiana sobe ao longo da fileira e se parte. Facetas índigo, "
            "aresta azul-fria. Emenda com a do sqm vizinho."),
          F("lamina_v", 64, 128, 6, 450, "ar", "sqm", "base",
            "↑ ao longo da coluna: vista de frente a lâmina é estreita — uma aresta alta brilhando."),
      ],
      reusa="Depois de cada fase, os sqm que já cortaram usam o resto.png da Coroa Partida (lascas apagadas = seguro).")

spell(tier="obsidian", key="redoma", nome="Redoma de Vidro", tipo="gaiola com uma porta",
      conceito="Uma redoma de cristal cresce em volta do jogador e se fecha. Só uma porta fica aberta. Quem ainda "
               "estiver dentro quando ela fechar é cortado pelos estilhaços.",
      mecanica=[
          "Uma paliçada de cristais sobe no contorno de um 5×5 centrado no jogador (16 sqm). Um desses sqm é a "
          "PORTA (sorteada, nunca num lado bloqueado por parede).",
          "Aviso de 3,0 s: os cristais crescem (relógio) e a porta brilha em azul-frio.",
          "Quando fecha, tudo dentro do 5×5 — o miolo 3×3 e o próprio contorno — é atingido. Fora é seguro.",
          "Atravessar a paliçada fora da porta corta (0,4 × R + Cortes): dói menos que ficar, mas dói.",
      ],
      esquiva="Sair pela porta (2 passos).",
      dano="1,6 × R físico + Cortes; atravessar a paliçada: 0,4 × R + Cortes",
      timeline=[("aviso", 3000), ("redoma fecha", 500)],
      files=[
          F("cristal_cresce", 64, 128, 12, 3000, "ar", "sqm", "base",
            "Um tufo de cristais índigo crescendo do chão num sqm do contorno: começa como lascas baixas e termina em "
            "pontas altas (relógio); nos últimos 0,25 s a luz corre pelas arestas. É um tufo (não uma parede reta), "
            "então serve para qualquer sqm do contorno, inclusive os cantos."),
          F("porta", 64, 128, 4, "loop", "ar", "sqm", "base",
            "A porta: dois cristais mais altos formando um arco, com luz azul-fria entre eles. Tem que ser o ponto "
            "mais claro e mais 'convidativo' da redoma — o jogador acha a saída num relance."),
          F("miolo_aviso", 192, 192, 12, 3000, "chão", "sqm", "centro",
            "O chão do 3×3 de dentro: vidro rachando sob os pés, luz violeta vazando pelas rachaduras (relógio)."),
          F("fecha", 320, 320, 8, 500, "ar", "sqm", "centro",
            "A redoma fecha: uma cúpula de luz e facetas se forma sobre o 5×5 e estilhaça para DENTRO. Nada passa "
            "para fora do 5×5."),
          F("cristal_quebra", 64, 128, 6, 400, "ar", "sqm", "base",
            "O tufo do contorno se partindo depois que a redoma fecha (vira lasca apagada)."),
      ])

# ---------------------------------------------------------------- LORD OF DEATH
spell(tier="deathlord", key="dobre", nome="Dobre de Finados", tipo="anéis alternados no compasso de um sino",
      conceito="Um sino fúnebre de fumaça aparece sobre o monstro e dobra três vezes, cada vez mais rápido. A cada "
               "badalada, anéis de sombra alternados sobem do chão.",
      mecanica=[
          "Em volta do monstro, 5 anéis de 1 sqm de largura (até 5 sqm, 11×11 arredondado).",
          "1ª badalada: anéis 1, 3 e 5 (aviso 3,0 s). 2ª: anéis 2 e 4 (aviso 2,2 s). 3ª: 1, 3 e 5 de novo (aviso 1,6 s).",
          "Durante cada aviso, os anéis da badalada seguinte aparecem fracos.",
      ],
      esquiva="A cada badalada, um passo reto para dentro ou para fora: ficar no anel apagado.",
      dano="1,5 × R de morte por badalada",
      timeline=[("aviso 1", 3000), ("dobre", 400), ("aviso 2", 2200), ("dobre", 400), ("aviso 3", 1600), ("dobre", 400)],
      files=[
          F("sino_surge", 192, 192, 6, 500, "ar", "monstro", "centro",
            "Um sino de fumaça negra com veias granada se forma no ar sobre o monstro (metade de cima do arquivo). "
            "Pesado, antigo, a boca do sino escura."),
          F("sino_dobra", 192, 192, 6, 400, "ar", "monstro", "centro",
            "O sino balança e dobra: um anel de som escuro se FECHA para dentro (o Lord implode, não explode). "
            "Tocado a cada badalada."),
          F("sino_some", 192, 192, 6, 500, "ar", "monstro", "centro", "Depois da 3ª badalada o sino implode e some."),
          F("anel_aviso", 64, 64, 12, 3000, "chão", "sqm", "centro",
            "A sombra subindo pelo chão num sqm do anel: veias granada se abrindo e fumaça negra rente ao chão "
            "(relógio). Emenda com as vizinhas: o anel inteiro é essa peça. O jogo toca mais rápido na 2ª e na 3ª "
            "badalada (2,2 s e 1,6 s), e com 30% de opacidade nos anéis da badalada seguinte."),
          F("anel_golpe", 64, 128, 6, 400, "ar", "sqm", "base",
            "Mãos de sombra sobem do chão no sqm e são puxadas de volta para baixo — para DENTRO, nunca uma explosão "
            "para fora."),
          F("anel_resto", 64, 64, 4, 600, "chão", "sqm", "centro",
            "Depois do golpe: cinza fria, apagada, sem brilho nenhum. Apagado = seguro nesta badalada."),
      ])

spell(tier="deathlord", key="pesagem", nome="Pesagem das Almas", tipo="metade do círculo, depois a outra",
      conceito="Uma balança de sombra aparece sobre o monstro e pesa as almas: o prato do lado do jogador afunda e "
               "aquela metade do chão é esmagada. Depois a balança vira e esmaga a outra.",
      mecanica=[
          "Círculo de 5 sqm em volta do monstro (11×11 arredondado), cortado ao meio por uma linha vertical que passa "
          "pelo monstro: o FIEL da balança, 1 sqm de largura.",
          "Fase 1: a metade onde está o jogador (aviso 3,0 s). Fase 2: a outra metade (aviso 2,0 s).",
          "O fiel é seguro nas duas fases. Fora do círculo também.",
      ],
      esquiva="Atravessar para a metade leve antes da 1ª e voltar antes da 2ª — ou parar em cima do fiel, o único "
              "lugar seguro nas duas.",
      dano="2,0 × R de morte por fase",
      timeline=[("fase 1", 3000), ("esmaga", 500), ("fase 2", 2000), ("esmaga", 500)],
      files=[
          F("balanca_surge", 256, 256, 6, 500, "ar", "monstro", "centro",
            "A balança se forma sobre o monstro (metade de cima do arquivo): travessão de fumaça negra, dois pratos "
            "com veias granada e, no eixo, o selo partido de cinco pontas."),
          F("balanca_pende_esq", 256, 256, 8, 1000, "ar", "monstro", "centro",
            "A balança pende para a esquerda: o prato da esquerda desce devagar e fica embaixo (último frame parado "
            "até a fase acabar)."),
          F("balanca_pende_dir", 256, 256, 8, 1000, "ar", "monstro", "centro", "↑ para a direita."),
          F("metade_aviso", 64, 64, 12, 3000, "chão", "sqm", "centro",
            "O chão da metade que vai afundar: rachaduras granada puxando na direção do fiel, fumaça negra pesando "
            "(relógio). Emenda com as vizinhas. Na fase 2 o jogo toca em 2,0 s."),
          F("fiel_v", 64, 64, 4, "loop", "chão", "sqm", "seg",
            "O fiel da balança: uma linha fina de luz fria (azul-pérola) no meio do sqm, vertical, emendando com as "
            "vizinhas. É a luz segura do Lord, a mesma ideia dos refúgios do Eclipse Total: a única luz da magia."),
          F("esmaga", 64, 128, 6, 500, "ar", "sqm", "base",
            "A metade é esmagada: um peso de sombra cai sobre o sqm e o chão afunda, implodindo."),
          F("resto", 64, 64, 4, 600, "chão", "sqm", "centro",
            "Depois do golpe: chão afundado, apagado, sem brilho. Apagado = seguro."),
      ])


def tier_of(key):
    for t in TIERS:
        if t["key"] == key:
            return t
    raise KeyError(key)


SPELL_MULT = {
    "mare": 1.2, "sopro": 1.4,
    "ciranda": 1.3, "pavio": 1.2,
    "persiana": 1.2, "redoma": 1.6,
    "dobre": 1.5, "pesagem": 2.0,
}

# etapa 1: uma por tier, para aprovar
STAGE1 = ["mare", "pavio", "redoma", "dobre"]
