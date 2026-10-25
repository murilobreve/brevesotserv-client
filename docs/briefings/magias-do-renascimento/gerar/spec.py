# -*- coding: utf-8 -*-
# Especificacao das magias dos tiers do Renascimento (fonte unica: o HTML,
# o CSV, os diagramas e a pasta de entrega saem daqui).

TIERS = [
    {
        "key": "pale", "pasta": "pale", "nome": "Pale", "material": "O Véu",
        "cor": (120, 171, 184), "luz": (229, 244, 241), "sombra": (41, 56, 68),
        "paleta": [("sombra", "#293844"), ("matéria", "#78ABB8"), ("luz", "#E5F4F1")],
        "mult": 1.0, "intervalo": 9, "elemento": "Gelo",
        "debuff": "Frio: −30% de velocidade por 2–3 s",
        "personalidade": "Silencioso, elegante, lento. É o tier que ENSINA a desviar: avisos longos, "
                         "formas simples, nunca dois perigos ao mesmo tempo.",
        "materia": "Névoa em fiapos, plumas, lágrimas de pérola, vidro do mar, estrelinhas de 4 pontas. "
                   "Sombras cinza-azuladas, nunca branco puro chapado.",
        "movimento": "Flutua e respira. Curvas lentas, nada estala. A coisa mais rápida do tier é a "
                     "pluma cortando a faixa.",
        "evitar": "Laranja, vermelho, roxo. Branco puro sem sombra (some na neve).",
    },
    {
        "key": "ashen", "pasta": "ashen", "nome": "Ashen", "material": "A Flor de Cinza",
        "cor": (201, 113, 53), "luz": (243, 189, 115), "sombra": (41, 34, 36),
        "paleta": [("sombra", "#292224"), ("carvão", "#6B6363"), ("cobre", "#C97135"), ("âmbar", "#F3BD73")],
        "mult": 1.35, "intervalo": 8, "elemento": "Fogo",
        "debuff": "Queimando: 3 ticks de fogo em 3 s",
        "personalidade": "Agressivo e territorial. Toma o chão: quase tudo que ele faz deixa brasa "
                         "queimando por alguns segundos (dano enquanto pisa).",
        "materia": "Carvão e cinza escura, rachaduras de cobre, faíscas âmbar, folhas de cinza, "
                   "pedrinhas. O fogo mora DENTRO das rachaduras — nunca uma bola laranja inteira.",
        "movimento": "Crepita e tremula. Faíscas sobem, folhas de cinza giram e caem.",
        "evitar": "Fogo amarelo/laranja chapado de RPG genérico; azul; roxo.",
    },
    {
        "key": "obsidian", "pasta": "obsidian", "nome": "Obsidian", "material": "A Coroa de Vidro",
        "cor": (143, 116, 216), "luz": (156, 188, 235), "sombra": (23, 23, 45),
        "paleta": [("sombra", "#17172D"), ("índigo", "#8F74D8"), ("borda fria", "#9CBCEB")],
        "mult": 1.8, "intervalo": 7, "elemento": "Físico (cortes de vidro)",
        "debuff": "Cortes: sangramento, 4 ticks em 4 s",
        "personalidade": "Preciso e geométrico. Quebra-cabeças de posição: xadrez, cruzes, mira que "
                         "persegue e trava. Castiga quem fica parado.",
        "materia": "Cristais facetados índigo, luz violeta atravessando o vidro, arestas azul-frias, "
                   "lascas, fumacinha roxa.",
        "movimento": "Tensão e estalo: encolhe e treme antes de estourar, depois quebra seco. A luz "
                     "corre pelas arestas.",
        "evitar": "Formas moles/fumaça como protagonista; laranja; verde.",
    },
    {
        "key": "deathlord", "pasta": "lord-of-death", "nome": "Lord of Death", "material": "O Eclipse",
        "cor": (121, 45, 66), "luz": (195, 92, 104), "sombra": (17, 16, 23),
        "paleta": [("sombra", "#111017"), ("vinho", "#33171F"), ("granada", "#792D42"), ("veia", "#C35C68"), ("luz fria", "#CFE0EE")],
        "mult": 2.2, "intervalo": 6, "elemento": "Morte",
        "debuff": "— (os golpes já são pesados)",
        "personalidade": "Opressor e inevitável. Puxa, persegue e tem o golpe final (Eclipse Total) "
                         "que mata quem não achar o refúgio. Mas é sempre justo: tudo avisado.",
        "materia": "Fumaça negra com toque de vinho, veias granada, bordas frias discretas, estrelas "
                   "escuras de 4 pontas, o selo de cinco pontas partido.",
        "movimento": "Pesado e para DENTRO: implode, suga, fecha. Nenhum flash brusco — a luz some.",
        "evitar": "Vermelho-sangue saturado; explosões para fora; brilho forte (a única luz forte do "
                  "tier é a luz fria dos refúgios).",
    },
]

