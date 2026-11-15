"""Wheel pictures for the Roleta de Raridade (wheel_2.png .. wheel_40.png), the
disc at its centre (wheel/center.png), the keep lock (ui/lock.png: open, open
under the mouse, closed) and the bonus icons pre-scaled with a smooth filter
(bonus/s16, s20, s24, s28). Colours of the Mythos kit: obsidian and violet
slices, gold trim.

usage: gen_wheel.py <images/forge dir>
"""
import math, os, sys
from PIL import Image, ImageDraw

out = sys.argv[1]
SIZE = 292
SS = 4  # supersampling
A = (0x3b, 0x30, 0x5c, 255)
B = (0x1f, 0x1a, 0x2e, 255)
ODD = (0x4c, 0x2f, 0x55, 255)
GOLD = (0xc9, 0xa2, 0x4a, 255)
PEG = (0xf0, 0xd9, 0x8c, 255)
DARK = (0x0f, 0x0a, 0x19, 255)

def wheel(n):
    s = SIZE * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    r = c - 2 * SS
    box = [c - r, c - r, c + r, c + r]
    seg = 360 / n
    for i in range(n):
        color = A if i % 2 == 0 else B
        if n % 2 == 1 and i == n - 1:
            color = ODD
        # PIL angles start at 3 o'clock and go clockwise; slice 0 starts at 12
        d.pieslice(box, -90 + i * seg, -90 + (i + 1) * seg, fill=color)
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
    wheel(n).save(os.path.join(wdir, 'wheel_%d.png' % n))

center().save(os.path.join(wdir, 'center.png'))

locks = Image.new('RGBA', (54, 18), (0, 0, 0, 0))
locks.paste(lock((0x6f, 0x68, 0x80, 255), False), (0, 0))
locks.paste(lock((0xd1, 0xcc, 0xd9, 255), False), (18, 0))
locks.paste(lock((0xe2, 0xc4, 0x6a, 255), True), (36, 0))
locks.save(os.path.join(out, 'ui', 'lock.png'))

bdir = os.path.join(out, 'bonus')
for size in (16, 20, 24, 28):
    sdir = os.path.join(bdir, 's%d' % size)
    os.makedirs(sdir, exist_ok=True)
    for name in sorted(os.listdir(bdir)):
        if not name.endswith('.png'):
            continue
        im = Image.open(os.path.join(bdir, name)).convert('RGBA')
        # premultiplied resize so transparent edges don't go dark
        im = im.resize((size, size), Image.LANCZOS, reducing_gap=None)
        im.save(os.path.join(sdir, name))
print('ok')
