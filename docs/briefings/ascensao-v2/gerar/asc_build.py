# -*- coding: utf-8 -*-
# Monta "Ascensao - artes v2 - briefing v1": o guia (HTML/PDF), a lista de
# camadas, os modelos de curvas e particulas, o diagnostico da v1, o video
# conceito a 60 fps e a pasta de entrega.
import csv
import glob
import html
import json
import os
import shutil
import struct
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.environ.get("BRIEFING_SHARED") or os.path.join(HERE, "..", "..", "magias-do-renascimento", "gerar")
sys.path.insert(0, HERE)
sys.path.insert(1, SHARED)

from PIL import Image, ImageDraw  # noqa: E402

import refs  # noqa: E402
from diagrams import font  # noqa: E402
from asc_spec import VOCATIONS, SPELLS, PILOT, voc_of  # noqa: E402

ROOT_NAME = "Ascensao - artes v2 - briefing v1"
OUT = sys.argv[1]
DEMO = sys.argv[2] if len(sys.argv) > 2 else None  # the concept video (demo60.py)
ROOT = os.path.join(OUT, ROOT_NAME)
IMAGES = os.path.join(refs.CLIENT, "game_skillshot", "images")
e = html.escape
CSS = open(os.path.join(SHARED, "build.py"), encoding="utf-8").read().split('CSS = """', 1)[1].split('"""', 1)[0]

TIPO = {"parada": "parada (1 frame)", "flipbook": "flipbook", "particula": "partícula", "relogio": "relógio"}


# ---------------------------------------------------------------- the v1 today
def apng(path):
    d = open(path, "rb").read()
    w, h = struct.unpack(">II", d[16:24])
    a = d.find(b"acTL")
    n = struct.unpack(">I", d[a + 4:a + 8])[0] if a > 0 else 1
    delays, i = [], 8
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        if d[i + 4:i + 8] == b"fcTL":
            dn, dd = struct.unpack(">HH", d[i + 16 + 12:i + 16 + 16])
            delays.append(1000 * dn / (dd or 100))
        i += 12 + ln
    return w, h, n, sum(delays), len(d)


def inventory():
    agg = defaultdict(lambda: {"files": 0, "frames": 0, "mem": 0, "bytes": 0, "fps": []})
    for path in glob.glob(os.path.join(IMAGES, "*", "*.png")):
        folder = os.path.basename(os.path.dirname(path))
        w, h, n, ms, size = apng(path)
        a = agg[folder]
        a["files"] += 1
        a["frames"] += n
        a["mem"] += w * h * 4 * n
        a["bytes"] += size
        if n > 1 and ms:
            a["fps"].append(n * 1000 / ms)
    return agg


V1_FOLDER = {"corte": "corte", "salto": "salto", "gancho": "gancho", "flecha": "flecha", "juizo": "juizo", "lanca": "lanca",
             "raio": "raio", "meteoro": "meteoro", "esfera": "esfera", "estilhaco": "estilhaco", "muralha": "muralha",
             "raizes": "raizes", "palma": "palma", "chute": "chute", "passo": "passo"}


def v2_cost(spell):
    files = len(spell["camadas"])
    mem = sum(c["w"] * c["h"] * 4 * c["frames"] for c in spell["camadas"])
    return files, mem