# arquivo: (nome, largura, altura, frames, ms | "loop" | "parado", camada, preso, ancora, descricao)
# ancora: "centro" = centro do arquivo no centro do sqm; "base" = o sqm e o quadrado
# de baixo do arquivo (64x64); "seg" = peca de linha que ocupa o sqm inteiro e
# emenda com a vizinha
def F(nome, w, h, frames, ms, camada, preso, ancora, desc):
    return {"nome": nome, "w": w, "h": h, "frames": frames, "ms": ms, "camada": camada,
            "preso": preso, "ancora": ancora, "desc": desc}

ORIENT = ["h", "v", "ne", "nw"]
DIR4 = ["n", "e", "s", "w"]

def seg(prefix, frames, ms, camada, desc):
    return [F(f"{prefix}_{o}", 64, 64, frames, ms, camada, "sqm", "seg", desc if i == 0 else "↑ mesma peça, outra orientação") for i, o in enumerate(ORIENT)]

def comum(tier, conj, fim, acerto, debuff=None):
    files = [
        F("conjurar", 128, 128, 8, "loop", "ar", "monstro", "centro", conj),
        F("conjurar_fim", 128, 128, 4, 250, "ar", "monstro", "centro", fim),
        F("acerto", 128, 128, 6, 300, "ar", "jogador", "centro", acerto),
    ]
    if debuff:
        files.append(F(debuff[0], 64, 96, 4, "loop", "ar", "jogador", "base", debuff[1]))
    return files

SPELLS = []

def spell(**kw):
    SPELLS.append(kw)

# ---------------------------------------------------------------- PALE
spell(tier="pale", key="comum", nome="Comum do Pale", tipo="peças usadas por todas as magias do tier",
      files=comum("pale",
                  "Névoa do véu se enrolando em volta do monstro, plumas subindo devagar em espiral. "
                  "É o 'vou lançar'. Translúcido: o monstro continua visível.",
                  "O véu se abre num sopro rápido no instante do disparo.",
                  "Golpe de gelo do véu em quem foi atingido: plumas e lascas de pérola abrindo, brilho frio.",
                  ("frio_loop", "Jogador lento pelo frio: fiapos de névoa nos pés e 1–2 estrelinhas de 4 pontas. Discreto.")))

spell(tier="pale", key="pluma", nome="Pluma do Véu", tipo="linha",
      conceito="Uma pluma de névoa corta uma faixa reta do monstro até o jogador.",
      mecanica=[
          "O monstro vira para o jogador (uma das 8 direções) e marca uma faixa de 1 sqm de largura e 7 sqm de comprimento.",
          "Aviso de 1,6 s. Depois a pluma corre a faixa, 60 ms por sqm, e atinge todos que estiverem nela.",
          "Para na primeira parede. Atravessa jogadores.",
      ],
      esquiva="Um passo para o lado da faixa.",
      dano="1,0 × R de gelo + Frio 2 s",
      timeline=[("aviso", 1600), ("pluma", 420), ("frio no atingido", 2000)],
      files=seg("faixa", 12, 1600, "chão",
                "A faixa de perigo. Começa como um fio de névoa no meio do sqm e engrossa até ocupar a largura "
                "do sqm (é o relógio); no último quarto fica cor de pérola = 'agora'.")
            + seg("rajada", 6, 300, "ar",
                  "A pluma passando pelo sqm como lâmina de vento: plumas e névoa cortando de ponta a ponta. "
                  "O jogo toca peça por peça ao longo da faixa (60 ms de diferença), então tem que parecer que 'passa'. "
                  "Simétrica: serve para os dois sentidos."))

