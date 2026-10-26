# -*- coding: utf-8 -*-
# Especificacao do chefe "ET de Varginha" (fonte unica do briefing: HTML,
# CSV, diagramas e pasta de entrega).

THEME = {
    "key": "et", "nome": "ET de Varginha", "pasta": "et",
    "cor": (216, 30, 30), "luz": (255, 107, 74), "sombra": (59, 36, 24),
}

# o chefe: XP de onde sai o golpe de referencia R (mesma formula das magias
# do Renascimento) e o resto dos numeros iniciais
BOSS = {"xp": 60000, "vida": 250000, "nivel": "grupo de 3 a 5 jogadores, nível 300+"}


def ref_hit(xp):
    return max(15, round(5 * min(xp, 100000) ** 0.55))


PALETAS = [
    ("Pele do ET", [("sombra", "#3B2418"), ("base", "#6B4229"), ("luz", "#A0673F"), ("brilho oleoso", "#E8C49A"), ("veia", "#4A2A1C")]),
    ("Olhos", [("fundo", "#7A0A0A"), ("vermelho", "#D81E1E"), ("brilho", "#FF6B4A"), ("reflexo", "#FFE3D6")]),
    ("Disco voador / feixe", [("metal escuro", "#1E2B3A"), ("metal", "#8FA3B5"), ("luz fria", "#BFF6FF"), ("verde de OVNI", "#6CFFD8")]),
    ("Amônia", [("sombra", "#4E5720"), ("gás", "#B8C24A"), ("borda", "#E6EC9A")]),
    ("Noite de Varginha", [("céu", "#141A2E"), ("poste de sódio", "#F2A03A"), ("folha de café", "#2F5D2A"), ("café maduro", "#B3261E")]),
]

# ---------------------------------------------------------------- arquivos
def F(nome, w, h, frames, ms, camada, preso, ancora, desc):
    return {"nome": nome, "w": w, "h": h, "frames": frames, "ms": ms, "camada": camada,
            "preso": preso, "ancora": ancora, "desc": desc}


ORIENT = ["h", "v", "ne", "nw"]
DIRS = [("norte", "N"), ("leste", "E"), ("sul", "S"), ("oeste", "W")]


def seg(prefix, frames, ms, camada, desc, ways=ORIENT):
    return [F(f"{prefix}_{o}", 64, 64, frames, ms, camada, "sqm", "seg", desc if i == 0 else "↑ mesma peça, outra orientação")
            for i, o in enumerate(ways)]


def sprite_frames(prefix, size, idle, walk, desc_idle, desc_walk):
    files = []
    for i, (d, _) in enumerate(DIRS):
        for k in range(1, idle + 1):
            files.append(F(f"{prefix}{d}_parado_{k}", size, size, 1, "sprite", "sprite", "—", "sprite",
                           desc_idle if (i == 0 and k == 1) else "↑"))
        for k in range(1, walk + 1):
            files.append(F(f"{prefix}{d}_andando_{k}", size, size, 1, "sprite", "sprite", "—", "sprite",
                           desc_walk if (i == 0 and k == 1) else "↑"))
    return files


# Grupos de entrega: sprites (pixel art 1x, como os do Tibia), itens do mapa,
# itens de loot e as magias (APNG 2x, como as do Renascimento).
GROUPS = []


def group(**kw):
    GROUPS.append(kw)


group(key="sprites/et_em_pe", nome="ET em pé", tipo="sprite do chefe (outfit 1)", etapa=1,
      intro="O ET andando e lutando. Corpo magro e curvado, cabeçona com os três calombos, olhos vermelhos enormes. "
            "Parado: respira, os olhos piscam um brilho fraco, um tremor leve. Andando: passos curtos e desajeitados, "
            "meio corridinho — ele não é um guerreiro, é um bicho perdido.",
      files=sprite_frames("", 64, 4, 8,
                          "Parado, 4 frames em loop (~200 ms cada). Frame 64×64, o sqm do ET é o quadrado 32×32 de baixo à direita "
                          "(igual a toda criatura grande do Tibia — ver referencias/gabarito_sprite.png).",
                          "Andando, 8 frames (um passo completo, ~150 ms cada)."))