def contact_sheets(outdir):
    names = {"knight": ["corte", "salto", "gancho"], "paladin": ["flecha", "juizo", "lanca"], "sorcerer": ["raio", "meteoro", "esfera"],
             "druid": ["estilhaco", "muralha", "raizes"], "monk": ["palma", "chute", "passo"]}
    skip_tail = {"n", "s", "w", "ne", "nw", "se", "sw", "v"}
    for voc, spells in names.items():
        rows = []
        for sp in spells:
            for path in sorted(glob.glob(os.path.join(IMAGES, sp, "*.png"))):
                parts = os.path.basename(path)[:-4].split("_")
                if parts[-1] in skip_tail or (parts[-1] in ("2", "3", "4") and len(parts) > 2):
                    continue
                im = Image.open(path)
                n = getattr(im, "n_frames", 1)
                picks = sorted({int(k * (n - 1) / 4) for k in range(5)}) if n > 1 else [0]
                frames = []
                for k in picks:
                    im.seek(k)
                    frames.append(im.convert("RGBA").copy())
                rows.append((f"{sp}/{os.path.basename(path)}", n, frames))
        cell = 104
        sheet = Image.new("RGB", (230 + cell * 5, 40 + len(rows) * (cell + 4)), (66, 74, 58))
        d = ImageDraw.Draw(sheet)
        d.text((10, 12), f"Arte v1 de hoje — {voc_of(voc)['nome']}", fill=(255, 255, 255), font=font(16, "b"))
        for r, (label, n, frames) in enumerate(rows):
            y = 40 + r * (cell + 4)
            d.text((10, y + cell // 2 - 8), label, fill=(255, 255, 255), font=font(12, "sb"))
            d.text((10, y + cell // 2 + 8), f"{n} frame(s)", fill=(200, 205, 190), font=font(11))
            for c, fr in enumerate(frames):
                t = fr.copy()
                t.thumbnail((cell, cell))
                bg = Image.new("RGBA", (cell, cell), (66, 74, 58, 255))
                bg.alpha_composite(t, ((cell - t.width) // 2, (cell - t.height) // 2))
                sheet.paste(bg.convert("RGB"), (230 + c * cell, y))
        sheet.save(os.path.join(outdir, f"arte_v1_{voc}.png"), optimize=True)


# ---------------------------------------------------------------- teaching images
def anatomy(path):
    """the layers of the concept video on a time line"""
    layers = [
        ("luz no mapa", 0, 1500, "luz"), ("impacto_nucleo (luz)", 0, 430, "luz"), ("fagulhas (partículas)", 0, 560, "luz"),
        ("impacto_anel", 30, 700, "normal"), ("rochas (partículas)", 0, 900, "normal"), ("tremor (código)", 0, 160, "code"),
        ("poeira", 120, 1700, "normal"), ("cratera (esfria)", 60, 3000, "normal"),
    ]
    W, row, left, scale = 1100, 34, 250, 0.26  # px per ms
    img = Image.new("RGB", (W, 110 + row * len(layers)), (24, 23, 27))
    d = ImageDraw.Draw(img)
    d.text((24, 18), "Anatomia de um impacto (o vídeo conceito): cada camada tem o seu tempo", fill=(232, 230, 226), font=font(19, "b"))
    for ms in range(0, 3001, 250):
        x = left + ms * scale
        d.line([(x, 56), (x, 70 + row * len(layers))], fill=(52, 51, 58))
        d.text((x, 50), f"{ms / 1000:g} s".replace(".", ","), fill=(150, 148, 145), font=font(11), anchor="ms")
    colors = {"luz": (255, 196, 92), "normal": (196, 120, 70), "code": (120, 160, 220)}
    for i, (name, a, b, kind) in enumerate(layers):
        y = 66 + i * row
        d.text((24, y + 10), name, fill=(232, 230, 226), font=font(14))
        x0, x1 = left + a * scale, left + b * scale
        # strong at the start, fading tail: the follow-through
        for k in range(int(x1 - x0)):
            f = k / max(1, x1 - x0)
            alpha = 1 - f ** 0.6 if kind != "code" else 1 - f
            c = tuple(int(24 + (v - 24) * alpha) for v in colors[kind])
            d.line([(x0 + k, y + 2), (x0 + k, y + 22)], fill=c)
    d.text((24, 76 + row * len(layers)), "antecipação → impacto (clarão em 2–3 frames) → um rabo longo que some devagar: é o rabo que dá peso.",
           fill=(150, 148, 145), font=font(14))
    img.save(path, optimize=True)


def orientation_guide(path):
    """how to draw what the game turns and stretches"""
    img = Image.new("RGB", (1100, 330), (24, 23, 27))
    d = ImageDraw.Draw(img, "RGBA")
    d.text((24, 18), "Desenhe apontando para a DIREITA → o jogo gira para as 8 direções (ou o ângulo exato)", fill=(232, 230, 226), font=font(19, "b"))
    import math
    cx, cy = 190, 180
    for k in range(8):
        a = -k * math.pi / 4
        x, y = cx + math.cos(a) * 95, cy + math.sin(a) * 95
        d.line([(cx, cy), (x, y)], fill=(255, 200, 90, 220 if k == 0 else 90), width=8 if k == 0 else 4)
        d.polygon([(x + math.cos(a) * 14, y + math.sin(a) * 14), (x + math.cos(a + 2.4) * 12, y + math.sin(a + 2.4) * 12),
                   (x + math.cos(a - 2.4) * 12, y + math.sin(a - 2.4) * 12)], fill=(255, 200, 90, 230 if k == 0 else 90))
    d.text((cx, cy + 130), "o arquivo: só este →", fill=(150, 148, 145), font=font(14), anchor="mm")
    # stretch
    ox = 470
    d.text((ox, 70), "\"estica\": uma peça horizontal que o jogo estica pelo caminho", fill=(232, 230, 226), font=font(15, "b"))
    for i, length in enumerate((140, 300, 560)):
        y = 120 + i * 60
        for k in range(length):
            f = k / length
            col = (int(255 - 130 * f), int(200 - 110 * f), int(90 + 120 * f), int(230 * (1 - f) ** 0.7))
            d.line([(ox + 560 - k, y - 6 + 3 * f), (ox + 560 - k, y + 6 - 3 * f)], fill=col)
        d.ellipse((ox + 552, y - 8, ox + 568, y + 8), fill=(255, 246, 216, 255))
        d.text((ox, y), f"{length // 64 * 1 or 1}–{length // 32} sqm", fill=(150, 148, 145), font=font(12), anchor="lm")
    d.text((ox, 300), "mantenha a ponta (cabeça) separada: ela não deforma; só o corpo/rastro estica", fill=(150, 148, 145), font=font(13))
    img.save(path, optimize=True)


# ---------------------------------------------------------------- tables and files
def write_models(base):
    rows = [
        ["momento", "camada", "t_ms", "escala", "opacidade", "x_sqm", "y_sqm", "rotacao_graus", "luz", "suavizacao"],
        ["impacto", "impacto_nucleo", 0, 0.35, 0, 0, 0.4, 0, "", "-"],
        ["impacto", "impacto_nucleo", 40, 0.8, 1, 0, 0.4, 0, "", "saida"],
        ["impacto", "impacto_nucleo", 90, 1.2, 1, 0, 0.4, 0, "", "saida"],
        ["impacto", "impacto_nucleo", 430, 1.35, 0, 0, 0.4, 0, "", "entrada"],
        ["impacto", "impacto_anel", 30, 0.25, 0.95, 0, 0.15, 0, "", "-"],
        ["impacto", "impacto_anel", 160, 0.9, 0.95, 0, 0.15, 0, "", "saida_forte"],
        ["impacto", "impacto_anel", 700, 1.05, 0, 0, 0.15, 0, "", "entrada"],
        ["impacto", "poeira", 120, 0.9, 0, 0, 0.4, 0, "", "-"],
        ["impacto", "poeira", 320, 1.1, 0.85, 0, 0.6, 0, "", "saida"],
        ["impacto", "poeira", 1700, 1.5, 0, 0, 0.8, 0, "", "entrada"],
        ["chão", "cratera", 60, 1, 0, 0, 0, 0, "", "-"],
        ["chão", "cratera", 220, 1, 1, 0, 0, 0, "", "saida"],
        ["chão", "cratera", 3000, 1, 0, 0, 0, 0, "", "entrada_saida"],
        ["impacto", "(luz do mapa)", 0, "", "", "", "", "", 0, "-"],
        ["impacto", "(luz do mapa)", 50, "", "", "", "", "", 8, "saida"],
        ["impacto", "(luz do mapa)", 1500, "", "", "", "", "", 0, "saida"],
        ["impacto", "(tremor)", 0, "", "", "", "", "", "", "forte 160 ms"],
    ]
    with open(os.path.join(base, "curvas_modelo.csv"), "w", newline="", encoding="utf-8-sig") as fh:
        csv.writer(fh, delimiter=";").writerows(rows)
    prow = [
        ["momento", "imagem", "quantidade", "atraso_ms", "vida_ms", "velocidade_sqm_s", "espalhamento_graus", "subida_sqm_s", "gravidade_sqm_s2", "tamanho", "gira", "luz"],
        ["impacto", "rocha_1..3", 16, 0, "550-900", "4-8", 360, "4-8", 14, "0.7-1.3", "sim", "não"],
        ["impacto", "fagulha_1..2", 26, 0, "260-560", "6.5-13", 360, "2.5-6.5", 11, "0.5-1", "não", "sim"],
    ]
    with open(os.path.join(base, "particulas_modelo.csv"), "w", newline="", encoding="utf-8-sig") as fh:
        csv.writer(fh, delimiter=";").writerows(prow)


def write_list(path):
    with open(path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["etapa", "vocacao", "magia", "pasta", "arquivo", "tipo", "largura_px", "altura_px", "frames", "blend", "gira_estica", "momento", "descricao"])
        for s in SPELLS:
            for c in s["camadas"]:
                w.writerow([1 if s["key"] in PILOT else 2, voc_of(s["voc"])["nome"], s["nome"], f"{s['voc']}/{s['key']}", c["nome"] + ".png",
                            TIPO[c["tipo"]], c["w"], c["h"], c["frames"], c["blend"], c["extra"], c["momento"], c["desc"]])


def write_skeleton(base):
    for s in SPELLS:
        d = os.path.join(base, s["voc"], s["key"])
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "_ARQUIVOS_ESPERADOS.txt"), "w", encoding="utf-8") as fh:
            fh.write(f"{s['nome']} (etapa {1 if s['key'] in PILOT else 2})\nCamadas (PNG/APNG 2x) com exatamente estes nomes, mais curvas.csv e particulas.csv:\n\n")
            for c in s["camadas"]:
                fh.write(f"  {c['nome']}.png   {c['w']}x{c['h']}  {TIPO[c['tipo']]}{' ' + str(c['frames']) + ' frames' if c['frames'] > 1 else ''}  {c['blend']}  {c['extra']}\n")
            fh.write("  curvas.csv\n  particulas.csv\n  previa_60fps.mp4\n\nApague este arquivo quando a pasta estiver completa.\n")


def layer_table(spell):
    rows = []
    for c in spell["camadas"]:
        kind = TIPO[c["tipo"]] + (f" · {c['frames']} frames" if c["frames"] > 1 else "")
        rows.append(f"<tr><td class='fn'>{e(c['nome'])}.png</td><td>{c['w']}×{c['h']}</td><td>{e(kind)}</td><td>{e(c['blend'])}</td>"
                    f"<td>{e(c['extra'] or '—')}</td><td>{e(c['momento'])}</td><td class='desc'>{e(c['desc'])}</td></tr>")
    return ("<table class='files'><thead><tr><th>camada</th><th>tamanho</th><th>tipo</th><th>blend</th><th>o jogo</th><th>momento</th>"
            "<th>o que é</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


def build():
    if os.path.exists(ROOT):
        shutil.rmtree(ROOT)
    for sub in ["referencias", "entrega"]:
        os.makedirs(os.path.join(ROOT, sub), exist_ok=True)
    contact_sheets(os.path.join(ROOT, "referencias"))
    anatomy(os.path.join(ROOT, "referencias", "anatomia_de_um_impacto.png"))
    orientation_guide(os.path.join(ROOT, "referencias", "girar_e_esticar.png"))
    refs.clock_sheet(os.path.join(ROOT, "referencias", "aviso_com_relogio_ja_no_jogo.png"))
    if DEMO and os.path.exists(DEMO):
        shutil.copy(DEMO, os.path.join(ROOT, "referencias", "conceito_60fps_meteoro.mp4"))
    write_models(ROOT)
    write_list(os.path.join(ROOT, "lista_de_camadas.csv"))
    write_skeleton(os.path.join(ROOT, "entrega"))

    inv = inventory()
    v1_files = sum(inv[f]["files"] for f in V1_FOLDER.values())
    v1_mem = sum(inv[f]["mem"] for f in V1_FOLDER.values())
    v2_files = sum(v2_cost(s)[0] for s in SPELLS)
    v2_mem = sum(v2_cost(s)[1] for s in SPELLS)
    mb = lambda b: f"{b / 1048576:.1f}".replace(".", ",")

    diag_rows = []
    for s in SPELLS:
        folder = V1_FOLDER.get(s["key"])
        f2, m2 = v2_cost(s)
        if folder:
            a = inv[folder]
            fps = f"{min(a['fps']):.0f}–{max(a['fps']):.0f}" if a["fps"] else "—"
            v1 = f"<td class='r'>{a['files']}</td><td class='r'>{a['frames']}</td><td>{fps}</td><td class='r'>{mb(a['mem'])} MB</td>"
        else:
            v1 = "<td colspan='4'>efeitos do Tibia</td>"
        diag_rows.append(f"<tr><td>{e(voc_of(s['voc'])['nome'])}</td><td><a href='#m-{s['key']}'>{e(s['nome'])}</a></td>{v1}"
                         f"<td class='r'>{f2}</td><td class='r'>{mb(m2)} MB</td></tr>")

    voc_cards = "".join(
        f"""<div class="tier" style="--c:{v['paleta'][2][1]}"><h3>{e(v['nome'])} — {e(v['tema'])} <small>({e(v['titulo'])})</small></h3>
  <dl><dt>Paleta</dt><dd><span class="sw">{''.join(f"<i style='background:{hx}' title='{e(n)}'></i>" for n, hx in v['paleta'])}</span>
  <small>{' · '.join(f"{e(n)} {hx}" for n, hx in v['paleta'])}</small></dd>
  <dt>Assinatura</dt><dd>{e(v['assinatura'])}</dd><dt>Movimento</dt><dd>{e(v['movimento'])}</dd><dt>Luz no mapa</dt><dd>{e(v['luz'])}</dd></dl></div>"""
        for v in VOCATIONS)

    spell_html = []
    for v in VOCATIONS:
        spell_html.append(f"<h2 id='v-{v['key']}'>7.{VOCATIONS.index(v) + 1} {e(v['nome'])} — {e(v['tema'])}</h2>")
        for s in SPELLS:
            if s["voc"] != v["key"]:
                continue
            f2, m2 = v2_cost(s)
            diag = "".join(f"<li>{e(x)}</li>" for x in s["diag"])
            mech = f"<div class='box'><b>Mudança de jogo:</b> {e(s['mecanica'])}</div>" if s.get("mecanica") else ""
            etapa = 1 if s["key"] in PILOT else 2
            spell_html.append(f"""<div class="spell" id="m-{s['key']}" style="--c:{v['paleta'][2][1]}">
  <h3><span class="tag">etapa {etapa}</span>{e(s['nome'])} <small>· {e(s['caminho'])} · <code>{e(s['words'])}</code></small></h3>
  <p class="lead">{e(s['direcao'])}</p>{mech}
  <div class="grid2"><div><h4>Momentos (vêm do servidor)</h4><p>{e(s['momentos'])}</p></div>
  <div><h4>O que melhorar na v1</h4><ul>{diag}</ul></div></div>
  <h4>Camadas — pasta <code>entrega/{s['voc']}/{s['key']}/</code> · {f2} arquivos · ~{mb(m2)} MB</h4>
  {layer_table(s)}</div>""")

    pilot = ", ".join(f"<a href='#m-{s['key']}'>{e(s['nome'])}</a>" for s in SPELLS if s["key"] in PILOT)
    toc = "".join(f"<li><a href='#v-{v['key']}'>{e(v['nome'])}</a>: " + ", ".join(f"<a href='#m-{s['key']}'>{e(s['nome'])}</a>" for s in SPELLS if s["voc"] == v["key"]) + "</li>" for v in VOCATIONS)

    page = f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ascensão artes v2</title>
<style>{CSS}
.cover{{border-image:linear-gradient(#FF7A2A,#FFC94D,#4F7BFF,#8FD3FF,#5FD1B0) 1}}
video{{width:100%;border-radius:8px;background:#000}}
.big{{font-size:22px;font-weight:700;margin:10px 0}}
</style></head>
<body><main>

<div class="cover">
  <small>Mythos · briefing de arte · Ascensão v2</small>
  <h1>Magias da Ascensão — artes v2</h1>
  <p class="lead">As 15 magias que a árvore da Ascensão ensina (3 por vocação) e a Translocação do Arcanist, refeitas para
  ficarem mais sofisticadas, intensas, bonitas e grandiosas — e rodando suaves a <b>60 fps</b> sem precisar de mais imagens
  nem pesar o jogo.</p>
</div>

<div class="kpis">
  <div class="kpi"><b>16</b><span>magias (5 vocações + Translocação)</span></div>
  <div class="kpi"><b>60 fps</b><span>o movimento é calculado pelo jogo a cada quadro</span></div>
  <div class="kpi"><b>{v1_files} → {v2_files}</b><span>arquivos: hoje → v2 (menos imagens)</span></div>
  <div class="kpi"><b>{mb(v1_mem)} → {mb(v2_mem)} MB</b><span>memória de vídeo: hoje → v2 (estimativa)</span></div>
</div>

<p class="big">A ideia: a imagem é o material, o código é o movimento.</p>
<p>Hoje cada efeito é um filme de 4 a 12 quadros tocado a 4–20 fps: para ficar suave assim seriam centenas de quadros por
efeito e o jogo pesaria. Na v2 você entrega <b>camadas</b> (a maioria é uma imagem parada só) e diz <b>como cada uma se
mexe</b> (curvas de tamanho, opacidade, posição, giro e luz). O jogo calcula isso a cada quadro da tela — 60 fps ou mais —
sem gastar memória com quadros. O vídeo <code>referencias/conceito_60fps_meteoro.mp4</code> mostra: à esquerda o impacto
do Meteoro de hoje, à direita a <b>mesma arte</b> cortada em 4 imagens paradas, com partículas e luz, movida por curvas.</p>
{"<video src='referencias/conceito_60fps_meteoro.mp4' controls loop muted playsinline></video>" if DEMO else ""}

<h4>Neste pacote</h4>
<ul>
  <li><code>LEIA-ME.pdf</code> / <code>.html</code> — este documento.</li>
  <li><code>lista_de_camadas.csv</code> — todas as {v2_files} camadas da v2 (tamanho, tipo, blend, o que o jogo faz com ela).</li>
  <li><code>curvas_modelo.csv</code> e <code>particulas_modelo.csv</code> — como descrever o movimento (o exemplo é o impacto do vídeo).</li>
  <li><code>referencias/</code> — o vídeo conceito, a anatomia de um impacto, o guia de girar e esticar, o relógio de aviso
      e a arte v1 de hoje de cada vocação (para comparar).</li>
  <li><code>entrega/</code> — uma pasta por magia com os nomes esperados.</li>
</ul>
<h4>Índice</h4>
<ol class="toc"><li><a href="#s1">O que está fraco hoje</a></li><li><a href="#s2">Como chegar a 60 fps com poucas imagens</a></li>
<li><a href="#s3">Curvas e partículas</a></li><li><a href="#s4">Princípios: grandioso, intenso, sofisticado e suave</a></li>
<li><a href="#s5">Identidade de cada vocação</a></li><li><a href="#s6">Orçamento</a></li><li><a href="#v-knight">As magias</a><ul>{toc}</ul></li>
<li><a href="#s8">Formato de entrega</a></li><li><a href="#s9">Etapas e checklist</a></li><li><a href="#s10">Apêndice para o programador</a></li></ol>

<h2 id="s1">1. O que está fraco hoje</h2>
<p>A v1 resolveu o principal (cada magia tem a sua cara e o aviso no chão funciona). O que falta é acabamento:</p>
<ul>
  <li><b>Travado:</b> 4 a 12 quadros por efeito, a 4–20 fps. O olho vê os saltos.</li>
  <li><b>Pequeno:</b> quase tudo cabe em 1–2 sqm. Não há momento "uau".</li>
  <li><b>Plano:</b> uma camada só, sem brilho que some na luz, sem luz no chão, sem contraste de valor.</li>
  <li><b>Projéteis pulando:</b> flecha, gancho, lança, onda e sementes são 4 imagens paradas trocando de sqm em sqm, e
      pequenas (~20 px). E custam caro: 8 direções × 4 quadros (a Flecha tem 96 arquivos só de voo).</li>
  <li><b>Sem antecipação e sem rabo:</b> o golpe aparece e some. Falta o "segurar antes" e o "deixar marca depois"
      (fumaça, brasa, penas caindo, névoa).</li>
</ul>
<table class="mult"><thead><tr><th>vocação</th><th>magia</th><th>v1: arquivos</th><th>quadros</th><th>fps</th><th>memória</th>
<th>v2: arquivos</th><th>memória</th></tr></thead><tbody>{''.join(diag_rows)}</tbody></table>
<p>As folhas <code>referencias/arte_v1_*.png</code> mostram cada arquivo de hoje em 5 quadros.</p>

<h2 id="s2">2. Como chegar a 60 fps com poucas imagens</h2>
<p>Quatro tipos de camada:</p>
<ul>
  <li><b>Parada</b> (PNG de 1 frame) — a maioria. Núcleo de luz, anel de choque, onda, decalque no chão, a cabeça de um
      projétil, um raio. O jogo anima tamanho, opacidade, posição, giro e luz pelas suas curvas, a cada quadro.</li>
  <li><b>Flipbook</b> (APNG curto, até 12 frames) — só para o que é orgânico e não dá para fazer movendo uma imagem: fogo
      rolando, fumaça, eletricidade crepitando, raízes crescendo. O jogo <b>mistura um frame no outro</b> (transição
      suave), então 8–12 frames parecem fluidos a 60 fps.</li>
  <li><b>Partícula</b> (PNG pequeno, 32 px, 2–3 variações) — pedras, fagulhas, penas, lascas. O jogo espalha várias
      cópias com velocidade, gravidade, giro e vida (o <code>particulas.csv</code> diz como).</li>
  <li><b>Relógio</b> (APNG de 12 frames no tempo exato) — só os avisos com tempo de jogo (o arco que fecha). Esse é tocado
      quadro a quadro de propósito: é o cronômetro.</li>
</ul>
<p>E o que o jogo faz com elas (é com isso que você pode contar):</p>
<ul>
  <li><b>Girar:</b> desenhe o que tem direção (flecha, gancho, lança, feixe, dragão, onda) <b>apontando para a direita</b>;
      o jogo gira para as 8 direções ou para o ângulo exato. Um arquivo no lugar de 8 a 32.</li>
  <li><b>Esticar:</b> rastros e feixes são uma peça horizontal que o jogo estica ao longo do caminho.</li>
  <li><b>Luz:</b> camadas marcadas "luz" são somadas por cima (brilham, não cobrem); e o efeito acende a luz do mapa na
      cor da vocação (aparece no escuro de caverna).</li>
  <li><b>Projétil inteiro num movimento:</b> a cabeça anda o caminho todo de forma contínua, não de sqm em sqm.</li>
  <li><b>Tremor leve da tela</b> nos golpes mais pesados (só onde a ficha pedir).</li>
</ul>
<figure><img src="referencias/girar_e_esticar.png" alt="Girar e esticar"></figure>

<h2 id="s3">3. Curvas e partículas</h2>
<p>Para cada magia, além das imagens, entregue <code>curvas.csv</code> (uma linha por ponto-chave) e
<code>particulas.csv</code>. Se você anima no After Effects, é só ler os valores dos keyframes. Os modelos têm o impacto do
vídeo pronto como exemplo.</p>
<table class="mult"><thead><tr><th>coluna</th><th>o que é</th></tr></thead><tbody>
<tr><td><code>momento</code></td><td>o momento da magia (os da ficha: carga, voo, acerto, impacto, chão...)</td></tr>
<tr><td><code>camada</code></td><td>o nome do arquivo sem .png (ou <code>(luz do mapa)</code>, <code>(tremor)</code>)</td></tr>
<tr><td><code>t_ms</code></td><td>tempo desde o início do momento</td></tr>
<tr><td><code>escala</code></td><td>1 = o tamanho do arquivo (2x: 64 px = 1 sqm)</td></tr>
<tr><td><code>opacidade</code></td><td>0 a 1</td></tr>
<tr><td><code>x_sqm</code>, <code>y_sqm</code></td><td>deslocamento em sqm (y positivo = para cima)</td></tr>
<tr><td><code>rotacao_graus</code></td><td>giro somado à direção da magia</td></tr>
<tr><td><code>luz</code></td><td>força da luz no mapa, 0 a 10 (a cor é a da vocação)</td></tr>
<tr><td><code>suavizacao</code></td><td>como chega neste ponto: <code>linear</code>, <code>entrada</code> (acelera), <code>saida</code> (freia),
<code>entrada_saida</code>, <code>saida_forte</code> (sai disparado e freia muito), <code>estouro</code> (passa do ponto e volta)</td></tr>
</tbody></table>
<figure><img src="referencias/anatomia_de_um_impacto.png" alt="Anatomia de um impacto"></figure>

<h2 id="s4">4. Princípios: grandioso, intenso, sofisticado e suave</h2>
<ul>
  <li><b>Três tamanhos de momento.</b> Golpe comum 2–3 sqm; golpe forte 4–5 sqm; o ápice (carga cheia, flecha de longe,
      último ricochete, a queda do Titã) 6–7 sqm com luz no mapa e, se fizer sentido, tremor.</li>
  <li><b>Antecipação → impacto → rabo.</b> Algo se junta antes (energia, poeira, runas); o impacto é um clarão de 2–3
      frames no máximo de brilho; o rabo dura 2 a 4 vezes o impacto e some devagar. O rabo é o que dá peso.</li>
  <li><b>Nada linear.</b> Tudo que surge sai rápido e freia (<code>saida</code>); o que some acelera para sumir
      (<code>entrada</code>); o que cresce pode passar do ponto (<code>estouro</code>). Camadas começam e terminam em tempos
      diferentes (sobreposição) — nunca tudo junto.</li>
  <li><b>Valor antes de cor.</b> Núcleo quase branco (camada de luz), meio saturado na cor da vocação, borda escura ou fria.
      É esse degrau que faz parecer intenso, não mais saturação.</li>
  <li><b>Uma assinatura por vocação</b> (seção 5) repetida nas três magias: é o que faz parecer um conjunto sofisticado.</li>
  <li><b>Leitura continua igual:</b> marcas no chão cobrem exatamente a área de dano e o relógio fecha no golpe (as regras
      das Magias do Renascimento). Floreio de impacto pode passar até 1 sqm da área; decalque no chão não.</li>
</ul>

<h2 id="s5">5. Identidade de cada vocação</h2>
<p>Do título máximo de cada caminho na Ascensão.</p>
{voc_cards}

<h2 id="s6">6. Orçamento (para rodar liso, inclusive no navegador)</h2>
<ul>
  <li><b>Por magia:</b> até ~17 arquivos e ~6 MB de memória de vídeo (as duas grandes de área, Salto do Titã e Meteoro,
      até ~9 MB); até ~1 MB em disco.</li>
  <li><b>Flipbook:</b> até 12 frames e 256×256. <b>Parada:</b> até 512×512 (é 1 frame só).</li>
  <li><b>Ao mesmo tempo:</b> até 6 camadas por momento, no máximo 2 grandes (≥ 256 px), e até ~24 partículas.</li>
  <li><b>Transparência grande custa:</b> evite camadas grandes quase vazias e muitas camadas grandes empilhadas.</li>
  <li>A soma da v2 estimada pela lista é <b>{mb(v2_mem)} MB</b>, contra <b>{mb(v1_mem)} MB</b> de hoje.</li>
</ul>

{''.join(spell_html)}

<h2 id="s8">8. Formato de entrega</h2>
<ul>
  <li>Camadas em <b>2x</b> (1 sqm = 64×64 px), fundo transparente. Paradas e partículas em PNG; flipbooks e relógios em
      APNG com frames de tempo igual (flipbooks em loop fecham sem pulo).</li>
  <li>Âncora: o centro do arquivo é o centro do sqm (ou da criatura); o que tem "base" (pilar, coluna) tem o sqm no
      quadrado de baixo. O que gira aponta para a direita, com o centro do giro no centro do arquivo.</li>
  <li>Em cada pasta: as camadas, <code>curvas.csv</code>, <code>particulas.csv</code> e <code>previa_60fps.mp4</code> (a
      sequência inteira a 60 fps sobre um chão de teste).</li>
  <li>Nomes exatamente como na lista; a pasta de entrega já tem as pastas certas.</li>
  <li>No fim: as prévias da janela da Ascensão (<code>game_ascensao/images/previas</code>, 288×144) refeitas com a v2.</li>
</ul>

<h2 id="s9">9. Etapas e checklist</h2>
<h4>Etapa 1 — o piloto (uma por vocação)</h4>
<p>{pilot}. Valida o jeito novo (camadas + curvas) dentro do jogo antes de fazer o resto.</p>
<h4>Etapa 2</h4>
<p>As outras 10, a Translocação e as prévias da janela. Devolver como <b>"Ascensao - artes v2"</b>.</p>
<h4>Antes de entregar, por magia</h4>
<ul>
  <li>☐ Tem antecipação, impacto e rabo; nada surge nem some de uma vez.</li>
  <li>☐ O núcleo é uma camada de luz; a borda tem contraste.</li>
  <li>☐ O que tem direção foi desenhado apontando para a direita.</li>
  <li>☐ A prévia a 60 fps está suave e as marcas no chão continuam do tamanho da área.</li>
  <li>☐ Dentro do orçamento (arquivos, frames, tamanhos).</li>
</ul>

<h2 id="s10">10. Apêndice para o programador</h2>
<ul>
  <li><b>Curvas no C++:</b> o <code>AttachedEffect</code> ganha keyframes (escala, opacidade, deslocamento, rotação, luz)
      com suavização, avaliados no <code>draw()</code> — 60 fps ou mais sem Lua por quadro. Rotação via
      <code>g_drawPool.rotate</code>; esticar via <code>setSize</code> não uniforme.</li>
  <li><b>Flipbook com mistura:</b> o <code>AnimatedTexture</code> desenha o frame atual e o próximo com opacidades
      complementares.</li>
  <li><b>Blend aditivo</b> para as camadas "luz"; <b>emissor de partículas</b> simples (lido de
      <code>particulas.csv</code>); <b>tremor</b> no mapa.</li>
  <li><b>Projéteis:</b> o servidor manda o caminho inteiro; o cliente move a cabeça num só <code>move()</code>.</li>
  <li><b>Flecha do Crepúsculo:</b> puxada de 0,4 s (paladino enraizado, mira travada no início) e voo de 30 ms por sqm
      em <code>scripts/skillshot/paladin.lua</code>.</li>
  <li>As curvas de cada magia ficam num arquivo por magia ao lado das camadas (<code>curvas.csv</code>).</li>
</ul>
</main></body></html>
"""
    with open(os.path.join(ROOT, "LEIA-ME.html"), "w", encoding="utf-8") as fh:
        fh.write(page)
    print(ROOT, v1_files, v2_files, mb(v1_mem), mb(v2_mem))


if __name__ == "__main__":
    build()
