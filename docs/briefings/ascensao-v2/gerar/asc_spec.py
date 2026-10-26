# -*- coding: utf-8 -*-
# Especificacao das artes v2 das magias da Ascensao: camadas + curvas, 60 fps.

# tipo: "parada" (PNG de 1 frame, o jogo anima por curvas), "flipbook" (APNG
# curto, o jogo mistura os frames), "particula" (PNG pequeno que o jogo
# espalha em varias copias), "relogio" (APNG tocado no tempo exato do aviso)
# blend: "normal" ou "luz" (somada por cima, como brilho)
# extra: "gira" (desenhada apontando para a direita, o jogo gira para a
# direcao), "estica" (o jogo estica ao longo do caminho)


def L(nome, tipo, w, h, momento, desc, frames=1, blend="normal", extra=""):
    return {"nome": nome, "tipo": tipo, "w": w, "h": h, "frames": frames, "blend": blend,
            "extra": extra, "momento": momento, "desc": desc}


def parts(prefix, n, w, momento, desc, blend="normal"):
    return [L(f"{prefix}_{i}", "particula", w, w, momento, desc if i == 1 else "↑ outra variação", blend=blend) for i in range(1, n + 1)]


VOCATIONS = [
    {"key": "knight", "nome": "Knight", "titulo": "Titan Knight", "tema": "O Titã",
     "paleta": [("aço", "#8E99A6"), ("terra", "#5B4632"), ("brasa", "#FF7A2A"), ("núcleo", "#FFD9A0"), ("sombra", "#1E1A17")],
     "assinatura": "Runas de brasa que acendem no chão e rachaduras com magma por dentro.",
     "movimento": "Peso: tudo demora a subir e cai de uma vez. Antecipação longa, impacto seco, poeira que fica.",
     "luz": "laranja de brasa (cor 199)"},
    {"key": "paladin", "nome": "Paladin", "titulo": "Seraph Paladin", "tema": "O Serafim",
     "paleta": [("núcleo", "#FFF6D8"), ("ouro", "#FFC94D"), ("âmbar", "#E8913A"), ("crepúsculo", "#7A5CC2"), ("noite", "#2A1F45")],
     "assinatura": "Penas de luz e halos. O dourado sempre esfria em violeta nas bordas (o crepúsculo).",
     "movimento": "Precisão: linhas retas, velocidade, um brilho limpo; depois as penas descem devagar.",
     "luz": "dourada (cor 205)"},
    {"key": "sorcerer", "nome": "Sorcerer", "titulo": "Archon Sorcerer", "tema": "O Arconte",
     "paleta": [("núcleo", "#DDEBFF"), ("arcano", "#4F7BFF"), ("vazio", "#6B2BD9"), ("inferno", "#FF6A1A"), ("noite", "#120C24")],
     "assinatura": "Círculos rúnicos geométricos que giram e se fecham. Energia instável que colapsa e explode.",
     "movimento": "Tensão: encolhe antes de explodir, gira, crepita; explosões com onda de choque.",
     "luz": "azul arcano (cor 53), violeta no vazio (119), laranja no fogo (199)"},
    {"key": "druid", "nome": "Druid", "titulo": "Primordial Druid", "tema": "O Primordial",
     "paleta": [("branco gelo", "#F4FBFF"), ("gelo", "#8FD3FF"), ("gelo fundo", "#2E6FA8"), ("verde vivo", "#4FAE4A"), ("casca", "#5A3B22"), ("veneno", "#9B5BC7")],
     "assinatura": "Cristais facetados que estalam e coisas que crescem: raízes, folhas, brotos.",
     "movimento": "Crescer e cristalizar: surge do chão, estala, se parte em lascas, a névoa fica.",
     "luz": "azul-gelo (cor 137), verde (cor 55)"},
    {"key": "monk", "nome": "Monk", "titulo": "Enlightened Monk", "tema": "O Iluminado",
     "paleta": [("ki branco", "#FFF3D1"), ("ki dourado", "#FFC86B"), ("jade", "#5FD1B0"), ("céu", "#9FD8FF"), ("tinta", "#1B2A3A")],
     "assinatura": "Pinceladas de tinta (estilo sumi-e) carregadas de ki, e ecos (vultos) do movimento.",
     "movimento": "Fluidez e kime: tudo desliza com rastro, para por um instante e explode.",
     "luz": "dourada suave (cor 205), jade no Passo Fantasma (cor 99)"},
]