group(key="sprites/et_agachado", nome="ET agachado", tipo="sprite do chefe (outfit 2)", etapa=1,
      intro="A pose do meme: agachado, abraçando os joelhos, tremendo, olhando de lado com medo. O jogo troca para este "
            "outfit no Agachadinho (e o ET pode se arrastar agachado). É a imagem que todo mundo vai printar.",
      files=sprite_frames("", 64, 4, 4,
                          "Agachado parado, 4 frames em loop: tremendo, os olhos se mexendo assustados.",
                          "Agachado se arrastando, 4 frames (o jogo repete para fazer 8)."))

group(key="sprites/et_cadaver", nome="Cadáver do ET", tipo="item (corpo)", etapa=1,
      intro="O ET caído de lado, olhos apagando. Três estágios: logo depois da morte, apodrecendo (pele mais escura, "
            "poça oleosa), só a ossada/pele seca com os três calombos.",
      files=[F("cadaver_1", 64, 64, 1, "sprite", "sprite", "—", "sprite", "Recém-morto: olhos ainda com um vermelho fraco."),
             F("cadaver_2", 64, 64, 1, "sprite", "sprite", "—", "sprite", "Apodrecendo: pele escura, poça oleosa."),
             F("cadaver_3", 64, 64, 1, "sprite", "sprite", "—", "sprite", "Seco: pele murcha e os três calombos.")])

group(key="sprites/etzinho", nome="ETzinho", tipo="sprite do lacaio", etapa=2,
      intro="Filhotes do ET (versão pequena, 1 sqm). Agachadinhos e medrosos: fogem dos jogadores. Mesma pele, mesmos "
            "olhos, calombos pequenininhos.",
      files=sprite_frames("", 32, 2, 4,
                          "Parado, 2 frames (32×32, ocupa 1 sqm): tremendo.",
                          "Andando/fugindo, 4 frames."))

group(key="sprites/montaria_disco", nome="Montaria: Disco Voador de Varginha", tipo="montaria (recompensa rara)", etapa=2,
      intro="Uma montaria no formato da caixa d'água-disco-voador de Varginha: disco prateado com luzinhas em volta e "
            "cúpula de vidro onde o jogador senta. Mesmo formato do Fusca, do Uno com escada e do Gol bolinha "
            "(referencias/exemplo_montaria_fusca/): 1 frame 64×64 por direção, o jogo faz o balanço.",
      files=[F(d, 64, 64, 1, "sprite", "sprite", "—", "sprite", "Na diagonal do Tibia, como o Fusca." if i == 0 else "↑")
             for i, (d, _) in enumerate(DIRS)])

group(key="itens/mapa", nome="Itens da arena", tipo="itens do mapa (1x)", etapa=1,
      intro="As peças que fazem a arena ser Varginha. Muro, chão e oficina usam sprites que já existem no Tibia; só estes "
            "são novos.",
      files=[
          F("ponto_onibus_base", 64, 64, 1, "sprite", "sprite", "—", "sprite",
            "Ponto de ônibus-disco-voador (como os de Varginha), 2×2 sqm: o chão, o banco e as colunas. O jogador fica "
            "embaixo — é o refúgio do golpe final."),
          F("ponto_onibus_teto", 64, 64, 1, "sprite", "sprite", "—", "sprite",
            "O teto em forma de disco voador, desenhado por cima de quem está embaixo (como a copa de uma árvore). "
            "Fino o bastante para ainda se ver o jogador."),
          F("caixa_dagua_disco", 128, 192, 1, "sprite", "sprite", "—", "sprite",
            "A caixa d'água-disco-voador de Varginha (4×6 sqm), cenário no fundo da arena: torre fina e o disco no alto "
            "com luzinhas."),
          F("pe_de_cafe_com_frutos", 32, 64, 1, "sprite", "sprite", "—", "sprite",
            "Pé de café (Varginha é capital do café) cheio de frutos vermelhos. O jogador usa: toma um Cafezinho."),
          F("pe_de_cafe_colhido", 32, 64, 1, "sprite", "sprite", "—", "sprite", "O mesmo pé depois de usado (sem frutos, 20 s)."),
          F("placa_varginha", 64, 32, 1, "sprite", "sprite", "—", "sprite",
            "Placa \"VARGINHA — TERRA DO ET\", com um ETzinho desenhado."),
          F("muro_grafite", 32, 64, 1, "sprite", "sprite", "—", "sprite",
            "Opcional: pedaço de muro chapiscado com o grafite \"O ET EXISTE\". Vai no lugar onde o ET se agacha."),
      ])

