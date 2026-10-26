# -*- coding: utf-8 -*-
# Monta "ET de Varginha - briefing v1": LEIA-ME.html, o CSV de arquivos, os
# diagramas (arena e magias), as referencias, os fundos de teste e a pasta de
# entrega com os nomes esperados.
import csv
import html
import math
import os
import shutil
import sys

# the spec beside this file; the diagrams, the references and the page's
# style come from the Magias do Renascimento's generator
HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(HERE, "..", "..", "magias-do-renascimento", "gerar")
sys.path.insert(0, HERE)
sys.path.insert(1, SHARED)

from PIL import Image, ImageDraw  # noqa: E402

import diagrams  # noqa: E402
import refs  # noqa: E402
from diagrams import Panel, circle, line, font  # noqa: E402
from et_spec import THEME, BOSS, PALETAS, GROUPS, SPELLS, ref_hit, all_items  # noqa: E402

diagrams.tier_of = lambda key: THEME  # the diagrams draw in the ET's colours

ROOT_NAME = "ET de Varginha - briefing v1"
OUT = sys.argv[1]
ROOT = os.path.join(OUT, ROOT_NAME)
FUSCA = str(refs.Path(refs.CLIENT).parent / "tools" / "custom-assets" / "art" / "fusca")
e = html.escape

# ---------------------------------------------------------------- the arena
W, H = 17, 13
WALL = [(0, y) for y in range(0, 13)]
WORKSHOP = [(16, y) for y in range(0, 13) if y != 6]
PILLARS = [(5, 3), (5, 9)]
FUSCA_TILES = [(9, 6), (10, 6), (9, 7), (10, 7)]
DRUMS = [(13, 3)]
STOPS = [[(3, 10), (4, 10), (3, 11), (4, 11)], [(12, 10), (13, 10), (12, 11), (13, 11)]]
COFFEE = [(3, 0), (6, 0), (10, 0), (13, 0), (2, 12), (14, 12)]
CROUCH = (1, 6)
BLOCKERS = set(PILLARS + FUSCA_TILES + DRUMS + WALL + WORKSHOP)
FLOOR = {(x, y) for x in range(1, 16) for y in range(0, 13)} - BLOCKERS - set(COFFEE)


def furnish(p, stops=True, coffee=True):
    for t in WALL + WORKSHOP:
        p.special("wall", *t)
    for t in PILLARS:
        p.special("block", *t, "pilar")
    for t in FUSCA_TILES:
        p.special("block", *t, "F")
    for t in DRUMS:
        p.special("block", *t, "T")
    if stops:
        for stop in STOPS:
            for t in stop:
                p.special("stop", *t, "P")
    if coffee:
        for t in COFFEE:
            p.special("coffee", *t)


def sight(a, b):
    """True when nothing in BLOCKERS stands between the centres of a and b."""
    ax, ay, bx, by = a[0] + .5, a[1] + .5, b[0] + .5, b[1] + .5
    steps = int(max(abs(bx - ax), abs(by - ay)) * 8) + 1
    for i in range(1, steps):
        t = i / steps
        cell = (int(ax + (bx - ax) * t), int(ay + (by - ay) * t))
        if cell != a and cell != b and cell in BLOCKERS:
            return False
    return True


def arena_map(path):
    p = Panel(W, H)
    furnish(p)
    p.special("block", 0, 6, "ET")
    p.monster(*CROUCH)
    p.note(8, 12, "entrada")
    p.note(8, 1, "↑ caixa d'água-disco ao fundo")
    p.note(11, 4, "Fusca velho")
    p.note(3, 9, "ponto de ônibus")
    p.note(13, 9, "ponto de ônibus")
    p.note(15, 4, "oficina")
    p.note(3, 6, "← muro do 1996")
    spell = {"tier": "et", "nome": "A arena: Terreno do Jardim Andere", "tipo": "noite de janeiro, 17×13 sqm", "timeline": [("luta", 1000)]}
    diagrams.diagram(spell, [p], path)


