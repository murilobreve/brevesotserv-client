# -*- coding: utf-8 -*-
# Diagramas em grade de cada magia: sqm de perigo, sqm seguros, monstro,
# jogador, a esquiva e a linha do tempo.
import math
from PIL import Image, ImageDraw, ImageFont

from spec import tier_of

FONT = "/usr/share/fonts/opentype/inter/Inter-Regular.otf"
FONT_B = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
FONT_SB = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"


def font(size, weight="r"):
    try:
        return ImageFont.truetype({"r": FONT, "b": FONT_B, "sb": FONT_SB}[weight], size)
    except OSError:
        # sem a Inter instalada (Windows): a fonte padrao do Pillow
        return ImageFont.load_default(size)


TILE = 40
BG = (24, 23, 27)
FLOOR_A = (46, 45, 50)
FLOOR_B = (51, 50, 55)
GRID = (64, 63, 70)
TEXT = (232, 230, 226)
MUTED = (150, 148, 145)
SAFE = (120, 220, 150)
DODGE = (255, 210, 100)


def circle(cx, cy, r, inner=None):
    out = set()
    R = int(math.ceil(r))
    for dy in range(-R, R + 1):
        for dx in range(-R, R + 1):
            d2 = dx * dx + dy * dy
            if d2 <= r * r and (inner is None or d2 > inner * inner):
                out.add((cx + dx, cy + dy))
    return out


def line(x, y, sx, sy, n, start=1):
    return [(x + i * sx, y + i * sy) for i in range(start, n + 1)]


class Panel:
    def __init__(self, w, h, title=None):
        self.w, self.h, self.title = w, h, title
        self.layers = []  # (kind, tiles, extra)
        self.marks = []   # (kind, (x, y), label)
        self.arrows = []  # (points, color, dashed)
        self.notes = []   # (x, y, text)

    def danger(self, tiles, label=None, strength=1.0):
        self.layers.append(("danger", set(tiles), {"label": label, "s": strength}))

    def danger2(self, tiles, label=None):
        self.layers.append(("danger2", set(tiles), {"label": label}))

    def residue(self, tiles, label=None):
        self.layers.append(("residue", set(tiles), {"label": label}))

    def threat(self, tiles, label=None):
        self.layers.append(("threat", set(tiles), {"label": label}))

    def spent(self, tiles):
        self.layers.append(("spent", set(tiles), {}))

    def safe(self, tiles):
        self.layers.append(("safe", set(tiles), {}))

    def monster(self, x, y):
        self.marks.append(("M", (x, y), "M"))

    def player(self, x, y, label="J"):
        self.marks.append(("J", (x, y), label))

    def ghost(self, x, y, label=""):
        self.marks.append(("ghost", (x, y), label))

    def special(self, kind, x, y, label=""):
        self.marks.append((kind, (x, y), label))

    def arrow(self, pts, color=DODGE, dashed=False):
        self.arrows.append((pts, color, dashed))

    def note(self, x, y, text):
        self.notes.append((x, y, text))


def tile_rect(ox, oy, x, y):
    return (ox + x * TILE, oy + y * TILE, ox + (x + 1) * TILE, oy + (y + 1) * TILE)


def tile_center(ox, oy, x, y):
    return (ox + x * TILE + TILE / 2, oy + y * TILE + TILE / 2)


def hatch(draw, rect, color, step=8, width=2):
    x0, y0, x1, y1 = rect
    for k in range(-TILE, TILE, step):
        a = (x0 + k, y1)
        b = (x0 + k + TILE, y0)
        # clip to rect
        pts = []
        for t in [i / 20 for i in range(21)]:
            px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            if x0 <= px <= x1 and y0 <= py <= y1:
                pts.append((px, py))
        if len(pts) >= 2:
            draw.line([pts[0], pts[-1]], fill=color, width=width)