group(key="itens/loot", nome="Itens de loot", tipo="ícones (1x)", etapa=2,
      intro="O que o ET deixa. Ícones 32×32 no estilo dos itens do Tibia.",
      files=[
          F("calombo_do_et", 32, 32, 1, "sprite", "sprite", "—", "sprite", "Troféu: um dos três calombos da cabeça, marrom e oleoso."),
          F("olho_vermelho", 32, 32, 1, "sprite", "sprite", "—", "sprite", "Amuleto com um olho vermelho sem pupila, brilhando."),
          F("cafe_de_varginha", 32, 32, 1, "sprite", "sprite", "—", "sprite", "Saquinho de café com a carinha do ET (comida: dá velocidade)."),
          F("boneco_do_et", 32, 32, 1, "sprite", "sprite", "—", "sprite", "Decoração: bonequinho do ET agachado, de lembrancinha."),
          F("pedaco_da_nave", 32, 32, 1, "sprite", "sprite", "—", "sprite", "Sucata metálica do disco com uma luzinha ciano."),
      ])

# ---------------------------------------------------------------- magias
SPELLS = []


def spell(**kw):
    kw.setdefault("tier", "et")
    SPELLS.append(kw)


spell(key="comum", nome="Peças comuns", tipo="usadas por várias magias", etapa=1,
      files=[
          F("olhos_brilho", 128, 128, 6, "loop", "ar", "chefe", "centro",
            "Os dois olhos acendendo vermelho forte na cabeça do ET (o 'vou lançar' do Olhar Vermelho e da fúria). "
            "Só o brilho: o sprite já tem os olhos."),
          F("acerto", 128, 128, 6, 300, "ar", "jogador", "centro",
            "Golpe de energia alienígena em quem foi atingido: faíscas vermelhas e um anel de distorção."),
      ])

spell(key="olhar", nome="Olhar Vermelho", tipo="mira que segue e trava", etapa=1, fase="1, 2 e 3",
      conceito="Os olhões vermelhos sem pupila miram no jogador e disparam dois raios paralelos.",
      mecanica=[
          "Fio de mira de 9 sqm nas 8 direções. Durante 1,0 s ele SEGUE o jogador.",
          "Então TRAVA e, 0,6 s depois, dispara: dano em toda a linha até a parede.",
          "Os olhos do ET (olhos_brilho) acendem durante todo o aviso.",
      ],
      esquiva="Quando travar, um passo para o lado.",
      dano="1,2 × R de energia", mult=1.2,
      timeline=[("mira segue", 1000), ("travada", 600), ("raios", 350)],
      files=seg("mira", 4, "loop", "chão", "Mira: um fio vermelho fino e tremido, pontilhado, saindo dos olhos.")
            + seg("trava", 8, 600, "chão", "Travou: o fio vira DOIS fios paralelos (os dois olhos) e vai ficando mais forte até o disparo (relógio).")
            + seg("raio", 6, 350, "ar", "Os dois raios vermelhos paralelos com calor tremendo em volta.")
            + [F("raio_fim", 128, 128, 6, 350, "ar", "sqm", "centro", "Onde os raios param (parede ou alcance): estouro vermelho.")])

