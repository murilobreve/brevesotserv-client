"""Pictures of the Forja de Raridade window (modules/game_raritybonus/images/forge).

All white on transparent: the window paints them with image-color (grade and
quality colours), so one picture serves every colour.

Usage (pillow, numpy):
  python3 gen_forge_art.py ../../modules/game_raritybonus/images/forge
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
SS = 4  # drawn 4x bigger, then reduced: smooth edges


def save(img, name, size):
    img.resize(size, Image.LANCZOS).save(os.path.join(OUT, name))


# the quality ring of a bonus card: 21 frames, 0% to 100% in steps of 5,
# side by side (image-clip picks one), starting at the top, clockwise
R = 76
frames = Image.new('RGBA', (R * 21, R), (0, 0, 0, 0))
for k in range(21):
    big = Image.new('RGBA', (R * SS, R * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    pad, w = 4 * SS, 7 * SS
    box = (pad, pad, R * SS - pad, R * SS - pad)
    if k == 20:
        d.ellipse(box, outline=(255, 255, 255, 255), width=w)
    elif k > 0:
        d.arc(box, -90, -90 + 360 * k / 20, fill=(255, 255, 255, 255), width=w)
    frames.paste(big.resize((R, R), Image.LANCZOS), (k * R, 0))
frames.save(os.path.join(OUT, 'ring.png'))

# a small diamond (grade pips, legend dots, history)
big = Image.new('RGBA', (12 * SS, 12 * SS), (0, 0, 0, 0))
ImageDraw.Draw(big).polygon([(6 * SS, 0), (12 * SS - 1, 6 * SS), (6 * SS, 12 * SS - 1), (0, 6 * SS)], fill=(255, 255, 255, 255))
save(big, 'pip.png', (12, 12))
big = Image.new('RGBA', (12 * SS, 12 * SS), (0, 0, 0, 0))
ImageDraw.Draw(big).polygon([(6 * SS, SS), (11 * SS, 6 * SS), (6 * SS, 11 * SS), (SS, 6 * SS)], outline=(255, 255, 255, 255), width=SS)
save(big, 'pip_empty.png', (12, 12))

# the grade crest of the Ascension: a diamond frame with an inner line, and
# its dark fill
C = 120
big = Image.new('RGBA', (C * SS, C * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(big)
m = C * SS // 2
def diamond(r):
    return [(m, m - r), (m + r, m), (m, m + r), (m - r, m)]
d.polygon(diamond(m - 2 * SS), outline=(255, 255, 255, 255), width=3 * SS)
d.polygon(diamond(m - 10 * SS), outline=(255, 255, 255, 150), width=SS)
save(big, 'crest.png', (C, C))
big = Image.new('RGBA', (C * SS, C * SS), (0, 0, 0, 0))
ImageDraw.Draw(big).polygon(diamond(m - 3 * SS), fill=(255, 255, 255, 255))
save(big, 'crest_fill.png', (C, C))

# the soft glow behind a lit crest or a perfect card
G = 160
yy, xx = np.mgrid[:G, :G]
r = np.hypot(xx - G / 2, yy - G / 2) / (G / 2)
a = np.clip(1 - r, 0, 1) ** 2.2
glow = np.zeros((G, G, 4), np.uint8)
glow[..., :3] = 255
glow[..., 3] = (a * 255).astype(np.uint8)
Image.fromarray(glow).save(os.path.join(OUT, 'glow.png'))

# the Ascension dial's needle: a 220 square turned around its middle, the
# needle pointing up from near the centre to the ring
N = 220
big = Image.new('RGBA', (N * SS, N * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(big)
c = N * SS // 2
d.polygon([(c, 14 * SS), (c + 5 * SS, 34 * SS), (c + 2 * SS, 74 * SS), (c - 2 * SS, 74 * SS), (c - 5 * SS, 34 * SS)], fill=(255, 255, 255, 255))
d.ellipse((c - 9 * SS, c - 9 * SS, c + 9 * SS, c + 9 * SS), outline=(255, 255, 255, 255), width=3 * SS)
save(big, 'needle.png', (N, N))

# the dial's tick: one short bar (the window turns 100 of them round)
big = Image.new('RGBA', (6 * SS, 18 * SS), (0, 0, 0, 0))
ImageDraw.Draw(big).rounded_rectangle((SS, 0, 5 * SS, 18 * SS - 1), radius=2 * SS, fill=(255, 255, 255, 255))
save(big, 'tick.png', (6, 18))

# the back of a face-down bonus card: two nested diamonds and a dot
E = 56
big = Image.new('RGBA', (E * SS, E * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(big)
m = E * SS // 2
d.polygon(diamond(m - 2 * SS), outline=(255, 255, 255, 255), width=2 * SS)
d.polygon(diamond(m - 12 * SS), outline=(255, 255, 255, 200), width=2 * SS)
d.ellipse((m - 3 * SS, m - 3 * SS, m + 3 * SS, m + 3 * SS), fill=(255, 255, 255, 255))
save(big, 'rune.png', (E, E))

# arrow for "before -> after"
big = Image.new('RGBA', (14 * SS, 14 * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(big)
d.line([(2 * SS, 7 * SS), (12 * SS, 7 * SS)], fill=(255, 255, 255, 255), width=2 * SS)
d.line([(8 * SS, 3 * SS), (12 * SS, 7 * SS), (8 * SS, 11 * SS)], fill=(255, 255, 255, 255), width=2 * SS)
save(big, 'arrow.png', (14, 14))
print('ok', OUT)
