# -*- coding: utf-8 -*-
# Monta a pasta "Magias do Renascimento - parte 2 - briefing v1": LEIA-ME.html,
# o CSV de arquivos, os diagramas, as referencias (com a arte da etapa 1 que ja
# esta no jogo), os fundos de teste e a pasta de entrega com os nomes esperados.
#   /usr/bin/python3 gerar/montar.py <pasta de saida>
import csv
import html
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import spec2  # noqa: E402  (poe a pasta da parte 1 no sys.path)
from spec2 import TIERS, SPELLS, SPELL_MULT, EXAMPLES, KIT, STAGE1, ref_hit, tier_of  # noqa: E402
import diagrams2  # noqa: E402
import refs2  # noqa: E402
import build as v1build  # noqa: E402  (a parte 1: CSS, tabelas de arquivos, cartoes dos tiers)

ROOT_NAME = "Magias do Renascimento - parte 2 - briefing v1"
OUT = sys.argv[1]
ROOT = os.path.join(OUT, ROOT_NAME)

e = html.escape
br, dec, ms_text, tiles_text = v1build.br, v1build.dec, v1build.ms_text, v1build.tiles_text
file_table, tier_card, ANCHOR_SHORT = v1build.file_table, v1build.tier_card, v1build.ANCHOR_SHORT


def folder_of(s):
    return f"{tier_of(s['tier'])['pasta']}/{s['key']}"


def write_csv(path):
    with open(path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["tier", "magia", "pasta", "arquivo", "largura_px", "altura_px", "frames", "duracao",
                    "camada", "preso_a", "ancora", "etapa", "descricao"])
        for s in SPELLS:
            for f in s["files"]:
                w.writerow([tier_of(s["tier"])["nome"], s["nome"], folder_of(s), f["nome"] + ".png", f["w"], f["h"],
                            f["frames"], ms_text(f["ms"]), f["camada"], f["preso"], ANCHOR_SHORT[f["ancora"]],
                            1 if s["key"] in STAGE1 else 2, f["desc"]])


def write_skeleton(base):
    for s in SPELLS:
        d = os.path.join(base, folder_of(s))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "_ARQUIVOS_ESPERADOS.txt"), "w", encoding="utf-8") as fh:
            fh.write(f"{tier_of(s['tier'])['nome']} - {s['nome']} (etapa {1 if s['key'] in STAGE1 else 2})\n")
            fh.write("Coloque aqui os PNG (APNG) com exatamente estes nomes:\n\n")
            for f in s["files"]:
                fh.write(f"  {f['nome']}.png   {f['w']}x{f['h']}  {f['frames']} frames  {ms_text(f['ms'])}  {f['camada']}\n")
            if s.get("reusa"):
                fh.write(f"\nReaproveita: {s['reusa']}\n")
            fh.write("\nApague este arquivo quando a pasta estiver completa.\n")


def mult_table():
    rows = []
    for t in TIERS:
        names = [s for s in SPELLS if s["tier"] == t["key"]]
        cells = " · ".join(f"{e(s['nome'])} <b>{dec(SPELL_MULT[s['key']])}</b>" for s in names)
        rows.append(f"<tr><td><span class='dot' style='background:rgb{t['cor']}'></span>{e(t['nome'])}</td>"
                    f"<td class='c'>{dec(t['mult'], 3)}</td><td>{cells}</td></tr>")
    return ("<table class='mult'><thead><tr><th>tier</th><th>× tier (hoje)</th><th>× magia (novas)</th></tr></thead>"
            "<tbody>" + "".join(rows) + "</tbody></table>")


