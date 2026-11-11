# Mythos Voz icon set: pixel art in the client's palette (game_brevespanel icons,
# the Mythos top-menu buttons). Fills are drawn as letters; a 1 px outline in
# the client's ink (#090a10) is added around every shape and the shading
# (light from the top left) is worked out from each pixel's neighbours.
#
# Writes the 17 PNGs of modules/game_voice/images (Python 3 with Pillow), from
# the client repo:
#
#   python3 tools/voz-luatest/icons_gen.py modules/game_voice/images data/images/options/button_empty.png
#
# The second argument is the stone frame of the 40x20 top-menu button; without
# it button.png is not written. Kept out of modules/ so it does not ship.
import sys, math, os
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else 'out'
os.makedirs(OUT, exist_ok=True)

def hexc(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

INK = hexc('#090a10')
# material: (shadow, mid, highlight)
MAT = {
    'G': ('#705035', '#c99c53', '#ffe0a0'),   # gold (board, tasks, top-menu buttons)
    'S': ('#5b4d6a', '#a99eb4', '#e9dec7'),   # silver-lavender (messages)
    'L': ('#53386e', '#a181dc', '#e5ceff'),   # lavender (rarity, bonus)
    'R': ('#7a2e2a', '#e0604a', '#ff9f84'),   # red (the panel's COLOR_BAD)
    'V': ('#2f6a26', '#78d04c', '#c2f29a'),   # green (the panel's COLOR_ON)
    'D': ('#3e394f', '#6f688a', '#8f88a3'),   # idle grey (the panel's COLOR_OFF)
}
# explicit tones
TONE = {
    'o': INK,
    '1': hexc(MAT['G'][0]), '2': hexc(MAT['G'][1]), '3': hexc(MAT['G'][2]),
    '4': hexc(MAT['S'][0]), '5': hexc(MAT['S'][1]), '6': hexc(MAT['S'][2]),
    '7': hexc(MAT['R'][0]), '8': hexc(MAT['R'][1]), '9': hexc(MAT['R'][2]),
    'l': hexc(MAT['L'][0]), 'm': hexc(MAT['L'][1]), 'n': hexc(MAT['L'][2]),
    'v': hexc(MAT['V'][0]), 'w': hexc(MAT['V'][1]), 'y': hexc(MAT['V'][2]),
    'g': hexc(MAT['D'][0]), 'h': hexc(MAT['D'][1]), 'j': hexc(MAT['D'][2]),
}

def grid(rows):
    rows = [r for r in rows]
    w = max(len(r) for r in rows)
    return [list(r.ljust(w, '.')) for r in rows]

def render(g, outline=True, shade=True, size=None, diag=False):
    h, w = len(g), len(g[0])
    W, H = size or (w, h)
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    px = im.load()
    def at(x, y):
        if 0 <= x < w and 0 <= y < h:
            return g[y][x]
        return '.'
    def filled(c):
        return c not in '._'
    for y in range(h):
        for x in range(w):
            c = g[y][x]
            if c in MAT:
                lo, mid, hi = MAT[c]
                if not shade:
                    px[x, y] = hexc(mid)
                    continue
                tl = at(x - 1, y) != c or at(x, y - 1) != c
                br = at(x + 1, y) != c or at(x, y + 1) != c
                if tl and not br:
                    px[x, y] = hexc(hi)
                elif br and not tl:
                    px[x, y] = hexc(lo)
                else:
                    px[x, y] = hexc(mid)
            elif c in TONE:
                px[x, y] = TONE[c]
    if outline:
        for y in range(H):
            for x in range(W):
                if filled(at(x, y)):
                    continue
                if at(x, y) == '_':
                    continue
                n = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                if diag:
                    n += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
                if any(filled(at(x + dx, y + dy)) and at(x + dx, y + dy) != 'o' for dx, dy in n):
                    px[x, y] = INK
    return im

def slash(g, band, gap, y0, y1, mat='R'):
    """a red slash from the top right to the bottom left: x + y in `band`,
    the filled pixels on its sides (x + y in `gap`) become ink"""
    g = [r[:] for r in g]
    h, w = len(g), len(g[0])
    for y in range(h):
        for x in range(w):
            s = x + y
            if y0 <= y <= y1 and s in band:
                g[y][x] = mat
            elif y0 - 1 <= y <= y1 + 1 and s in gap and g[y][x] not in '._':
                g[y][x] = 'o'
    return g

def save(im, name):
    im.save(os.path.join(OUT, name + '.png'))

# --- 16x16 header buttons ---------------------------------------------------------
MIC16 = grid([
    "................",
    "................",
    "......SSSS......",
    ".....SSSSSS.....",
    ".....S4444S.....",
    "...G.SSSSSS.G...",
    "...G.S4444S.G...",
    "...G.SSSSSS.G...",
    "...G..SSSS..G...",
    "....G......G....",
    ".....GGGGGG.....",
    ".......GG.......",
    ".......GG.......",
    ".....GGGGGG.....",
    "................",
    "................",
])
save(render(MIC16), 'mic')
MIC16_OFF = slash(MIC16, band={15, 16}, gap={14, 17}, y0=2, y1=13)
save(render(MIC16_OFF), 'mic_off')

HEADSET16 = grid([
    "................",
    "................",
    "......GGGG......",
    "....GG....GG....",
    "...G........G...",
    "..G..........G..",
    "..G..........G..",
    "..G..........G..",
    "..G..........G..",
    "..SSS......SSS..",
    "..SSSS....SSSS..",
    "..SSSS....SSSS..",
    "..SSSS....SSSS..",
    "..SSS......SSS..",
    "................",
    "................",
])
save(render(HEADSET16), 'headset')
save(render(slash(HEADSET16, band={15, 16}, gap={14, 17}, y0=2, y1=13)), 'headset_off')

def gear(n, r_body, r_tooth, r_hole, teeth=8, tooth_w=1.1, mat='S', hub=None):
    c = (n - 1) / 2
    rows = []
    for y in range(n):
        row = ''
        for x in range(n):
            dx, dy = x - c, y - c
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            on = d <= r_body
            if not on and d <= r_tooth:
                for k in range(teeth):
                    ta = k * 2 * math.pi / teeth
                    # distance from the tooth's axis
                    perp = abs(-math.sin(ta) * dx + math.cos(ta) * dy)
                    along = math.cos(ta) * dx + math.sin(ta) * dy
                    if along > 0 and perp <= tooth_w:
                        on = True
                        break
            if on and d <= r_hole:
                row += 'o'
            elif on and hub and d <= hub:
                row += 'G'
            else:
                row += mat if on else '.'
        rows.append(row)
    return grid(rows)

GEAR16 = grid([
    "................",
    "................",
    ".......SS.......",
    "...SS..SS..SS...",
    "...SSSSSSSSSS...",
    "....SSSSSSSS....",
    "....SSSooSSS....",
    "..SSSSooooSSSS..",
    "..SSSSooooSSSS..",
    "....SSSooSSS....",
    "....SSSSSSSS....",
    "...SSSSSSSSSS...",
    "...SS..SS..SS...",
    ".......SS.......",
    "................",
    "................",
])
save(render(GEAR16), 'gear')

# --- 12x12 member icons ---------------------------------------------------------------
MIC12 = grid([
    "............",
    "....SSSS....",
    "....S44S....",
    "..G.SSSS.G..",
    "..G.S44S.G..",
    "..G.SSSS.G..",
    "...G.SS.G...",
    "....GGGG....",
    ".....GG.....",
    "....GGGG....",
    "............",
    "............",
])
save(render(MIC12), 's_mic')
save(render(slash(MIC12, band={11}, gap={10, 12}, y0=1, y1=10)), 's_selfmuted')
HEADSET12 = grid([
    "............",
    "....GGGG....",
    "...G....G...",
    "..G......G..",
    "..G......G..",
    "..G......G..",
    "..SSS..SSS..",
    "..SSS..SSS..",
    "..SSS..SSS..",
    "..SS....SS..",
    "............",
    "............",
])
save(render(slash(HEADSET12, band={11}, gap={10, 12}, y0=1, y1=10)), 's_deaf')
# muted by the staff: the "not allowed" sign, apart from the slashed icons
# the players set themselves
def prohibited(n=12):
    c = (n - 1) / 2
    g = grid([''.join('R' if 3.6 <= math.hypot(x - c, y - c) <= 4.9 else '.' for x in range(n)) for y in range(n)])
    for y in range(2, n - 2):
        g[y][n - 1 - y] = 'R'
    return g
save(render(prohibited()), 's_srvmuted')
SPEAKER12_X = grid([
    "............",
    ".....S......",
    "....SS......",
    "...SSS......",
    ".SSSSS.R..R.",
    ".SSSSS..RR..",
    ".SSSSS..RR..",
    ".SSSSS.R..R.",
    "...SSS......",
    "....SS......",
    ".....S......",
    "............",
])
save(render(SPEAKER12_X), 's_mutedforme')
STAR12 = grid([
    "............",
    ".....GG.....",
    ".....GG.....",
    "....GGGG....",
    ".GGGGGGGGGG.",
    "..GGGGGGGG..",
    "...GGGGGG...",
    "...GGGGGG...",
    "..GGG..GGG..",
    "..GG....GG..",
    "............",
    "............",
])
save(render(STAR12), 's_staff')
EYE12 = grid([
    "............",
    "............",
    "....SSSS....",
    "..SSSSSSSS..",
    ".SSSmmmmSSS.",
    ".SSmmo6mmSS.",
    ".SSmmoommSS.",
    ".SSSmmmmSSS.",
    "..SSSSSSSS..",
    "....SSSS....",
    "............",
    "............",
])
save(render(EYE12), 'lite')

def ring(n, r_out, r_in, r_dot, mat_ring, mat_dot):
    c = (n - 1) / 2
    rows = []
    for y in range(n):
        row = ''
        for x in range(n):
            d = math.hypot(x - c, y - c)
            if r_in <= d <= r_out:
                row += mat_ring
            elif d <= r_dot:
                row += mat_dot
            else:
                row += '.'
        rows.append(row)
    return grid(rows)

DOT12 = ring(12, 0, 1, 1.6, '.', 'D')
save(render(DOT12), 'dot')
RING12 = ring(12, 4.75, 3.2, 1.6, 'V', 'V')
save(render(RING12), 'speaking_ring')

# --- 18x16 over the head of who is talking ----------------------------------------
# green like the speaking ring: a speaker and two curved waves, outlined for
# any floor (sand, grass, a dark cave)
SPEAKER_HEAD = grid([
    "..................",
    "..................",
    "........V.........",
    ".......VV....VV...",
    "......VVV.V...VV..",
    ".....VVVV.VV...VV.",
    "..VVVVVVV..V....V.",
    "..VVVVVVV..V....V.",
    "..VVVVVVV..V....V.",
    "..VVVVVVV..V....V.",
    ".....VVVV.VV...VV.",
    "......VVV.V...VV..",
    ".......VV....VV...",
    "........V.........",
    "..................",
    "..................",
])
save(render(SPEAKER_HEAD), 'speaker_head')

# --- 40x20 top-menu button: it sits in the right panel's grid of stock
# buttons (data/images/options: button_empty's stone frame, a flat #c9c9c9
# glyph; the right half is the pressed/on state, its bevel turned over and
# the glyph 1 px down and right), so it is drawn the same way ------------------
FRAME = sys.argv[2] if len(sys.argv) > 2 else None
MIC_GLYPH = [
    "..............",
    ".....####.....",
    "....######....",
    "....#....#....",
    ".#..######..#.",
    ".#..#....#..#.",
    ".#..######..#.",
    ".#...####...#.",
    "..#........#..",
    "...########...",
    "......##......",
    "......##......",
    "....######....",
    "..............",
]
if FRAME:
    btn = Image.open(FRAME).convert('RGBA')
    glyph = hexc('#c9c9c9')
    for half, off in ((0, 3), (20, 4)):
        for y, row in enumerate(MIC_GLYPH):
            for x, ch in enumerate(row):
                if ch == '#':
                    btn.putpixel((half + off + x, off + y), glyph)
    save(btn, 'button')

# --- 48x48 touch push-to-talk (mobile) ----------------------------------------------
def shape(n, m, test):
    return grid([''.join(test(x, y) or '.' for x in range(n)) for y in range(m)])

def rrect(x, y, x0, y0, x1, y1, r):
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x0 <= x <= x1 and y0 <= y <= y1) and math.hypot(x - cx, y - cy) <= r + 0.35