spell(tier="pale", key="lagrimas", nome="Lágrimas de Pérola", tipo="chuva de marcas",
      conceito="Lágrimas de gelo leitoso caem do alto em sqm marcados em volta dos jogadores.",
      mecanica=[
          "5 marcas de 1 sqm: uma no sqm de cada jogador a até 7 sqm (no máx. 3) e o resto sorteado a até 2 sqm deles.",
          "As marcas aparecem uma a uma (150 ms entre elas); cada uma tem 1,6 s de aviso.",
          "A lágrima cai nos últimos 0,3 s do aviso. Quem está no sqm toma o dano.",
          "Deixa Geada por 2,5 s: quem pisa fica com Frio (sem dano).",
      ],
      esquiva="Sair do sqm marcado (1 passo) e não pisar na geada.",
      dano="0,9 × R de gelo por lágrima",
      timeline=[("aviso", 1600), ("queda", 300), ("geada", 2500)],
      files=[
          F("marca", 64, 64, 12, 1600, "chão", "sqm", "centro",
            "Círculo do véu no chão com o RELÓGIO: um arco cor de pérola que se completa no sentido horário "
            "(igual ao Meteoro e à Chuva de Juízo) e fecha no instante da queda. Gotinhas de névoa caindo para dentro."),
          F("queda", 64, 192, 6, 300, "ar", "sqm", "base",
            "A lágrima de pérola (gota de gelo leitosa, brilho azul-mar por dentro) caindo do alto e tocando o "
            "centro do sqm no último frame."),
          F("impacto", 128, 128, 6, 350, "ar", "sqm", "centro",
            "A gota se parte: respingos de pérola e plumas de névoa em coroa, rápido."),
          F("geada_entrada", 64, 64, 4, 250, "chão", "sqm", "centro",
            "A geada que fica 2,5 s: placa fina de gelo azul-pérola com cristais, plana. SEM relógio "
            "(resíduo nunca tem relógio). Entrada → loop respirando de leve → saída."),
          F("geada_loop", 64, 64, 4, "loop", "chão", "sqm", "centro", "↑"),
          F("geada_saida", 64, 64, 4, 300, "chão", "sqm", "centro", "↑"),
      ])

spell(tier="pale", key="veu", nome="Véu que se Fecha", tipo="anel (donut)",
      conceito="Uma cortina de névoa sobe num anel em volta do monstro e se fecha cortando quem está nela.",
      mecanica=[
          "Anel de perigo entre 2 e 3 sqm do monstro (forma exata no diagrama).",
          "Seguro: colado no monstro (os 8 sqm em volta) ou a 4+ sqm dele.",
          "Aviso de 2,0 s; o monstro fica parado conjurando.",
      ],
      esquiva="Correr PARA DENTRO (colar no monstro) ou para fora do anel. Ensina o 'donut' do Path of Exile.",
      dano="1,4 × R de gelo + Frio 3 s",
      timeline=[("aviso", 2000), ("véu fecha", 500), ("frio no atingido", 3000)],
      files=[
          F("anel_marca", 448, 448, 12, 2000, "chão", "monstro (sqm)", "centro",
            "O anel de perigo (7×7 sqm, monstro no centro). As DUAS bordas — de dentro e de fora — bem "
            "desenhadas: o jogador vê na hora onde o anel começa e acaba. Névoa subindo das bordas como "
            "cortina; o miolo e o lado de fora ficam limpos. Relógio: a cortina sobe de zero até a altura "
            "máxima durante o aviso."),
          F("anel_fecha", 448, 448, 8, 500, "ar", "monstro (sqm)", "centro",
            "O véu se fecha: as plumas da cortina giram em espiral e cortam o anel, sem invadir o miolo."),
      ])

# ---------------------------------------------------------------- ASHEN
spell(tier="ashen", key="comum", nome="Comum do Ashen", tipo="peças usadas por todas as magias do tier",
      files=comum("ashen",
                  "Folhas de cinza girando em volta do monstro, fissuras de cobre acendendo no corpo, faíscas âmbar subindo.",
                  "Baforada de cinza e faíscas no instante do disparo.",
                  "Estouro de brasa em quem foi atingido: cinza escura com rachaduras de cobre e faíscas.",
                  ("queimando_loop", "Jogador queimando: chaminhas de cobre e cinza subindo do corpo. Discreto.")))