def damage_table():
    head = "".join(f"<th style='--c:rgb{t['cor']}'>{e(t['nome'])}</th>" for t in TIERS)
    rng = {}
    for t in TIERS:
        ks = [SPELL_MULT[s["key"]] for s in SPELLS if s["tier"] == t["key"]]
        rng[t["key"]] = (min(ks), max(ks))
    rows = []
    for name, xp in EXAMPLES:
        r = ref_hit(xp)
        cells = "".join(
            f"<td>{br(round(r * t['mult'] * rng[t['key']][0]))} <span class='muted'>– "
            f"{br(round(r * t['mult'] * rng[t['key']][1]))}</span></td>" for t in TIERS)
        rows.append(f"<tr><td>{e(name)}</td><td class='r'>{br(xp)}</td><td class='r'><b>{br(r)}</b></td>{cells}</tr>")
    return ("<table class='dmg'><thead><tr><th>monstro</th><th>XP</th><th>R</th>" + head + "</tr></thead><tbody>"
            + "".join(rows) + "</tbody></table>")


def summary_table():
    rows = []
    for t in TIERS:
        for s in SPELLS:
            if s["tier"] != t["key"]:
                continue
            stage = "1" if s["key"] in STAGE1 else "2"
            rows.append(
                f"<tr><td><span class='dot' style='background:rgb{t['cor']}'></span>{e(t['nome'])}</td>"
                f"<td><a href='#{s['tier']}-{s['key']}'>{e(s['nome'])}</a></td><td>{e(s['tipo'])}</td>"
                f"<td>{e(s['esquiva'])}</td><td class='c'>{len(s['files'])}</td><td class='c'>{stage}</td></tr>")
    return ("<table class='sum'><thead><tr><th>tier</th><th>magia</th><th>tipo</th><th>como desviar</th>"
            "<th>arquivos</th><th>etapa</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


def kit_box(t):
    k = KIT[t["key"]]
    have = ", ".join(e(x) for x in k["ja_tem"])
    return (f"<p class='kit'><b>Já no kit (parte 1):</b> {have}.<br><b>As novas:</b> {e(k['novas'])}</p>")


def spell_section(s, diag_rel):
    t = tier_of(s["tier"])
    anchor = f"{s['tier']}-{s['key']}"
    folder = f"entrega/{folder_of(s)}/"
    mech = "".join(f"<li>{e(m)}</li>" for m in s["mecanica"])
    stage = ("<span class='stage s1'>etapa 1</span>" if s["key"] in STAGE1 else "<span class='stage'>etapa 2</span>")
    reusa = f"<p class='reuse'><b>Reaproveita:</b> {e(s['reusa'])}</p>" if s.get("reusa") else ""
    return f"""
<div class="spell" id="{anchor}" style="--c:rgb{t['cor']}">
  <h3><span class="tag">{e(t['nome'])}</span>{e(s['nome'])} <small>· {e(s['tipo'])}</small> {stage}</h3>
  <p class="lead">{e(s['conceito'])}</p>
  <div class="grid2">
    <div><h4>Como funciona</h4><ul>{mech}</ul></div>
    <div><h4>Como o jogador desvia</h4><p>{e(s['esquiva'])}</p>
         <h4>Dano</h4><p>{e(s['dano'])} <small>(R = golpe de referência pela XP, ver seção 5)</small></p></div>
  </div>
  <figure><img src="{diag_rel}" alt="Diagrama da {e(s['nome'])}"><figcaption>Grade vista de cima: cada quadrado é 1 sqm.
  A arte tem que cobrir exatamente os sqm marcados.</figcaption></figure>
  <h4>Arquivos — pasta <code>{folder}</code></h4>
  {file_table(s)}
  {reusa}
</div>"""


EXTRA_CSS = """
.kit{background:#f6f4f8;border:1px solid var(--line);border-radius:8px;padding:8px 12px;margin:8px 0 0}
.stage{display:inline-block;font-size:11px;font-weight:600;padding:1px 8px;border-radius:99px;border:1px solid #bbb;
color:#555;margin-left:6px;vertical-align:middle}
.stage.s1{border-color:#3a7d44;color:#2e6b38;background:#eaf6ec}
.reuse{font-size:13.5px;color:#3b3940;background:#f3f7ff;border:1px solid #d6e2f6;border-radius:8px;padding:6px 10px}
.idea{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:10px 0}
.idea div{background:var(--card);border:1px solid var(--line);border-top:5px solid var(--c);border-radius:10px;padding:10px 12px;font-size:13.5px}
.idea b{display:block;font-size:14.5px;margin-bottom:2px}
@media (max-width:760px){.idea{grid-template-columns:1fr 1fr}}
"""


def build():
    if os.path.exists(ROOT):
        shutil.rmtree(ROOT)
    for sub in ["diagramas", "referencias", "fundos_de_teste", "entrega"]:
        os.makedirs(os.path.join(ROOT, sub), exist_ok=True)

    diags = diagrams2.build_all({s["key"]: s for s in SPELLS}, os.path.join(ROOT, "diagramas"))
    ref = lambda name: os.path.join(ROOT, "referencias", name)  # noqa: E731
    refs2.delivered_sheet(ref("sua_etapa1_no_jogo.png"))
    refs2.clock_strip(ref("relogio_da_etapa1.png"))
    refs2.palettes(ref("paletas_dos_tiers.png"))
    refs2.line_pieces(ref("pecas_de_linha.png"))
    refs2.kit_sheet(ref("kit_renascimento_atual.png"))
    refs2.copy_delivered(ref("arte_entregue_etapa1"))
    floors = refs2.test_floors(os.path.join(ROOT, "fundos_de_teste"))
    write_csv(os.path.join(ROOT, "lista_de_arquivos.csv"))
    write_skeleton(os.path.join(ROOT, "entrega"))

    n_files = sum(len(s["files"]) for s in SPELLS)
    n_spells = len(SPELLS)
    n_stage1 = sum(len(s["files"]) for s in SPELLS if s["key"] in STAGE1)

    sections = []
    for i, t in enumerate(TIERS, 1):
        sections.append(f"<h2 id='tier-{t['key']}'>7.{i} {e(t['nome'])} — {e(t['material'])}</h2>")
        sections.append(kit_box(t))
        for s in SPELLS:
            if s["tier"] == t["key"]:
                sections.append(spell_section(s, "diagramas/" + os.path.basename(diags[s["key"]])))

    toc = "".join(
        f"<li><a href='#tier-{t['key']}'>{e(t['nome'])}</a>: "
        + ", ".join(f"<a href='#{s['tier']}-{s['key']}'>{e(s['nome'])}</a>" for s in SPELLS if s["tier"] == t["key"])
        + "</li>" for t in TIERS)

    ideas = "".join(
        f"<div style='--c:rgb{tier_of(s['tier'])['cor']}'><b>{e(s['nome'])}</b>{e(s['tipo'])}</div>" for s in SPELLS)

    stage1_links = ", ".join(f"<a href='#{s['tier']}-{s['key']}'>{e(s['nome'])}</a>" for s in SPELLS if s["key"] in STAGE1)
    stage2_links = ", ".join(f"<a href='#{s['tier']}-{s['key']}'>{e(s['nome'])}</a>" for s in SPELLS if s["key"] not in STAGE1)

    page = f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Magias do Renascimento - parte 2</title>
<style>{v1build.CSS}{EXTRA_CSS}</style></head>
<body><main>

<div class="cover">
  <small>Mythos · briefing de arte · parte 2 · v1</small>
  <h1>Magias do Renascimento — parte 2</h1>
  <p class="lead">Mais <b>duas magias de chefe para cada tier</b> — Pale, Ashen, Obsidian e Lord of Death — no mesmo estilo
  das primeiras: tudo é avisado no chão antes de bater, e quem lê o aviso desvia. Mesmo kit visual, mesmas regras, mesmo
  formato de entrega da parte 1. A diferença: cada uma traz uma ideia de desvio que o kit ainda não tinha.</p>
</div>

<div class="kpis">
  <div class="kpi"><b>{n_spells}</b><span>magias novas (2 por tier)</span></div>
  <div class="kpi"><b>{n_files}</b><span>arquivos de arte (lista no CSV)</span></div>
  <div class="kpi"><b>0</b><span>peças comuns novas: as da parte 1 servem</span></div>
  <div class="kpi"><b>2</b><span>etapas: 1 por tier para aprovar ({n_stage1} arquivos), depois o resto</span></div>
</div>

<div class="idea">{ideas}</div>

<h4>Neste pacote</h4>
<ul>
  <li><code>LEIA-ME.pdf</code> / <code>LEIA-ME.html</code> — este documento.</li>
  <li><code>lista_de_arquivos.csv</code> — os {n_files} arquivos com tamanho, frames, duração, camada, etapa e descrição.</li>
  <li><code>diagramas/</code> — uma imagem por magia: os sqm de perigo, os seguros, a esquiva e a linha do tempo.</li>
  <li><code>referencias/</code> — <b>a sua etapa 1 como está no jogo</b> (<code>sua_etapa1_no_jogo.png</code>,
      <code>relogio_da_etapa1.png</code> e os arquivos em <code>arte_entregue_etapa1/</code>), as paletas, o guia das
      peças de linha e o kit do renascimento.</li>
  <li><code>fundos_de_teste/</code> — {len(floors)} chãos 7×7 sqm para testar o contraste.</li>
  <li><code>entrega/</code> — as pastas com os nomes certos; cada uma tem um <code>_ARQUIVOS_ESPERADOS.txt</code>.
      Devolver essa pasta preenchida.</li>
</ul>

<h4>Índice</h4>
<ol class="toc">
  <li><a href="#s1">O que muda desde a parte 1</a></li>
  <li><a href="#s2">O que já está no jogo (a sua arte)</a></li>
  <li><a href="#s3">Regras de leitura</a></li>
  <li><a href="#s4">Os tiers</a></li>
  <li><a href="#s5">Força pela XP do monstro</a></li>
  <li><a href="#s6">Resumo das magias novas</a></li>
  <li><a href="#tier-pale">As magias, uma por uma</a><ul>{toc}</ul></li>
  <li><a href="#s8">Formato de entrega</a></li>
  <li><a href="#s9">Etapas e checklist</a></li>
  <li><a href="#s10">Apêndice para o programador</a></li>
</ol>

<h2 id="s1">1. O que muda desde a parte 1</h2>
<ul>
  <li><b>O kit cresce.</b> Cada tier passa de 3 magias (4 no Lord of Death) para 5 (6 no Lord). O monstro continua
      lançando uma magia do tier a cada 9 s (Pale), 8 s (Ashen), 7 s (Obsidian) e 6 s (Lord of Death), sorteada do kit,
      nunca a mesma duas vezes seguidas, e nunca dois avisos ao mesmo tempo.</li>
  <li><b>As peças comuns não mudam.</b> O <code>conjurar</code>, o <code>conjurar_fim</code>, o <code>acerto</code> e o
      loop de efeito no jogador (frio, queimando, cortes) da parte 1 servem para estas magias também.</li>
  <li><b>O jogo mudou um pouco desde a parte 1:</b> todos os tiers avisam <b>3 s</b> (antes o Pale, o Ashen e o Obsidian
      avisavam 1–2 s) e, durante o aviso, o mapa escurece de leve na cor do tier e dá um clarão quando o golpe cai
      (isso é do código, não precisa de arte). As durações deste pacote já seguem os 3 s.</li>
  <li><b>A parte 1 continua valendo.</b> As 9 magias da etapa 2 dela (Pluma, Véu, Brasa, Investida, Feixe, Reflexos,
      Garra, Sol Negro e Colapso) ainda estão na fila; combine com o Mythos a ordem.</li>
</ul>

<h2 id="s2">2. O que já está no jogo (a sua arte)</h2>
<p>A etapa 1 da parte 1 está no cliente e funciona muito bem. <b>Faça as novas no mesmo acabamento</b>: a mesma
espessura de contorno, a mesma opacidade no miolo, o mesmo jeito de marcar o tempo (o arco que se completa e fecha no
golpe) e as mesmas paletas.</p>
<figure><img src="referencias/sua_etapa1_no_jogo.png" alt="A etapa 1 no jogo">
<figcaption>Um quadro do meio de cada animação, na escala do arquivo (a grade é 1 sqm). Os PNG estão em
<code>referencias/arte_entregue_etapa1/</code>.</figcaption></figure>
<figure><img src="referencias/relogio_da_etapa1.png" alt="O relógio da etapa 1">
<figcaption>O relógio quadro a quadro, de 0% a 100% do aviso: é o que todas as marcas novas também fazem.</figcaption></figure>

<h2 id="s3">3. Regras de leitura</h2>
<p>As 10 regras da parte 1 continuam valendo, resumidas aqui, e as duas últimas são novas, porque estas magias têm
coisas que se movem e lugares seguros para achar.</p>
<ol class="rules">
  <li><b>A arte é a hitbox.</b> Os sqm do diagrama são exatamente os que tomam dano (um brilho suave de até 8 px pode vazar).</li>
  <li><b>Todo aviso tem relógio</b> e fecha no instante exato do golpe; os últimos ~0,25 s ficam mais claros.</li>
  <li><b>Aviso no chão, golpe no ar.</b></li>
  <li><b>Brilho = perigo, apagado = seguro.</b> O que já explodiu fica apagado.</li>
  <li><b>Resíduo não tem relógio</b> (brasa, geada): plano, respira de leve e some em estágios.</li>
  <li><b>Contorno nítido, miolo translúcido</b> (30–60%).</li>
  <li><b>Lê em qualquer chão</b> (<code>fundos_de_teste/</code>; o Pale na neve e o Ashen na lava são os perigosos).</li>
  <li><b>Cada tier só usa as cores dele.</b></li>
  <li><b>Segue a grade.</b> Círculo de magia é redondo na grade, igual ao diagrama.</li>
  <li><b>Nada de flash na tela inteira.</b></li>
  <li><b>O que é seguro parece seguro.</b> A fresta da Maré, a sombra do Sopro, a porta da Redoma e o fiel da Pesagem
      são calmos: luz suave, sem relógio, sem a cor de perigo. O jogador acha o lugar seguro num relance, sem ler nada.</li>
  <li><b>O que anda mostra para onde vai.</b> A onda da Maré, a ciranda e a faísca do pavio deixam claro o próximo
      passo antes de dar: a seta curva da ciranda, a fileira da frente da onda, a faísca mais clara que o pavio.</li>
</ol>

<h2 id="s4">4. Os tiers</h2>
<p>As mesmas identidades da parte 1 (as cores são as dos shaders que pintam o monstro de cada tier). Em cada tier, o que o
kit já tem e o que as duas novas acrescentam estão na seção 7.</p>
{''.join(tier_card(t) for t in TIERS)}
<figure><img src="referencias/paletas_dos_tiers.png" alt="Paletas dos tiers"></figure>

<h2 id="s5">5. Força pela XP do monstro</h2>
<p>A mesma fórmula da parte 1: o dano sai da XP da espécie que renasceu.</p>
<div class="formula">R = 5 × XP<sup>0,55</sup> &nbsp;<small style="color:#aaa">(mín. 15, XP limitada a 100.000)</small><br>
dano = R × tier × magia &nbsp;<small style="color:#aaa">(±15% de variação)</small></div>
{mult_table()}
<p>Exemplos (dano de um golpe das magias novas, <span class="muted">da mais fraca – à mais forte do tier</span>):</p>
{damage_table()}
<div class="box"><b>Para a arte, isso não muda nada:</b> a mesma arte serve para o rato e para o demônio.</div>

<h2 id="s6">6. Resumo das magias novas</h2>
{summary_table()}

{''.join(sections)}

<h2 id="s8">8. Formato de entrega</h2>
<p>O mesmo da parte 1 (e dos skillshots).</p>
<ul>
  <li><b>PNG animado (APNG)</b>, fundo transparente. Frames parados (<code>faisca_1..4</code> do Pavio) são PNG simples,
      1 por arquivo, e o jogo troca um por outro a cada sqm.</li>
  <li><b>2×:</b> 1 sqm = 64×64 px; os tamanhos da tabela já estão em 2×. Novos tamanhos grandes: <b>576×576</b> (a seta da
      Ciranda, 9×9 sqm), <b>320×320</b> (a Redoma fechando, 5×5 sqm) e <b>256×256</b> (a balança da Pesagem).</li>
  <li><b>Âncora:</b> <code>centro</code> = centro do arquivo no centro do sqm (ou do monstro); <code>base</code> = o sqm é o
      quadrado 64×64 de baixo do arquivo; <code>peça de linha</code> (<code>_h _v _ne _nw</code>) = ocupa o sqm inteiro e
      emenda na vizinha (<code>referencias/pecas_de_linha.png</code>).</li>
  <li><b>Camada:</b> <code>chão</code> = embaixo das criaturas; <code>ar</code> = por cima.</li>
  <li><b>Duração:</b> os de tempo fixo tocam uma vez; os <code>_loop</code> fecham o ciclo sem pulo. Vários avisos são
      esticados ou encurtados pelo jogo (a fase 2 da Persiana e da Pesagem, as badaladas do Dobre, o 3×3 de cada carga do
      Pavio), então <b>o relógio tem que ser uniforme</b>, sem pausas no meio.</li>
  <li><b>Peças que se repetem lado a lado</b> (a névoa da Maré, a geada do Sopro, as fatias da Ciranda, o chão do Dobre e
      da Pesagem) emendam com as vizinhas dos 4 lados sem costura: a área inteira é a mesma peça repetida.</li>
  <li><b>Peso:</b> até ~300 KB por arquivo; os de 576 até ~600 KB. O cliente também roda no navegador.</li>
  <li><b>Nomes exatamente como na lista</b>, minúsculos e sem acento, em <code>entrega/&lt;tier&gt;/&lt;magia&gt;/</code>.</li>
  <li><b>Prévia:</b> para cada magia, um GIF ou MP4 curto com a sequência inteira em cima de um print do jogo, com o
      monstro e um jogador.</li>
</ul>

<h2 id="s9">9. Etapas e checklist</h2>
<h4>Etapa 1 — aprovar o estilo das ideias novas ({n_stage1} arquivos)</h4>
<p>Uma por tier, com prévia: {stage1_links}.</p>
<h4>Etapa 2 — o resto</h4>
<p>{stage2_links}. Devolver a pasta <code>entrega/</code> completa com o nome
<b>“Magias do Renascimento - parte 2 - artes v1”</b>.</p>
<h4>Antes de entregar, para cada magia</h4>
<ul>
  <li>☐ A arte cobre exatamente os sqm do diagrama (testar em cima de um fundo de teste com a grade).</li>
  <li>☐ O aviso tem relógio uniforme e fecha no fim; os últimos frames são os mais claros.</li>
  <li>☐ O lugar seguro (fresta, sombra, porta, fiel) parece seguro: calmo, sem relógio.</li>
  <li>☐ O que anda mostra o próximo passo (seta, fileira da frente, faísca).</li>
  <li>☐ As peças repetidas emendam sem costura; as de linha emendam nas 4 orientações.</li>
  <li>☐ Lê na neve, na lava, na grama e na caverna.</li>
  <li>☐ Só as cores do próprio tier; nomes, tamanhos, frames e durações iguais à lista.</li>
</ul>

<h2 id="s10">10. Apêndice para o programador</h2>
<p><small>Não é para o designer — é para quem vai ligar a arte no jogo.</small></p>
<ul>
  <li><b>Servidor:</b> cada magia é uma função em <code>RareSpells</code> (<code>scripts/rarity/spells.lua</code>), com os
      números em <code>RarityConfig.tierSpells.spells</code> e o nome na lista <code>spells</code> do tier
      (<code>00_config.lua</code>). Os eventos vão pelo <code>Skillshot.show</code> com <code>fx = "rare_&lt;tier&gt;"</code>,
      como os da parte 1; quem não tem a arte recebe os efeitos do Tibia de <code>FALLBACK</code>. Nada adiado guarda
      userdata (ids e posições).</li>
  <li><b>Máscaras</b> (as dos diagramas):
    <ul>
      <li><b>Maré:</b> 9 de largura × 8 de comprimento na frente do monstro (4 direções); fresta de 2 a 1–3 sqm de lado do
          jogador; a onda passa uma fileira a cada 120 ms. Proposta: <code>mare = {{ power = 1.2, width = 9, length = 8,
          lane = 2, laneMin = 1, laneMax = 3, warn = 3000, step = 120, frost = 3000 }}</code>.</li>
      <li><b>Sopro:</b> círculo de raio 4,5 menos as sombras; coluna a 2 sqm do monstro, sombra = a coluna + 2 sqm na mesma
          direção. <code>sopro = {{ power = 1.4, radius = 4.5, pillars = 3, at = 2, shadow = 2, warn = 3000 }}</code>.</li>
      <li><b>Ciranda:</b> raio 4,5; fatia = <code>round(atan2(dy, dx) / 45°) mod 8</code>; uma fatia a cada 250 ms a partir de uma
          que não é a do jogador; brasa nos sqm com 3,5 &lt; d ≤ 4,5. <code>ciranda = {{ power = 1.3, ember = 0.15,
          radius = 4.5, warn = 3000, slice = 250, emberMs = 3000 }}</code>.</li>
      <li><b>Pavio:</b> cargas no sqm do jogador e a 2 sqm dele; pavio pela grade (Bresenham), faísca a 300 ms/sqm depois de
          1 s, primeira explosão nunca antes de 3 s; 3×3 por carga. <code>pavio = {{ power = 1.2, ember = 0.15, charges = 3,
          around = 2, light = 1000, step = 300, minWarn = 3000, emberMs = 3000 }}</code>.</li>
      <li><b>Persiana:</b> 9×9 centrado no jogador; fase 1 = fileiras com (y − y0) par, fase 2 = colunas com (x − x0) par.
          <code>persiana = {{ power = 1.2, half = 4, warn = 3000, warn2 = 2000, blade = 450 }}</code>.</li>
      <li><b>Redoma:</b> 5×5 centrado no jogador; porta = 1 sqm do contorno que não seja parede; atravessar o contorno fora da
          porta (pisar nele vindo de dentro) corta. <code>redoma = {{ power = 1.6, cross = 0.4, half = 2, warn = 3000 }}</code>.</li>
      <li><b>Dobre:</b> anel k = os sqm com k − 0,5 &lt; d ≤ k + 0,5 (k = 1..5); badaladas 1, 3, 5 / 2, 4 / 1, 3, 5.
          <code>dobre = {{ power = 1.5, rings = 5, warns = {{ 3000, 2200, 1600 }}, toll = 400 }}</code>.</li>
      <li><b>Pesagem:</b> raio 5,5; fiel = a coluna do monstro (seguro); fase 1 = a metade (x &lt; x0 ou x &gt; x0) do jogador
          mais próximo. <code>pesagem = {{ power = 2.0, radius = 5.5, warn = 3000, warn2 = 2000 }}</code>.</li>
    </ul></li>
  <li><b>Cliente:</b> as pastas novas entram no art set do renascimento em <code>game_skillshot</code>
      (<code>images/renascimento/&lt;tier&gt;/&lt;magia&gt;/</code>); tamanhos da tabela ÷ 2 no <code>set.add</code>;
      avisos esticados com <code>effect:setSpeed</code>; a faísca troca de frame a cada sqm como a pétala da Flor.</li>
</ul>
<p><small>Gerado por <code>docs/briefings/magias-do-renascimento-2/gerar/</code> (cliente) a partir da parte 1 e da arte
que está hoje no jogo.</small></p>
</main></body></html>
"""
    with open(os.path.join(ROOT, "LEIA-ME.html"), "w", encoding="utf-8") as fh:
        fh.write(page)
    print(ROOT, n_files, n_spells)


if __name__ == "__main__":
    build()
