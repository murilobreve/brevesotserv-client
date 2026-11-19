# Draws two icons of the Mythos bar (16x16, the size of the bar's icons):
#   modules/game_brevespanel/images/market.png    the Market row: a stall
#   modules/game_brevespanel/images/teleport.png  the Teleports row: a portal
#   python3 tools/brevespanel-icons/make_market_teleport.py [out dir]
import math
import sys
from PIL import Image

S = 16
OUT = sys.argv[1] if len(sys.argv) > 1 else 'modules/game_brevespanel/images'
OUTLINE = (10, 6, 14)

# ---------------------------------------------------------------- market
# a stall: a striped awning, two posts, coins and a gem on the counter
STALL = [
    '................',
    '.oooooooooooooo.',
    'orrwwrrwwrrwwrro',
    'orrwwrrwwrrwwrro',
    'oRRWWRRWWRRWWRRo',
    'oRoWWoRRoWWoRRoo',
    '.o.oo.oo.oo.oo..',
    '..obddddddddbo..',
    '..obdgydddpdbo..',
    '..obgyygdpPpbo..',
    '.oooooooooooooo.',
    '.ocbbbbbbbbbbco.',
    '.oBBBBBBBBBBBBo.',
    '.oBBBBBBBBBBBBo.',
    '.oooooooooooooo.',
    '................',
]
COLORS = {
    'o': OUTLINE,
    'r': (226, 52, 52), 'R': (160, 30, 38),
    'w': (250, 244, 228), 'W': (196, 186, 170),
    'b': (176, 116, 54), 'B': (116, 70, 30), 'c': (214, 156, 84),
    'd': (34, 28, 46),
    'g': (232, 182, 64), 'y': (255, 236, 150),
    'p': (170, 110, 240), 'P': (226, 190, 255),
}
im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
px = im.load()
for y, row in enumerate(STALL):
    for x, ch in enumerate(row):
        if ch != '.':
            px[x, y] = COLORS[ch] + (255,)
im.save(OUT + '/market.png')

# -------------------------------------------------------------- teleport
# a portal: a ring of blue light with two spiral arms turning into a bright
# centre, as the game's own teleports are
DEEP, MID, LIGHT, WHITE = (26, 38, 128), (56, 112, 232), (126, 208, 255), (240, 252, 255)
im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
px = im.load()
cx = cy = 7.5
for y in range(S):
    for x in range(S):
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        if d > 8.1:
            continue
        if d > 7.3:
            c = OUTLINE
        elif d < 1.3:
            c = WHITE
        else:
            # two arms: the angle of the bright line turns with the radius
            arm = math.cos(2 * (math.atan2(dy, dx) - d * 0.55))
            if d > 6.2:
                c = LIGHT if arm > 0.2 else MID
            elif arm > 0.65:
                c = WHITE if d < 3.2 else LIGHT
            elif arm > 0.0:
                c = MID
            else:
                c = DEEP
        px[x, y] = c + (255,)
im.save(OUT + '/teleport.png')
print('wrote market.png and teleport.png in', OUT)