spell(key="calombos", nome="Três Calombos", tipo="3 áreas, relógio na cabeça", etapa=1, fase="1, 2 e 3",
      conceito="Os três calombos da cabeça acendem um por um — é o relógio — e no terceiro três áreas explodem.",
      mecanica=[
          "Marca 3 círculos 3×3: um embaixo de cada jogador (até 3) e o resto perto deles.",
          "Os calombos acendem em 0,6 s, 1,2 s e 1,8 s (1, 2, 3). As marcas acendem um terço junto com cada calombo.",
          "No terceiro, os três círculos explodem ao mesmo tempo.",
      ],
      esquiva="Sair do círculo antes do terceiro calombo.",
      dano="1,0 × R de energia", mult=1.0,
      timeline=[("1º calombo", 600), ("2º calombo", 600), ("3º calombo", 600), ("pulso", 400)],
      files=[F(f"coroa_{n}", 128, 128, 4, "loop", "ar", "chefe", "centro",
               "Brilho em cima da cabeça com 1, 2 e 3 luzes acesas (uma por calombo). Fica sobre o sprite, nas 4 direções — "
               "por isso é um halo no alto da cabeça, não precisa bater pixel a pixel." if n == 1 else "↑ com mais uma luz acesa")
             for n in (1, 2, 3)]
          + [F("marca", 192, 192, 12, 1800, "chão", "sqm", "centro",
               "Círculo 3×3 dividido em três terços: cada terço acende junto com um calombo (o relógio é contado em 3, "
               "não em arco contínuo)."),
             F("pulso", 192, 192, 6, 400, "ar", "sqm", "centro", "Pulso psíquico: anel de distorção vermelho-marrom subindo do círculo.")])

spell(key="grito", nome="Agachadinho e o Grito", tipo="esconda-se atrás do muro", etapa=1, fase="1, 2 e 3 (a cada 30 s)",
      conceito="O ET corre para o muro e se agacha, morrendo de medo — exatamente como em 1996. Aí ele grita. Sem boca: "
               "o grito é dentro da cabeça de quem está olhando para ele.",
      mecanica=[
          "O ET vai até o canto do muro e troca para o outfit agachado: 3,0 s tremendo, toma 90% menos dano.",
          "No fim, o Grito: todo jogador na arena com linha de visão até o ET toma o golpe e fica com Medo (sai correndo) por 1,5 s.",
          "Quem estiver ATRÁS de algo que bloqueia a visão (pilar do muro, o Fusca velho, os tambores) não toma nada.",
          "O jogo marca no chão os sqm de sombra seguros (sombra_segura).",
      ],
      esquiva="Esconder-se atrás de um obstáculo durante os 3 s.",
      dano="2,2 × R de energia + Medo 1,5 s", mult=2.2,
      timeline=[("agachado, tremendo", 3000), ("grito", 600)],
      files=[
          F("tremendo", 128, 128, 4, "loop", "ar", "chefe", "centro",
            "Por cima do ET agachado: gotinhas de suor, linhas de tremor e um '!' — o 'ele estava com medo' do meme."),
          F("ondas_carga", 448, 448, 12, 3000, "chão", "chefe", "centro",
            "Anéis no chão em volta do ET (7×7 sqm), apertando para dentro até ele gritar (relógio)."),
          F("sombra_segura", 64, 64, 4, "loop", "chão", "sqm", "centro",
            "Marca dos sqm protegidos: uma sombra azulada e calma no chão. Tem que ler como 'aqui pode'."),
          F("grito", 448, 448, 8, 600, "ar", "chefe", "centro",
            "O grito: ondas de distorção saindo do ET em todas as direções (cor de olho e de pele, nada de branco)."),
          F("medo", 64, 96, 4, "loop", "ar", "jogador", "base",
            "Jogador com Medo: carinha de susto/estrelinhas em cima da cabeça. Discreto."),
      ])

