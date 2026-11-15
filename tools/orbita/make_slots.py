# Órbita: one gem cut per equipment slot, in every element colour.
# core_<slot>_<element>.png: a cut gem whose outline recalls the piece.
import math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
OUT = sys.argv[1]
ELEMENTS = {
    'none': (232, 228, 255), 'igneus': (255, 106, 42), 'terrenus': (108, 209, 58), 'fulmineus': (181, 107, 255),
    'glacialis': (82, 220, 255), 'sacer': (255, 216, 74), 'mortifer': (138, 61, 191), 'corporalis': (184, 190, 198),
}
N, SS = 64, 4
R = 25  # half size of a shape, in final pixels

def arc(cx, cy, r, a0, a1, n=28):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]

SHAPES = {  # lists of polygons in -1..1 (y down); 'hole' polygons are cut out
    'helmet': [[(-0.80, 0.62), (-0.80, -0.10)] + arc(0, -0.10, 0.80, 180, 360) + [(0.80, 0.62), (0.34, 0.62), (0.34, 0.02), (-0.34, 0.02), (-0.34, 0.62)]],
    'amulet': [[(0, -0.96)] + arc(0, 0.28, 0.62, -52, 232)],
    'armor': [[(-0.88, -0.72), (-0.36, -0.72), (0, -0.40), (0.36, -0.72), (0.88, -0.72), (0.72, 0.08), (0.46, 0.84), (-0.46, 0.84), (-0.72, 0.08)]],
    'shield': [[(-0.74, -0.82), (0.74, -0.82), (0.74, 0.04), (0, 0.94), (-0.74, 0.04)]],
    'weapon': [[(0, -0.98), (0.21, -0.62), (0.21, 0.30), (-0.21, 0.30), (-0.21, -0.62)], [(-0.64, 0.30), (0.64, 0.30), (0.64, 0.52), (-0.64, 0.52)], [(-0.15, 0.52), (0.15, 0.52), (0.15, 0.96), (-0.15, 0.96)]],
    'ring': [arc(0, 0.06, 0.80, 0, 360, 48)],
    'legs': [[(-0.76, -0.86), (0.76, -0.86), (0.76, 0.92), (0.20, 0.92), (0.08, -0.22), (-0.08, -0.22), (-0.20, 0.92), (-0.76, 0.92)]],
    'boots': [[(-0.58, -0.92), (0.08, -0.92), (0.08, 0.12), (0.86, 0.36), (0.86, 0.86), (-0.58, 0.86)]],
}
HOLES = {'ring': [arc(0, 0.06, 0.40, 0, 360, 40)]}

def mask_of(slot):
    S = N * SS; im = Image.new('L', (S, S), 0); d = ImageDraw.Draw(im)
    def P(poly): return [(S / 2 + x * R * SS, S / 2 + y * R * SS) for x, y in poly]
    for poly in SHAPES[slot]: d.polygon(P(poly), fill=255)
    for poly in HOLES.get(slot, []): d.polygon(P(poly), fill=0)
    return im

def core(slot, col):
    m = mask_of(slot); S = N * SS
    rim = m.filter(ImageFilter.MaxFilter(2 * (3 * SS // 2) + 1))
    inner = m.filter(ImageFilter.MinFilter(2 * (4 * SS) + 1))
    heart = m.filter(ImageFilter.MinFilter(2 * (7 * SS) + 1))
    a = np.asarray(m, dtype=np.float32) / 255
    yy, xx = np.mgrid[0:S, 0:S]
    t = (xx + yy) / (2.0 * S)  # 0 upper left, 1 lower right
    c = np.array(col, dtype=np.float32)
    light, dark = c + (255 - c) * 0.38, c * 0.55
    body = np.where(t[..., None] < 0.46, light, np.where(t[..., None] > 0.56, dark, c))
    out = np.zeros((S, S, 4), dtype=np.float32)
    rimA = np.asarray(rim, dtype=np.float32) / 255
    out[..., :3] = np.array((18, 10, 30)); out[..., 3] = rimA * 235
    out[..., :3] = out[..., :3] * (1 - a[..., None]) + body * a[..., None]
    out[..., 3] = np.maximum(out[..., 3], a * 255)
    ia = (np.asarray(inner, dtype=np.float32) / 255)[..., None]
    out[..., :3] = out[..., :3] * (1 - ia) + (c + (255 - c) * 0.55) * ia
    ha = (np.asarray(heart, dtype=np.float32) / 255)[..., None]
    out[..., :3] = out[..., :3] * (1 - ha) + 255 * ha
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), 'RGBA').resize((N, N), Image.LANCZOS)

for slot in SHAPES:
    for name, col in ELEMENTS.items():
        core(slot, col).save(f'{OUT}/core_{slot}_{name}.png')
sheet = Image.new('RGBA', (N * 3 * 8, N * 3 * 2), (40, 34, 60, 255))
for i, slot in enumerate(SHAPES):
    for j, el in enumerate(('glacialis', 'igneus')):
        sheet.alpha_composite(Image.open(f'{OUT}/core_{slot}_{el}.png').resize((N * 3, N * 3), Image.NEAREST), (i * N * 3, j * N * 3))
if len(sys.argv) > 2:  # a sheet to look at, outside the module
    sheet.save(sys.argv[2])
