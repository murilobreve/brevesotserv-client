# Draws modules/game_brevespanel/images/bonus.png: the Roleta button of the
# Mythos bar, a casino roulette wheel (16x16, the size of the bar's icons).
#   python3 tools/brevespanel-icons/make_roleta.py [out.png]
import math
import sys
from PIL import Image

S = 16
OUT = sys.argv[1] if len(sys.argv) > 1 else 'modules/game_brevespanel/images/bonus.png'

OUTLINE = (10, 6, 14)
RIM_HI, RIM, RIM_LO = (255, 236, 150), (232, 182, 64), (158, 104, 28)
RED = (226, 40, 48)
BLACK = (26, 22, 34)
GREEN = (40, 200, 96)
WELL = (92, 52, 20)
HUB_HI = (255, 244, 190)
BALL, BALL_LO = (255, 255, 255), (206, 208, 224)

im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
px = im.load()
cx = cy = 7.5
for y in range(S):
    for x in range(S):
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        lit = dx + dy  # the light comes from the top left
        if d > 8.1:
            continue
        if d > 7.3:
            c = OUTLINE
        elif d > 6.2:
            c = RIM_HI if lit < -3 else RIM_LO if lit > 5 else RIM
        elif d > 3.1:
            # eight flat pockets, red and black, the one at the top green
            a = (math.degrees(math.atan2(dy, dx)) + 90 + 22.5) % 360
            pocket = int(a // 45)
            c = GREEN if pocket == 0 else RED if pocket % 2 else BLACK
        elif d > 2.1:
            c = RIM_LO if lit > 1 else RIM
        elif d > 1.0:
            c = WELL
        else:
            c = HUB_HI
        px[x, y] = c + (255,)
# the ball, in the red pocket on the upper right
px[11, 4] = BALL + (255,)
px[12, 4] = BALL_LO + (255,)
px[11, 5] = BALL_LO + (255,)
im.save(OUT)
print('wrote', OUT, im.size)
