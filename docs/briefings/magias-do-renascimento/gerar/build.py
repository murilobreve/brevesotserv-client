# -*- coding: utf-8 -*-
# Monta a pasta "Magias do Renascimento - briefing v1": LEIA-ME.html, o CSV de
# arquivos, os diagramas, as referencias, os fundos de teste e a pasta de
# entrega com os nomes esperados.
import csv
import html
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(__file__))

from spec import TIERS, SPELLS, SPELL_MULT, EXAMPLES, ref_hit, tier_of  # noqa: E402
from diagrams import build_all  # noqa: E402
import refs  # noqa: E402

ROOT_NAME = "Magias do Renascimento - briefing v1"
OUT = sys.argv[1]
ROOT = os.path.join(OUT, ROOT_NAME)
REVIVE = refs.REVIVE

e = html.escape


def br(n):
    return f"{n:,}".replace(",", ".")


def dec(x, nd=2):
    s = f"{x:.{nd}f}".rstrip("0").rstrip(".")
    return s.replace(".", ",")


def ms_text(ms):
    if ms == "loop":
        return "loop"
    if ms == "parado":
        return "parado (1 frame)"
    return f"{ms} ms"


def tiles_text(w, h):
    tw, th = w / 64, h / 64
    if w == 512:
        return "512×512 (jogo amplia p/ 11×11 sqm)"
    return f"{w}×{h} ({dec(tw)}×{dec(th)} sqm)"


def tier_folder(tier_key):
    return tier_of(tier_key)["pasta"]


def all_files():
    for s in SPELLS:
        for f in s["files"]:
            yield s, f


def write_csv(path):
    with open(path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["tier", "magia", "pasta", "arquivo", "largura_px", "altura_px", "frames", "duracao",
                    "camada", "preso_a", "ancora", "descricao"])
        for s, f in all_files():
            folder = f"{tier_folder(s['tier'])}/{s['key']}"
            w.writerow([tier_of(s["tier"])["nome"], s["nome"], folder, f["nome"] + ".png", f["w"], f["h"],
                        f["frames"], ms_text(f["ms"]), f["camada"], f["preso"], ANCHOR_SHORT[f["ancora"]], f["desc"]])


ANCHOR_SHORT = {
    "centro": "centro do arquivo = centro do sqm",
    "base": "o sqm é o quadrado 64×64 de baixo do arquivo",
    "seg": "peça de linha: ocupa o sqm todo e emenda na vizinha",
}


def write_skeleton(base):
    for s in SPELLS:
        d = os.path.join(base, tier_folder(s["tier"]), s["key"])
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "_ARQUIVOS_ESPERADOS.txt"), "w", encoding="utf-8") as fh:
            fh.write(f"{tier_of(s['tier'])['nome']} - {s['nome']}\n")
            fh.write("Coloque aqui os PNG (APNG) com exatamente estes nomes:\n\n")
            for f in s["files"]:
                fh.write(f"  {f['nome']}.png   {f['w']}x{f['h']}  {f['frames']} frames  {ms_text(f['ms'])}  {f['camada']}\n")
            fh.write("\nApague este arquivo quando a pasta estiver completa.\n")