spell(key="abducao", nome="Abdução", tipo="círculo que persegue", etapa=2, fase="2 e 3",
      conceito="Um disco voador pequeno chega por cima de um jogador e liga o feixe trator.",
      mecanica=[
          "O disco surge sobre um jogador e o segue 1 sqm a cada 0,6 s por 3,0 s (mais devagar que qualquer jogador andando).",
          "No chão, um círculo 3×3 de luz que vai fechando (relógio).",
          "No fim, quem estiver no círculo é abduzido: sobe (preso) por 2 s, toma dano e cai num lugar aleatório da arena.",
      ],
      esquiva="Continuar andando para longe do círculo.",
      dano="1,5 × R de energia + abdução", mult=1.5,
      timeline=[("disco chega", 500), ("persegue e fecha", 3000), ("abduz", 500), ("no ar", 2000)],
      files=[
          F("disco_chega", 128, 128, 6, 500, "ar", "sqm", "centro", "O discozinho descendo do alto com as luzes girando."),
          F("disco_loop", 128, 128, 8, "loop", "ar", "sqm", "centro", "Pairando ~1,5 sqm acima do chão, luzes girando."),
          F("disco_voo_1", 128, 128, 1, "parado", "ar", "sqm", "centro", "Frames PARADOS do disco andando de um sqm para o outro."),
          F("disco_voo_2", 128, 128, 1, "parado", "ar", "sqm", "centro", "↑"),
          F("disco_voo_3", 128, 128, 1, "parado", "ar", "sqm", "centro", "↑"),
          F("disco_voo_4", 128, 128, 1, "parado", "ar", "sqm", "centro", "↑"),
          F("disco_vai", 128, 128, 6, 500, "ar", "sqm", "centro", "Sobe e some com um brilho."),
          F("circulo", 192, 192, 12, 3000, "chão", "sqm", "centro", "Círculo de luz fria no chão (3×3) fechando para o centro (relógio)."),
          F("feixe", 192, 288, 6, 500, "ar", "sqm", "base",
            "O feixe trator do disco até o chão (3 sqm de largura, ~4,5 de altura). A base de 192×64 é o chão."),
          F("levitando", 64, 128, 4, "loop", "ar", "jogador", "base", "O jogador abduzido flutuando dentro da luz."),
      ])

spell(key="chuva", nome="Chuva de Discos", tipo="faixas que atravessam a arena", etapa=2, fase="2 e 3",
      conceito="Uma frota de discos pequenos atravessa a arena em fileiras, com farol aceso.",
      mecanica=[
          "Onda 1: metade das fileiras (alternadas) é marcada na arena inteira; 1,5 s depois os discos atravessam (40 ms por sqm).",
          "Onda 2: logo em seguida, as outras fileiras.",
          "Na fase 3 também vem em colunas (de cima para baixo).",
      ],
      esquiva="Ficar numa fileira não marcada; na segunda onda, trocar de fileira.",
      dano="1,1 × R de energia por disco", mult=1.1,
      timeline=[("onda 1", 1500), ("discos", 600), ("onda 2", 1500), ("discos", 600)],
      files=[F(f"faixa_{d}", 64, 64, 4, "loop", "chão", "sqm", "seg",
               "Fileira marcada: setinhas de luz no chão apontando para onde os discos vão (leste, oeste, norte ou sul)."
               if i == 0 else "↑ outra direção") for i, d in enumerate(["e", "w", "n", "s"])]
          + [F("farol", 128, 128, 4, "loop", "ar", "sqm", "centro", "Na borda da arena, de onde os discos vêm: o farol ofuscando."),
             F("disquinho_1", 64, 64, 1, "parado", "ar", "sqm", "centro", "Disquinho voando (frames parados, gira — serve para as 4 direções)."),
             F("disquinho_2", 64, 64, 1, "parado", "ar", "sqm", "centro", "↑"),
             F("disquinho_3", 64, 64, 1, "parado", "ar", "sqm", "centro", "↑"),
             F("disquinho_4", 64, 64, 1, "parado", "ar", "sqm", "centro", "↑")]
          + seg("rastro", 4, 250, "ar", "Rastro de luz atrás do disquinho.", ways=["h", "v"]))

spell(key="amonia", nome="Cheiro de Amônia", tipo="gás que anda + cafezinho", etapa=2, fase="3",
      conceito="Na fúria, o ET solta o cheiro forte de amônia que todo relato menciona. A cura é a especialidade da cidade: café.",
      mecanica=[
          "A cada 6 s nasce uma nuvem 3×3 perto de um jogador; ela anda devagar atrás dele e dura 8 s.",
          "Dentro da nuvem: dano de terra por segundo e Enjoado (–20% de velocidade).",
          "Os pés de café da arena dão um Cafezinho (usar o pé): tira o Enjoado e dá +20% de velocidade por 5 s. Cada pé recarrega em 20 s.",
      ],
      esquiva="Andar para fora do gás; tomar um cafezinho quando enjoar.",
      dano="0,3 × R de terra por segundo", mult=0.3,
      timeline=[("nuvem nasce", 400), ("nuvem anda (8 s)", 8000), ("some", 500)],
      files=[
          F("nuvem_entrada", 192, 192, 6, 400, "ar", "sqm", "centro", "A nuvem de gás amarelo-esverdeado surgindo (3×3)."),
          F("nuvem_loop", 192, 192, 8, "loop", "ar", "sqm", "centro",
            "O gás vivo, com as 'ondinhas de fedor' de desenho animado, mas pintado no estilo do kit. Translúcido."),
          F("nuvem_saida", 192, 192, 6, 500, "ar", "sqm", "centro", "Dissipando."),
          F("enjoado", 64, 96, 4, "loop", "ar", "jogador", "base", "Jogador enjoado: fiapos verdes e ondinhas de fedor em volta da cabeça."),
          F("cafezinho", 64, 96, 6, 600, "ar", "jogador", "base", "O cafezinho: xicrinha com vapor subindo e o enjoo indo embora."),
      ])