spell(tier="ashen", key="brasa", nome="Brasa Rastejante", tipo="leque de 3 linhas + chão queimando",
      conceito="Três rachaduras de fogo rastejam pelo chão em leque na direção do jogador.",
      mecanica=[
          "3 linhas de 6 sqm saindo do monstro: a do meio na direção do jogador, as outras a 45° para cada lado.",
          "Aviso de 1,3 s (as rachaduras abrindo). O fogo corre as linhas, 70 ms por sqm.",
          "As linhas ficam em brasa por 3 s: quem pisa toma dano a cada segundo.",
      ],
      esquiva="Ficar entre as linhas (o vão aumenta com a distância) e não atravessar a brasa.",
      dano="1,0 × R de fogo + Queimando; chão: 0,15 × R por segundo",
      timeline=[("aviso", 1300), ("fogo corre", 420), ("brasa no chão", 3000)],
      files=seg("fissura", 12, 1300, "chão",
                "Uma rachadura de carvão abrindo no chão ao longo da linha; o cobre vai acendendo por dentro "
                "até ficar âmbar no fim (relógio).")
            + [F(f"labareda_{o}", 64, 128, 6, 400, "ar", "sqm", "base",
                 "O fogo correndo pela rachadura: labareda baixa de cobre com folhas de cinza, sobe ~1 sqm. "
                 "Tocada sqm por sqm ao longo da linha." if i == 0 else "↑ mesma peça, outra orientação") for i, o in enumerate(ORIENT)]
            + [F("brasas_fortes", 64, 64, 4, "loop", "chão", "sqm", "centro",
                 "O chão que fica queimando 3 s (1 s em cada estágio, cada um mais apagado — igual às brasas do "
                 "Meteoro, mas em 1 sqm e emendando com a vizinha). Sem relógio. Também usado pela Investida."),
               F("brasas_medias", 64, 64, 4, "loop", "chão", "sqm", "centro", "↑"),
               F("brasas_fracas", 64, 64, 4, "loop", "chão", "sqm", "centro", "↑")])

spell(tier="ashen", key="flor", nome="Flor de Cinza", tipo="área + estrela (2 tempos)",
      conceito="O monstro planta um botão de cinza sob o jogador; ele desabrocha e solta pétalas em brasa nas 8 direções.",
      mecanica=[
          "Botão 3×3 no sqm do jogador. Desde o início aparecem também as 8 trilhas das pétalas (4 sqm além do botão).",
          "Aviso de 1,5 s. A flor explode nos 3×3.",
          "No mesmo instante 8 pétalas voam pelas trilhas (60 ms por sqm).",
      ],
      esquiva="Sair do 3×3 para um sqm que NÃO esteja numa das 8 trilhas (o 'pulo do cavalo' do xadrez).",
      dano="Botão 1,4 × R de fogo; pétala 0,7 × R",
      timeline=[("aviso (botão + trilhas)", 1500), ("explosão + pétalas", 500)],
      files=[
          F("botao", 192, 192, 12, 1500, "chão", "sqm", "centro",
            "Botão de flor de cinza ocupando os 3×3: pétalas de carvão fechadas com veios de cobre que vão "
            "se abrindo. Relógio no contorno (arco âmbar no sentido horário)."),
      ] + seg("trilha", 4, "loop", "chão",
              "O caminho das pétalas: linha fina de cinza com pontinhos âmbar. Mais fraca que o botão, mas visível "
              "desde o início — é ela que mostra onde NÃO ficar quando a flor abrir.")
        + [F("desabrocha", 320, 320, 8, 500, "ar", "sqm", "centro",
             "A flor explode aberta: pétalas de cinza e anel de faíscas, miolo âmbar claro. O dano é nos 3×3."),
           F("petala_1", 64, 64, 1, "parado", "ar", "sqm", "centro",
             "A pétala em brasa voando: frames PARADOS que o jogo troca a cada sqm (como a Esfera do Vazio). "
             "Folha de cinza girando com borda de cobre. Gira, então serve para as 8 direções."),
           F("petala_2", 64, 64, 1, "parado", "ar", "sqm", "centro", "↑"),
           F("petala_3", 64, 64, 1, "parado", "ar", "sqm", "centro", "↑"),
           F("petala_4", 64, 64, 1, "parado", "ar", "sqm", "centro", "↑")])