def mic48(x, y):
    # capsule
    if rrect(x, y, 18, 8, 29, 28, 5.6):
        if y in (14, 18, 22) and 20 <= x <= 27:
            return '1'
        return 'G'
    # holder arc: a U around the capsule
    cx, cy = 23.5, 22.0
    d = math.hypot((x - cx) / 1.0, (y - cy) / 1.0)
    if y >= 19 and 9.3 <= d <= 11.2:
        return 'G'
    if y < 22 and y >= 18 and (13 <= x <= 14 or 33 <= x <= 34):
        return 'G'
    # stem and base
    if 22 <= x <= 25 and 33 <= y <= 36:
        return 'G'
    if 16 <= x <= 31 and 37 <= y <= 39:
        return 'G'
    return None

base = Image.new('RGBA', (48, 48), (0, 0, 0, 0))
c = 23.5
for y in range(48):
    for x in range(48):
        d = math.hypot(x - c, y - c)
        if d <= 23.6:
            if d > 22.4:
                col = INK
            elif d > 20.4:
                # the rim, lit from the top left
                lit = (-(x - c) - (y - c)) / (d * 1.4142)
                col = hexc('#e5ceff') if lit > 0.55 else hexc('#b296f5') if lit > -0.55 else hexc('#53386e')
            elif d > 19.4:
                col = INK
            elif d > 18.4:
                # the inner bevel: light on the top left, dark on the bottom right
                lit = (-(x - c) - (y - c)) / (d * 1.4142)
                col = hexc('#3a3150') if lit > 0.3 else hexc('#101018') if lit < -0.3 else hexc('#1a1626')
            else:
                col = hexc('#1a1626')
            base.putpixel((x, y), col)
base.alpha_composite(render(shape(48, 48, mic48)))
save(base, 'ptt_touch')