def file_table(spell):
    rows = []
    for f in spell["files"]:
        rows.append(
            "<tr>"
            f"<td class='fn'>{e(f['nome'])}.png</td>"
            f"<td>{tiles_text(f['w'], f['h'])}</td>"
            f"<td class='c'>{f['frames']}</td>"
            f"<td>{e(ms_text(f['ms']))}</td>"
            f"<td>{e(f['camada'])}</td>"
            f"<td>{e(f['preso'])}</td>"
            f"<td class='desc'>{e(f['desc'])}</td>"
            "</tr>")
    return ("<table class='files'><thead><tr><th>arquivo</th><th>tamanho</th><th>frames</th><th>duração</th>"
            "<th>camada</th><th>preso a</th><th>o que é</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


def damage_table():
    head = "".join(f"<th style='--c:rgb{t['cor']}'>{e(t['nome'])}<br><small>×{dec(t['mult'])}</small></th>" for t in TIERS)
    maxes = {}
    for t in TIERS:
        ks = [s["key"] for s in SPELLS if s["tier"] == t["key"] and s["key"] != "comum"]
        maxes[t["key"]] = max(SPELL_MULT[k] for k in ks)
    rows = []
    for name, xp in EXAMPLES:
        r = ref_hit(xp)
        cells = "".join(
            f"<td>{br(round(r * t['mult']))} <span class='muted'>– {br(round(r * t['mult'] * maxes[t['key']]))}</span></td>"
            for t in TIERS)
        rows.append(f"<tr><td>{e(name)}</td><td class='r'>{br(xp)}</td><td class='r'><b>{br(r)}</b></td>{cells}</tr>")
    return ("<table class='dmg'><thead><tr><th>monstro</th><th>XP</th><th>R</th>" + head + "</tr></thead><tbody>"
            + "".join(rows) + "</tbody></table>")


def spell_mult_table():
    rows = []
    for t in TIERS:
        names = [s for s in SPELLS if s["tier"] == t["key"] and s["key"] != "comum"]
        cells = " · ".join(f"{e(s['nome'])} <b>{dec(SPELL_MULT[s['key']])}</b>" for s in names)
        rows.append(f"<tr><td><span class='dot' style='background:rgb{t['cor']}'></span>{e(t['nome'])}</td>"
                    f"<td class='c'>{dec(t['mult'])}</td><td>{cells}</td></tr>")
    return ("<table class='mult'><thead><tr><th>tier</th><th>× tier</th><th>× magia</th></tr></thead><tbody>"
            + "".join(rows) + "</tbody></table>")


def summary_table():
    rows = []
    for t in TIERS:
        for s in SPELLS:
            if s["tier"] != t["key"] or s["key"] == "comum":
                continue
            aviso = s.get("aviso") or f"{s['timeline'][0][1] / 1000:.1f} s".replace(".", ",")
            rows.append(
                f"<tr><td><span class='dot' style='background:rgb{t['cor']}'></span>{e(t['nome'])}</td>"
                f"<td><a href='#{s['tier']}-{s['key']}'>{e(s['nome'])}</a></td><td>{e(s['tipo'])}</td>"
                f"<td>{e(aviso)}</td><td>{e(s['esquiva'])}</td><td class='c'>{len(s['files'])}</td></tr>")
    return ("<table class='sum'><thead><tr><th>tier</th><th>magia</th><th>tipo</th><th>aviso</th><th>como desviar</th>"
            "<th>arquivos</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


CSS = """
:root{--ink:#1d1c20;--muted:#6b6870;--line:#dedbe2;--bg:#faf9f7;--card:#ffffff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 Inter,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:1060px;margin:0 auto;padding:40px 28px 80px}
h1{font-size:34px;line-height:1.15;margin:0 0 6px;letter-spacing:-.01em}
h2{font-size:24px;margin:48px 0 12px;padding-top:12px;border-top:2px solid var(--ink);letter-spacing:-.005em}
h3{font-size:19px;margin:30px 0 6px}
h4{font-size:15px;margin:18px 0 6px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted)}
h4 code{text-transform:none;letter-spacing:0}
p{margin:6px 0 10px}
small,.muted{color:var(--muted)}
.lead{font-size:17px;color:#3b3940;max-width:820px}
.cover{border-left:8px solid;border-image:linear-gradient(#78ABB8,#C97135,#8F74D8,#792D42) 1;padding:6px 0 6px 22px;margin-bottom:26px}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:18px 0}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.kpi b{display:block;font-size:26px;line-height:1.1}
.kpi span{color:var(--muted);font-size:13px}
ol.rules{padding-left:22px}
ol.rules li{margin:6px 0}
ol.rules li b{display:inline}
table{border-collapse:collapse;width:100%;margin:10px 0 16px;font-size:13.5px;background:var(--card)}
th,td{border:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}
th{background:#f0eef2;font-weight:600}
td.c{text-align:center}td.r{text-align:right}
td.fn{font-family:"JetBrains Mono",Consolas,monospace;font-size:12.5px;white-space:nowrap}
td.desc{min-width:300px}
table.files td:nth-child(2),table.files td:nth-child(4){white-space:nowrap}
table.dmg th{border-top:4px solid var(--c,#ccc)}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:7px;vertical-align:baseline}
.tier{border:1px solid var(--line);border-radius:12px;background:var(--card);padding:16px 18px;margin:14px 0;border-top:6px solid var(--c)}
.tier h3{margin-top:0}
.tier dl{display:grid;grid-template-columns:140px 1fr;gap:4px 14px;margin:8px 0 0}
.tier dt{color:var(--muted);font-weight:600}
.tier dd{margin:0}
.sw{display:inline-flex;gap:6px;flex-wrap:wrap}
.sw i{display:inline-block;width:46px;height:24px;border-radius:4px;border:1px solid rgba(0,0,0,.15)}
.spell{margin:24px 0 34px;padding-top:6px;border-top:1px dashed var(--line)}
.spell .tag{display:inline-block;font-size:12px;font-weight:600;padding:2px 9px;border-radius:99px;color:#fff;background:var(--c);margin-right:8px;vertical-align:middle}
.spell .grid2{display:grid;grid-template-columns:1fr 1fr;gap:6px 28px}
.spell ul{margin:4px 0 8px;padding-left:20px}
.k{font-weight:600}
figure{margin:12px 0}
figure img{max-width:100%;border-radius:8px;display:block}
figcaption{color:var(--muted);font-size:13px;margin-top:4px}
.box{background:#fff8e6;border:1px solid #f0dca8;border-radius:10px;padding:12px 16px;margin:12px 0}
.formula{font:600 20px/1.4 "JetBrains Mono",Consolas,monospace;background:#1d1c20;color:#f3efe6;border-radius:10px;padding:14px 18px;margin:10px 0}
code{font-family:"JetBrains Mono",Consolas,monospace;font-size:.92em;background:#efedf1;padding:1px 5px;border-radius:4px}
.toc{columns:2;font-size:14px}
.toc a{color:var(--ink)}
a{color:#4a3ea8}
@media (max-width:760px){.kpis{grid-template-columns:repeat(2,1fr)}.spell .grid2{grid-template-columns:1fr}.toc{columns:1}.tier dl{grid-template-columns:1fr}}
@media print{body{background:#fff;font-size:12.5px}main{max-width:none;padding:0}h2{break-before:page}
.spell{break-inside:auto}figure,table.dmg,.tier,.kpis,.spell .grid2{break-inside:avoid}table.files tr{break-inside:avoid}
.spell h3,.spell .lead,h4{break-after:avoid}}
@page{size:A4;margin:14mm 12mm}
"""


def tier_card(t):
    sw = "".join(f"<i title='{e(n)} {hx}' style='background:{hx}'></i>" for n, hx in t["paleta"])
    return f"""
<div class="tier" style="--c:rgb{t['cor']}">
  <h3>{e(t['nome'])} — {e(t['material'])}</h3>
  <p>{e(t['personalidade'])}</p>
  <dl>
    <dt>Paleta</dt><dd><span class="sw">{sw}</span> <small>{' · '.join(f"{e(n)} {hx}" for n, hx in t['paleta'])}</small></dd>
    <dt>Matéria</dt><dd>{e(t['materia'])}</dd>
    <dt>Movimento</dt><dd>{e(t['movimento'])}</dd>
    <dt>Evitar</dt><dd>{e(t['evitar'])}</dd>
    <dt>Elemento</dt><dd>{e(t['elemento'])}</dd>
    <dt>Efeito extra</dt><dd>{e(t['debuff'])}</dd>
    <dt>Ritmo</dt><dd>1 magia do tier a cada {t['intervalo']} s</dd>
  </dl>
</div>"""


def spell_section(s, diag_rel):
    t = tier_of(s["tier"])
    anchor = f"{s['tier']}-{s['key']}"
    folder = f"entrega/{t['pasta']}/{s['key']}/"
    if s["key"] == "comum":
        return f"""
<div class="spell" id="{anchor}" style="--c:rgb{t['cor']}">
  <h3><span class="tag">{e(t['nome'])}</span>Peças comuns do tier</h3>
  <p>Usadas por todas as magias do {e(t['nome'])}. O <b>conjurar</b> fica no monstro durante todo o aviso de qualquer
  magia (é o “vou lançar”, igual à animação de wind-up dos chefes do Path of Exile); o <b>conjurar_fim</b> toca no disparo.
  Pasta: <code>{folder}</code></p>
  {file_table(s)}
</div>"""
    mech = "".join(f"<li>{e(m)}</li>" for m in s["mecanica"])
    return f"""
<div class="spell" id="{anchor}" style="--c:rgb{t['cor']}">
  <h3><span class="tag">{e(t['nome'])}</span>{e(s['nome'])} <small>· {e(s['tipo'])}</small></h3>
  <p class="lead">{e(s['conceito'])}</p>
  <div class="grid2">
    <div><h4>Como funciona</h4><ul>{mech}</ul></div>
    <div><h4>Como o jogador desvia</h4><p>{e(s['esquiva'])}</p>
         <h4>Dano</h4><p>{e(s['dano'])} <small>(R = golpe de referência pela XP, ver seção 5)</small></p></div>
  </div>
  <figure><img src="{diag_rel}" alt="Diagrama da {e(s['nome'])}"><figcaption>Grade vista de cima: cada quadrado é 1 sqm. A arte tem que
  cobrir exatamente os sqm marcados.</figcaption></figure>
  <h4>Arquivos — pasta <code>{folder}</code></h4>
  {file_table(s)}
</div>"""


def build():
    if os.path.exists(ROOT):
        shutil.rmtree(ROOT)
    for sub in ["diagramas", "referencias/arte_atual_do_renascimento", "fundos_de_teste", "entrega"]:
        os.makedirs(os.path.join(ROOT, sub), exist_ok=True)

    by_key = {s["key"]: s for s in SPELLS if s["key"] != "comum"}
    diags = build_all(by_key, os.path.join(ROOT, "diagramas"))
    refs.palettes(os.path.join(ROOT, "referencias", "paletas_dos_tiers.png"))
    refs.kit_sheet(os.path.join(ROOT, "referencias", "kit_renascimento_atual.png"))
    refs.clock_sheet(os.path.join(ROOT, "referencias", "aviso_com_relogio_ja_no_jogo.png"))
    refs.line_pieces(os.path.join(ROOT, "referencias", "pecas_de_linha.png"))
    floors = refs.test_floors(os.path.join(ROOT, "fundos_de_teste"))
    for folder in ["pale", "ashen", "obsidian", "lord-of-death"]:
        dst = os.path.join(ROOT, "referencias", "arte_atual_do_renascimento", folder)
        shutil.copytree(os.path.join(REVIVE, folder), dst)
    write_csv(os.path.join(ROOT, "lista_de_arquivos.csv"))
    write_skeleton(os.path.join(ROOT, "entrega"))

    n_files = sum(len(s["files"]) for s in SPELLS)
    n_spells = len([s for s in SPELLS if s["key"] != "comum"])

    sections = []
    for t in TIERS:
        sections.append(f"<h2 id='tier-{t['key']}'>7.{TIERS.index(t) + 1} {e(t['nome'])} — {e(t['material'])}</h2>")
        for s in SPELLS:
            if s["tier"] != t["key"]:
                continue
            rel = "diagramas/" + os.path.basename(diags[s["key"]]) if s["key"] != "comum" else ""
            sections.append(spell_section(s, rel))

    toc = "".join(
        f"<li><a href='#tier-{t['key']}'>{e(t['nome'])}</a>: "
        + ", ".join(f"<a href='#{s['tier']}-{s['key']}'>{e(s['nome'])}</a>" for s in SPELLS if s["tier"] == t["key"] and s["key"] != "comum")
        + "</li>" for t in TIERS)

    page = f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Magias do Renascimento</title>
<style>{CSS}</style></head>
<body><main>

<div class="cover">
  <small>Mythos · briefing de arte · v1</small>
  <h1>Magias do Renascimento</h1>
  <p class="lead">As magias de chefe dos monstros que voltam da morte como <b>Pale</b>, <b>Ashen</b>, <b>Obsidian</b> e
  <b>Lord of Death</b>. Estilo chefe do Path of Exile: tudo é avisado no chão antes de bater, e quem lê o aviso desvia.
  Visual no mesmo kit do renascimento (“Renascimento, quatro presenças”).</p>
</div>

<div class="kpis">
  <div class="kpi"><b>4</b><span>tiers, cada um com um kit fixo</span></div>
  <div class="kpi"><b>{n_spells}</b><span>magias (3 por tier, 4 no Lord of Death)</span></div>
  <div class="kpi"><b>{n_files}</b><span>arquivos de arte (lista completa no CSV)</span></div>
  <div class="kpi"><b>2</b><span>etapas: 1 magia por tier para aprovar o estilo, depois o resto</span></div>
</div>

<h4>Neste pacote</h4>
<ul>
  <li><code>LEIA-ME.pdf</code> / <code>LEIA-ME.html</code> — este documento.</li>
  <li><code>lista_de_arquivos.csv</code> — todos os {n_files} arquivos com tamanho, frames, duração, camada e descrição (abre no Excel/Sheets).</li>
  <li><code>diagramas/</code> — uma imagem por magia: os sqm de perigo, os seguros e a linha do tempo.</li>
  <li><code>referencias/</code> — o kit atual do renascimento, as paletas tiradas dos shaders do jogo, o “relógio” de aviso que o jogo já usa e o guia das peças de linha.</li>
  <li><code>fundos_de_teste/</code> — {len(floors)} chãos 7×7 sqm (grama, neve, lava…) para testar o contraste da arte.</li>
  <li><code>entrega/</code> — as pastas com os nomes certos; cada uma tem um <code>_ARQUIVOS_ESPERADOS.txt</code>. Devolver essa pasta preenchida.</li>
</ul>

<h4>Índice</h4>
<ol class="toc">
  <li><a href="#s1">O que é o Renascimento</a></li>
  <li><a href="#s2">Como as magias funcionam na luta</a></li>
  <li><a href="#s3">Regras de leitura (as mais importantes)</a></li>
  <li><a href="#s4">Identidade visual de cada tier</a></li>
  <li><a href="#s5">Força pela XP do monstro</a></li>
  <li><a href="#s6">Resumo das magias</a></li>
  <li><a href="#tier-pale">As magias, uma por uma</a><ul>{toc}</ul></li>
  <li><a href="#s8">Formato de entrega</a></li>
  <li><a href="#s9">Etapas e checklist</a></li>
  <li><a href="#s10">Apêndice para o programador</a></li>
</ol>

<h2 id="s1">1. O que é o Renascimento</h2>
<p>Qualquer monstro que morre tem uma chance pequena de voltar alguns segundos depois numa versão mais forte. O corpo
pulsa na cor do tier, o monstro se levanta de dentro dele (a arte de chão / ar / eclosão que você já fez) e passa a andar
com o shader e a aura do tier. Ele pode subir de novo ao morrer: um Pale vira Ashen, um Ashen vira Obsidian, um Obsidian
vira Lord of Death.</p>
<table>
  <thead><tr><th>tier</th><th>material do kit</th><th>chance por morte</th><th>vida</th><th>dano normal</th><th>caveira</th></tr></thead>
  <tbody>
    <tr><td><span class="dot" style="background:#78ABB8"></span>Pale</td><td>O Véu (névoa)</td><td>2%</td><td>forte</td><td>×1,75</td><td>branca</td></tr>
    <tr><td><span class="dot" style="background:#C97135"></span>Ashen</td><td>A Flor de Cinza</td><td>0,7%</td><td>mais forte</td><td>×2,15</td><td>vermelha</td></tr>
    <tr><td><span class="dot" style="background:#8F74D8"></span>Obsidian</td><td>A Coroa de Vidro</td><td>0,5%</td><td>muito forte</td><td>×2,65</td><td>preta</td></tr>
    <tr><td><span class="dot" style="background:#792D42"></span>Lord of Death</td><td>O Eclipse</td><td>0,05%</td><td>chefe</td><td>×3,3</td><td>preta + selo</td></tr>
  </tbody>
</table>
<p><b>O que muda agora:</b> além dos ataques normais da espécie (um Pale Dragon continua cuspindo fogo), cada tier ganha
um <b>kit fixo de magias de chefe</b>. O kit é o mesmo em qualquer monstro do tier — um Pale Rat e um Pale Demon usam as
mesmas três magias, com a mesma arte. O que muda entre eles é só a força (seção 5).</p>
<figure><img src="referencias/kit_renascimento_atual.png" alt="Kit atual do renascimento">
<figcaption>O kit atual (a sua arte, que está em <code>referencias/arte_atual_do_renascimento/</code>). As magias são esses
mesmos materiais atacando.</figcaption></figure>

<h2 id="s2">2. Como as magias funcionam na luta</h2>
<p>A referência é o chefe do Path of Exile: golpes fortes, mas <b>sempre avisados</b>. O jogador perde vida porque não
leu o aviso, nunca porque o golpe foi impossível de ver.</p>
<ul>
  <li><b>Toda magia tem 3 momentos:</b> <span class="k">aviso</span> (marca no chão + o monstro conjurando) →
      <span class="k">golpe</span> (o dano, no instante em que o aviso termina) → às vezes <span class="k">resíduo</span>
      (chão que fica: geada, brasa).</li>
  <li><b>Durante o aviso o monstro para</b> e não usa os ataques normais — ele está “comprometido” com a magia.</li>
  <li><b>Ritmo:</b> 1 magia do tier a cada 9 s (Pale), 8 s (Ashen), 7 s (Obsidian) e 6 s (Lord of Death). A primeira vem
      2 s depois de ele terminar de levantar. Ele sorteia do kit e nunca repete a mesma duas vezes seguidas.</li>
  <li><b>Uma de cada vez:</b> nunca há dois avisos ao mesmo tempo. Exceção: o Sol Negro do Lord of Death (que persegue
      enquanto o Lord faz outra coisa).</li>
  <li>Só lança com um jogador a até 7 sqm e à vista. Não atravessa paredes. Não acontece em zona de proteção.</li>
  <li><b>Tempo mínimo de aviso:</b> 1,0 s para quem precisa dar 1 passo, 1,5 s para 2 passos, 2,5 s+ para o golpe final.
      Jogador de nível baixo anda devagar (≈0,5 s por sqm), então o Pale é o mais generoso.</li>
  <li>Todo monstro ocupa 1 sqm no jogo, mesmo os grandes (dragão): a origem de toda magia é o sqm dele. O
      <code>conjurar</code> é ampliado pelo jogo nos monstros grandes, como a aura.</li>
</ul>

<h2 id="s3">3. Regras de leitura</h2>
<p>Essas regras valem para todas as {n_spells} magias. Se uma escolha de arte bater com uma delas, a regra ganha.</p>
<ol class="rules">
  <li><b>A arte é a hitbox.</b> Os sqm marcados no diagrama são exatamente os que tomam dano. Nada importante pode vazar
      para um sqm seguro (um brilho suave de até 8 px tudo bem), e nenhum sqm perigoso pode ficar sem marca.</li>
  <li><b>Todo aviso tem relógio.</b> O jogador tem que saber quanto tempo falta. Use a mesma ideia que o jogo já tem no
      Meteoro e na Chuva de Juízo: um arco que se completa no sentido horário, ou uma marca que enche, e que <b>fecha no
      instante exato do golpe</b>. Os últimos ~0,25 s ficam mais claros: “agora”.
      (<code>referencias/aviso_com_relogio_ja_no_jogo.png</code>)</li>
  <li><b>Aviso no chão, golpe no ar.</b> Marcas ficam embaixo das criaturas (camada chão); o golpe fica por cima (camada ar).</li>
  <li><b>Brilho = perigo, apagado = seguro.</b> Um sqm que já explodiu fica apagado, sem cor de tier forte (Coroa Partida).</li>
  <li><b>Resíduo não tem relógio.</b> Geada e brasa são planas, respiram de leve e somem em estágios. Assim ninguém
      confunde “vai explodir” com “está queimando”.</li>
  <li><b>Contorno nítido, miolo translúcido.</b> O jogador precisa ver o chão, os itens e os outros monstros por baixo da
      marca. Borda forte, interior com 30–60% de opacidade.</li>
  <li><b>Lê em qualquer chão.</b> Teste nos <code>fundos_de_teste/</code> (o Pale na neve e o Ashen na lava são os
      perigosos) e em prints do jogo. Se sumir, ponha uma sombra/borda escura por fora.</li>
  <li><b>Cada tier tem a sua cor.</b> O Pale nunca usa laranja, o Ashen nunca usa azul, e assim por diante. Bater o
      olho na cor já diz qual monstro lançou.</li>
  <li><b>Segue a grade.</b> O chão do renascimento é uma elipse em perspectiva; as marcas de magia <b>não</b>: um círculo
      de 3 sqm é redondo na grade (7×7 sqm), igual ao diagrama.</li>
  <li><b>Nada de flash na tela inteira.</b> O único momento que escurece tudo é o Eclipse Total, e isso é feito pelo código.</li>
</ol>

<h2 id="s4">4. Identidade visual de cada tier</h2>
<p>As cores abaixo são as mesmas dos shaders que pintam o monstro de cada tier no jogo (sombra / matéria / luz do kit).
As magias são o material do tier ganhando vida — não um efeito genérico de gelo ou fogo.</p>
{''.join(tier_card(t) for t in TIERS)}
<figure><img src="referencias/paletas_dos_tiers.png" alt="Paletas dos tiers"></figure>

<h2 id="s5">5. Força pela XP do monstro</h2>
<p>O dano de cada magia sai da XP do monstro <b>normal</b> que renasceu (a XP da espécie, não a XP extra do tier).
Medimos os 1.257 monstros do servidor: o golpe mais forte de um monstro comum fica perto de 5 × XP<sup>0,54</sup>.
Esse é o <b>golpe de referência R</b> (arredondamos o expoente para 0,55); as magias são múltiplos dele.</p>
<div class="formula">R = 5 × XP<sup>0,55</sup> &nbsp;<small style="color:#aaa">(mín. 15, XP limitada a 100.000)</small><br>
dano = R × tier × magia &nbsp;<small style="color:#aaa">(±15% de variação)</small></div>
{spell_mult_table()}
<p>Exemplos (dano de um golpe comum do tier, <span class="muted">– o maior golpe do kit</span>):</p>
{damage_table()}
<div class="box"><b>Para a arte, isso não muda nada:</b> a mesma arte serve para o rato e para o demônio. Não precisa de
versão fraca/forte. O número que aparece em cima do jogador é que muda. (O multiplicador de dano normal do tier — ×1,75 a
×3,3 — não se aplica nessas magias; elas usam só a fórmula acima.)</div>

<h2 id="s6">6. Resumo das magias</h2>
{summary_table()}

{''.join(sections)}

<h2 id="s8">8. Formato de entrega</h2>
<p>O mesmo formato das artes dos skillshots (Meteoro, Corte Sísmico, Chuva de Juízo…).</p>
<ul>
  <li><b>PNG animado (APNG)</b>, fundo transparente. Frames parados (projétil andando: <code>petala_1..4</code>,
      <code>sol_voo_1..4</code>) são PNG simples, 1 por arquivo.</li>
  <li><b>2×:</b> 1 sqm = 64×64 px. Os tamanhos da tabela já estão em 2×. Exceção: os de <b>512×512</b> (selo e eclipse) são
      ampliados pelo jogo para 11×11 sqm — pintura suave, sem detalhe de 1 pixel.</li>
  <li><b>Âncora</b> (onde o arquivo encaixa no sqm):
    <ul>
      <li><code>centro</code> — o centro do arquivo é o centro do sqm (ou do monstro).</li>
      <li><code>base</code> — o sqm é o quadrado 64×64 de baixo do arquivo; o resto é altura (espinho, labareda, queda, refúgio).</li>
      <li><code>peça de linha</code> (<code>_h _v _ne _nw</code>) — ocupa o sqm inteiro e emenda na vizinha
          (<code>referencias/pecas_de_linha.png</code>): <code>_ne</code> vai do canto de baixo-esquerda ao de cima-direita,
          <code>_nw</code> do de cima-esquerda ao de baixo-direita. Simétricas: servem para os dois sentidos.</li>
    </ul></li>
  <li><b>Camada:</b> <code>chão</code> = embaixo das criaturas; <code>ar</code> = por cima.</li>
  <li><b>Duração:</b> a da tabela é a do desenho. Os de tempo fixo tocam uma vez (sem loop no fim); os <code>_loop</code>
      precisam fechar o ciclo sem pulo. O jogo pode acelerar/desacelerar um aviso (ex.: a 2ª fase da Coroa), então o relógio
      tem que ser uniforme — sem pausas no meio.</li>
  <li><b>Frames com o mesmo tempo</b> cada um (ex.: 12 frames em 1600 ms ≈ 133 ms por frame).</li>
  <li><b>Peso:</b> até ~300 KB por arquivo; os de 448 e 512 até ~600 KB. O cliente também roda no navegador.</li>
  <li><b>Nomes exatamente como na lista</b>, minúsculos e sem acento, dentro de <code>entrega/&lt;tier&gt;/&lt;magia&gt;/</code>.</li>
  <li><b>Prévia:</b> para cada magia, um GIF ou MP4 curto com a sequência inteira (conjurar → aviso → golpe → resíduo) em
      cima de um print do jogo com o monstro e um jogador — como as prévias da Ascensão.</li>
</ul>

<h2 id="s9">9. Etapas e checklist</h2>
<h4>Etapa 1 — aprovar o estilo</h4>
<ul>
  <li>Os 4 <code>conjurar</code> + <code>conjurar_fim</code> + <code>acerto</code> (pastas <code>comum/</code>).</li>
  <li>Uma magia por tier, com prévia: <a href="#pale-lagrimas">Lágrimas de Pérola</a>, <a href="#ashen-flor">Flor de Cinza</a>,
      <a href="#obsidian-coroa">Coroa Partida</a> e <a href="#deathlord-eclipse">Eclipse Total</a>.</li>
</ul>
<h4>Etapa 2 — o resto</h4>
<p>As outras magias, devolvendo a pasta <code>entrega/</code> completa com o nome <b>“Magias do Renascimento - artes v1”</b>.</p>
<h4>Antes de entregar, para cada magia</h4>
<ul>
  <li>☐ A arte cobre exatamente os sqm do diagrama (coloque o arquivo em cima de um fundo de teste com a grade).</li>
  <li>☐ O aviso tem relógio e fecha no fim; os últimos frames são os mais claros.</li>
  <li>☐ Dá para ler na neve, na lava, na grama e na caverna.</li>
  <li>☐ Resíduo sem relógio; sqm que já explodiu apagado.</li>
  <li>☐ Peças de linha emendam com a vizinha (h, v e as duas diagonais).</li>
  <li>☐ Cores só do próprio tier; nomes, tamanhos, frames e durações iguais à lista.</li>
</ul>

<h2 id="s10">10. Apêndice para o programador</h2>
<p><small>Não é para o designer — é para quem vai ligar a arte no jogo.</small></p>
<ul>
  <li><b>Servidor:</b> o kit começa em <code>Rarity.applyTier</code> (<code>scripts/rarity/01_core.lua</code>) e roda num
      laço por monstro com o id re-resolvido a cada passo (callback adiado vira no-op se o monstro sumiu). Números em
      <code>RarityConfig</code> (<code>00_config.lua</code>): <code>tierSpells = {{ ref = {{ mult = 5, exp = 0.55, xpCap = 100000,
      min = 15 }}, tierMult, interval, spells }}</code>. XP base: <code>monster:getType():experience()</code>. O dano é fixo
      (não passa pelo <code>getAttackMultiplier</code> da forja).</li>
  <li><b>Cliente:</b> um módulo novo (ex.: <code>game_rarespells</code>) usando o <code>newArtSet</code> de
      <code>game_skillshot/art.lua</code>; tamanhos da tabela ÷ 2 no <code>set.add</code>, âncoras como no Meteoro.
      Eventos pelo opcode do skillshot (131) com <code>fx = "rare_&lt;tier&gt;_&lt;magia&gt;"</code>; quem não tiver a arte
      recebe efeitos do Tibia. Os de 512 px usam <code>setSize</code> para 11×11 sqm (como o renascimento). O aviso que
      muda de duração usa <code>effect:setSpeed</code>.</li>
  <li><b>Hitbox:</b> as máscaras dos diagramas são as do servidor: círculo = distância euclidiana ≤ r (r = 1,5 / 2,5 / 3,5 / 5,5);
      linhas nas 8 direções; leque da Garra 1-3-5; xadrez = paridade de x+y.</li>
</ul>
<p><small>Gerado a partir do código atual do servidor e do cliente (rarity, game_shaders, game_raritybonus, game_skillshot).</small></p>
</main></body></html>
"""
    with open(os.path.join(ROOT, "LEIA-ME.html"), "w", encoding="utf-8") as fh:
        fh.write(page)
    print(ROOT, n_files, n_spells)


if __name__ == "__main__":
    build()
