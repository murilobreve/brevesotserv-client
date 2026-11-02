# -*- coding: utf-8 -*-
# Diagramas em grade das magias da parte 2, com o motor da parte 1
# (Panel, circle, line, diagram em ../magias-do-renascimento/gerar/diagrams.py).
import math

import spec2  # noqa: F401  (poe a pasta da parte 1 no sys.path)
from diagrams import Panel, circle, line, diagram  # parte 1
from spec import tier_of  # parte 1: as cores dos tiers


def bresenham(a, b):
    """Os sqm de a ate b pela grade (sem as pontas)."""
    (x0, y0), (x1, y1) = a, b
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err, out = dx + dy, []
    while (x0, y0) != (x1, y1):
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy
        out.append((x0, y0))
    return out[:-1]


def square(cx, cy, r):
    return {(cx + dx, cy + dy) for dx in range(-r, r + 1) for dy in range(-r, r + 1)}


def slice_of(cx, cy, t):
    """Fatia (0 = leste, 2 = sul, 4 = oeste, 6 = norte) de um sqm em volta do monstro."""
    ang = math.degrees(math.atan2(t[1] - cy, t[0] - cx)) % 360
    return int(round(ang / 45)) % 8


def build_all(spells_by_key, outdir):
    out = {}
    light = {k: tier_of(k)["luz"] for k in ("pale", "ashen", "obsidian", "deathlord")}

    def go(key, panels):
        s = spells_by_key[key]
        p = f"{outdir}/{s['tier']}_{key}.png".replace("deathlord", "lord-of-death")
        diagram(s, panels, p)
        out[key] = p

    # ------------------------------------------------------------ Mare de Bruma
    p = Panel(13, 11)
    p.monster(6, 0)
    band = {(x, y) for x in range(2, 11) for y in range(1, 9)}
    lane = {(x, y) for x in (8, 9) for y in range(1, 9)}
    p.danger(band - lane)
    p.safe(lane)
    p.player(6, 5)
    p.arrow([(6, 5), (7, 5), (8, 5)])
    p.arrow([(11, 1), (11, 4), (11, 8)], color=light["pale"], dashed=True)
    p.note(6, 10, "fresta: 2 sqm, a 1–3 sqm de lado do jogador")
    p.note(11, 9, "a onda")
    go("mare", [p])

    # ------------------------------------------------------------ Sopro do Veu
    p = Panel(13, 13)
    m = (6, 6)
    area = circle(*m, 4.5) - {m}
    pillars = [((1, 0), (8, 6)), ((-1, 1), (4, 8)), ((0, -1), (6, 4))]
    shadows = set()
    for (dx, dy), (px, py) in pillars:
        shadows |= {(px, py), (px + dx, py + dy), (px + 2 * dx, py + 2 * dy)}
    p.danger(area - shadows)
    p.safe(shadows)
    for _, t in pillars:
        p.special("statue", *t)
    p.monster(*m)
    p.player(9, 4)
    p.arrow([(9, 4), (9, 5), (9, 6)])
    p.note(6, 12, "sombra = a coluna + 2 sqm atrás dela")
    go("sopro", [p])

    # ------------------------------------------------------------ Ciranda de Brasa
    m = (6, 6)
    area = circle(*m, 4.5) - {m}
    start = 6  # norte; sentido horario = fatia + 1
    order = [(start + i) % 8 for i in range(8)]
    p = Panel(13, 13, "Aviso: começa no norte e gira no sentido horário")
    first = {t for t in area if slice_of(*m, t) == start}
    p.danger(first)
    p.danger2(area - first)
    for n, k in enumerate(order, 1):
        a = math.radians(k * 45)
        tx, ty = round(m[0] + 3 * math.cos(a)), round(m[1] + 3 * math.sin(a))
        p.special("num", tx, ty, str(n))
    p.monster(*m)
    p.player(10, 6, "J1")
    p.arrow([(10, 6), (11, 6)])
    p.player(4, 3, "J2")
    p.arrow([(4, 3), (5, 2)], color=(255, 210, 100), dashed=True)
    p.note(6, 12, "1 fatia a cada 250 ms")
    q = Panel(13, 13, "Depois: a borda em brasa 3 s")
    q.residue(circle(*m, 4.5) - circle(*m, 3.5))
    q.monster(*m)
    q.player(11, 6, "J1")
    q.player(5, 2, "J2")
    q.note(6, 12, "J2 entrou na fatia que já queimou")
    go("ciranda", [p, q])

    # ------------------------------------------------------------ Pavio de Cobre
    m = (1, 5)
    charges = [(8, 5), (10, 3), (6, 7)]
    by_len = sorted(charges, key=lambda c: max(abs(c[0] - m[0]), abs(c[1] - m[1])))
    blast = set()
    for c in charges:
        blast |= square(*c, 1)
    p = Panel(13, 11, "Aviso: as faíscas correm os pavios")
    p.danger(blast)
    fuse = set()
    for c in charges:
        fuse |= set(bresenham(m, c))
    p.threat(fuse - blast)
    p.monster(*m)
    for n, c in enumerate(by_len, 1):
        if c != (8, 5):
            p.special("block", *c, str(n))
    p.player(8, 5)
    p.safe([(8, 3)])
    p.arrow([(8, 5), (8, 4), (8, 3)])
    p.note(8, 9, "a carga 2 caiu no jogador; a 1 estoura primeiro")
    q = Panel(13, 11, "Depois: brasa 3 s nos 3×3")
    q.residue(blast)
    q.monster(*m)
    q.player(8, 3)
    go("pavio", [p, q])

    # ------------------------------------------------------------ Persiana de Vidro
    c = (5, 5)
    area = square(*c, 4)
    rows = {t for t in area if (t[1] - c[1]) % 2 == 0}
    cols = {t for t in area if (t[0] - c[0]) % 2 == 0}
    p = Panel(11, 11, "Fase 1: as fileiras (3,0 s)")
    p.danger(rows)
    p.danger2(cols - rows)
    p.monster(10, 10)
    p.player(*c)
    p.safe([(4, 4), (6, 4), (4, 6), (6, 6)])
    p.arrow([c, (6, 4)])
    q = Panel(11, 11, "Fase 2: as colunas (2,0 s)")
    q.spent(rows - cols)
    q.danger(cols)
    q.monster(10, 10)
    q.player(6, 4)
    q.note(5, 10, "fileira ímpar + coluna ímpar = seguro nas duas")
    go("persiana", [p, q])

    # ------------------------------------------------------------ Redoma de Vidro
    c = (5, 5)
    dome = square(*c, 2)
    door = (7, 5)
    p = Panel(11, 11, "Aviso: a paliçada cresce (3,0 s)")
    p.danger(dome)
    p.monster(1, 9)
    p.special("stop", *door, "porta")
    p.player(*c)
    p.safe([(8, 5)])
    p.arrow([c, (6, 5), (7, 5), (8, 5)])
    p.note(5, 9, "atravessar fora da porta corta")
    q = Panel(11, 11, "Fecha: o 5×5 inteiro estilhaça")
    q.danger(dome)
    q.monster(1, 9)
    q.player(8, 5)
    go("redoma", [p, q])

    # ------------------------------------------------------------ Dobre de Finados
    m = (6, 6)
    radii = [0.5, 1.5, 2.5, 3.5, 4.5, 5.5]
    rings = [circle(*m, radii[i + 1]) - circle(*m, radii[i]) - {m} for i in range(5)]
    odd = rings[0] | rings[2] | rings[4]
    even = rings[1] | rings[3]
    p = Panel(13, 13, "1ª e 3ª badalada: anéis 1, 3 e 5")
    p.danger(odd)
    p.danger2(even)
    p.monster(*m)
    p.player(9, 6)
    p.safe([(10, 6)])
    p.arrow([(9, 6), (10, 6)])
    q = Panel(13, 13, "2ª badalada: anéis 2 e 4")
    q.danger(even)
    q.danger2(odd)
    q.monster(*m)
    q.player(10, 6)
    q.safe([(9, 6)])
    q.arrow([(10, 6), (9, 6)])
    q.note(6, 12, "cada badalada mais rápida")
    go("dobre", [p, q])

    # ------------------------------------------------------------ Pesagem das Almas
    m = (6, 6)
    area = circle(*m, 5.5) - {m}
    fiel = {t for t in area if t[0] == m[0]}
    left = {t for t in area if t[0] < m[0]}
    right = {t for t in area if t[0] > m[0]}
    p = Panel(13, 13, "Fase 1: a metade do jogador (3,0 s)")
    p.danger(left)
    p.danger2(right)
    p.safe(fiel)
    p.monster(*m)
    p.player(3, 7)
    p.arrow([(3, 7), (4, 7), (5, 7), (6, 7)])
    p.note(6, 12, "o fiel é seguro nas duas fases")
    q = Panel(13, 13, "Fase 2: a outra metade (2,0 s)")
    q.spent(left)
    q.danger(right)
    q.safe(fiel)
    q.monster(*m)
    q.player(6, 7)
    go("pesagem", [p, q])

    return out