spell(tier="ashen", key="investida", nome="Investida Incandescente", tipo="avanço do monstro",
      conceito="O monstro avança em linha reta pegando fogo e deixa o caminho em brasa.",
      mecanica=[
          "Marca um caminho de 1 sqm de largura e até 6 sqm na direção do jogador (8 direções).",
          "Aviso de 1,0 s. O monstro atravessa o caminho (60 ms por sqm) e para no fim ou antes de uma parede.",
          "Quem está no caminho toma dano e é empurrado 1 sqm para o lado. O caminho fica em brasa 3 s.",
      ],
      esquiva="Um passo para o lado do caminho.",
      dano="1,2 × R de fogo + Queimando; chão: 0,15 × R por segundo",
      timeline=[("aviso", 1000), ("avanço", 360), ("brasa no chão", 3000)],
      files=seg("caminho", 12, 1000, "chão",
                "O caminho da investida: chão chamuscado e marcas de arrasto acendendo em cobre; no fim fica âmbar (relógio).")
            + seg("arrasto", 4, 250, "ar",
                  "O rastro do monstro passando pelo sqm: borrão de fogo e cinza na direção da peça.")
            + [F("chegada", 192, 192, 6, 400, "ar", "sqm", "centro",
                 "O monstro freia no fim do caminho: estouro de cinza e onda de faíscas no chão.")])

# ---------------------------------------------------------------- OBSIDIAN
spell(tier="obsidian", key="comum", nome="Comum do Obsidian", tipo="peças usadas por todas as magias do tier",
      files=comum("obsidian",
                  "Cristais índigo se formando e orbitando o monstro, luz violeta correndo pelas arestas. Tensão: "
                  "os cristais encolhem e tremem.",
                  "Estalo de vidro: lascas e um flash frio.",
                  "Cortes de vidro em quem foi atingido: lascas índigo em leque e um risco de luz fria.",
                  ("cortes_loop", "Jogador sangrando pelos cortes: lasquinhas de obsidiana presas e brilho violeta pulsando. Discreto.")))

spell(tier="obsidian", key="feixe", nome="Feixe Refratado", tipo="mira que persegue e trava",
      conceito="Um cristal mira no jogador com um fio de luz que o segue, trava e dispara um feixe.",
      mecanica=[
          "Fio de mira de 8 sqm saindo do monstro, nas 8 direções. Durante 1,0 s ele SEGUE o jogador (troca de direção quando ele muda de lado).",
          "Então TRAVA (clique visual) e, 0,7 s depois, dispara: dano em toda a linha até a parede.",
      ],
      aviso="1,0 s seguindo + 0,7 s travada",
      esquiva="Não se mexer à toa enquanto a mira segue; quando travar, um passo para o lado.",
      dano="1,3 × R físico + Cortes",
      timeline=[("mira segue", 1000), ("travada", 700), ("feixe", 350)],
      files=seg("mira", 4, "loop", "chão",
                "A mira: fio de luz violeta fino e trêmulo. O jogo redesenha a linha quando o jogador muda de lado, "
                "então ela é fina e 'instável' — ainda não é perigo, é ameaça.")
            + seg("trava", 8, 700, "chão",
                  "Depois de travar: nos 2 primeiros frames o fio engrossa num clique e fica azul-frio; depois pulsa "
                  "cada vez mais claro até o disparo (relógio).")
            + seg("feixe", 6, 350, "ar",
                  "O feixe: luz atravessando vidro — núcleo branco-azulado, bordas violetas facetadas, partículas de vidro.")
            + [F("feixe_origem", 128, 128, 6, 350, "ar", "monstro", "centro", "Flash prismático saindo do monstro no disparo."),
               F("feixe_fim", 128, 128, 6, 350, "ar", "sqm", "centro", "Onde o feixe acaba (alcance ou parede): a luz se estilhaça em lascas.")])

