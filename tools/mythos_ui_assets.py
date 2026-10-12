#!/usr/bin/env python3
"""Draws the Mythos window kit into data/images/mythos/.

The colours come from the login screen: the obsidian of the background, the
violet of the halo above the logo and the pearl of the logo letters. The
window body reuses the grain of the Tibia stone texture, darkened to
obsidian, so the windows still feel like part of the game.

Run from the repository root:  python3 tools/mythos_ui_assets.py
"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = os.path.join(ROOT, 'data', 'images', 'mythos')

OBSIDIAN = (31, 21, 47)       # window body
BAND = (19, 12, 31)           # title band
EDGE = (6, 3, 11)              # outer line
RIM = (78, 57, 118)            # inner light edge
HAIR = (62, 45, 94)           # hairlines inside windows
HALO = (155, 123, 255)        # halo violet (focus, selection, the title line)
PEARL = (236, 232, 246)       # pearl (primary button, titles)
INK = (15, 10, 25)            # wells: lists, inputs


def img(w, h, c=(0, 0, 0, 0)):
    return Image.new('RGBA', (w, h), c if len(c) == 4 else c + (255,))


def rect(im, x0, y0, x1, y1, c):
    c = c if len(c) == 4 else c + (255,)
    for y in range(y0, y1):
        for x in range(x0, x1):
            im.putpixel((x, y), c)


def frame(im, c, inset=0):
    w, h = im.size
    rect(im, inset, inset, w - inset, inset + 1, c)
    rect(im, inset, h - inset - 1, w - inset, h - inset, c)
    rect(im, inset, inset, inset + 1, h - inset, c)
    rect(im, w - inset - 1, inset, w - inset, h - inset, c)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def save(im, name):
    im.save(os.path.join(OUT, name + '.png'))


def window():
    stone = Image.open(os.path.join(ROOT, 'data', 'images', 'ui', 'window.png')).convert('RGB')
    w = h = 256
    band = 28
    im = img(w, h, OBSIDIAN)
    for y in range(band, h):
        for x in range(w):
            g = sum(stone.getpixel((x, y))) / 3 - 71   # grain of the stone, about +-5
            im.putpixel((x, y), tuple(max(0, min(255, round(OBSIDIAN[i] + g * 0.55))) for i in range(3)) + (255,))
    for y in range(band):
        for x in range(w):
            g = sum(stone.getpixel((x, 40 + y))) / 3 - 71
            im.putpixel((x, y), tuple(max(0, round(BAND[i] + g * 0.3)) for i in range(3)) + (255,))
    # the halo line under the title: brightest in the middle, gone at the sides
    for x in range(w):
        d = abs(x - (w - 1) / 2) / ((w - 1) / 2)
        t = max(0.0, 1 - d) ** 1.6
        im.putpixel((x, band - 1), mix(HAIR, HALO, t) + (255,))
        im.putpixel((x, band), mix(BAND, mix(OBSIDIAN, HALO, 0.35), t) + (255,))
    frame(im, EDGE)
    frame(im, RIM, 1)
    rect(im, 2, 2, w - 2, 3, (255, 255, 255, 18))
    save(im, 'window')


def section():
    # sub panel with a title strip, image-border 4, top 21
    w = h = 64
    im = img(w, h, (22, 14, 35, 235))
    rect(im, 1, 1, w - 1, 20, (38, 26, 60, 255))
    rect(im, 1, 20, w - 1, 21, HAIR)
    frame(im, HAIR)
    save(im, 'section')
    # same panel without a title strip, image-border 4
    im = img(32, 32, (22, 14, 35, 235))
    frame(im, HAIR)
    save(im, 'panel')
    # the same panel chosen in a list: halo border over a violet tint
    im = img(32, 32, (44, 28, 74, 245))
    frame(im, HALO)
    save(im, 'panel_on')


def well():
    # list or text area, sunk into the window
    im = img(32, 32, INK + (230,))
    frame(im, (50, 36, 76))
    rect(im, 1, 1, 31, 2, (0, 0, 0, 255))
    save(im, 'well')


def button(name, fill, border, top, bottom=None):
    w, h = 64, 22
    im = img(w, h, fill)
    frame(im, border)
    rect(im, 1, 1, w - 1, 2, top)
    if bottom:
        rect(im, 1, h - 2, w - 1, h - 1, bottom)
    # round the corners by one pixel
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        im.putpixel((x, y), (0, 0, 0, 0))
    save(im, name)


def buttons():
    button('button', (44, 30, 68), (88, 64, 132), (255, 255, 255, 20), (0, 0, 0, 60))
    button('button_hover', (55, 38, 84), HALO, (255, 255, 255, 28), (0, 0, 0, 60))
    button('button_pressed', (26, 17, 42), (88, 64, 132), (0, 0, 0, 90))
    button('button_disabled', (34, 24, 50), (56, 42, 82), (255, 255, 255, 8))
    button('button_pearl', PEARL, (255, 255, 255), (255, 255, 255, 255), (196, 188, 214, 255))
    button('button_pearl_hover', (255, 255, 255), (255, 255, 255), (255, 255, 255, 255), (214, 207, 230, 255))
    button('button_pearl_pressed', (205, 198, 222), (226, 220, 238), (180, 172, 200, 255))
    button('button_pearl_disabled', (64, 50, 92), (80, 64, 112), (255, 255, 255, 10))


def tabs():
    # tab strip button: text only until chosen, then a halo line under it
    w, h = 64, 24
    im = img(w, h)
    rect(im, 0, h - 1, w, h, HAIR)
    save(im, 'tab')
    im = img(w, h, (255, 255, 255, 8))
    rect(im, 0, h - 1, w, h, HAIR)
    save(im, 'tab_hover')
    im = img(w, h, (140, 123, 217, 26))
    rect(im, 0, h - 2, w, h, HALO)
    save(im, 'tab_on')


def inputs():
    w, h = 32, 22
    im = img(w, h, INK)
    frame(im, (78, 57, 118))
    rect(im, 1, 1, w - 1, 2, (0, 0, 0, 255))
    save(im, 'input')
    im = img(w, h, INK)
    frame(im, HALO)
    rect(im, 1, 1, w - 1, 2, (0, 0, 0, 255))
    save(im, 'input_focus')


def chevron(im, cx, cy, c, up=False):
    for i in range(4):
        y = cy - i if up else cy + i - 2
        for x in range(cx - 3 + i, cx + 4 - i):
            im.putpixel((x, y), c)


def combobox():
    # three states of 20 px stacked: normal, hover, open
    w, h = 91, 20
    im = img(w, h * 3)
    for k, border in enumerate(((78, 57, 118), HALO, HALO)):
        sub = img(w, h, (29, 19, 45))
        frame(sub, border)
        rect(sub, 1, 1, w - 1, 2, (255, 255, 255, 14))
        rect(sub, w - 19, 4, w - 18, h - 4, (58, 52, 72, 255))
        chevron(sub, w - 10, h // 2, PEARL + (255,) if k else (186, 168, 220, 255))
        im.paste(sub, (0, k * h))
    save(im, 'combobox')
    # popup list behind the options
    im = img(32, 32, (25, 16, 40, 250))
    frame(im, HALO)
    save(im, 'popup')


def scrollbar():
    # track
    im = img(10, 32, (14, 9, 24, 200))
    frame(im, (46, 33, 70))
    save(im, 'scroll_track')
    # thumb, image-border 4
    im = img(10, 24, (86, 64, 128))
    frame(im, (112, 86, 160))
    for x, y in ((0, 0), (9, 0), (0, 23), (9, 23)):
        im.putpixel((x, y), (0, 0, 0, 0))
    save(im, 'scroll_thumb')
    im = img(10, 24, (124, 96, 206))
    frame(im, HALO)
    for x, y in ((0, 0), (9, 0), (0, 23), (9, 23)):
        im.putpixel((x, y), (0, 0, 0, 0))
    save(im, 'scroll_thumb_hover')
    # arrows: 10x10, up and down, idle and pressed side by side
    im = img(20, 20)
    for k, c in enumerate(((164, 146, 200, 255), PEARL + (255,))):
        chevron(im, 4 + k * 10, 6, c, up=True)
        chevron(im, 4 + k * 10, 15, c)
    save(im, 'scroll_arrows')


def side_chevron(im, cx, cy, c, left=False):
    for i in range(4):
        x = cx - i if left else cx + i - 2
        for y in range(cy - 3 + i, cy + 4 - i):
            im.putpixel((x, y), c)


def slider():
    # horizontal versions for the percentage sliders
    im = img(32, 10, (14, 9, 24, 200))
    frame(im, (46, 33, 70))
    save(im, 'scroll_track_h')
    for name, fill, border in (('scroll_thumb_h', (86, 64, 128), (112, 86, 160)),
                               ('scroll_thumb_h_hover', (124, 96, 206), HALO)):
        im = img(24, 10, fill)
        frame(im, border)
        for x, y in ((0, 0), (23, 0), (0, 9), (23, 9)):
            im.putpixel((x, y), (0, 0, 0, 0))
        save(im, name)
    im = img(20, 20)
    for k, c in enumerate(((164, 146, 200, 255), PEARL + (255,))):
        side_chevron(im, 6 + k * 10, 4, c, left=True)
        side_chevron(im, 4 + k * 10, 15, c)
    save(im, 'scroll_arrows_h')


def fold_marks():
    # the small marks before a Mythos panel group title: open and folded
    for name, left in (('fold_open', False), ('fold_closed', True)):
        im = img(8, 8)
        if left:
            side_chevron(im, 2, 3, (176, 160, 214, 255))
        else:
            chevron(im, 3, 3, (176, 160, 214, 255))
        save(im, name)


def corner_notice():
    # small toast in the corner of the map
    w = h = 32
    im = img(w, h, (25, 16, 40, 242))
    frame(im, (88, 64, 132))
    rect(im, 1, 1, w - 1, 2, HALO + (255,))
    save(im, 'notice')


def bullets():
    # four small gems for the login feature list, in the rarity colours
    gems = {
        'gem_pearl': (232, 228, 255),
        'gem_gold': (226, 164, 67),
        'gem_amethyst': (166, 121, 230),
        'gem_sapphire': (79, 143, 232),
    }
    for name, c in gems.items():
        im = img(12, 12)
        for y in range(12):
            for x in range(12):
                d = abs(x - 5.5) + abs(y - 5.5)
                if d <= 5.0:
                    shade = 1.0 if (x + y) < 11 else 0.72
                    if d > 4.0:
                        shade *= 0.8
                    col = tuple(min(255, round(v * shade)) for v in c)
                    im.putpixel((x, y), col + (255,))
        im.putpixel((4, 4), (255, 255, 255, 230))
        im.putpixel((5, 3), (255, 255, 255, 160))
        save(im, name)


def rounded(w, h, r, fill, border, top=None, scale=4):
    """Rounded box drawn 4x larger and scaled down, so the corners are smooth."""
    from PIL import ImageDraw
    big = Image.new('RGBA', (w * scale, h * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), r * scale, fill=border)
    d.rounded_rectangle((scale, scale, (w - 1) * scale - 1, (h - 1) * scale - 1), (r - 1) * scale, fill=fill)
    im = big.resize((w, h), Image.LANCZOS)
    if top:
        for x in range(r, w - r):
            im.putpixel((x, 1), top)
    return im


def login_kit():
    # the login card and its fields, in the same obsidian as the windows
    out = os.path.join(ROOT, 'data', 'images', 'brevesui')
    rounded(64, 64, 8, (24, 15, 38, 245), (72, 53, 108, 255), (255, 255, 255, 14)).save(os.path.join(out, 'panel.png'))
    rounded(32, 32, 4, INK + (255,), (72, 53, 108, 255)).save(os.path.join(out, 'input.png'))
    rounded(32, 32, 4, INK + (255,), HALO + (255,)).save(os.path.join(out, 'input_focus.png'))
    # hairline between the brand side and the form, halo-bright in the middle
    im = img(1, 64)
    for y in range(64):
        t = max(0.0, 1 - abs(y - 31.5) / 31.5) ** 1.4
        im.putpixel((0, y), mix(HAIR, HALO, t * 0.8) + (255,))
    im.save(os.path.join(out, 'separator_v.png'))


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    window()
    section()
    well()
    buttons()
    tabs()
    inputs()
    combobox()
    scrollbar()
    slider()
    fold_marks()
    corner_notice()
    bullets()
    login_kit()
    print('wrote', sorted(os.listdir(OUT)))
