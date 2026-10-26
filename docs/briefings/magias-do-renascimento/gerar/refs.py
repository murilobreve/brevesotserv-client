# -*- coding: utf-8 -*-
# Imagens de referencia do briefing: paleta, kit atual do renascimento, a
# linguagem de aviso que ja existe no jogo, as pecas de linha e fundos de teste.
import os
import random
from pathlib import Path
from PIL import Image, ImageDraw

from spec import TIERS
from diagrams import font

# a pasta modules/ do cliente: CLIENT_MODULES, ou a do repositorio onde este
# gerador esta (docs/briefings/<briefing>/gerar/)
CLIENT = os.environ.get("CLIENT_MODULES") or str(Path(__file__).resolve().parents[4] / "modules")
REVIVE = CLIENT + "/game_raritybonus/images/revive/"
SKILL = CLIENT + "/game_skillshot/images/"
BG = (24, 23, 27)
TEXT = (232, 230, 226)
MUTED = (150, 148, 145)


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def palettes(path):
    W, row = 1100, 150
    img = Image.new("RGB", (W, 40 + row * len(TIERS)), BG)
    d = ImageDraw.Draw(img)
    for i, t in enumerate(TIERS):
        y = 30 + i * row
        d.text((30, y), f"{t['nome']} — {t['material']}", fill=TEXT, font=font(22, "b"))
        d.text((30, y + 32), f"Elemento: {t['elemento']}", fill=MUTED, font=font(15))
        x = 360
        for name, hx in t["paleta"]:
            d.rounded_rectangle((x, y, x + 120, y + 80), 8, fill=hexrgb(hx), outline=(80, 80, 86))
            d.text((x, y + 90), name, fill=TEXT, font=font(14, "sb"))
            d.text((x, y + 110), hx, fill=MUTED, font=font(13))
            x += 140
    img.save(path, optimize=True)


