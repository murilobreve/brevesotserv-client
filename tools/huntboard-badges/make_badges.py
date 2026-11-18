# Draws data/images/game/huntboard/boost_badges.png: the badges the client
# puts above a boosted monster's name (Creature::drawBoostBadges).
# Only the icon, no number: its colour says how near the rate is to the
# highest of the Hunt Board (green, yellow, orange, red at the top).
# 12x12 cells; rows: loot heat 1-4 (a bag), rare monsters heat 1-4
# (crystals), experience heat 1-4 (the letters XP);
# 6 frames a row: 0 at rest, 1-5 a glint crossing the badge (drawn for every
# row, used by the red one).
#   python3 tools/huntboard-badges/make_badges.py [out.png]
import math
import sys
from PIL import Image

S = 12
FRAMES = 6
OUT = sys.argv[1] if len(sys.argv) > 1 else 'data/images/game/huntboard/boost_badges.png'

# the same scale for the three badges, from a rate just above 1x to the top
HEAT = (
    {'o': (14, 50, 18), 'h': (214, 255, 196), 'm': (112, 214, 92), 's': (50, 148, 50)},
    {'o': (60, 46, 6), 'h': (255, 250, 196), 'm': (250, 214, 70), 's': (194, 148, 24)},
    {'o': (70, 30, 4), 'h': (255, 214, 150), 'm': (255, 146, 44), 's': (206, 90, 16)},
    {'o': (72, 6, 6), 'h': (255, 170, 130), 'm': (240, 62, 46), 's': (168, 22, 26), 'c': (255, 232, 140)},
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


def bag(px, pal):
    """A loot bag: a round body lit from the top left, a tied neck and a
    flared mouth."""
    cx, cy, r = 6.0, 7.4, 3.9
    for y in range(S):
        for x in range(S):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            # the body, a little wider than tall
            if (dx / 1.08) ** 2 + dy * dy <= r * r:
                k = dx + dy
                px[x, y] = (pal['h'] if k <= -r * 0.8 else pal['s'] if k >= r * 0.55 else pal['m']) + (255,)
    # the neck and the mouth above it
    for x in range(5, 7):
        px[x, 3] = pal['m'] + (255,)
    for x in range(4, 8):
        px[x, 2] = (pal['h'] if x < 6 else pal['m']) + (255,)
    px[3, 1] = pal['m'] + (255,)
    px[8, 1] = pal['s'] + (255,)
    # the string tied round the neck
    for x in range(4, 8):
        px[x, 4] = pal['s'] + (255,)


# "XP" in bold pixel letters, 7 rows tall
XP_LETTERS = (
    '1...1.111.',
    '11.11.11.1',
    '.111..11.1',
    '..1...111.',
    '.111..11..',
    '11.11.11..',
    '1...1.11..',
)


def letters(px, pal):
    """The letters XP: light on top, shaded at the bottom."""
    for row, line in enumerate(XP_LETTERS):
        for col, ch in enumerate(line):
            if ch == '1':
                c = pal['h'] if row <= 1 else pal['s'] if row >= 5 else pal['m']
                px[1 + col, 2 + row] = c + (255,)


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


def base(kind, heat):
    pal = HEAT[heat - 1]
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    px = im.load()
    if kind == 'loot':
        bag(px, pal)
    elif kind == 'xp':
        letters(px, pal)
    else:
        shard(px, 8.5, 5, 10, 1.7, pal)
        outline(im, pal)
        shard(px, 4.5, 1, 10, 2.9, pal)
    outline(im, pal)
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


sheet = Image.new('RGBA', (S * FRAMES, S * 12), (0, 0, 0, 0))
row = 0
for kind in ('loot', 'rare', 'xp'):
    for heat in (1, 2, 3, 4):
        b = base(kind, heat)
        for f in range(FRAMES):
            sheet.paste(b if f == 0 else glint(b, f, HEAT[heat - 1]), (f * S, row * S))
        row += 1
sheet.save(OUT)
print('wrote', OUT, sheet.size)
