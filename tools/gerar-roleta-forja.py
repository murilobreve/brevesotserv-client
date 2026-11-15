"""Wheel pictures for the Roleta de Raridade (for 2 to 40 slices: lines_n.png,
the trim, and wedge_n.png, one white slice the client tints), the disc at its
centre (wheel/center.png), the keep lock (ui/lock.png: open, open
under the mouse, closed) and the bonus icons pre-scaled with a smooth filter
(bonus/s16 .. s40). Gold trim, as the Mythos kit's.

usage: gen_wheel.py <images/forge dir>
"""
import math, os, sys
from PIL import Image, ImageDraw

out = sys.argv[1]
SIZE = 292
SS = 4  # supersampling
GOLD = (0xc9, 0xa2, 0x4a, 255)
PEG = (0xf0, 0xd9, 0x8c, 255)
DARK = (0x0f, 0x0a, 0x19, 255)

# the wheel's trim for n slices: rim, dividers and pegs over clear slices.
# The slices themselves are one white wedge (wedge_n.png) the client tints,
# one per bonus, in the colour of the bonus's family.
def lines(n):
    s = SIZE * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    r = c - 2 * SS
    box = [c - r, c - r, c + r, c + r]
    seg = 360 / n
    for i in range(n):
        a = math.radians(-90 + i * seg)
        d.line([c, c, c + r * math.cos(a), c + r * math.sin(a)], fill=GOLD, width=int(1.5 * SS))
    d.ellipse(box, outline=DARK, width=5 * SS)
    d.ellipse([box[0] + SS, box[1] + SS, box[2] - SS, box[3] - SS], outline=GOLD, width=3 * SS)
    # a peg on the rim at each divider, as on a prize wheel
    pr = (2.6 if n <= 24 else 2.0) * SS
    rr = r - 2.5 * SS
    for i in range(n):
        a = math.radians(-90 + i * seg)
        x, y = c + rr * math.cos(a), c + rr * math.sin(a)
        d.ellipse([x - pr, y - pr, x + pr, y + pr], fill=PEG, outline=DARK, width=max(1, SS // 2))
    return img.resize((SIZE, SIZE), Image.LANCZOS)

# the first slice (from 12 o'clock, clockwise), white, a hair wider than
# the slice so two neighbours meet under the divider
def wedge(n):
    s = SIZE * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    r = c - 4 * SS
    seg = 360 / n
    d.pieslice([c - r, c - r, c + r, c + r], -90 - 0.4, -90 + seg + 0.4, fill=(255, 255, 255, 255))
    return img.resize((SIZE, SIZE), Image.LANCZOS)

# the disc over the wheel's centre: the roll's number shows on it
def center(size=104):
    s = size * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, s - 1, s - 1], fill=DARK)
    d.ellipse([2 * SS, 2 * SS, s - 1 - 2 * SS, s - 1 - 2 * SS], fill=GOLD)
    d.ellipse([4 * SS, 4 * SS, s - 1 - 4 * SS, s - 1 - 4 * SS], fill=(0x17, 0x12, 0x24, 255))
    return img.resize((size, size), Image.LANCZOS)