def dashed_line(draw, a, b, color, width=3, dash=8, gap=6):
    length = math.dist(a, b)
    if length == 0:
        return
    dx, dy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    pos = 0
    while pos < length:
        end = min(pos + dash, length)
        draw.line([(a[0] + dx * pos, a[1] + dy * pos), (a[0] + dx * end, a[1] + dy * end)], fill=color, width=width)
        pos = end + gap


def draw_arrow(draw, pts, color, dashed, ox, oy):
    centers = [tile_center(ox, oy, *p) for p in pts]
    for a, b in zip(centers, centers[1:]):
        if dashed:
            dashed_line(draw, a, b, color, 4)
        else:
            draw.line([a, b], fill=color, width=4)
    a, b = centers[-2], centers[-1]
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    size = 13
    tip = (b[0] - math.cos(ang) * 6, b[1] - math.sin(ang) * 6)
    left = (tip[0] - size * math.cos(ang - 0.45), tip[1] - size * math.sin(ang - 0.45))
    right = (tip[0] - size * math.cos(ang + 0.45), tip[1] - size * math.sin(ang + 0.45))
    draw.polygon([tip, left, right], fill=color)


def render_panel(img, panel, ox, oy, tier):
    draw = ImageDraw.Draw(img, "RGBA")
    col = tier["cor"]
    light = tier["luz"]
    for y in range(panel.h):
        for x in range(panel.w):
            draw.rectangle(tile_rect(ox, oy, x, y), fill=FLOOR_A if (x + y) % 2 == 0 else FLOOR_B)
    inside = lambda t: 0 <= t[0] < panel.w and 0 <= t[1] < panel.h
    for kind, tiles, extra in panel.layers:
        for t in filter(inside, tiles):
            r = tile_rect(ox, oy, *t)
            if kind == "danger":
                a = int(170 * extra["s"])
                draw.rectangle(r, fill=col + (a,))
                hatch(draw, r, light + (110,), 9, 2)
            elif kind == "danger2":
                draw.rectangle(r, fill=col + (70,))
                hatch(draw, r, light + (70,), 6, 1)
            elif kind == "residue":
                draw.rectangle(r, fill=(col[0] // 2, col[1] // 2, col[2] // 2, 150))
                for i in range(3):
                    for j in range(3):
                        cx, cy = r[0] + 8 + i * 12, r[1] + 8 + j * 12
                        draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=light + (150,))
            elif kind == "spent":
                draw.rectangle(r, fill=(70, 68, 74, 255))
                draw.line([(r[0] + 10, r[1] + 12), (r[0] + 18, r[1] + 26)], fill=(120, 118, 125), width=2)
                draw.line([(r[0] + 24, r[1] + 10), (r[0] + 30, r[1] + 22)], fill=(120, 118, 125), width=2)
            elif kind == "threat":
                draw.rectangle(r, fill=col + (40,))
                c = tile_center(ox, oy, *t)
                draw.ellipse((c[0] - 3, c[1] - 3, c[0] + 3, c[1] + 3), fill=light + (200,))
            elif kind == "safe":
                draw.rectangle((r[0] + 2, r[1] + 2, r[2] - 3, r[3] - 3), outline=SAFE + (255,), width=3)
    for y in range(panel.h + 1):
        draw.line([(ox, oy + y * TILE), (ox + panel.w * TILE, oy + y * TILE)], fill=GRID, width=1)
    for x in range(panel.w + 1):
        draw.line([(ox + x * TILE, oy), (ox + x * TILE, oy + panel.h * TILE)], fill=GRID, width=1)
    for pts, color, dashed in panel.arrows:
        draw_arrow(draw, pts, color, dashed, ox, oy)
    f = font(17, "b")
    for kind, t, label in panel.marks:
        cx, cy = tile_center(ox, oy, *t)
        if kind == "M":
            draw.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=light, outline=tier["sombra"], width=3)
            draw.text((cx, cy), "M", fill=tier["sombra"], font=f, anchor="mm")
        elif kind == "J":
            draw.ellipse((cx - 15, cy - 15, cx + 15, cy + 15), fill=(250, 250, 250), outline=(20, 20, 20), width=3)
            draw.text((cx, cy), label, fill=(20, 20, 20), font=font(14 if len(label) > 1 else 17, "b"), anchor="mm")
        elif kind == "ghost":
            draw.ellipse((cx - 14, cy - 14, cx + 14, cy + 14), outline=(250, 250, 250, 160), width=2)
            if label:
                draw.text((cx, cy), label, fill=(250, 250, 250, 160), font=font(13, "sb"), anchor="mm")
        elif kind == "statue":
            draw.polygon([(cx, cy - 17), (cx + 11, cy), (cx, cy + 17), (cx - 11, cy)], fill=light, outline=tier["sombra"])
        elif kind == "refuge":
            draw.rectangle((cx - 15, cy - 15, cx + 15, cy + 15), fill=(207, 224, 238, 230), outline=(255, 255, 255), width=2)
            draw.text((cx, cy), "R", fill=(30, 30, 40), font=f, anchor="mm")
        elif kind == "sun":
            draw.ellipse((cx - 15, cy - 15, cx + 15, cy + 15), fill=(10, 8, 12), outline=light, width=4)
        elif kind == "ghostsun":
            draw.ellipse((cx - 12, cy - 12, cx + 12, cy + 12), outline=light + (130,), width=2)
        elif kind == "x":
            draw.line([(cx - 9, cy - 9), (cx + 9, cy + 9)], fill=(255, 255, 255, 200), width=3)
            draw.line([(cx - 9, cy + 9), (cx + 9, cy - 9)], fill=(255, 255, 255, 200), width=3)
        elif kind == "num":
            draw.text((cx, cy), label, fill=(255, 255, 255), font=font(15, "b"), anchor="mm", stroke_width=3, stroke_fill=(0, 0, 0))
    fn = font(13, "sb")
    for x, y, text in panel.notes:
        cx, cy = tile_center(ox, oy, x, y)
        draw.text((cx, cy), text, fill=(255, 255, 255), font=fn, anchor="mm", stroke_width=3, stroke_fill=(0, 0, 0))