# ---------------------------------------------------------------- the spells' diagrams
def build_diagrams(outdir):
    by = {s["key"]: s for s in SPELLS}
    out = {}

    def go(key, panels):
        path = os.path.join(outdir, f"et_{key}.png")
        diagrams.diagram(by[key], panels, path)
        out[key] = path

    # Olhar Vermelho
    p = Panel(W, H, "1) A mira segue (1,0 s)")
    furnish(p, coffee=False)
    p.monster(3, 5)
    p.threat(line(3, 5, 1, 0, 9))
    p.ghost(9, 5)
    p.threat(line(3, 5, 1, 1, 6))
    p.player(8, 10)
    p.arrow([(9, 5), (9, 6), (9, 7), (8, 8), (8, 9), (8, 10)], color=(200, 200, 200), dashed=True)
    q = Panel(W, H, "2) Travou: 0,6 s para sair")
    furnish(q, coffee=False)
    q.monster(3, 5)
    q.danger(line(3, 5, 1, 0, 9))
    q.player(9, 5)
    q.safe([(9, 4)])
    q.arrow([(9, 5), (9, 4)])
    go("olhar", [p, q])

    # Tres Calombos
    p = Panel(W, H)
    furnish(p)
    p.monster(3, 6)
    centers = [(9, 4), (12, 8), (7, 8)]
    for n, c in enumerate(centers, 1):
        p.danger({(c[0] + dx, c[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)} & FLOOR)
        p.special("num", c[0], c[1] - 1, str(n))
    p.player(9, 4, "J1")
    p.player(12, 8, "J2")
    p.safe([(9, 2), (12, 10)])
    p.arrow([(9, 4), (9, 3), (9, 2)])
    p.arrow([(12, 8), (12, 9), (12, 10)])
    p.note(8, 12, "1 · 2 · 3: os calombos acendem; no 3 explode")
    go("calombos", [p])

    # Agachadinho e o Grito
    p = Panel(W, H)
    furnish(p)
    lit = {t for t in FLOOR if sight(CROUCH, t)}
    shadow = {t for t in FLOOR if not sight(CROUCH, t)}
    p.danger(lit - {CROUCH})
    p.safe(shadow)
    p.monster(*CROUCH)
    p.player(7, 4, "J1")
    p.arrow([(7, 4), (6, 4), (6, 3)])
    p.player(8, 8, "J2")
    p.arrow([(8, 8), (9, 8), (10, 8), (11, 7)])
    p.note(9, 12, "verde = atrás de pilar, Fusca ou tambor: o grito não chega")
    go("grito", [p])

    # Abducao
    p = Panel(W, H)
    furnish(p, stops=False)
    sun = (7, 6)
    p.danger({(sun[0] + dx, sun[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)} & FLOOR)
    p.special("ghostsun", 5, 6)
    p.special("ghostsun", 6, 6)
    p.special("saucer", *sun)
    p.player(8, 6)
    p.arrow([(8, 6), (8, 5), (8, 4), (8, 3)])
    p.arrow([(7, 6), (8, 6)], color=(191, 246, 255), dashed=True)
    p.note(8, 11, "o disco anda 1 sqm a cada 0,6 s; quem para é abduzido")
    go("abducao", [p])

    # Chuva de Discos
    rows1 = [y for y in range(1, 12) if y % 2 == 0]
    rows2 = [y for y in range(1, 12) if y % 2 == 1]
    def lanes(rows):
        return [(x, y) for y in rows for x in range(1, 16) if (x, y) in FLOOR]
    p = Panel(W, H, "Onda 1 (1,5 s)")
    furnish(p, coffee=False)
    p.danger(lanes(rows1))
    for y in rows1:
        p.special("saucer", 1, y)
    p.player(8, 5)
    p.safe([(8, 5)])
    q = Panel(W, H, "Onda 2 (1,5 s)")
    furnish(q, coffee=False)
    q.spent(lanes(rows1))
    q.danger(lanes(rows2))
    for y in rows2:
        q.special("saucer", 15, y)
    q.player(8, 5)
    q.arrow([(8, 5), (8, 4)])
    q.safe([(8, 4)])
    go("chuva", [p, q])

    # Cheiro de Amonia
    p = Panel(W, H)
    furnish(p)
    for c in [(9, 5), (5, 8)]:
        p.residue({(c[0] + dx, c[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)} & FLOOR)
        p.special("cloud", *c)
    p.player(10, 4, "J1")
    p.arrow([(10, 4), (10, 3), (10, 2), (10, 1)])
    p.player(5, 8, "J2")
    p.arrow([(5, 8), (4, 8), (3, 8), (3, 9)])
    p.arrow([(9, 5), (10, 4)], color=(184, 194, 74), dashed=True)
    p.note(10, 1, "cafezinho ↑")
    p.monster(2, 4)
    go("amonia", [p])

    # BUSQUEM CONHECIMENTO
    p = Panel(W, H)
    furnish(p)
    refuges = {t for stop in STOPS for t in stop}
    p.danger(FLOOR - refuges)
    p.monster(8, 6)
    p.player(6, 8, "J1")
    p.arrow([(6, 8), (5, 9), (4, 10)])
    p.player(10, 9, "J2")
    p.arrow([(10, 9), (11, 10), (12, 10)])
    p.safe(refuges)
    p.note(8, 1, "a frase se escreve no céu: na última letra, o raio")
    go("busquem_conhecimento", [p])
    return out


# ---------------------------------------------------------------- references
def gabarito(path):
    """The 64x64 frame of a big Tibia creature, 6 times bigger: where the ET's
    sqm is and a rough idea of the two poses (not the art)."""
    S = 6
    img = Image.new("RGB", (64 * S * 2 + 120, 64 * S + 170), (24, 23, 27))
    d = ImageDraw.Draw(img, "RGBA")
    d.text((30, 22), "Gabarito do sprite (64×64, 1x) — esquema, não é a arte", fill=(232, 230, 226), font=font(20, "b"))
    for i, (label, crouch) in enumerate([("em pé", False), ("agachado", True)]):
        ox, oy = 30 + i * (64 * S + 60), 70
        d.rectangle((ox, oy, ox + 64 * S, oy + 64 * S), fill=(46, 45, 50))
        d.rectangle((ox + 32 * S, oy + 32 * S, ox + 64 * S, oy + 64 * S), fill=(70, 66, 58))
        for k in range(0, 65, 8):
            d.line([(ox + k * S, oy), (ox + k * S, oy + 64 * S)], fill=(60, 59, 66))
            d.line([(ox, oy + k * S), (ox + 64 * S, oy + k * S)], fill=(60, 59, 66))
        d.rectangle((ox + 32 * S, oy + 32 * S, ox + 64 * S, oy + 64 * S), outline=(120, 220, 150), width=3)
        skin, dark = (107, 66, 41), (59, 36, 24)
        # feet on the sqm, the body drawn up and to the left like Tibia's 3/4 view
        fx, fy = ox + 46 * S, oy + 58 * S
        if not crouch:
            d.line([(fx - 4 * S, fy), (fx - 3 * S, fy - 12 * S)], fill=skin, width=2 * S)
            d.line([(fx + 3 * S, fy), (fx + 2 * S, fy - 12 * S)], fill=skin, width=2 * S)
            d.ellipse((fx - 7 * S, fy - 28 * S, fx + 6 * S, fy - 10 * S), fill=skin, outline=dark, width=S)
            hx, hy, hr = fx - 2 * S, fy - 36 * S, 10 * S
        else:
            d.ellipse((fx - 11 * S, fy - 16 * S, fx + 9 * S, fy), fill=skin, outline=dark, width=S)
            hx, hy, hr = fx - 3 * S, fy - 22 * S, 10 * S
        for bx in (-6, 0, 6):
            d.ellipse((hx + bx * S - 3 * S, hy - hr - 4 * S, hx + bx * S + 3 * S, hy - hr + 3 * S), fill=skin, outline=dark, width=S)
        d.ellipse((hx - hr, hy - hr, hx + hr, hy + hr * .9), fill=skin, outline=dark, width=S)
        for ex in (-5, 4):
            d.ellipse((hx + ex * S - 3 * S, hy - 2 * S, hx + ex * S + 3 * S, hy + 4 * S), fill=(216, 30, 30), outline=(122, 10, 10), width=S)
            d.ellipse((hx + ex * S - 1 * S, hy - 1 * S, hx + ex * S, hy), fill=(255, 227, 214))
        d.text((ox + 64 * S // 2, oy + 64 * S + 26), label, fill=(232, 230, 226), font=font(18, "b"), anchor="mm")
    notes = ["verde: o sqm da criatura (32×32 de baixo à direita) — o resto é desenho por cima dos vizinhos, como no Tibia",
             "três calombos no alto da cabeça · olhos vermelhos enormes, sem pupila · sem boca e sem nariz",
             "pele marrom oleosa com veias saltadas · corpo magro · ~1,6 m: um pouco menor que um humano do Tibia"]
    for k, n in enumerate(notes):
        d.text((30, 64 * S + 110 + k * 20), n, fill=(150, 148, 145), font=font(14))
    img.save(path, optimize=True)


def palettes(path):
    W_, row = 1100, 140
    img = Image.new("RGB", (W_, 30 + row * len(PALETAS)), (24, 23, 27))
    d = ImageDraw.Draw(img)
    for i, (name, swatches) in enumerate(PALETAS):
        y = 24 + i * row
        d.text((30, y + 30), name, fill=(232, 230, 226), font=font(20, "b"))
        x = 330
        for label, hx in swatches:
            d.rounded_rectangle((x, y, x + 120, y + 74), 8, fill=refs.hexrgb(hx), outline=(80, 80, 86))
            d.text((x, y + 82), label, fill=(232, 230, 226), font=font(14, "sb"))
            d.text((x, y + 102), hx, fill=(150, 148, 145), font=font(13))
            x += 140
    img.save(path, optimize=True)


def night_floor(path):
    """the vacant lot at night, 7x7 sqm at 2x, for testing the spells' art"""
    import random
    rnd = random.Random(96)
    img = Image.new("RGB", (448, 448), (58, 52, 44))
    px = img.load()
    for y in range(0, 448, 4):
        for x in range(0, 448, 4):
            base = (58, 52, 44) if rnd.random() > .25 else (44, 60, 38)
            k = rnd.randint(-10, 10)
            c = tuple(max(0, min(255, v + k)) for v in base)
            for yy in range(4):
                for xx in range(4):
                    px[x + xx, y + yy] = c
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle((0, 0, 448, 448), fill=(20, 26, 46, 90))
    for i in range(8):
        d.line([(i * 64, 0), (i * 64, 448)], fill=(0, 0, 0, 40))
        d.line([(0, i * 64), (448, i * 64)], fill=(0, 0, 0, 40))
    img.save(path, optimize=True)


# ---------------------------------------------------------------- tables
KIND = {"sprite": "PNG 1x", "seg": "APNG 2x"}


def size_text(f):
    if f["ms"] == "sprite":
        return f"{f['w']}×{f['h']}"
    if f["w"] == 512:
        return "512×512 (ampliado pelo jogo)"
    return f"{f['w']}×{f['h']} ({f['w'] / 64:g}×{f['h'] / 64:g} sqm)".replace(".", ",")


def ms_text(ms):
    return {"loop": "loop", "parado": "parado (1 frame)", "sprite": "—"}.get(ms, f"{ms} ms") if not isinstance(ms, int) else f"{ms} ms"


def file_table(item):
    rows = []
    for f in item["files"]:
        rows.append(f"<tr><td class='fn'>{e(f['nome'])}.png</td><td>{e(size_text(f))}</td><td class='c'>{f['frames']}</td>"
                    f"<td>{e(ms_text(f['ms']))}</td><td>{e(f['camada'])}</td><td>{e(f['preso'])}</td><td class='desc'>{e(f['desc'])}</td></tr>")
    return ("<table class='files'><thead><tr><th>arquivo</th><th>tamanho</th><th>frames</th><th>duração</th><th>camada</th>"
            "<th>preso a</th><th>o que é</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


def folder_of(item):
    return item["key"] if "/" in item["key"] else f"magias/{item['key']}"


def write_csv(path):
    with open(path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["etapa", "grupo", "pasta", "arquivo", "formato", "largura_px", "altura_px", "frames", "duracao", "camada", "preso_a", "descricao"])
        for item, f in all_items():
            fmt = "PNG 1x (pixel art)" if f["ms"] == "sprite" else "APNG 2x"
            w.writerow([item.get("etapa", 1), item["nome"], folder_of(item), f["nome"] + ".png", fmt, f["w"], f["h"], f["frames"],
                        ms_text(f["ms"]), f["camada"], f["preso"], f["desc"]])


def write_skeleton(base):
    for item in GROUPS + SPELLS:
        d = os.path.join(base, folder_of(item))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "_ARQUIVOS_ESPERADOS.txt"), "w", encoding="utf-8") as fh:
            fh.write(f"{item['nome']} (etapa {item.get('etapa', 1)})\nColoque aqui os PNG com exatamente estes nomes:\n\n")
            for f in item["files"]:
                fh.write(f"  {f['nome']}.png   {f['w']}x{f['h']}  {f['frames']} frame(s)  {ms_text(f['ms'])}\n")
            fh.write("\nApague este arquivo quando a pasta estiver completa.\n")


def damage_table():
    r = ref_hit(BOSS["xp"])
    rows = []
    for s in SPELLS:
        if "mult" not in s:
            continue
        rows.append(f"<tr><td><a href='#m-{s['key']}'>{e(s['nome'])}</a></td><td class='c'>{str(s['mult']).replace('.', ',')}</td>"
                    f"<td class='r'>{round(r * s['mult']):,}</td><td class='r'>{round(r * s['mult'] * 1.3):,}</td></tr>".replace(",", "."))
    return (f"<p>XP do chefe: <b>{BOSS['xp']:,}</b> → R = <b>{r:,}</b>.</p>".replace(",", ".")
            + "<table class='mult'><thead><tr><th>magia</th><th>× R</th><th>dano</th><th>com o rateMonsterAttack 1,3 do servidor</th></tr></thead><tbody>"
            + "".join(rows) + "</tbody></table>")


CSS = open(os.path.join(SHARED, "build.py"), encoding="utf-8").read().split('CSS = """', 1)[1].split('"""', 1)[0]


def section_item(item, diag=None):
    anchor = f"m-{item['key']}" if "/" not in item["key"] else "g-" + item["key"].replace("/", "-")
    head = f"<h3><span class='tag'>etapa {item.get('etapa', 1)}</span>{e(item['nome'])} <small>· {e(item['tipo'])}</small></h3>"
    body = ""
    if item.get("intro"):
        body += f"<p>{e(item['intro'])}</p>"
    if item.get("conceito"):
        mech = "".join(f"<li>{e(m)}</li>" for m in item["mecanica"])
        body += f"""<p class="lead">{e(item['conceito'])}</p>
  <div class="grid2">
    <div><h4>Como funciona</h4><ul>{mech}</ul></div>
    <div><h4>Como o jogador desvia</h4><p>{e(item['esquiva'])}</p>
         <h4>Dano</h4><p>{e(item['dano'])}</p><h4>Fase</h4><p>{e(item.get('fase', ''))}</p></div>
  </div>"""
    if diag:
        body += f"<figure><img src='{diag}' alt='Diagrama'><figcaption>Grade vista de cima, 1 quadrado = 1 sqm. A arte cobre exatamente os sqm marcados.</figcaption></figure>"
    body += f"<h4>Arquivos — pasta <code>entrega/{folder_of(item)}/</code></h4>{file_table(item)}"
    return f"<div class='spell' id='{anchor}' style='--c:rgb{THEME['cor']}'>{head}{body}</div>"


def build():
    if os.path.exists(ROOT):
        shutil.rmtree(ROOT)
    for sub in ["diagramas", "referencias/exemplo_montaria_fusca", "fundos_de_teste", "entrega"]:
        os.makedirs(os.path.join(ROOT, sub), exist_ok=True)
    arena_map(os.path.join(ROOT, "diagramas", "et_arena.png"))
    diags = build_diagrams(os.path.join(ROOT, "diagramas"))
    gabarito(os.path.join(ROOT, "referencias", "gabarito_sprite.png"))
    palettes(os.path.join(ROOT, "referencias", "paletas.png"))
    refs.clock_sheet(os.path.join(ROOT, "referencias", "aviso_com_relogio_ja_no_jogo.png"))
    refs.line_pieces(os.path.join(ROOT, "referencias", "pecas_de_linha.png"))
    for name in os.listdir(FUSCA):
        shutil.copy(os.path.join(FUSCA, name), os.path.join(ROOT, "referencias", "exemplo_montaria_fusca", name))
    refs.test_floors(os.path.join(ROOT, "fundos_de_teste"))
    night_floor(os.path.join(ROOT, "fundos_de_teste", "terreno_a_noite.png"))
    write_csv(os.path.join(ROOT, "lista_de_arquivos.csv"))
    write_skeleton(os.path.join(ROOT, "entrega"))

    n_files = sum(len(i["files"]) for i in GROUPS + SPELLS)
    n_sprites = sum(len(g["files"]) for g in GROUPS)
    n_spells = len([s for s in SPELLS if s["key"] != "comum"])
    stage1 = sum(len(i["files"]) for i in GROUPS + SPELLS if i.get("etapa", 1) == 1)

    sprites_html = "".join(section_item(g) for g in GROUPS if g["key"].startswith("sprites"))
    items_html = "".join(section_item(g) for g in GROUPS if g["key"].startswith("itens"))
    spells_html = "".join(section_item(s, "diagramas/" + os.path.basename(diags[s["key"]]) if s["key"] in diags else None) for s in SPELLS)
    summary = "".join(
        f"<tr><td><a href='#m-{s['key']}'>{e(s['nome'])}</a></td><td>{e(s['tipo'])}</td><td>{e(s.get('fase', ''))}</td>"
        f"<td>{e(s['esquiva'])}</td><td class='c'>{s['etapa']}</td></tr>" for s in SPELLS if s["key"] != "comum")

    page = f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ET de Varginha</title>
<style>{CSS}
.cover{{border-image:linear-gradient(#D81E1E,#6B4229,#B8C24A,#BFF6FF) 1}}
.no{{background:#fdecea;border:1px solid #f3c2bd;border-radius:10px;padding:12px 16px;margin:12px 0}}
.quote{{font-size:20px;font-weight:600;border-left:4px solid #D81E1E;padding:4px 14px;margin:14px 0}}
</style></head>
<body><main>

<div class="cover">
  <small>Mythos · briefing de arte · v1</small>
  <h1>ET de Varginha</h1>
  <p class="lead">O chefe do meme mais famoso do Brasil. 30 anos depois de 1996, ele voltou para o terreno do Jardim
  Andere — e desta vez não vai ficar só agachado. Luta no estilo chefe do Path of Exile (tudo avisado no chão, igual às
  magias do Renascimento), com a cara do meme: os três calombos, os olhos vermelhos, o medo, o cheiro de amônia, a caixa
  d'água-disco-voador, os pontos de ônibus-nave e o café de Varginha. E o golpe mais forte demora a sair:
  <b>BUSQUEM CONHECIMENTO</b>.</p>
</div>

<div class="kpis">
  <div class="kpi"><b>3</b><span>fases de luta</span></div>
  <div class="kpi"><b>{n_spells}</b><span>magias</span></div>
  <div class="kpi"><b>{n_files}</b><span>arquivos ({n_sprites} sprites e itens em 1x, {n_files - n_sprites} de efeito em 2x)</span></div>
  <div class="kpi"><b>{stage1}</b><span>arquivos na etapa 1 (dá para ligar a fase 1 no jogo)</span></div>
</div>

<h4>Neste pacote</h4>
<ul>
  <li><code>LEIA-ME.pdf</code> / <code>.html</code> — este documento.</li>
  <li><code>lista_de_arquivos.csv</code> — os {n_files} arquivos com formato, tamanho, frames, duração e descrição.</li>
  <li><code>diagramas/</code> — o mapa da arena e uma imagem por magia (sqm de perigo, seguros, linha do tempo).</li>
  <li><code>referencias/</code> — gabarito do sprite, paletas, o relógio de aviso que o jogo já usa, as peças de linha e o
      Fusca como exemplo de montaria.</li>
  <li><code>fundos_de_teste/</code> — chãos para testar contraste, incluindo o terreno à noite da arena.</li>
  <li><code>entrega/</code> — as pastas com os nomes certos (<code>_ARQUIVOS_ESPERADOS.txt</code> em cada uma).</li>
</ul>

<h2 id="s1">1. O meme</h2>
<p>Em 20 de janeiro de 1996, no Jardim Andere, em Varginha (MG), três jovens disseram ter visto uma criatura agachada
junto a um muro, ao lado de uma oficina: cerca de 1,6 m, pele marrom e oleosa com veias saltadas, olhos vermelhos enormes
e sem pupila, três calombos na cabeça parecendo chifres, sem boca e sem nariz, e um cheiro forte de amônia. Ela parecia
assustada. Vieram depois as histórias de captura, de caminhão misterioso e de segredo — e o caso virou o ET mais famoso do
Brasil.</p>
<p>A cidade abraçou: a <b>caixa d'água em forma de disco voador</b> (20 m, na Praça Marechal Floriano), <b>pontos de ônibus
em formato de nave</b>, esculturas do ET pelas praças, o <b>Memorial do ET</b> (2022, um prédio em forma de nave), a
<b>Rota do ET</b> (2024) e o caso virou <b>patrimônio cultural imaterial</b> do município (2023). E Varginha é um dos
maiores centros de café do país. Em 2026 o caso fez 30 anos.</p>
<p class="quote">O tom: carinho de meme. O ET é um bicho assustado e esquisito-fofo, não um monstro de terror. A graça está
nos detalhes (o agachadinho, o "!" de susto, o ponto de ônibus que salva, o cafezinho), e a luta é séria.</p>
<div class="no"><b>O que NÃO usar</b><ul>
  <li>Nenhuma pessoa real: nem as testemunhas, nem policiais ou militares envolvidos, nem o morador da região que a
      versão oficial do Exército apontou como explicação. Nada de piada com deficiência.</li>
  <li>Nenhuma instituição real como inimiga (Exército, bombeiros, polícia). Os "caçadores" da história não aparecem.</li>
  <li>Nada de outros memes de ET misturados — é o de Varginha. A única exceção é o nome do golpe final,
      <b>BUSQUEM CONHECIMENTO</b>: entra só o bordão, sem o visual de outro ET e sem nenhuma pessoa real.</li>
</ul></div>

<h2 id="s2">2. O chefe</h2>
<ul>
  <li><b>Nome no jogo:</b> ET de Varginha. Para {e(BOSS['nivel'])}. Vida inicial {str(BOSS['vida'] // 1000) + '.000'}, XP {str(BOSS['xp'] // 1000) + '.000'} (ajustáveis).</li>
  <li><b>Arena:</b> o Terreno do Jardim Andere numa noite de janeiro: chão de terra com mato, o muro de tijolo chapiscado
      onde ele se agachou, a oficina com portão de ferro, um Fusca velho parado, tambores, pés de café nas bordas, dois
      pontos de ônibus-disco-voador e, ao fundo, a caixa d'água-disco iluminada. Luz de poste de sódio (laranja).</li>
  <li><b>Fase 1 — O Avistamento</b> (100% a 70%): Olhar Vermelho, Três Calombos e o Agachadinho com o Grito.</li>
  <li><b>Fase 2 — A Nave Chegou</b> (70% a 35%): somam-se a Abdução e a Chuva de Discos; nascem 2 ETzinhos (enquanto
      vivos, o ET toma 30% menos dano).</li>
  <li><b>Fase 3 — Cheiro de Amônia</b> (35% a 0%): o ET fica furioso (o código deixa ele avermelhado), entra o gás de
      amônia, e aos 35% e aos 15% vem o golpe mais forte, com 6 s de carga: <b>BUSQUEM CONHECIMENTO</b>.</li>
  <li><b>Falas</b> (o ET não tem boca: os textos são em itálico, como pensamento): <i>*o ET está agachado no canto do muro,
      tremendo*</i> · <i>*um grito sem boca ecoa dentro da sua cabeça*</i> · <i>*bzzzt... casa...?*</i> · <i>*um cheiro
      forte de amônia toma o terreno*</i> · no golpe final, a única fala em voz alta, ecoando na cabeça de todos:
      <b>BUSQUEM CONHECIMENTO!</b> · na morte: <i>*o ET de Varginha finalmente vai para casa*</i>.</li>
</ul>
<figure><img src="diagramas/et_arena.png" alt="Mapa da arena"><figcaption>A arena (proposta para o mapa). M = onde o ET
começa, agachado no muro de 1996. P = pontos de ônibus. Pilar, F (Fusca) e T (tambores) bloqueiam a visão.</figcaption></figure>

<h2 id="s3">3. Identidade visual</h2>
<ul>
  <li><b>Silhueta:</b> cabeçona (quase metade da altura) com os três calombos no alto — o do meio maior —, corpo magro e
      curvado, braços finos e compridos, dedos longos. Lê-se o ET de longe só pela cabeça.</li>
  <li><b>Olhos:</b> os maiores e mais brilhantes da tela, vermelhos e sem pupila, com um reflexo úmido. São o ponto focal.</li>
  <li><b>Pele:</b> marrom com brilho oleoso (reflexos claros e molhados) e veias saltadas na cabeça e nos braços.</li>
  <li><b>Expressão:</b> medo (sobrancelhas que não existem, mas o corpo diz: encolhido, olhando de lado). Na fase 3, os
      olhos mais acesos — o código cuida do vermelho.</li>
  <li><b>Efeitos:</b> vermelho dos olhos para os ataques do ET; luz fria ciano-branca para a nave; amarelo-esverdeado para
      a amônia; branco-frio para o que é seguro (ponto de ônibus, sombra atrás do muro).</li>
  <li><b>Dois estilos:</b> sprites e itens são <b>pixel art 1x no estilo do Tibia</b> (contorno escuro, luz de cima à
      esquerda, vista 3/4 como as criaturas do jogo). Efeitos de magia são <b>pintados em 2x</b>, como as artes do
      Renascimento e dos skillshots.</li>
</ul>
<figure><img src="referencias/paletas.png" alt="Paletas"></figure>

<h2 id="s4">4. Sprites</h2>
<p>Formato das criaturas grandes do Tibia: cada frame é um PNG de <b>64×64</b> (2×2 sqm), e o sqm da criatura é o quadrado
<b>32×32 de baixo à direita</b>; o resto do desenho invade os sqm de cima e da esquerda. Quatro direções (norte, leste, sul,
oeste) na diagonal do jogo — o Fusca em <code>referencias/exemplo_montaria_fusca/</code> mostra o ângulo. Um PNG por frame,
fundo transparente, sem antisserrilhado contra o fundo (borda de pixel limpa).</p>
<figure><img src="referencias/gabarito_sprite.png" alt="Gabarito do sprite"></figure>
{sprites_html}

<h2 id="s5">5. Itens da arena e loot</h2>
{items_html}

<h2 id="s6">6. As magias</h2>
<p>As mesmas regras de leitura das Magias do Renascimento: a arte é a hitbox; todo aviso tem relógio e fecha no instante do
golpe; aviso no chão, golpe no ar; brilho = perigo, apagado = seguro; resíduo sem relógio; contorno nítido e miolo
translúcido; segue a grade. O "relógio" do Três Calombos é o único contado em 3 passos, porque são os três calombos.</p>
<table class="sum"><thead><tr><th>magia</th><th>tipo</th><th>fase</th><th>como desviar</th><th>etapa</th></tr></thead><tbody>{summary}</tbody></table>
{spells_html}

<h2 id="s7">7. Força</h2>
<p>Mesma fórmula das magias do Renascimento: R = 5 × XP<sup>0,55</sup> com a XP do chefe, e cada magia é um múltiplo de R.
Para a arte não muda nada.</p>
{damage_table()}

<h2 id="s8">8. Formato de entrega</h2>
<ul>
  <li><b>Sprites e itens</b> (<code>entrega/sprites/</code>, <code>entrega/itens/</code>): PNG estático, <b>1x</b>, um
      arquivo por frame, nos tamanhos da tabela (64×64 criatura grande, 32×32 ETzinho e ícones). Paleta limitada, pixel
      limpo, sem semitransparência nas bordas.</li>
  <li><b>Efeitos</b> (<code>entrega/magias/</code>): APNG <b>2x</b> (1 sqm = 64×64 px), fundo transparente, frames com o
      mesmo tempo, os <code>_loop</code> fechando sem pulo, os de tempo fixo tocando uma vez. Frames parados (disco
      voando, disquinhos) são PNG simples. Os de 512×512 são ampliados pelo jogo: pintura suave.</li>
  <li><b>Âncoras</b> como no Renascimento: <code>centro</code> (centro do arquivo = centro do sqm), <code>base</code> (o sqm
      é o quadrado de baixo do arquivo), <code>peça de linha</code> (<code>_h _v _ne _nw</code>, emenda na vizinha).</li>
  <li><b>Peso:</b> até ~300 KB por efeito; os de 448 e 512 até ~600 KB.</li>
  <li><b>Prévia:</b> um vídeo curto por magia sobre <code>fundos_de_teste/terreno_a_noite.png</code> e um com o sprite
      andando nas 4 direções.</li>
  <li>Nomes exatamente como na lista, minúsculos e sem acento.</li>
</ul>

<h2 id="s9">9. Etapas e checklist</h2>
<h4>Etapa 1 — o ET e a fase 1</h4>
<p>Sprites do ET (em pé, agachado, cadáver), itens da arena, Olhar Vermelho, Três Calombos e Agachadinho/Grito, e as peças
comuns. Com isso a fase 1 já vai para o jogo e dá para aprovar o estilo.</p>
<h4>Etapa 2 — o resto</h4>
<p>ETzinho, montaria, loot, Abdução, Chuva de Discos, Cheiro de Amônia e BUSQUEM CONHECIMENTO. Devolver como
<b>"ET de Varginha - artes v1"</b>.</p>
<h4>Antes de entregar</h4>
<ul>
  <li>☐ O ET se reconhece só pela silhueta (cabeça + três calombos) e pelos olhos, nas 4 direções.</li>
  <li>☐ O agachado parece com medo.</li>
  <li>☐ Cada efeito cobre exatamente os sqm do diagrama e tem relógio que fecha no golpe.</li>
  <li>☐ A sombra segura do Grito e o brilho dos pontos de ônibus leem como "aqui pode" na hora.</li>
  <li>☐ A frase BUSQUEM CONHECIMENTO lê de qualquer canto da tela e a última letra é o instante do raio.</li>
  <li>☐ Nenhuma pessoa ou instituição real.</li>
</ul>

<h2 id="s10">10. Apêndice para o programador</h2>
<ul>
  <li>Dois outfits (em pé, agachado) pelo mesmo caminho das montarias próprias (<code>tools/custom-assets/build_mounts.py</code>,
      grupo parado com 4 fases e andando com 8); o agachado entra por <code>monster:setOutfit</code> no Agachadinho.</li>
  <li>Magias no padrão de <code>scripts/rarity/spells.lua</code>: eventos pelo opcode 131 com <code>fx = "et_varginha"</code>,
      arte num conjunto do <code>game_skillshot</code>. O Grito usa <code>Position:isSightClear</code> do ET até cada
      jogador; a sombra segura é a lista de sqm sem visão até ele, enviada ao cliente.</li>
  <li>BUSQUEM CONHECIMENTO: carga de 6 s com o ET enraizado no centro (setOutfit em pé, sem atacar); a frase é um
      efeito único de 6 s sobre o centro da arena; os refúgios são os sqm dos dois pontos de ônibus do mapa; o escurecer
      é o mesmo do Eclipse Total. Fala em voz alta: <code>monster:say("BUSQUEM CONHECIMENTO!", TALKTYPE_MONSTER_YELL)</code>.</li>
  <li>Cafezinho: ação nos pés de café (troca para o item colhido por 20 s), tira o Enjoado e dá haste.</li>
</ul>
<h4>Fontes do caso</h4>
<ul>
  <li><a href="https://www.tecmundo.com.br/ciencia/410041-et-de-varginha-completa-30-anos-e-caso-continua-recebendo-novidades.htm">TecMundo — ET de Varginha completa 30 anos</a></li>
  <li><a href="https://www.folhavitoria.com.br/viralizou/tres-decadas-depois-o-caso-do-et-de-varginha-em-30-pontos-viral/">Folha Vitória — o caso em 30 pontos</a></li>
  <li><a href="https://www.em.com.br/emfoco/2026/07/31/cidade-mineira-que-virou-patrimonio-cultural-por-causa-de-um-suposto-et-e-hoje-lidera-a-exportacao-de-cafe-do-brasil/">Estado de Minas — patrimônio cultural e café</a></li>
</ul>
</main></body></html>
"""
    with open(os.path.join(ROOT, "LEIA-ME.html"), "w", encoding="utf-8") as fh:
        fh.write(page)
    print(ROOT, n_files, n_spells, stage1)


if __name__ == "__main__":
    build()