def kit_sheet(path):
    folders = ["pale", "ashen", "obsidian", "lord-of-death"]
    names = {"pale": "Pale — O Véu", "ashen": "Ashen — A Flor de Cinza", "obsidian": "Obsidian — A Coroa de Vidro", "lord-of-death": "Lord of Death — O Eclipse"}
    layers = [("chao", "chão"), ("ar", "ar"), ("eclosao", "eclosão"), ("aura", "aura")]
    S = 230
    left = 40
    img = Image.new("RGB", (left + S * 4 + 20, 60 + (S + 40) * 4), BG)
    d = ImageDraw.Draw(img)
    for c, (_, label) in enumerate(layers):
        d.text((left + c * S + S // 2, 30), label, fill=MUTED, font=font(16, "sb"), anchor="mm")
    for r, folder in enumerate(folders):
        y = 60 + r * (S + 40)
        d.text((left, y + 4), names[folder], fill=TEXT, font=font(17, "b"))
        for c, (layer, _) in enumerate(layers):
            im = Image.open(f"{REVIVE}{folder}/revive_{folder}_{layer}.png").convert("RGBA").resize((S - 14, S - 14))
            tile = Image.new("RGBA", (S - 14, S - 14), (62, 58, 52, 255))
            tile.alpha_composite(im)
            img.paste(tile.convert("RGB"), (left + c * S, y + 30))
    img.save(path, optimize=True)


def frames(path_png, picks):
    im = Image.open(path_png)
    n = getattr(im, "n_frames", 1)
    out = []
    for p in picks:
        im.seek(min(n - 1, int(p * (n - 1))))
        out.append(im.convert("RGBA").copy())
    return out


def clock_sheet(path):
    rows = [
        ("Meteoro — marca (o relógio: o arco fecha no impacto)", SKILL + "meteoro/marca.png"),
        ("Chuva de Juízo — círculo (mesma ideia)", SKILL + "juizo/circulo.png"),
        ("Meteoro — brasas (resíduo: sem relógio, só apaga)", SKILL + "meteoro/brasas_fortes.png"),
    ]
    S = 200
    img = Image.new("RGB", (40 + S * 5, 30 + len(rows) * (S + 50)), BG)
    d = ImageDraw.Draw(img)
    for r, (label, p) in enumerate(rows):
        y = 20 + r * (S + 50)
        d.text((40, y), label, fill=TEXT, font=font(17, "b"))
        for c, fr in enumerate(frames(p, [0, 0.25, 0.5, 0.75, 1.0])):
            tile = Image.new("RGBA", (S - 10, S - 10), (70, 80, 60, 255))
            fr.thumbnail((S - 20, S - 20))
            tile.alpha_composite(fr, ((tile.width - fr.width) // 2, (tile.height - fr.height) // 2))
            img.paste(tile.convert("RGB"), (40 + c * S, y + 34))
    img.save(path, optimize=True)


def line_pieces(path):
    """Como as pecas h / v / ne / nw emendam: cada uma ocupa o sqm inteiro e
    a linha entra e sai pelo meio das bordas (h, v) ou pelos cantos (ne, nw)."""
    T = 64
    img = Image.new("RGB", (1100, 640), BG)
    d = ImageDraw.Draw(img, "RGBA")
    d.text((40, 24), "Peças de linha (64×64 cada = 1 sqm): por onde a linha entra e sai", fill=TEXT, font=font(20, "b"))
    pieces = [("h", ((0, 0.5), (1, 0.5))), ("v", ((0.5, 0), (0.5, 1))), ("ne", ((0, 1), (1, 0))), ("nw", ((0, 0), (1, 1)))]
    for i, (name, (a, b)) in enumerate(pieces):
        x, y = 60 + i * 250, 90
        S = 160
        d.rectangle((x, y, x + S, y + S), fill=(46, 45, 50), outline=(110, 108, 115), width=2)
        d.line([(x + a[0] * S, y + a[1] * S), (x + b[0] * S, y + b[1] * S)], fill=(229, 244, 241), width=14)
        d.text((x + S // 2, y + S + 24), f"_{name}", fill=TEXT, font=font(20, "b"), anchor="mm")
    examples = [
        ("linha reta: h h h h", [(0, 0), (1, 0), (2, 0), (3, 0)], "h"),
        ("diagonal: ne ne ne", [(0, 2), (1, 1), (2, 0)], "ne"),
    ]
    ox = 60
    for label, cells, kind in examples:
        oy = 360
        d.text((ox, oy - 26), label, fill=MUTED, font=font(15, "sb"))
        for cx, cy in cells:
            x, y = ox + cx * T, oy + cy * T
            d.rectangle((x, y, x + T, y + T), fill=(46, 45, 50), outline=(110, 108, 115))
            if kind == "h":
                d.line([(x, y + T / 2), (x + T, y + T / 2)], fill=(229, 244, 241), width=8)
            else:
                d.line([(x, y + T), (x + T, y)], fill=(229, 244, 241), width=8)
        ox += 5 * T + 60
    d.text((40, 600), "A peça é desenhada para emendar na vizinha sem costura. As peças de linha seguem a mesma regra do Corte Sísmico (fenda_h / _v / _ne / _nw).", fill=MUTED, font=font(14))
    img.save(path, optimize=True)


def test_floors(outdir):
    """Fundos 7x7 sqm a 2x (448 px) com a grade, para testar o contraste."""
    floors = {
        "grama": ((62, 104, 44), 18), "terra": ((112, 84, 58), 16), "areia": ((214, 192, 138), 14),
        "neve": ((226, 234, 240), 10), "caverna": ((58, 52, 50), 12), "lava": ((190, 78, 26), 30),
        "pedra_clara": ((150, 146, 140), 14), "pantano": ((52, 70, 50), 16),
    }
    rnd = random.Random(7)
    for name, (base, var) in floors.items():
        img = Image.new("RGB", (448, 448), base)
        px = img.load()
        for y in range(0, 448, 4):
            for x in range(0, 448, 4):
                k = rnd.randint(-var, var)
                c = tuple(max(0, min(255, v + k)) for v in base)
                for yy in range(4):
                    for xx in range(4):
                        px[x + xx, y + yy] = c
        d = ImageDraw.Draw(img, "RGBA")
        for i in range(8):
            d.line([(i * 64, 0), (i * 64, 448)], fill=(0, 0, 0, 40))
            d.line([(0, i * 64), (448, i * 64)], fill=(0, 0, 0, 40))
        img.save(f"{outdir}/{name}.png", optimize=True)
    return list(floors)
