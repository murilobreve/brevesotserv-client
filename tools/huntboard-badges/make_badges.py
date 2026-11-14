# Draws data/images/game/huntboard/boost_badges.png: the badges the client
# puts above a boosted monster's name (Creature::drawBoostBadges).
# 12x12 cells; rows: loot tier 1-3 (coins), rare monsters tier 1-3 (crystals),
# experience tier 1-3 (a star: pale at 2x, orange at 3x, red with a hot core
# from 4x); 6 frames a row: 0 at rest, 1-5 a glint crossing the badge (drawn
# for every tier, used by the third).
#   python3 tools/huntboard-badges/make_badges.py [out.png]
import math
import sys
from PIL import Image

S = 12
FRAMES = 6
OUT = sys.argv[1] if len(sys.argv) > 1 else 'data/images/game/huntboard/boost_badges.png'

GOLD = {'o': (56, 36, 8), 'h': (255, 240, 170), 'm': (240, 196, 82), 's': (188, 132, 36)}
CYAN = {'o': (8, 38, 58), 'h': (222, 251, 255), 'm': (112, 216, 255), 's': (44, 132, 186)}
# the star of each experience tier; 'c' is the core of the third
XP = (
    {'o': (52, 44, 20), 'h': (255, 255, 240), 'm': (250, 238, 170), 's': (206, 178, 96)},
    {'o': (66, 28, 4), 'h': (255, 226, 150), 'm': (255, 160, 52), 's': (212, 100, 20)},
    {'o': (70, 6, 6), 'h': (255, 170, 130), 'm': (240, 62, 46), 's': (168, 22, 26), 'c': (255, 232, 140)},
)


def star(px, cx, cy, outer, inner, pal):
    """A five-pointed star, lit from the top left."""
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = outer if i % 2 == 0 else inner
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))

    def inside(x, y):
        hit = False
        for i in range(10):
            (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % 10]
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                hit = not hit
        return hit

    for y in range(S):
        for x in range(S):
            n = sum(inside(x + ox, y + oy) for ox in (0.2, 0.5, 0.8) for oy in (0.2, 0.5, 0.8))
            if n >= 4:
                k = (x + 0.5 - cx) + (y + 0.5 - cy)
                c = pal['h'] if k <= -outer * 0.45 else pal['s'] if k >= outer * 0.5 else pal['m']
                if 'c' in pal and (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= 2.3:
                    c = pal['c']
                px[x, y] = c + (255,)


def coin(px, cx, cy, r, pal):
    """A coin: lit from the top left, a darker rim below, a mark in the middle."""
    for y in range(S):
        for x in range(S):
            dx, dy = x - cx, y - cy
            d2 = dx * dx + dy * dy
            if d2 <= (r + 1) ** 2 + 0.6 and d2 > r * r + 0.6:
                px[x, y] = pal['o'] + (255,)
            elif d2 <= r * r + 0.6:
                k = dx + dy
                px[x, y] = (pal['h'] if k <= -r * 0.7 else pal['s'] if k >= r * 0.7 else pal['m']) + (255,)
    px[int(cx), int(cy)] = pal['s'] + (255,)
    px[int(cx), int(cy) - 1] = pal['s'] + (255,)


def shard(px, cx, top, bottom, half, pal):
    """A crystal: a tall rhombus, its left facet in the light."""
    mid = (top + bottom) / 2.0
    for y in range(top, bottom + 1):
        w = half * (1 - abs(y - mid) / (mid - top + 0.5))
        w = max(0.0, w)
        for x in range(S):
            dx = x - cx
            if abs(dx) <= w + 0.2:
                if dx < -w * 0.25:
                    c = pal['h'] if y < mid else pal['m']
                elif dx > w * 0.35:
                    c = pal['s']
                else:
                    c = pal['m'] if y < mid + 1 else pal['s']
                px[x, y] = c + (255,)


def outline(im, pal):
    px = im.load()
    edge = []
    for y in range(S):
        for x in range(S):
            if px[x, y][3] == 0:
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < S and 0 <= ny < S and px[nx, ny][3] and px[nx, ny][:3] != pal['o']:
                        edge.append((x, y))
                        break
    for x, y in edge:
        px[x, y] = pal['o'] + (255,)


def sparkle(px, x, y, big):
    px[x, y] = (255, 255, 255, 255)
    if big:
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < S and 0 <= ny < S:
                px[nx, ny] = (255, 255, 255, 230)


def base(kind, tier):
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    px = im.load()
    if kind == 'loot':
        if tier == 1:
            coin(px, 5.5, 6.5, 3, GOLD)
        elif tier == 2:
            coin(px, 7.5, 4.5, 3, GOLD)
            coin(px, 4.5, 7.5, 3, GOLD)
        else:
            coin(px, 5.5, 3.5, 2.6, GOLD)
            coin(px, 8.2, 7.6, 2.8, GOLD)
            coin(px, 3.6, 7.8, 2.8, GOLD)
        outline(im, GOLD)
    elif kind == 'xp':
        star(px, 6.0, 6.4, (4.3, 5.0, 5.4)[tier - 1], (1.9, 2.2, 2.4)[tier - 1], XP[tier - 1])
        outline(im, XP[tier - 1])
    else:
        if tier == 1:
            shard(px, 5.5, 2, 10, 2.6, CYAN)
        elif tier == 2:
            shard(px, 8.5, 5, 10, 1.7, CYAN)
            outline(im, CYAN)
            shard(px, 4.5, 1, 10, 2.9, CYAN)
        else:
            shard(px, 2.5, 5, 10, 1.6, CYAN)
            shard(px, 9.0, 4, 10, 1.9, CYAN)
            outline(im, CYAN)
            shard(px, 5.6, 0, 10, 2.8, CYAN)
        outline(im, CYAN)
    return im


def glint(im, frame, pal):
    """Frame 1-5: a bright band crossing the badge from the top left."""
    out = im.copy()
    px = out.load()
    line = -3 + frame * 5  # x + y of the band's centre: 2, 7, 12, 17, 22
    for y in range(S):
        for x in range(S):
            r, g, b, a = px[x, y]
            if not a or (r, g, b) == pal['o']:
                continue
            d = abs(x + y - line)
            if d <= 1:
                k = 0.95 if d == 0 else 0.55
                px[x, y] = (int(r + (255 - r) * k), int(g + (255 - g) * k), int(b + (255 - b) * k), a)
    if frame in (2, 3, 4):
        sparkle(px, 10, 1, frame == 3)
    return out


sheet = Image.new('RGBA', (S * FRAMES, S * 9), (0, 0, 0, 0))
row = 0
for kind, pals in (('loot', (GOLD,) * 3), ('rare', (CYAN,) * 3), ('xp', XP)):
    for tier in (1, 2, 3):
        b = base(kind, tier)
        for f in range(FRAMES):
            sheet.paste(b if f == 0 else glint(b, f, pals[tier - 1]), (f * S, row * S))
        row += 1
sheet.save(OUT)
print('wrote', OUT, sheet.size)