spell(tier="obsidian", key="coroa", nome="Coroa Partida", tipo="xadrez (2 fases)",
      conceito="O chão em volta do monstro racha em xadrez e espinhos de vidro irrompem em duas ondas.",
      mecanica=[
          "Área redonda de 3 sqm em volta do monstro (7×7 arredondado), dividida em xadrez.",
          "Fase 1: as casas 'pretas' racham (1,4 s) e os espinhos sobem.",
          "Fase 2 (logo em seguida): as casas 'brancas' racham (1,0 s) e sobem. As casas da fase 1 já estão seguras.",
      ],
      aviso="1,4 s + 1,0 s",
      esquiva="Fase 1: ficar numa casa branca. Fase 2: voltar para uma casa preta (que já explodiu). Dois passos de 1 sqm.",
      dano="1,1 × R físico por fase",
      timeline=[("fase 1", 1400), ("espinhos", 450), ("fase 2", 1000), ("espinhos", 450)],
      files=[
          F("marca", 64, 64, 12, 1400, "chão", "sqm", "centro",
            "Rachadura de vidro no sqm com luz violeta subindo por baixo. Relógio: as rachaduras se espalham até "
            "a borda e acendem no fim. Tem que ler como 'o quadrado inteiro é perigo'. Na fase 2 o jogo toca a mesma "
            "marca mais rápido (1,0 s)."),
          F("espinho", 64, 128, 6, 450, "ar", "sqm", "base",
            "Um cristal facetado irrompe do chão até ~1 sqm de altura e se parte."),
          F("resto", 64, 64, 4, 600, "chão", "sqm", "centro",
            "Lascas APAGADAS no chão, sem brilho nenhum, sumindo. Apagado = seguro."),
      ])

spell(tier="obsidian", key="reflexos", nome="Reflexos", tipo="estátuas em cruz",
      conceito="Estátuas de obsidiana surgem perto do jogador e explodem em cruz.",
      mecanica=[
          "2 estátuas (3 se houver 2+ jogadores) em sqm livres a até 2 sqm do jogador.",
          "Cada uma marca uma cruz: 4 sqm para cima, baixo, esquerda e direita.",
          "Aviso de 2,2 s; nos últimos 0,5 s a estátua racha. Então explode e as lascas correm pela cruz.",
          "As estátuas são só efeito (não bloqueiam a passagem).",
      ],
      aviso="2,2 s",
      esquiva="Ficar fora das linhas e colunas das estátuas — as diagonais são seguras.",
      dano="1,2 × R físico + Cortes",
      timeline=[("aviso", 1700), ("estátua racha", 500), ("explosão", 450)],
      files=[
          F("estatua_surge", 64, 128, 6, 400, "ar", "sqm", "base",
            "Uma estátua de obsidiana (cristal alto em forma de ponta de coroa) se ergue do chão."),
          F("estatua_loop", 64, 128, 4, "loop", "ar", "sqm", "base", "A estátua viva: luz violeta correndo por dentro."),
          F("estatua_racha", 64, 128, 6, 500, "ar", "sqm", "base",
            "Últimos 0,5 s: rachaduras com luz vazando — 'vai estourar'."),
          F("cruz_h", 64, 64, 12, 2200, "chão", "sqm", "seg",
            "Braço da cruz no chão: linha de luz violeta saindo da estátua, enchendo (relógio) até a explosão."),
          F("cruz_v", 64, 64, 12, 2200, "chão", "sqm", "seg", "↑ vertical"),
          F("estilhaco_h", 64, 64, 6, 300, "ar", "sqm", "seg", "Lascas voando pelo braço, de dentro para fora."),
          F("estilhaco_v", 64, 64, 6, 300, "ar", "sqm", "seg", "↑ vertical"),
          F("estatua_explode", 192, 192, 8, 450, "ar", "sqm", "centro", "A estátua explode em cacos."),
      ])

# ---------------------------------------------------------------- LORD OF DEATH
spell(tier="deathlord", key="comum", nome="Comum do Lord of Death", tipo="peças usadas por todas as magias do tier",
      files=comum("deathlord",
                  "Fumaça negra com veias granada se fechando em volta do monstro, puxada para DENTRO (o Lord implode, "
                  "não explode). Bordas frias discretas.",
                  "Pulso escuro para dentro no instante do disparo.",
                  "Mordida de sombra em quem foi atingido: fiapos negros com veios granada fechando."))