SPELLS = [
    # ------------------------------------------------------------ knight
    dict(voc="knight", key="corte", nome="Corte Sísmico", caminho="Reaver · alvo único", words="exori tera ico",
         momentos="carga (3 níveis) → cheia (clarão) → o corte corre sqm a sqm pela linha → acerto; ou cancelamento.",
         diag=["A carga lê como uma poça de brasa: não sobe, não cresce de verdade entre os níveis.",
               "A fenda tem 6 frames em 1 sqm e some rápido; o corte não tem peso nem pedras voando."],
         direcao="Um anel de runas de brasa acende no chão e gira enquanto a arma do cavaleiro brilha cada vez mais; "
                 "ao soltar, a terra abre em linha reta com magma, pedras voam a cada sqm e o acerto explode em brasa.",
         camadas=[
             L("carga_runas", "parada", 192, 192, "carga", "Anel de runas de brasa no chão sob o cavaleiro. Os 3 níveis são a curva (escala, luz e giro crescem) — não há mais carga_1/2/3."),
             L("carga_brilho", "parada", 128, 128, "carga", "Brilho na arma/no corpo, pulsa mais rápido a cada nível.", blend="luz"),
             *parts("carga_fagulha", 3, 32, "carga", "Fagulhas subindo do anel.", blend="luz"),
             L("cheia_flash", "parada", 192, 192, "cheia", "Clarão quando a carga está cheia.", blend="luz"),
             *[L(f"fenda_{o}", "flipbook", 64, 64, "corte", "A rachadura abrindo com magma (chão em perspectiva: uma por orientação)." if o == "h" else "↑ outra orientação", frames=8) for o in ("h", "v", "ne", "nw")],
             L("fenda_brilho", "parada", 64, 64, "corte", "Brilho do magma na fenda.", blend="luz", extra="gira"),
             *parts("rocha", 3, 32, "corte", "Pedras arremessadas em arco a cada sqm."),
             L("poeira", "parada", 128, 128, "corte", "Nuvem de poeira que incha e some."),
             L("acerto_nucleo", "parada", 128, 128, "acerto", "Estouro de brasa no atingido.", blend="luz"),
             L("acerto_onda", "parada", 192, 192, "acerto", "Onda de choque no chão."),
         ]),
    dict(voc="knight", key="salto", nome="Salto do Titã", caminho="Juggernaut · área", words="exani gran ico",
         momentos="salto (poeira na saída, sombra crescendo onde vai cair, `ms`) → queda (impacto e onda 5×5).",
         diag=["A sombra é só uma elipse escura: não diz onde a onda vai pegar (5×5).",
               "A onda de 8 frames em 400 ms acaba antes de dar a sensação de peso."],
         direcao="O titã sai do chão deixando um anel de poeira; o pouso é marcado no chão com runas de brasa 5×5 que se "
                 "completam como relógio; a queda é o momento mais pesado da Ascensão: núcleo de luz, onda de choque, chão "
                 "rachado que fica, pedras, poeira em anel e a tela treme.",
         camadas=[
             L("saida_poeira", "flipbook", 128, 128, "salto", "Poeira levantando onde ele pula.", frames=8),
             L("saida_anel", "parada", 192, 192, "salto", "Anel de ar e poeira saindo do pé."),
             L("sombra", "parada", 128, 128, "salto", "A sombra crescendo onde ele cai."),
             L("alvo_relogio", "relogio", 320, 320, "salto", "As runas da área 5×5 acendendo até completar no instante da queda (o relógio).", frames=12),
             L("queda_nucleo", "parada", 192, 192, "queda", "Clarão do impacto.", blend="luz"),
             L("onda", "parada", 320, 320, "queda", "Onda de choque no chão (5×5)."),
             L("rachaduras", "parada", 320, 320, "queda", "Chão rachado com brasa que fica e esfria (pela curva)."),
             L("poeira_anel", "flipbook", 256, 256, "queda", "Anel de poeira rolando para fora.", frames=10),
             *parts("rocha", 3, 32, "queda", "Pedras voando (pode ser a mesma do Corte)."),
         ]),
    dict(voc="knight", key="gancho", nome="Gancho do Carrasco", caminho="Bastion · utilidade", words="exori grip",
         momentos="voo (o gancho anda sqm a sqm deixando a corrente) → acerto e puxão (a criatura cai ao lado, presa 600 ms); ou erro.",
         diag=["32 arquivos só para o gancho voando (8 direções × 4 frames) e ele ainda 'pula' de sqm em sqm.",
               "A corrente é uma tirinha fina; o impacto e o puxão são pequenos."],
         direcao="Um gancho pesado girando no ar com um risco vermelho, a corrente esticada atrás; no acerto, faíscas e "
                 "um tranco; a corrente fecha em anel nos pés de quem foi puxado.",
         camadas=[
             L("gancho", "parada", 64, 64, "voo", "O gancho desenhado apontando para a direita: o jogo gira para a direção e faz o giro no ar. Substitui os 32 arquivos de voo.", extra="gira"),
             L("corrente_elo", "parada", 64, 64, "voo", "Um elo da corrente: o jogo repete ao longo do caminho, girado.", extra="gira"),
             L("rastro", "parada", 256, 32, "voo", "Risco vermelho atrás do gancho.", blend="luz", extra="estica gira"),
             L("impacto_nucleo", "parada", 128, 128, "acerto", "Faísca grande do tranco.", blend="luz"),
             L("impacto_onda", "parada", 192, 192, "acerto", "Anel de impacto."),
             *parts("faisca", 3, 32, "acerto", "Faíscas de metal.", blend="luz"),
             L("puxao_arrasto", "flipbook", 64, 64, "puxão", "Poeira do arrasto.", frames=6),
             L("puxao_anel", "parada", 128, 128, "puxão", "A corrente fechando em anel nos pés (entra por escala)."),
             L("erro_poeira", "parada", 64, 64, "erro", "Poeirinha onde o gancho cai (o jogo faz o gancho girar e cair)."),
         ]),
    # ------------------------------------------------------------ paladin
    dict(voc="paladin", key="flecha", nome="Flecha do Crepúsculo", caminho="Hawkeye · alvo único", words="exori gran san vis",
         momentos="NOVO: puxar o arco (0,4 s, o paladino para) → soltar → a flecha voa muito rápido (30 ms por sqm: 12 sqm em 0,36 s) → acerto perto (1–7 sqm) ou longe (8–12, o feixe de luz) e o halo nos pés de quem fica preso; ou erro.",
         diag=["Não existe o gesto de atirar: a flecha simplesmente sai do paladino.",
               "96 arquivos de voo (3 forças × 8 direções × 4 frames) para uma flecha de ~20 px que anda devagar (80 ms por sqm).",
               "O acerto de longe é bonito, mas curto; não há rastro."],
         direcao="Pedido do dono do servidor: o paladino puxa um ARCO de luz, força a corda para trás e solta uma flecha "
                 "RÁPIDA. Um arco espectral dourado aparece na direção da mira; em 0,4 s a corda vai para trás e a energia "
                 "junta na ponta da flecha; na soltura, clarão e um tranco para trás; a flecha vira um risco de luz que "
                 "cruza a tela quase na hora, dourado esfriando em violeta. De longe, ela crava uma coluna de luz e penas.",
         mecanica="Entra a puxada de 0,4 s antes do disparo (paladino parado, mira travada no início) e o "
                  "voo passa de 80 ms para 30 ms por sqm. Dano por distância, prisão e alcance não mudam.",
         camadas=[
             L("arco_1", "parada", 128, 128, "puxar", "O arco espectral relaxado (corda reta). Desenhado apontando para a direita; o jogo gira para a mira.", blend="luz", extra="gira"),
             L("arco_2", "parada", 128, 128, "puxar", "Meio puxado.", blend="luz", extra="gira"),
             L("arco_3", "parada", 128, 128, "puxar", "Totalmente puxado (corda atrás, arco curvado). O jogo faz a transição suave 1→2→3 em 0,4 s.", blend="luz", extra="gira"),
             L("ponta_energia", "parada", 64, 64, "puxar", "Energia juntando na ponta da flecha encaixada (cresce com a puxada).", blend="luz"),
             L("soltar_flash", "parada", 192, 192, "soltar", "Clarão da soltura, alongado para a frente.", blend="luz", extra="gira"),
             L("soltar_anel", "parada", 128, 128, "soltar", "Anel de ar no arco (o tranco)."),
             L("flecha", "parada", 64, 64, "voo", "A flecha de luz (a cabeça).", blend="luz", extra="gira"),
             L("rastro", "parada", 256, 32, "voo", "O risco que se estica atrás da flecha e some: dourado na frente, violeta no fim.", blend="luz", extra="estica gira"),
             L("acerto_nucleo", "parada", 128, 128, "acerto", "Estouro de luz no atingido (perto).", blend="luz"),
             L("acerto_raio", "parada", 64, 256, "acerto longe", "Coluna de luz que sobe do atingido (8–12 sqm).", blend="luz"),
             L("acerto_anel", "parada", 192, 192, "acerto", "Anel dourado no chão."),
             *parts("pena", 3, 32, "acerto", "Penas de luz caindo devagar.", blend="luz"),
             L("preso_halo", "parada", 128, 128, "preso", "Halo nos pés de quem ficou preso; gira devagar."),
             L("erro_cravada", "parada", 64, 64, "erro", "A flecha cravada no chão, apagando."),
         ]),
    dict(voc="paladin", key="juizo", nome="Chuva de Juízo", caminho="Radiant · área", words="exevo gran san vis",
         momentos="marca (círculo dourado 3×3, 1 s; o raio desce nos últimos 0,2 s) → impacto.",
         diag=["O círculo é fino e plano; o raio é uma linha de 32 px.",
               "O impacto (8 frames) não deixa nada no chão."],
         direcao="Um círculo dourado com inscrições gira no chão e se completa (relógio); do céu desce um pilar de luz "
                 "largo; no impacto, raios de luz em leque, anel dourado, penas e o chão brilhando por um tempo.",
         camadas=[
             L("circulo", "parada", 192, 192, "marca", "Círculo com inscrições; gira devagar."),
             L("circulo_relogio", "relogio", 192, 192, "marca", "O arco que fecha em 1 s (a mesma linguagem de hoje, mais rico).", frames=12),
             L("centro", "parada", 64, 64, "marca", "Brilho no centro, pulsando.", blend="luz"),
             L("raio", "parada", 64, 384, "raio", "O pilar de luz descendo do céu (o jogo estica de cima para baixo).", blend="luz"),
             L("impacto_nucleo", "parada", 192, 192, "impacto", "Clarão.", blend="luz"),
             L("impacto_raios", "parada", 256, 256, "impacto", "Raios de luz em leque, o jogo gira e abre.", blend="luz"),
             L("impacto_anel", "parada", 256, 256, "impacto", "Anel dourado no chão."),
             L("brilho_chao", "parada", 192, 192, "impacto", "O chão abençoado brilhando e apagando devagar."),
             *parts("pena", 3, 32, "impacto", "Penas de luz.", blend="luz"),
         ]),
    dict(voc="paladin", key="lanca", nome="Lança Ricochete", caminho="Warden · utilidade", words="exori con vis",
         momentos="voo → ricochete (pula do atingido para o próximo, `ms`, até 3 vezes, +15% cada) → acerto (mais forte a cada pulo); errou: fica no chão brilhando; pisou nela: some com um clarão.",
         diag=["24 arquivos de voo para uma lança pequena; o ricochete é uma linha reta.",
               "Os 3 acertos são quase iguais; a lança no chão é discreta."],
         direcao="A lança corta o ar com um risco dourado e, a cada ricochete, faz um arco no ar (o jogo dá a altura); cada "
                 "acerto é maior que o anterior, o último com estrela de luz.",
         camadas=[
             L("lanca", "parada", 64, 64, "voo", "A lança apontando para a direita.", extra="gira"),
             L("rastro", "parada", 256, 32, "voo", "Risco dourado.", blend="luz", extra="estica gira"),
             L("acerto_nucleo", "parada", 128, 128, "acerto", "Estouro de luz; o jogo aumenta a cada ricochete.", blend="luz"),
             L("acerto_estrela", "parada", 192, 192, "acerto", "Estrela de luz (entra forte no último ricochete).", blend="luz", extra="gira"),
             *parts("faisca", 3, 32, "acerto", "Faíscas douradas.", blend="luz"),
             L("chao_lanca", "parada", 64, 64, "chão", "A lança cravada no chão."),
             L("chao_brilho", "parada", 128, 128, "chão", "Brilho em volta dela, pulsando.", blend="luz"),
             L("pegou_flash", "parada", 128, 128, "pegou", "Clarão quando o paladino pega.", blend="luz"),
         ]),
    # ------------------------------------------------------------ sorcerer
    dict(voc="sorcerer", key="raio", nome="Raio Arcano", caminho="Dread · alvo único", words="exevo gran vis",
         momentos="carga (3 níveis) → cheia → o feixe inteiro de uma vez em todos os sqm → acerto; ou para sem disparar.",
         diag=["24 peças de feixe (início, meio e ponta × 8 direções) e o feixe é fino.",
               "A carga é bonita mas pequena e com 4 frames."],
         direcao="Um círculo rúnico gira em volta do feiticeiro e um orbe cresce crepitando; o feixe é largo, com núcleo "
                 "branco e energia correndo por dentro, aberto de uma vez até o alvo; no fim, estouro e centelhas.",
         camadas=[
             L("carga_orbe", "parada", 128, 128, "carga", "O orbe que cresce (os 3 níveis são a curva).", blend="luz"),
             L("carga_runas", "parada", 192, 192, "carga", "Círculo rúnico girando em volta."),
             L("carga_raios", "flipbook", 128, 128, "carga", "Eletricidade crepitando.", frames=8, blend="luz"),
             L("cheia_flash", "parada", 192, 192, "cheia", "Clarão da carga cheia.", blend="luz"),
             L("feixe_corpo", "parada", 256, 64, "feixe", "O corpo do feixe na horizontal: o jogo estica até o fim e gira para a direção (substitui as 24 peças).", blend="luz", extra="estica gira"),
             L("feixe_turbulencia", "flipbook", 256, 64, "feixe", "A energia correndo por dentro.", frames=8, blend="luz", extra="estica gira"),
             L("feixe_origem", "parada", 128, 128, "feixe", "O clarão na mão do feiticeiro.", blend="luz"),
             L("feixe_ponta", "parada", 128, 128, "feixe", "A ponta do feixe.", blend="luz", extra="gira"),
             L("acerto_nucleo", "parada", 128, 128, "acerto", "Estouro arcano.", blend="luz"),
             L("acerto_anel", "parada", 192, 192, "acerto", "Anel de choque."),
             *parts("centelha", 3, 32, "acerto", "Centelhas azuis.", blend="luz"),
         ]),
    dict(voc="sorcerer", key="meteoro", nome="Meteoro", caminho="Inferno · área", words="exevo meteor",
         momentos="marca 3×3 (1,5 s; a rocha cai nos últimos 0,4 s, de cima à esquerda) → impacto → o chão queima 3 s.",
         diag=["O impacto dura 400 ms em 8 frames: acaba antes de impressionar.",
               "A queda são 8 imagens paradas pulando de sqm em sqm.",
               "Três arquivos de brasa (fortes, médias, fracas) para algo que a curva faz com um."],
         direcao="Ver o vídeo referencias/conceito_60fps_meteoro.mp4: a marca com runas girando e a sombra da rocha "
                 "crescendo; a rocha desce num só movimento suave com cauda de fogo; o impacto tem clarão, anel, "
                 "bola de fogo, pedras, fagulhas, luz no chão e tremor; a cratera esfria em 3 s.",
         camadas=[
             L("marca_relogio", "relogio", 192, 192, "marca", "O quadrado e o arco de hoje, mais ricos (o relógio de 1,5 s).", frames=12),
             L("marca_runas", "parada", 192, 192, "marca", "Runas de fogo girando devagar dentro da marca."),
             L("sombra", "parada", 192, 192, "marca", "A sombra da rocha crescendo no chão."),
             L("meteoro", "parada", 128, 128, "queda", "A rocha em chamas (apontando para a direita, o jogo gira para a descida).", extra="gira"),
             L("meteoro_cauda", "parada", 256, 64, "queda", "Cauda de fogo.", blend="luz", extra="estica gira"),
             L("impacto_nucleo", "parada", 256, 256, "impacto", "O clarão.", blend="luz"),
             L("impacto_anel", "parada", 320, 320, "impacto", "O anel de fogo do chão."),
             L("impacto_fogo", "flipbook", 256, 256, "impacto", "A bola de fogo e fumaça subindo.", frames=10),
             L("cratera", "parada", 192, 192, "chão", "Chão queimado com brasas: esfria pela curva em 3 s (substitui as 3 brasas)."),
             L("poeira", "parada", 256, 256, "impacto", "Poeira que incha, sobe e some."),
             *parts("rocha", 3, 32, "impacto", "Pedras."),
             *parts("fagulha", 2, 32, "impacto", "Fagulhas.", blend="luz"),
         ]),
    dict(voc="sorcerer", key="esfera", nome="Esfera do Vazio", caminho="Arcanist · utilidade", words="exevo vis mort",
         momentos="voo (atravessa criaturas, deixa rastro) → dito de novo: implode e explode (2 sqm); senão se desfaz no fim.",
         diag=["A esfera é uma bolinha de 4 frames parados; o rastro quase não aparece.",
               "A explosão é boa, mas a implosão que vem antes não existe."],
         direcao="Uma esfera escura com anel de acreção girando e borda violeta, deixando um rastro de vazio; ao comando, "
                 "tudo é sugado (implosão) e explode numa onda violeta.",
         camadas=[
             L("esfera", "parada", 64, 64, "voo", "O núcleo escuro com borda violeta."),
             L("esfera_anel", "parada", 128, 128, "voo", "Anel de acreção (o jogo gira sem parar)."),
             L("esfera_brilho", "parada", 96, 96, "voo", "Brilho violeta.", blend="luz"),
             L("rastro", "parada", 256, 32, "voo", "Rastro de vazio.", blend="luz", extra="estica gira"),
             L("implosao", "parada", 256, 256, "explosão", "Anel que encolhe até o centro."),
             L("explosao_nucleo", "parada", 192, 192, "explosão", "Clarão violeta.", blend="luz"),
             L("explosao_onda", "parada", 320, 320, "explosão", "Onda de vazio."),
             *parts("fragmento", 3, 32, "explosão", "Fragmentos escuros.", blend="normal"),
             L("desfazendo", "flipbook", 128, 128, "fim", "A esfera se desfazendo.", frames=8),
         ]),
    dict(voc="sorcerer", key="translocacao", nome="Translocação", caminho="Arcanist · 3º círculo", words="exani vis",
         momentos="o feiticeiro some, risca o ar e reaparece no destino (hoje usa efeitos do Tibia).",
         diag=["Não tem arte própria: são os efeitos antigos de teleporte e de energia."],
         direcao="Um círculo rúnico fecha sobre o feiticeiro, ele vira um risco arcano até o destino e abre outro círculo lá.",
         camadas=[
             L("saida_anel", "parada", 192, 192, "saída", "Círculo rúnico que se fecha."),
             L("saida_nucleo", "parada", 128, 128, "saída", "Ponto de luz que engole o feiticeiro.", blend="luz"),
             L("rastro", "parada", 256, 32, "trajeto", "Risco arcano da origem ao destino.", blend="luz", extra="estica gira"),
             L("chegada_anel", "parada", 192, 192, "chegada", "Círculo que se abre."),
             L("chegada_flash", "parada", 128, 128, "chegada", "Clarão.", blend="luz"),
             *parts("runa", 2, 32, "chegada", "Runinhas flutuando.", blend="luz"),
         ]),
    # ------------------------------------------------------------ druid
    dict(voc="druid", key="estilhaco", nome="Estilhaço de Gelo", caminho="Frostfang · alvo único", words="exori frigo vis",
         momentos="voo (atravessa, gela quem passa) → dito de novo: estilhaça 3×3 e atordoa (estrelas na cabeça); senão se desfaz.",
         diag=["A orbe é uma bolinha de gelo de 4 frames parados.",
               "O estilhaço tem 8 frames; a névoa e as lascas somem rápido."],
         direcao="Uma orbe facetada brilhando, soltando cristais pelo caminho; ao comando, estala em lascas que voam "
                 "girando, com uma névoa fria que se espalha; os atordoados ganham uma coroa de cristais girando.",
         camadas=[
             L("orbe", "parada", 64, 64, "voo", "A orbe facetada."),
             L("orbe_brilho", "parada", 96, 96, "voo", "Brilho frio.", blend="luz"),
             *parts("cristal", 2, 32, "voo", "Cristaizinhos soltando no caminho.", blend="luz"),
             L("geada", "parada", 64, 64, "passa", "Geada nos pés de quem a orbe atravessou."),
             L("estilhaco_nucleo", "parada", 128, 128, "estilhaço", "Clarão gelado.", blend="luz"),
             L("estilhaco_onda", "parada", 192, 192, "estilhaço", "Anel de gelo 3×3."),
             L("nevoa", "parada", 192, 192, "estilhaço", "Névoa fria que se espalha e some."),
             *parts("lasca", 3, 32, "estilhaço", "Lascas de gelo (o jogo gira cada uma)."),
             L("atordoado", "parada", 64, 64, "atordoado", "Coroa de cristais sobre a cabeça; o jogo gira."),
             L("desfazendo", "flipbook", 64, 64, "fim", "A orbe derretendo.", frames=6),
         ]),
    dict(voc="druid", key="muralha", nome="Muralha Glacial", caminho="Tempest · área", words="exevo frigo grav",
         momentos="cada bloco sobe (250 ms), fica brilhando, racha no último segundo e quebra (300 ms); gela os pés de quem encosta.",
         diag=["Subida, parada e rachando são 12 arquivos de 4–5 frames: o gelo 'pisca' em vez de brilhar."],
         direcao="Os blocos brotam do chão com um tranco e lascas, um brilho corre por dentro do gelo, as rachaduras "
                 "aparecem e a muralha explode em lascas e névoa.",
         camadas=[
             *[L(f"pilar_{o}", "parada", 64, 128, "subir/parado", "O bloco de gelo; a subida é o jogo crescendo do chão." if o == "ns" else "↑ outra orientação") for o in ("ns", "eo", "ne", "nw")],
             L("pilar_brilho", "parada", 64, 128, "parado", "O brilho correndo dentro do gelo.", blend="luz"),
             *[L(f"rachaduras_{o}", "parada", 64, 128, "rachando", "Rachaduras por cima do bloco (entram no último segundo)." if o == "ns" else "↑ outra orientação") for o in ("ns", "eo", "ne", "nw")],
             L("quebra", "flipbook", 128, 128, "quebra", "O bloco explodindo.", frames=8),
             *parts("lasca", 3, 32, "subir/quebra", "Lascas (pode ser a mesma do Estilhaço)."),
             L("nevoa", "parada", 128, 128, "quebra", "Névoa."),
             L("frio", "parada", 64, 64, "frio", "Gelo nos pés de quem encosta."),
         ]),
    dict(voc="druid", key="raizes", nome="Raízes Errantes", caminho="Verdant · utilidade", words="exori tera vis",
         momentos="voo da semente → acerto (estouro, as raízes prendem, `ms`, e soltam; veneno 1×/s por 5 s); errou: brota.",
         diag=["A semente pula em 4 frames parados.",
               "As raízes têm 4 frames: crescem aos saltos."],
         direcao="Uma semente girando com folhas no rastro; no acerto, a terra explode e raízes vivas brotam e se fecham "
                 "em volta, apertando; o veneno sobe em bolhas violetas.",
         camadas=[
             L("semente", "parada", 64, 64, "voo", "A semente (o jogo gira).", extra="gira"),
             *parts("folha", 2, 32, "voo", "Folhinhas no rastro."),
             L("acerto_nucleo", "parada", 128, 128, "acerto", "Estouro verde.", blend="luz"),
             *parts("terra", 2, 32, "acerto", "Torrões de terra."),
             L("raizes_crescendo", "flipbook", 128, 128, "prende", "As raízes brotando e se fechando (orgânico: precisa de flipbook).", frames=10),
             L("raizes_presas", "parada", 128, 128, "preso", "As raízes fechadas; o jogo faz um aperto pulsando."),
             L("raizes_soltando", "flipbook", 128, 128, "solta", "Soltando e murchando.", frames=6),
             *parts("bolha", 2, 32, "veneno", "Bolhas violetas do veneno.", blend="luz"),
             L("broto", "flipbook", 64, 64, "erro", "A semente brotando no chão.", frames=8),
         ]),
    # ------------------------------------------------------------ monk
    dict(voc="monk", key="palma", nome="Palma Sônica", caminho="Tigerclaw · alvo único", words="exori sonic pug",
         momentos="voo da onda → acerto (estouro + marca que segue o alvo: entra, fica, pisca 0,5 s antes, sai); errou: se desfaz; dito de novo: o monge some e aparece ao lado do marcado com o golpe final.",
         diag=["32 arquivos de onda (8 direções × 4) para um crescente pequeno.",
               "Marca em 4 arquivos (entrada, loop, aviso, saída) que a curva faz com um."],
         direcao="Um crescente sônico com ecos atrás (vultos); a marca é um selo de ki girando nos pés; o avanço é uma "
                 "pincelada de tinta-ki; o golpe final é uma palma de ki gigante com anéis e respingos de tinta.",
         camadas=[
             L("onda", "parada", 96, 96, "voo", "O crescente sônico apontando para a direita; o jogo desenha 2 ecos atrás.", blend="luz", extra="gira"),
             L("acerto_onda", "parada", 192, 192, "acerto", "Anéis concêntricos."),
             L("acerto_nucleo", "parada", 96, 96, "acerto", "Clarão.", blend="luz"),
             L("marca", "parada", 128, 128, "marca", "O selo de ki nos pés (entra, gira, pisca e sai pela curva)."),
             L("marca_brilho", "parada", 128, 128, "marca", "O brilho do selo (o aviso).", blend="luz"),
             L("avanco_pincelada", "parada", 256, 64, "avanço", "Pincelada de tinta-ki ao longo do avanço.", extra="estica gira"),
             L("golpe_palma", "parada", 192, 192, "golpe", "A palma de ki gigante.", blend="luz"),
             L("golpe_onda", "parada", 320, 320, "golpe", "Onda do golpe."),
             *parts("tinta", 3, 32, "golpe", "Respingos de tinta."),
             L("erro", "flipbook", 96, 96, "erro", "A onda se desfazendo.", frames=6),
         ]),
    dict(voc="monk", key="chute", nome="Chute do Dragão", caminho="Whirlwind · área", words="exori dra pug",
         momentos="chute (o dragão de ki no atingido, na direção do chute) → o atingido voa sqm a sqm (poeira) → bate em alguém ou para (queda).",
         diag=["O dragão é o melhor da v1, mas são 8 arquivos (um por direção) de 6 frames.",
               "O rastro e a queda são poeira pequena."],
         direcao="O dragão de ki dourado avança rugindo (o jogo gira para a direção); o atingido voa deixando um risco de "
                 "ki e poeira; a parada é um estouro com o chão rachado.",
         camadas=[
             L("dragao", "flipbook", 192, 192, "chute", "O dragão de ki avançando, desenhado para a direita (substitui os 8 arquivos).", frames=10, extra="gira"),
             L("dragao_brilho", "parada", 192, 192, "chute", "Brilho dourado do dragão.", blend="luz", extra="gira"),
             L("rastro_ki", "parada", 256, 64, "voo", "Risco de ki atrás de quem voa.", blend="luz", extra="estica gira"),
             *parts("poeira", 2, 32, "voo", "Poeira."),
             L("atropelo_nucleo", "parada", 128, 128, "batida", "Clarão do choque.", blend="luz"),
             L("atropelo_onda", "parada", 192, 192, "batida", "Onda do choque."),
             L("queda", "flipbook", 128, 128, "queda", "Poeira e chão rachando onde para.", frames=8),
         ]),
    dict(voc="monk", key="passo", nome="Passo Fantasma", caminho="Serene · utilidade", words="exani tera pug",
         momentos="avanço (saída, rastro sobre quem atravessa, o corte nele, chegada, tudo junto) e o bônus no monge (1 a 4) enquanto a corrente durar.",
         diag=["Bônus em 4 arquivos (1 a 4) que a curva faz com um.",
               "A saída e a chegada são bonitas mas pequenas."],
         direcao="O monge deixa um vulto de ki que se desfaz, vira um risco jade e corta quem atravessa com um arco "
                 "limpo; o bônus é uma aura de chamas de ki que cresce a cada nível.",
         camadas=[
             L("saida_vulto", "parada", 128, 128, "saída", "Borrão de ki/tinta onde o monge estava."),
             *parts("fagulha", 2, 32, "saída", "Fagulhas jade.", blend="luz"),
             L("rastro", "parada", 256, 32, "avanço", "Risco jade.", blend="luz", extra="estica gira"),
             L("corte", "parada", 192, 192, "corte", "O arco do corte (o jogo abre e gira).", blend="luz", extra="gira"),
             L("chegada_anel", "parada", 128, 128, "chegada", "Anel de chegada."),
             L("chegada_flash", "parada", 96, 96, "chegada", "Clarão.", blend="luz"),
             L("bonus_aura", "parada", 96, 96, "bônus", "Anel de ki nos pés; os níveis 1–4 são a curva."),
             L("bonus_chama", "flipbook", 96, 96, "bônus", "Chamas de ki em volta (mais fortes a cada nível).", frames=8, blend="luz"),
         ]),
]

# a primeira etapa: uma de cada vocação, incluindo a Flecha pedida
PILOT = ["salto", "flecha", "meteoro", "muralha", "chute"]


def voc_of(key):
    for v in VOCATIONS:
        if v["key"] == key:
            return v
    raise KeyError(key)
