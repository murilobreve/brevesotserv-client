# Draws data/images/game/huntboard/boost_badges.png: the badges the client
# puts above a boosted monster's name (Creature::drawBoostBadges).
# Only the icon, no number: its colour says how near the rate is to the
# highest of the Hunt Board (green, yellow, orange, red at the top).
# 9x7 cells (the letters XP take the width; the bag and the crystal sit in
# the middle 7); rows: loot heat 1-4 (a bag), rare monsters heat 1-4 (a
# crystal), experience heat 1-4 (the letters XP); 6 frames a row: 0 at rest,
# 1-5 a glint crossing the badge (drawn for every row, used by the red one).
#   python3 tools/huntboard-badges/make_badges.py [out.png]
import sys
from PIL import Image

W, H = 9, 7
FRAMES = 6
OUT = sys.argv[1] if len(sys.argv) > 1 else 'data/images/game/huntboard/boost_badges.png'

# the same scale for the three badges, from a rate just above 1x to the top
HEAT = (
    {'o': (14, 50, 18), 'h': (214, 255, 196), 'm': (112, 214, 92), 's': (50, 148, 50)},
    {'o': (60, 46, 6), 'h': (255, 250, 196), 'm': (250, 214, 70), 's': (194, 148, 24)},
    {'o': (70, 30, 4), 'h': (255, 214, 150), 'm': (255, 146, 44), 's': (206, 90, 16)},
    {'o': (72, 6, 6), 'h': (255, 170, 130), 'm': (240, 62, 46), 's': (168, 22, 26)},
)

# each icon as rows of: h light, m middle, s shade (the outline is added)
ICONS = {
    'xp': (
        'm.m.mm.',
        'm.m.m.m',
        '.s..mm.',
        's.s.s..',
        's.s.s..',
    ),
    'loot': (
        'h.m',
        '.m.',
        'hmmm.',
        'hmmms',
        '.mss.',
    ),
    'rare': (
        '.h.',
        'hms',
        'hms',
        'mss',
        '.s.',
    ),
}


def draw(kind, pal):
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    px = im.load()
    rows = ICONS[kind]
    width = max(len(r) for r in rows)
    x0 = (W - width) // 2
    y0 = (H - len(rows)) // 2
    for y, row in enumerate(rows):
        pad = (width - len(row)) // 2
        for x, ch in enumerate(row):
            if ch in 'hms':
                px[x0 + pad + x, y0 + y] = pal[ch] + (255,)
    # a dark outline round the shape, corners too
    edge = []
    for y in range(H):
        for x in range(W):
            if px[x, y][3]:
                continue
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if (dx or dy) and 0 <= nx < W and 0 <= ny < H and px[nx, ny][3] and px[nx, ny][:3] != pal['o']:
                        edge.append((x, y))
    for x, y in edge:
        px[x, y] = pal['o'] + (255,)
    return im


def glint(im, frame, pal):
    """Frame 1-5: a bright band crossing the badge from the top left."""
    out = im.copy()
    px = out.load()
    line = -2 + frame * 3  # x + y of the band's centre: 1, 4, 7, 10, 13
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if not a or (r, g, b) == pal['o']:
                continue
            if abs(x + y - line) == 0:
                px[x, y] = (int(r + (255 - r) * 0.9), int(g + (255 - g) * 0.9), int(b + (255 - b) * 0.9), a)
    return out


sheet = Image.new('RGBA', (W * FRAMES, H * 12), (0, 0, 0, 0))
row = 0
for kind in ('loot', 'rare', 'xp'):
    for heat in (1, 2, 3, 4):
        b = draw(kind, HEAT[heat - 1])
        for f in range(FRAMES):
            sheet.paste(b if f == 0 else glint(b, f, HEAT[heat - 1]), (f * W, row * H))
        row += 1
sheet.save(OUT)
print('wrote', OUT, sheet.size)