# the keep lock, 18px: open (dim), open under the mouse, closed (gold)
def lock(color, closed):
    s = 18 * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = int(2 * SS)
    # shackle: an arch over the body; open, its right leg is lifted off
    left, right, top = 5 * SS, 13 * SS, 2 * SS
    if not closed:
        left, right = left - 3 * SS, right - 3 * SS
    d.arc([left, top, right, top + 8 * SS], 180, 360, fill=color, width=w)
    d.line([left + w // 2 - 1, top + 4 * SS, left + w // 2 - 1, 9 * SS], fill=color, width=w)
    d.line([right - w // 2, top + 4 * SS, right - w // 2, (9 if closed else 6) * SS], fill=color, width=w)
    d.rounded_rectangle([3 * SS, 8 * SS, 15 * SS, 16 * SS], radius=int(1.5 * SS), fill=color)
    d.ellipse([8 * SS, 10.5 * SS, 10 * SS, 12.5 * SS], fill=(0x17, 0x12, 0x24, 255))
    d.line([9 * SS, 12 * SS, 9 * SS, 14 * SS], fill=(0x17, 0x12, 0x24, 255), width=SS)
    return img.resize((18, 18), Image.LANCZOS)

wdir = os.path.join(out, 'wheel')
for n in range(2, 41):
    lines(n).save(os.path.join(wdir, 'lines_%d.png' % n))
    wedge(n).save(os.path.join(wdir, 'wedge_%d.png' % n))

center().save(os.path.join(wdir, 'center.png'))

locks = Image.new('RGBA', (54, 18), (0, 0, 0, 0))
locks.paste(lock((0x6f, 0x68, 0x80, 255), False), (0, 0))
locks.paste(lock((0xd1, 0xcc, 0xd9, 255), False), (18, 0))
locks.paste(lock((0xe2, 0xc4, 0x6a, 255), True), (36, 0))
locks.save(os.path.join(out, 'ui', 'lock.png'))

# ---------------------------------------------------------------------------
# The bonus icons, cut from the client's imbuement icons (64 px, the art on a
# patterned backdrop with a gem under it). The backdrop is the empty slot's
# pattern (icons/0.png) in the icon's colour: it is fitted on the frame's
# outer ring, then on every pixel that agrees, and what does not fit is the
# art. Each art is centred by its own outline on a 48 px canvas (the bigger
# ones scaled down to fit) and saved scaled, with a smooth filter, for each
# size the wheel uses (bonus/s16 .. s40).
# ---------------------------------------------------------------------------
import numpy as np

ICONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'images', 'game', 'imbuing', 'icons')
SOURCES = {
    'crit': 1, 'flame_death': 4, 'flame_earth': 7, 'flame_energy': 10, 'flame_fire': 13, 'flame_holy': 16,
    'flame_ice': 19, 'flame_phys': 22, 'shield_death': 25, 'shield_earth': 28, 'shield_energy': 31,
    'shield_fire': 34, 'shield_holy': 37, 'shield_ice': 40, 'shield_phys': 43, 'life': 46, 'mana': 49,
    'axe': 52, 'club': 55, 'bow': 58, 'fist': 61, 'wand': 64, 'shield': 67, 'sword': 70, 'wings': 73,
    'backpack': 76, 'boots': 79,
}
MASTER = 48
SIZES = (16, 20, 24, 28, 32, 36, 40)
pattern = np.asarray(Image.open(os.path.join(ICONS, '0.png')).convert('L')).astype(float)

def components(mask):
    seen = np.zeros(mask.shape, bool)
    h, w = mask.shape
    found = []
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                stack, pixels = [(y, x)], []
                while stack:
                    a, b = stack.pop()
                    pixels.append((a, b))
                    for da in (-1, 0, 1):
                        for db in (-1, 0, 1):
                            c, e = a + da, b + db
                            if 0 <= c < h and 0 <= e < w and mask[c, e] and not seen[c, e]:
                                seen[c, e] = True
                                stack.append((c, e))
                found.append(pixels)
    return found

def art_mask(rgb):
    weight = np.zeros(pattern.shape)
    weight[:7, :] = 1
    weight[:, :7] = 1
    weight[:, -7:] = 1
    weight[-3:, :] = 1
    for _ in range(10):
        residual = np.zeros(pattern.shape)
        for c in range(3):
            a = np.stack([pattern.ravel(), np.ones(pattern.size)], 1) * weight.ravel()[:, None]
            fit = np.linalg.lstsq(a, rgb[:, :, c].ravel() * weight.ravel(), rcond=None)[0]
            residual += np.abs(rgb[:, :, c] - (fit[0] * pattern + fit[1]))
        weight = (residual < 22).astype(float)
    return residual > 30

# where the gem sits, the same in every icon: the lowest piece of an icon
# whose art does not reach it
gem = [p for p in components(art_mask(np.asarray(Image.open(os.path.join(ICONS, '1.png')).convert('RGB')).astype(float)))
       if min(q[0] for q in p) >= 50]
gem_top = min(q[0] for p in gem for q in p) - 1

def cut(index):
    rgb = np.asarray(Image.open(os.path.join(ICONS, '%d.png' % index)).convert('RGB')).astype(float)
    mask = art_mask(rgb)
    mask[gem_top:, :] = False
    keep = np.zeros(mask.shape, bool)
    for pixels in components(mask):
        if len(pixels) >= 10:
            for q in pixels:
                keep[q] = True
    # a few pixels of the art that happen to match the backdrop: small holes
    # are filled, big ones (between a bow and its string) stay open
    for pixels in components(~keep):
        ys = [q[0] for q in pixels]
        xs = [q[1] for q in pixels]
        inside = min(ys) > 0 and min(xs) > 0 and max(ys) < 63 and max(xs) < 63
        if inside and len(pixels) <= 6:
            for q in pixels:
                keep[q] = True
    ys, xs = np.where(keep)
    art = Image.fromarray(np.dstack([rgb, keep * 255]).astype('uint8'), 'RGBA')
    art = art.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    fit = min(1.0, (MASTER - 2) / max(art.size))
    if fit < 1:
        art = art.resize((max(1, round(art.width * fit)), max(1, round(art.height * fit))), Image.LANCZOS)
    canvas = Image.new('RGBA', (MASTER, MASTER), (0, 0, 0, 0))
    canvas.alpha_composite(art, ((MASTER - art.width) // 2, (MASTER - art.height) // 2))
    return canvas

bdir = os.path.join(out, 'bonus')
for size in SIZES:
    os.makedirs(os.path.join(bdir, 's%d' % size), exist_ok=True)
for name, index in sorted(SOURCES.items()):
    master = cut(index)
    master.save(os.path.join(bdir, name + '.png'))
    for size in SIZES:
        master.resize((size, size), Image.LANCZOS).save(os.path.join(bdir, 's%d' % size, name + '.png'))
print('ok')