spell(tier="deathlord", key="garra", nome="Garra do Eclipse", tipo="leque frontal",
      conceito="Garras de sombra rasgam um leque na frente do monstro.",
      mecanica=[
          "Leque de 3 sqm de profundidade na frente do monstro: 1, 3 e 5 sqm de largura (forma no diagrama).",
          "O monstro vira para o jogador (4 direções, como todo monstro do Tibia).",
          "Aviso de 1,2 s.",
      ],
      esquiva="Ir para o lado ou para trás do monstro, ou sair do alcance.",
      dano="1,8 × R de morte",
      timeline=[("aviso", 1200), ("garras", 400)],
      files=[F(f"garra_marca_{d}", 448, 448, 12, 1200, "chão", "monstro (sqm)", "centro",
               "O leque no chão (arquivo 7×7 sqm com o monstro no CENTRO). Veias granada se espalhando em forma de "
               "garra até a borda do leque (relógio). Atrás e dos lados do monstro fica limpo." if i == 0 else "↑ outra direção")
             for i, d in enumerate(DIR4)]
          + [F(f"garra_golpe_{d}", 448, 448, 6, 400, "ar", "monstro (sqm)", "centro",
               "As garras de sombra rasgando o leque." if i == 0 else "↑ outra direção") for i, d in enumerate(DIR4)])

spell(tier="deathlord", key="sol", nome="Sol Negro", tipo="ameaça que persegue",
      conceito="Um sol negro nasce sobre o jogador e o persegue devagar, pulsando sombra no chão.",
      mecanica=[
          "Surge sobre o jogador e o segue por 6 s, 1 sqm a cada 0,6 s (mais devagar que qualquer jogador andando).",
          "A cada 1,2 s pulsa nos 3×3 embaixo dele; cada pulso tem o seu próprio relógio.",
          "Pode coexistir com outra magia do Lord (é o único caso).",
      ],
      aviso="1,2 s por pulso",
      esquiva="Continuar andando. Quem fica parado toma todos os pulsos.",
      dano="0,6 × R de morte por pulso (5 pulsos)",
      timeline=[("surge", 400), ("pulso", 1200), ("pulso", 1200), ("pulso", 1200), ("pulso", 1200), ("pulso", 1200)],
      files=[
          F("sol_surge", 128, 128, 6, 400, "ar", "sqm", "centro", "Um eclipse se forma no ar: disco negro, coroa granada e fria."),
          F("sol_loop", 128, 128, 8, "loop", "ar", "sqm", "centro", "O sol negro flutuando ~1 sqm acima do chão, a coroa girando devagar."),
          F("sol_voo_1", 128, 128, 1, "parado", "ar", "sqm", "centro",
            "Frames PARADOS do sol andando de um sqm para o outro (efeito em movimento não anima)."),
          F("sol_voo_2", 128, 128, 1, "parado", "ar", "sqm", "centro", "↑"),
          F("sol_voo_3", 128, 128, 1, "parado", "ar", "sqm", "centro", "↑"),
          F("sol_voo_4", 128, 128, 1, "parado", "ar", "sqm", "centro", "↑"),
          F("sol_some", 128, 128, 6, 400, "ar", "sqm", "centro", "O sol implode e some."),
          F("pulso_marca", 192, 192, 12, 1200, "chão", "sqm", "centro",
            "A sombra do sol no chão (3×3) com um anel granada que se FECHA para o centro (relógio). Anda junto com o sol."),
          F("pulso", 192, 192, 6, 300, "ar", "sqm", "centro", "O pulso: a sombra afunda no chão com um estalo granada."),
      ])

