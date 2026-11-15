"""Wheel pictures for the Forja de Raridade roulette (wheel_2.png .. wheel_40.png)
and the bonus icons pre-scaled with a smooth filter (bonus/s16, s20, s24, s28).

usage: gen_wheel.py <images/forge dir>
"""
import math, os, sys
from PIL import Image, ImageDraw

out = sys.argv[1]
SIZE = 292
SS = 4  # supersampling
A = (0x4a, 0x3d, 0x22, 255)
B = (0x2e, 0x34, 0x46, 255)
ODD = (0x40, 0x2c, 0x3e, 255)
GOLD = (0xc9, 0xa2, 0x4a, 255)
DARK = (0x1c, 0x18, 0x10, 255)

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
    return img.resize((SIZE, SIZE), Image.LANCZOS)

wdir = os.path.join(out, 'wheel')
for n in range(2, 41):
    wheel(n).save(os.path.join(wdir, 'wheel_%d.png' % n))

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
