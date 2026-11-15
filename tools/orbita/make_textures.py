# Órbita: textures of the runes that circle a player wearing rare items.
# One set per element (the colours of shaders/fragment/rarity_item.frag).
import math, sys
from PIL import Image, ImageDraw, ImageFilter
OUT = sys.argv[1]
ELEMENTS = {
    'none': (232, 228, 255), 'igneus': (255, 106, 42), 'terrenus': (108, 209, 58), 'fulmineus': (181, 107, 255),
    'glacialis': (82, 220, 255), 'sacer': (255, 216, 74), 'mortifer': (138, 61, 191), 'corporalis': (184, 190, 198),
}
N = 64
def mix(a, b, t): return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

def core(col):
    """a cut gem seen from the front: dark rim, coloured facets, a white heart"""
    S = 8; im = Image.new('RGBA', (N * S, N * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c = N * S / 2
    def diamond(rx, ry, fill):
        d.polygon([(c, c - ry), (c + rx, c), (c, c + ry), (c - rx, c)], fill=fill)
    diamond(21 * S, 29 * S, (18, 10, 30, 235))               # rim
    diamond(17.5 * S, 25 * S, mix(col, (0, 0, 0), 0.25) + (255,))
    # facets: lit upper left, shaded lower right
    d.polygon([(c, c - 25 * S), (c - 17.5 * S, c), (c, c)], fill=mix(col, (255, 255, 255), 0.35) + (255,))
    d.polygon([(c, c + 25 * S), (c + 17.5 * S, c), (c, c)], fill=mix(col, (0, 0, 0), 0.45) + (255,))
    diamond(8 * S, 12 * S, mix(col, (255, 255, 255), 0.82) + (255,))
    diamond(3.5 * S, 5.5 * S, (255, 255, 255, 255))
    return im.resize((N, N), Image.LANCZOS)

def halo(col, power=2.0, peak=1.0):
    im = Image.new('RGBA', (N, N)); px = im.load()
    for y in range(N):
        for x in range(N):
            r = math.hypot(x - N / 2 + .5, y - N / 2 + .5) / (N / 2)
            a = max(0.0, 1 - r) ** power * peak
            px[x, y] = mix(col, (255, 255, 255), max(0, 0.55 - r)) + (int(255 * min(1, a)),)
    return im

def ring(col, front, W=192, H=96, width=2.4, alpha=1.0, dashed=False):
    """half of an ellipse seen at an angle; the two halves make the whole orbit"""
    S = 4; im = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    cx, cy, rx, ry = W * S / 2, H * S / 2, (W / 2 - 6) * S, (H / 2 - 6) * S
    steps = 360
    for i in range(steps):
        a0, a1 = math.pi * i / steps, math.pi * (i + 1) / steps
        if not front: a0, a1 = a0 + math.pi, a1 + math.pi
        if dashed and (i // 9) % 2: continue
        # brighter where it faces the viewer
        k = (0.70 + 0.30 * abs(math.sin(a0))) if front else (0.45 + 0.25 * abs(math.sin(a0)))
        d.line([(cx + rx * math.cos(a0), cy + ry * math.sin(a0)), (cx + rx * math.cos(a1), cy + ry * math.sin(a1))],
               fill=mix(col, (255, 255, 255), 0.35) + (int(255 * alpha * k),), width=int(width * S))
    im = im.resize((W, H), Image.LANCZOS)
    glow = im.filter(ImageFilter.GaussianBlur(2.2))
    return Image.alpha_composite(glow, im)

def spark():
    """the flash of a rune whose bonus has just fired: a four-point star"""
    im = Image.new('RGBA', (N, N)); px = im.load()
    for y in range(N):
        for x in range(N):
            dx, dy = abs(x - N / 2 + .5) / (N / 2), abs(y - N / 2 + .5) / (N / 2)
            a = max(0, 1 - (dx * 5 + dy * 0.9)) + max(0, 1 - (dy * 5 + dx * 0.9)) + max(0, 1 - math.hypot(dx, dy) * 2.2) ** 2
            px[x, y] = (255, 255, 255, int(255 * min(1, a)))
    return im

for name, col in ELEMENTS.items():
    core(col).save(f'{OUT}/core_{name}.png')
    halo(col).save(f'{OUT}/halo_{name}.png')
    halo(col, power=1.4, peak=0.5).save(f'{OUT}/aura_{name}.png')
    ring(col, True).save(f'{OUT}/orbit_front_{name}.png')
    ring(col, False).save(f'{OUT}/orbit_back_{name}.png')
    ring(col, True, W=128, H=56, width=1.8, alpha=0.95, dashed=True).save(f'{OUT}/seal_front_{name}.png')
    ring(col, False, W=128, H=56, width=1.8, alpha=0.95, dashed=True).save(f'{OUT}/seal_back_{name}.png')
spark().save(f'{OUT}/spark.png')
# a sheet to look at
sheet = Image.new('RGBA', (N * 8 * 3, N * 3 * 2), (40, 34, 60, 255))
for i, name in enumerate(ELEMENTS):
    for j, kind in enumerate(('core', 'halo')):
        t = Image.open(f'{OUT}/{kind}_{name}.png').resize((N * 3, N * 3), Image.NEAREST if kind == 'core' else Image.BILINEAR)
        sheet.alpha_composite(t, (i * N * 3, j * N * 3))
if len(sys.argv) > 2:  # a sheet to look at, outside the module
    sheet.save(sys.argv[2])
