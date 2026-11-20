"""The plain parts of the Ascensao's web (modules/game_ascensao/images/teia):
white shapes the client tints by the node's state. Drawn at 4x and scaled
down, so the edges are smooth.

    python3 tools/ascensao-teia/make_nodes.py
"""
import math
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'modules', 'game_ascensao', 'images', 'teia')
S = 4


def canvas(size):
    return Image.new('RGBA', (size * S, size * S), (0, 0, 0, 0))


def save(image, size, name):
    image.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name))


def polygon(size, sides, turn, rim):
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    c = size * S / 2

    def points(radius):
        return [(c + radius * math.cos(math.radians(turn + 360 * i / sides)), c + radius * math.sin(math.radians(turn + 360 * i / sides))) for i in range(sides)]

    draw.polygon(points(c - S), fill=(255, 255, 255, 255))
    draw.polygon(points(c - S - rim * S), fill=(40, 34, 54, 255))
    draw.polygon(points(c - S - rim * S * 2.2), fill=(255, 255, 255, 235))
    return image


# a small node: a dot with a dark ring inside its rim
dot = canvas(24)
d = ImageDraw.Draw(dot)
d.ellipse((S, S, 24 * S - S, 24 * S - S), fill=(255, 255, 255, 255))
d.ellipse((4 * S, 4 * S, 20 * S, 20 * S), fill=(40, 34, 54, 255))
d.ellipse((7 * S, 7 * S, 17 * S, 17 * S), fill=(255, 255, 255, 235))
save(dot, 24, 'small.png')

save(polygon(40, 4, 0, 3), 40, 'notable.png')  # a diamond
save(polygon(56, 6, 30, 3.5), 56, 'keystone.png')  # a hexagon

# the centre: a sun of two rings
core = canvas(64)
d = ImageDraw.Draw(core)
d.ellipse((S, S, 64 * S - S, 64 * S - S), fill=(255, 255, 255, 255))
d.ellipse((6 * S, 6 * S, 58 * S, 58 * S), fill=(40, 34, 54, 255))
d.ellipse((12 * S, 12 * S, 52 * S, 52 * S), fill=(255, 255, 255, 255))
d.ellipse((17 * S, 17 * S, 47 * S, 47 * S), fill=(40, 34, 54, 255))
d.ellipse((22 * S, 22 * S, 42 * S, 42 * S), fill=(255, 255, 255, 255))
save(core, 64, 'core.png')

# the ring around the chosen node
ring = canvas(64)
d = ImageDraw.Draw(ring)
d.ellipse((S, S, 64 * S - S, 64 * S - S), outline=(255, 255, 255, 255), width=3 * S)
save(ring, 64, 'chosen.png')

# a link: a white bar the client stretches and turns
Image.new('RGBA', (8, 4), (255, 255, 255, 255)).save(os.path.join(OUT, 'link.png'))
print('written to', os.path.normpath(OUT))