spell(key="busquem_conhecimento", nome="BUSQUEM CONHECIMENTO", tipo="golpe final, carga longa, refúgios", etapa=2,
      fase="aos 35% e aos 15% de vida",
      conceito="O golpe mais forte do ET, e o mais demorado. Ele flutua no meio da arena e manda, direto na cabeça de todo "
               "mundo: BUSQUEM CONHECIMENTO. A frase vai se escrevendo no céu, letra por letra — é o relógio. Quando ela "
               "completa, a nave-mãe (a caixa d'água-disco-voador!) despeja o raio na arena toda. Só escapa quem está "
               "embaixo dos pontos de ônibus-disco-voador, como bom varginhense esperando o circular.",
      mecanica=[
          "Carga longa: 6,0 s. O ET vai para o centro, flutua e não ataca nem anda — é a janela para bater nele.",
          "A frase BUSQUEM CONHECIMENTO aparece sobre a arena e acende uma letra a cada 0,3 s (20 caracteres = 6 s).",
          "Ao mesmo tempo a sombra da nave cobre a arena e a tela escurece (código). Os dois pontos de ônibus (2×2) brilham: são os refúgios.",
          "Na última letra, o raio da nave atinge toda a arena, menos quem está embaixo de um ponto de ônibus.",
      ],
      esquiva="Chegar embaixo de um ponto de ônibus antes da última letra (cabem 4 jogadores em cada). Quem ficar batendo no ET até o fim, morre.",
      dano="3,5 × R de energia (feito para matar)", mult=3.5,
      timeline=[("BUSQUEM CONHECIMENTO — a frase se escreve", 6000), ("raio", 700)],
      files=[
          F("frase", 768, 192, 20, 6000, "ar", "centro da arena", "centro",
            "A frase \"BUSQUEM CONHECIMENTO\" flutuando sobre a arena (12×3 sqm), letras de luz vermelho-alienígena com "
            "contorno escuro. Frame 1: tudo apagado; cada frame acende mais uma letra (o espaço também conta); no frame 20 "
            "a frase inteira brilha forte. É o relógio do golpe: tem que ler de qualquer canto da tela."),
          F("aura_carga", 192, 192, 8, "loop", "ar", "chefe", "centro",
            "O ET carregando: aura psíquica em volta dele, os três calombos e os olhos no máximo, poeira e pedrinhas "
            "subindo do chão como se ele flutuasse."),
          F("sombra", 512, 512, 12, 6000, "chão", "centro da arena", "centro",
            "A sombra da nave cobrindo a arena, com um anel de luzinhas na borda. 512×512, o jogo amplia para a arena "
            "inteira (~15×15 sqm): pintura suave."),
          F("nave_passando", 512, 512, 10, 1000, "ar", "centro da arena", "centro",
            "A barriga da nave-mãe passando por cima, luzes acesas — bem translúcida no centro para não esconder os jogadores."),
          F("ponto_seguro", 128, 128, 4, "loop", "chão", "ponto de ônibus", "centro",
            "Brilho branco-frio no chão embaixo de um ponto de ônibus (2×2): 'aqui é seguro'. A luz mais forte da tela."),
          F("raio", 512, 512, 8, 700, "ar", "centro da arena", "centro",
            "O raio da nave: colunas de luz caindo na arena toda. O jogo desenha o ponto_seguro por cima nos refúgios."),
      ])


def all_items():
    for g in GROUPS:
        for f in g["files"]:
            yield g, f
    for s in SPELLS:
        for f in s["files"]:
            yield s, f
