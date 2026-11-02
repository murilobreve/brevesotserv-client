# -*- coding: utf-8 -*-
# Referencias da parte 2: as da parte 1 (paletas, relogio, pecas de linha,
# fundos de teste, kit do renascimento) e a arte da etapa 1 que o designer ja
# entregou e esta no cliente (modules/game_skillshot/images/renascimento/).
import os
import shutil

from PIL import Image, ImageDraw

import spec2  # noqa: F401  (poe a pasta da parte 1 no sys.path)
import refs as v1refs  # parte 1
from diagrams import font  # parte 1

CLIENT = v1refs.CLIENT
DELIVERED = os.path.join(CLIENT, "game_skillshot", "images", "renascimento")
BG = (24, 23, 27)
TEXT = (232, 230, 226)
MUTED = (150, 148, 145)

# (pasta do tier, pasta da magia, titulo, arquivos na folha)
SHEET = [
    ("pale", "lagrimas", "Pale — Lágrimas de Pérola", ["marca", "queda", "impacto", "geada_loop"]),
    ("ashen", "flor", "Ashen — Flor de Cinza", ["botao", "desabrocha", "trilha_h", "petala_1"]),
    ("obsidian", "coroa", "Obsidian — Coroa Partida", ["marca", "espinho", "resto"]),
    ("lord-of-death", "eclipse", "Lord of Death — Eclipse Total", ["selo_marca", "refugio_loop", "eclipse"]),
    ("pale", "comum", "Peças comuns (conjurar) dos 4 tiers", None),
]
FLOOR = (78, 92, 70)


def _frame(path, at):
    im = Image.open(path)
    n = getattr(im, "n_frames", 1)
    im.seek(min(n - 1, int(at * (n - 1))))
    return im.convert("RGBA").copy(), n


def _cell(img, d, x, y, size, path, label, at):
    tile = Image.new("RGBA", (size, size), FLOOR + (255,))
    # a grade de sqm por baixo, para dar a escala (1 sqm = 64 px no arquivo)
    fr, n = _frame(path, at)
    scale = min((size - 12) / fr.width, (size - 12) / fr.height, 1.0)
    if scale < 1:
        fr = fr.resize((max(1, int(fr.width * scale)), max(1, int(fr.height * scale))), Image.LANCZOS)
    gd = ImageDraw.Draw(tile, "RGBA")
    step = 64 * scale
    if step >= 12:
        k = 0.0
        while k <= size:
            gd.line([(k, 0), (k, size)], fill=(0, 0, 0, 40))
            gd.line([(0, k), (size, k)], fill=(0, 0, 0, 40))
            k += step
    tile.alpha_composite(fr, ((size - fr.width) // 2, (size - fr.height) // 2))
    img.paste(tile.convert("RGB"), (x, y))
    d.text((x, y + size + 6), label, fill=TEXT, font=font(14, "sb"))
    w, h = Image.open(path).size
    d.text((x, y + size + 24), f"{w}×{h} · {n} frames", fill=MUTED, font=font(12))


def delivered_sheet(path):
    """A etapa 1 como esta no cliente: um quadro de cada arquivo (o do meio da
    animacao), na escala do arquivo, sobre um chao de grama com a grade."""
    size, gap, left = 190, 26, 34
    rows = []
    for tier, key, title, names in SHEET:
        if names is None:
            files = [(os.path.join(DELIVERED, t, "comum", "conjurar.png"), f"{t}/conjurar")
                     for t in ("pale", "ashen", "obsidian", "lord-of-death")]
        else:
            files = [(os.path.join(DELIVERED, tier, key, n + ".png"), n) for n in names]
        files = [(p, n) for p, n in files if os.path.exists(p)]
        if files:
            rows.append((title, files))
    W = left * 2 + 4 * (size + gap)
    H = 70 + len(rows) * (size + 90)
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((left, 22), "A sua etapa 1 no jogo (um quadro do meio de cada animação; a grade é 1 sqm)",
           fill=TEXT, font=font(19, "b"))
    for r, (title, files) in enumerate(rows):
        y = 64 + r * (size + 90)
        d.text((left, y), title, fill=TEXT, font=font(16, "b"))
        for c, (p, label) in enumerate(files[:4]):
            _cell(img, d, left + c * (size + gap), y + 24, size, p, label, 0.6)
    img.save(path, optimize=True)


def clock_strip(path):
    """O relogio da etapa 1 quadro a quadro: o jeito de marcar o tempo que as
    magias novas tambem usam."""
    strips = [
        ("Lágrimas de Pérola — marca", os.path.join(DELIVERED, "pale", "lagrimas", "marca.png")),
        ("Coroa Partida — marca", os.path.join(DELIVERED, "obsidian", "coroa", "marca.png")),
        ("Flor de Cinza — botão", os.path.join(DELIVERED, "ashen", "flor", "botao.png")),
    ]
    S, left = 170, 34
    strips = [(t, p) for t, p in strips if os.path.exists(p)]
    img = Image.new("RGB", (left * 2 + 6 * (S + 12), 40 + len(strips) * (S + 60)), BG)
    d = ImageDraw.Draw(img)
    for r, (title, p) in enumerate(strips):
        y = 20 + r * (S + 60)
        d.text((left, y), title + "  (0% → 100% do aviso)", fill=TEXT, font=font(16, "b"))
        for c, at in enumerate([0, 0.2, 0.4, 0.6, 0.8, 1.0]):
            fr, _ = _frame(p, at)
            fr.thumbnail((S - 10, S - 10))
            tile = Image.new("RGBA", (S, S), FLOOR + (255,))
            tile.alpha_composite(fr, ((S - fr.width) // 2, (S - fr.height) // 2))
            img.paste(tile.convert("RGB"), (left + c * (S + 12), y + 28))
    img.save(path, optimize=True)


def copy_delivered(dst):
    if os.path.isdir(DELIVERED):
        shutil.copytree(DELIVERED, dst)


palettes = v1refs.palettes
line_pieces = v1refs.line_pieces
test_floors = v1refs.test_floors
kit_sheet = v1refs.kit_sheet