TL_COLORS = {
    "aviso": 1.0, "mira": 0.55, "fase": 1.0, "selo": 1.0, "tentáculos": 0.7, "círculo": 1.0, "surge": 0.5,
}


def render_timeline(img, timeline, ox, oy, width, tier):
    draw = ImageDraw.Draw(img, "RGBA")
    total = sum(ms for _, ms in timeline)
    x = ox
    f = font(13, "sb")
    fs = font(12)
    draw.text((ox, oy - 6), "Linha do tempo", fill=MUTED, font=font(13, "b"), anchor="ls")
    for label, ms in timeline:
        w = max(40, width * ms / total)
        lower = label.lower()
        if lower.startswith(("aviso", "fase", "selo", "círculo", "mira", "tentáculos", "pulso", "travada", "estátua racha")):
            fill = tier["cor"] + (210,)
        elif any(k in lower for k in ("brasa", "geada", "frio", "chão")):
            fill = (tier["cor"][0] // 2, tier["cor"][1] // 2, tier["cor"][2] // 2, 200)
        else:
            fill = tier["luz"] + (235,)
        draw.rectangle((x, oy + 4, x + w - 3, oy + 34), fill=fill)
        tc = (20, 20, 20) if sum(fill[:3]) > 380 else (245, 245, 245)
        txt = label
        while draw.textlength(txt, font=f) > w - 10 and len(txt) > 4:
            txt = txt[:-2] + "…" if not txt.endswith("…") else txt[:-2] + "…"
        draw.text((x + 6, oy + 19), txt, fill=tc, font=f, anchor="lm")
        draw.text((x + 2, oy + 40), f"{ms/1000:.1f} s".replace(".", ","), fill=MUTED, font=fs, anchor="lt")
        x += w


LEGEND = [
    ("danger", "perigo (o golpe)"),
    ("danger2", "perigo da 2ª parte"),
    ("residue", "resíduo no chão (dano/efeito ao pisar)"),
    ("spent", "já explodiu = seguro"),
    ("threat", "ameaça ainda não decidida"),
    ("safe", "sqm seguro"),
    ("dodge", "esquiva"),
]


def render_legend(img, kinds, ox, oy, tier):
    draw = ImageDraw.Draw(img, "RGBA")
    f = font(13)
    x = ox
    col, light = tier["cor"], tier["luz"]
    for kind, label in LEGEND:
        if kind not in kinds:
            continue
        r = (x, oy, x + 20, oy + 20)
        if kind == "danger":
            draw.rectangle(r, fill=col + (170,))
        elif kind == "danger2":
            draw.rectangle(r, fill=col + (70,))
        elif kind == "residue":
            draw.rectangle(r, fill=(col[0] // 2, col[1] // 2, col[2] // 2, 150))
            draw.ellipse((x + 8, oy + 8, x + 12, oy + 12), fill=light)
        elif kind == "spent":
            draw.rectangle(r, fill=(70, 68, 74))
        elif kind == "threat":
            draw.rectangle(r, fill=col + (40,))
            draw.ellipse((x + 7, oy + 7, x + 13, oy + 13), fill=light)
        elif kind == "safe":
            draw.rectangle(r, outline=SAFE, width=3)
        elif kind == "dodge":
            draw.line([(x, oy + 10), (x + 20, oy + 10)], fill=DODGE, width=4)
        draw.text((x + 27, oy + 10), label, fill=TEXT, font=f, anchor="lm")
        x += 27 + draw.textlength(label, font=f) + 22


def diagram(spell, panels, path):
    tier = tier_of(spell["tier"])
    pad = 28
    gap = 34
    title_h = 74
    panel_w = sum(p.w * TILE for p in panels) + gap * (len(panels) - 1)
    panel_h = max(p.h * TILE for p in panels) + (26 if any(p.title for p in panels) else 0)
    W = max(panel_w + pad * 2, 900)
    H = title_h + panel_h + 150
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img, "RGBA")
    draw.rectangle((0, 0, W, 6), fill=tier["cor"])
    draw.text((pad, 24), f"{tier['nome'].upper()} · {spell['nome']}", fill=TEXT, font=font(26, "b"), anchor="lt")
    draw.text((pad, 56), spell["tipo"], fill=MUTED, font=font(15), anchor="lt")
    kinds = {"dodge"}
    x = (W - panel_w) // 2
    y0 = title_h + (26 if any(p.title for p in panels) else 0)
    for p in panels:
        if p.title:
            draw.text((x, y0 - 10), p.title, fill=TEXT, font=font(15, "b"), anchor="ls")
        render_panel(img, p, x, y0, tier)
        kinds |= {k for k, _, _ in p.layers}
        x += p.w * TILE + gap
    render_legend(img, kinds, pad, title_h + panel_h + 18, tier)
    render_timeline(img, spell["timeline"], pad, title_h + panel_h + 76, W - pad * 2, tier)
    img.convert("RGB").save(path, optimize=True)


# ---------------------------------------------------------------- the 13 spells

def build_all(spells_by_key, outdir):
    out = {}

    def go(key, panels):
        s = spells_by_key[key]
        p = f"{outdir}/{s['tier']}_{key}.png".replace("deathlord", "lord-of-death")
        diagram(s, panels, p)
        out[key] = p

    # Pluma do Veu
    p = Panel(12, 9)
    p.monster(2, 4)
    p.danger(line(2, 4, 1, 0, 7))
    p.player(7, 4)
    p.safe([(7, 3)])
    p.arrow([(7, 4), (7, 3)])
    p.note(9, 6, "7 sqm, 1 de largura")
    go("pluma", [p])

    # Lagrimas de Perola
    p = Panel(12, 9)
    p.monster(1, 4)
    marks = [(7, 4), (5, 3), (8, 6), (9, 3), (6, 6)]
    p.danger(marks)
    for i, t in enumerate(marks):
        p.special("num", t[0], t[1], str(i + 1))
    p.player(7, 4)
    p.safe([(7, 3)])
    p.arrow([(7, 4), (7, 3)])
    p.note(7, 8, "1 marca no jogador + 4 a até 2 sqm dele (ordem 1→5)")
    q = Panel(12, 9, "Depois: geada 2,5 s")
    q.monster(1, 4)
    q.residue(marks)
    q.player(7, 3)
    go("lagrimas", [p, q])

    # Veu que se Fecha
    p = Panel(11, 11)
    ring = circle(5, 5, 3.5, inner=1.5)
    p.danger(ring)
    p.safe(circle(5, 5, 1.5) - {(5, 5)})
    p.monster(5, 5)
    p.player(7, 5, "J1")
    p.arrow([(7, 5), (6, 5)])
    p.player(2, 4, "J2")
    p.arrow([(2, 4), (1, 4)])
    p.safe([(1, 4)])
    p.note(5, 10, "perigo: 2 e 3 sqm do monstro")
    go("veu", [p])

    # Brasa Rastejante
    p = Panel(12, 11)
    p.monster(2, 5)
    lines = line(2, 5, 1, 0, 6) + line(2, 5, 1, -1, 5) + line(2, 5, 1, 1, 5)
    p.danger(lines)
    p.player(6, 5)
    p.safe([(6, 4)])
    p.arrow([(6, 5), (6, 4)])
    q = Panel(12, 11, "Depois: brasa 3 s")
    q.monster(2, 5)
    q.residue(lines)
    q.player(6, 4)
    go("brasa", [p, q])

    # Flor de Cinza
    p = Panel(13, 13)
    c = (6, 6)
    bud = {(c[0] + dx, c[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    petals = []
    for sx, sy in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]:
        petals += line(c[0], c[1], sx, sy, 5, start=2)
    p.danger(bud)
    p.danger2(petals)
    p.monster(1, 11)
    p.player(6, 6)
    p.safe([(8, 5), (4, 7), (7, 4), (5, 8)])
    p.arrow([(6, 6), (7, 5), (8, 5)])
    p.note(6, 12, "trilhas aparecem junto com o botão")
    go("flor", [p])

    # Investida Incandescente
    p = Panel(12, 9)
    p.monster(1, 4)
    path = line(1, 4, 1, 0, 6)
    p.danger(path)
    p.player(5, 4)
    p.safe([(5, 3)])
    p.arrow([(5, 4), (5, 3)])
    p.note(7, 6, "o monstro para aqui")
    p.special("x", 7, 4)
    q = Panel(12, 9, "Depois: monstro no fim, brasa 3 s")
    q.residue(line(1, 4, 1, 0, 5) + [(1, 4)])
    q.monster(7, 4)
    q.player(5, 3)
    go("investida", [p, q])

    # Feixe Refratado
    p = Panel(12, 9, "1) Mira segue (1,0 s)")
    p.monster(1, 4)
    p.threat(line(1, 4, 1, 0, 8))
    p.ghost(6, 4, "")
    p.threat(line(1, 4, 1, -1, 4))
    p.player(5, 0)
    p.arrow([(6, 4), (6, 3), (5, 2), (5, 1), (5, 0)], color=(200, 200, 200), dashed=True)
    p.note(8, 7, "a linha troca de direção com o jogador")
    q = Panel(12, 9, "2) Travou: 0,7 s para sair")
    q.monster(1, 4)
    q.danger(line(1, 4, 1, 0, 8))
    q.player(6, 4)
    q.safe([(6, 3)])
    q.arrow([(6, 4), (6, 3)])
    go("feixe", [p, q])

    # Coroa Partida
    area = circle(5, 5, 3.5) - {(5, 5)}
    a = {t for t in area if (t[0] + t[1]) % 2 == 0}
    b = area - a
    p = Panel(11, 11, "Fase 1 (1,4 s)")
    p.danger(a)
    p.danger2(b)
    p.monster(5, 5)
    p.player(7, 5)
    p.arrow([(7, 5), (7, 4)])
    p.safe([(7, 4)])
    q = Panel(11, 11, "Fase 2 (1,0 s)")
    q.spent(a)
    q.danger(b)
    q.monster(5, 5)
    q.player(7, 4)
    q.arrow([(7, 4), (7, 5)])
    q.safe([(7, 5)])
    go("coroa", [p, q])

    # Reflexos
    p = Panel(13, 11)
    statues = [(5, 3), (7, 6)]
    cross = set()
    for sx, sy in statues:
        cross.add((sx, sy))
        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            cross |= set(line(sx, sy, dx, dy, 4))
    p.danger(cross)
    for s in statues:
        p.special("statue", *s)
    p.monster(1, 9)
    p.player(5, 5)
    p.safe([(6, 4), (4, 5)])
    p.arrow([(5, 5), (6, 4)])
    p.note(10, 9, "diagonais = seguras")
    go("reflexos", [p])

    # Garra do Eclipse
    p = Panel(11, 9)
    m = (3, 4)
    cone = [(4, 4), (5, 3), (5, 4), (5, 5), (6, 2), (6, 3), (6, 4), (6, 5), (6, 6)]
    p.danger(cone)
    p.monster(*m)
    p.player(5, 4)
    p.safe([(4, 3), (4, 5), (2, 4)])
    p.arrow([(5, 4), (4, 3)])
    p.note(8, 8, "larguras 1 · 3 · 5")
    go("garra", [p])

    # Sol Negro
    p = Panel(12, 9)
    sun = (4, 4)
    p.danger({(sun[0] + dx, sun[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)})
    p.special("ghostsun", 2, 4)
    p.special("ghostsun", 3, 4)
    p.special("sun", *sun)
    p.player(5, 4)
    p.arrow([(5, 4), (6, 4), (7, 4), (8, 4)])
    p.arrow([(4, 4), (5, 4)], color=tier_of("deathlord")["luz"], dashed=True)
    p.monster(1, 8)
    p.note(6, 7, "o sol anda 1 sqm a cada 0,6 s")
    go("sol", [p])

    # Colapso
    p = Panel(11, 11, "1) Tentáculos (1,0 s) e puxão")
    p.monster(5, 5)
    p.threat(line(5, 5, 1, 0, 3) + line(5, 5, 0, -1, 3))
    p.player(9, 5, "J1")
    p.player(5, 1, "J2")
    p.arrow([(9, 5), (8, 5), (7, 5)], color=tier_of("deathlord")["luz"], dashed=True)
    p.arrow([(5, 1), (5, 2), (5, 3)], color=tier_of("deathlord")["luz"], dashed=True)
    q = Panel(11, 11, "2) Círculo (1,4 s)")
    q.danger(circle(5, 5, 2.5) - {(5, 5)})
    q.monster(5, 5)
    q.player(7, 5, "J1")
    q.player(5, 3, "J2")
    q.arrow([(7, 5), (8, 5)])
    q.arrow([(5, 3), (5, 2)])
    q.safe([(8, 5), (5, 2)])
    go("colapso", [p, q])

    # Eclipse Total
    p = Panel(15, 15)
    seal = circle(7, 7, 5.5)
    refuges = [(7, 3), (10, 9), (4, 9)]
    p.danger(set(seal) - set(refuges) - {(7, 7)})
    p.monster(7, 7)
    for r in refuges:
        p.special("refuge", *r)
    p.player(9, 5)
    p.arrow([(9, 5), (8, 4), (7, 3)])
    p.player(11, 6, "J2")
    p.arrow([(11, 6), (12, 5), (13, 4)])
    p.safe([(13, 4)])
    p.note(7, 14, "3 refúgios a 3–5 sqm · fora do selo também é seguro")
    go("eclipse", [p])
    return out