spell(tier="deathlord", key="colapso", nome="Colapso", tipo="puxão + área em volta",
      conceito="Tentáculos de sombra puxam os jogadores para perto e o monstro implode.",
      mecanica=[
          "Cada jogador a até 5 sqm é ligado ao monstro por tentáculos (aviso de 1,0 s).",
          "Depois é puxado 2 sqm na direção do monstro (para em parede).",
          "Logo em seguida aparece um círculo de 2 sqm em volta do monstro (5×5 arredondado): 1,4 s e implode.",
      ],
      aviso="1,0 s + 1,4 s",
      esquiva="Depois do puxão, sair do círculo (1–2 passos).",
      dano="2,0 × R de morte",
      timeline=[("tentáculos", 1000), ("puxão", 200), ("círculo", 1400), ("implosão", 500)],
      files=seg("tentaculo", 4, "loop", "chão",
                "Tentáculos de sombra rastejando do monstro até o jogador marcado.")
            + [F("agarrado", 128, 128, 6, "loop", "ar", "jogador", "centro", "A garra de sombra fechando em volta do jogador que vai ser puxado."),
               F("implosao_marca", 320, 320, 12, 1400, "chão", "monstro (sqm)", "centro",
                 "Círculo de 2 sqm em volta do monstro. Sombras escorrendo para o centro, borda granada nítida; relógio."),
               F("implosao", 320, 320, 8, 500, "ar", "monstro (sqm)", "centro",
                 "Tudo é sugado para o monstro: implosão negra, um anel frio no último frame.")])

spell(tier="deathlord", key="eclipse", nome="Eclipse Total", tipo="golpe final com refúgios",
      conceito="O selo partido de cinco pontas se abre sob o monstro; a luz morre — só os refúgios de luz fria salvam.",
      mecanica=[
          "Usado ao chegar a 70% e a 30% de vida (e no máx. 1 vez a cada 35 s). O monstro fica parado.",
          "O selo cobre 5 sqm em volta do monstro (11×11 arredondado). A tela escurece em volta (feito pelo código).",
          "3 refúgios: sqm a 3–5 sqm do monstro, em direções diferentes, com colunas de luz fria.",
          "Aviso de 3,0 s. Quem estiver no selo e fora de um refúgio toma o golpe.",
      ],
      esquiva="Chegar a um refúgio (sempre a no máx. 3 passos) ou sair do selo.",
      dano="2,5 × R de morte (feito para matar quem não desviar)",
      timeline=[("selo + refúgios", 3000), ("eclipse", 700)],
      files=[
          F("selo_marca", 512, 512, 12, 3000, "chão", "monstro (sqm)", "centro",
            "O selo de cinco pontas partido (o MESMO da aura do Lord of Death) se desenha no chão: veias granada "
            "convergindo, fumaça negra. Entregar em 512×512 — o jogo amplia para 11×11 sqm, então pintura suave, "
            "sem detalhe de 1 pixel. Relógio: o selo se completa no fim."),
          F("refugio_entrada", 64, 192, 6, 300, "ar", "sqm", "base",
            "Os refúgios: coluna de luz fria (azul-pérola) subindo de 1 sqm. A ÚNICA luz forte da tela — tem que ser o mais visível."),
          F("refugio_loop", 64, 192, 4, "loop", "ar", "sqm", "base", "↑ em loop até o eclipse."),
          F("eclipse", 512, 512, 10, 700, "ar", "monstro (sqm)", "centro",
            "O eclipse: tudo escurece e implode para o monstro; os refúgios continuam acesos. 512×512, ampliado para 11×11 sqm."),
      ])


def tier_of(key):
    for t in TIERS:
        if t["key"] == key:
            return t
    raise KeyError(key)


SPELL_MULT = {
    "pluma": 1.0, "lagrimas": 0.9, "veu": 1.4,
    "brasa": 1.0, "flor": 1.4, "investida": 1.2,
    "feixe": 1.3, "coroa": 1.1, "reflexos": 1.2,
    "garra": 1.8, "sol": 0.6, "colapso": 2.0, "eclipse": 2.5,
}


def ref_hit(xp):
    return max(15, round(5 * min(xp, 100000) ** 0.55))


EXAMPLES = [("Rat", 5), ("Rotworm", 40), ("Cyclops", 150), ("Necromancer", 580), ("Dragon", 700),
            ("Dragon Lord", 2100), ("Behemoth", 2500), ("Warlock", 4000), ("Demon", 6000),
            ("Hellflayer", 11000), ("Brachiodemon", 22880), ("Infernal Demon", 26000)]
