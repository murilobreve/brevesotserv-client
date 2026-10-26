# -*- coding: utf-8 -*-
# Concept video for the Ascensao v2 brief: the Meteoro's impact as it is today
# (8 frames at 20 fps) next to the same art cut into 4 still layers, a few
# particles and a light, moved by curves and drawn at 60 fps.
import math
import os
import random
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from pathlib import Path
# the client's modules/: CLIENT_MODULES, or the ones of the repository this
# generator is in (docs/briefings/ascensao-v2/gerar/)
MODULES = os.environ.get('CLIENT_MODULES') or str(Path(__file__).resolve().parents[4] / 'modules')
IMG = MODULES + '/game_skillshot/images/meteoro/'
FLOOR = sys.argv[1]           # a 448x448 floor tile
OUT = sys.argv[2]             # the mp4
TMP = sys.argv[3]             # a folder for the frames
FPS = 60
CYCLE = 2000                  # ms per impact
LOOPS = 3
PW, PH = 640, 400             # one panel (2x pixels: 64 px = 1 sqm)
CX, CY = PW // 2, PH // 2 + 20
F_B = ImageFont.truetype('/usr/share/fonts/opentype/inter/Inter-Bold.otf', 20)
F_R = ImageFont.truetype('/usr/share/fonts/opentype/inter/Inter-Regular.otf', 15)


def frames(name):
    im = Image.open(IMG + name)
    out = []
    for i in range(getattr(im, 'n_frames', 1)):
        im.seek(i)
        out.append((im.convert('RGBA').copy(), im.info.get('duration', 100)))
    return out


IMPACT = frames('impacto.png')
EMBERS = {k: frames(f'brasas_{k}.png') for k in ('fortes', 'medias')}
# the v2 layers: still images cut from the v1 art
CORE = IMPACT[1][0]
RING = IMPACT[4][0]
DUST = IMPACT[6][0]
SCORCH = EMBERS['fortes'][0][0]


def floor():
    tile = Image.open(FLOOR).convert('RGB')
    img = Image.new('RGB', (PW, PH))
    for y in range(0, PH, tile.height):
        for x in range(0, PW, tile.width):
            img.paste(tile, (x, y))
    a = np.asarray(img).astype(np.float32) / 255
    return a * 0.55  # dusk, so the light shows


BASE = floor()


def clamp01(x):
    return max(0.0, min(1.0, x))


def seg(t, a, b):
    return clamp01((t - a) / (b - a)) if b > a else float(t >= a)


def out_cubic(x):
    return 1 - (1 - x) ** 3


def out_expo(x):
    return 1.0 if x >= 1 else 1 - 2 ** (-10 * x)


def in_quad(x):
    return x * x


def blend(canvas, img, cx, cy, scale, opacity, additive=False, sy=None):
    if opacity <= 0.003 or scale <= 0.01:
        return
    w = max(1, int(img.width * scale))
    h = max(1, int(img.height * (sy if sy is not None else scale)))
    im = img.resize((w, h), Image.BILINEAR)
    a = np.asarray(im).astype(np.float32) / 255
    x0, y0 = int(cx - w / 2), int(cy - h / 2)
    xs, ys = max(0, x0), max(0, y0)
    xe, ye = min(PW, x0 + w), min(PH, y0 + h)
    if xe <= xs or ye <= ys:
        return
    part = a[ys - y0:ye - y0, xs - x0:xe - x0]
    rgb, alpha = part[..., :3], part[..., 3:4] * opacity
    region = canvas[ys:ye, xs:xe]
    if additive:
        region += rgb * alpha
    else:
        region[:] = region * (1 - alpha) + rgb * alpha


def glow(canvas, cx, cy, radius, color, intensity):
    if intensity <= 0.003:
        return
    yy, xx = np.mgrid[0:PH, 0:PW]
    d = np.sqrt(((xx - cx) / radius) ** 2 + ((yy - cy) / (radius * 0.6)) ** 2)
    falloff = np.clip(1 - d, 0, 1) ** 2
    canvas += falloff[..., None] * np.array(color, dtype=np.float32) * intensity


rnd = random.Random(7)
ROCKS = [dict(a=rnd.uniform(0, 2 * math.pi), v=rnd.uniform(260, 520), up=rnd.uniform(250, 520), life=rnd.uniform(550, 900),
              size=rnd.uniform(4, 9)) for _ in range(16)]
SPARKS = [dict(a=rnd.uniform(0, 2 * math.pi), v=rnd.uniform(420, 820), up=rnd.uniform(150, 420), life=rnd.uniform(260, 560))
          for _ in range(26)]


def particles(canvas, t):
    img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img, 'RGBA')
    for p in ROCKS:
        if t > p['life']:
            continue
        s = t / 1000
        x = CX + math.cos(p['a']) * p['v'] * s
        y = CY + math.sin(p['a']) * p['v'] * s * 0.55 - (p['up'] * s - 900 * s * s / 2)
        fade = 1 - seg(t, p['life'] * 0.7, p['life'])
        r = p['size']
        d.ellipse((x - r, y - r, x + r, y + r), fill=(52, 34, 26, int(255 * fade)), outline=(255, 140, 50, int(200 * fade)))
    canvas[:] = np.asarray(img).astype(np.float32) / 255
    for p in SPARKS:
        if t > p['life']:
            continue
        s, s0 = t / 1000, max(0, t - 30) / 1000
        def at(q):
            return (CX + math.cos(p['a']) * p['v'] * q, CY + math.sin(p['a']) * p['v'] * q * 0.55 - (p['up'] * q - 700 * q * q / 2))
        (x, y), (x0, y0) = at(s), at(s0)
        fade = 1 - seg(t, p['life'] * 0.5, p['life'])
        # a short streak, added like light
        steps = 6
        for k in range(steps + 1):
            px, py = int(x0 + (x - x0) * k / steps), int(y0 + (y - y0) * k / steps)
            if 1 <= px < PW - 1 and 1 <= py < PH - 1:
                canvas[py - 1:py + 2, px - 1:px + 2] += np.array([1.0, 0.62, 0.25], dtype=np.float32) * 0.5 * fade * (0.4 + 0.6 * k / steps)


def v1(t):
    c = BASE.copy()
    # the embers under it, as the game shows them today (4 frames, 250 ms each)
    stage = 'fortes' if t < 1000 else 'medias'
    fr = EMBERS[stage]
    local = (t % 1000)
    idx = min(len(fr) - 1, int(local // max(1, fr[0][1])))
    blend(c, fr[idx][0], CX, CY, 1.0, 1.0)
    # the impact: 8 frames, 50 ms each
    i = int(t // 50)
    if i < len(IMPACT):
        blend(c, IMPACT[i][0], CX, CY - 24, 1.0, 1.0)
    return c


def v2(t):
    c = BASE.copy()
    big = 1.25  # the whole moment a little bigger
    # light on the ground: flares at once, dies slowly
    glow(c, CX, CY, 300, (1.0, 0.5, 0.18), 0.85 * out_cubic(seg(t, 0, 50)) * (1 - out_cubic(seg(t, 60, 1500))))
    # the scorch with its embers: fades in, then cools
    blend(c, SCORCH, CX, CY, big, seg(t, 60, 220) * (1 - 0.55 * seg(t, 250, 2000)))
    # dust: slow, swelling, rising
    k = seg(t, 120, 1700)
    blend(c, DUST, CX, CY - 24 - 26 * out_cubic(k), big * (0.9 + 0.6 * out_cubic(k)), 0.85 * seg(t, 120, 320) * (1 - in_quad(k)))
    # the shock ring: fast out, eases to a stop, fades
    k = seg(t, 30, 700)
    blend(c, RING, CX, CY - 10, big * (0.25 + 0.8 * out_expo(k)), 0.95 * (1 - in_quad(seg(t, 160, 700))), sy=big * (0.25 + 0.8 * out_expo(k)) * 0.95)
    # the core: pops past full size, then burns out (added like light)
    k1, k2 = seg(t, 0, 90), seg(t, 90, 430)
    blend(c, CORE, CX, CY - 24, big * (0.35 + 0.85 * out_cubic(k1) + 0.15 * k2), out_cubic(seg(t, 0, 40)) * (1 - in_quad(k2)), additive=True)
    particles(c, t)
    # a short shake of the ground at the hit
    shake = int(5 * (1 - seg(t, 0, 160)) * math.sin(t / 8))
    if shake:
        c = np.roll(c, shake, axis=1)
    return c


def label(img, x, title, sub):
    d = ImageDraw.Draw(img)
    d.text((x + 16, 14), title, fill=(255, 255, 255), font=F_B, stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((x + 16, 42), sub, fill=(225, 225, 225), font=F_R, stroke_width=3, stroke_fill=(0, 0, 0))


os.makedirs(TMP, exist_ok=True)
total = CYCLE * LOOPS
n = int(total * FPS / 1000)
for i in range(n):
    t = (i * 1000 / FPS) % CYCLE
    left = Image.fromarray((np.clip(v1(t), 0, 1) * 255).astype(np.uint8))
    right = Image.fromarray((np.clip(v2(t), 0, 1) * 255).astype(np.uint8))
    frame = Image.new('RGB', (PW * 2 + 8, PH), (20, 20, 24))
    frame.paste(left, (0, 0))
    frame.paste(right, (PW + 8, 0))
    label(frame, 0, 'Hoje (v1)', '8 frames a 20 fps · 1 camada')
    label(frame, PW + 8, 'Conceito v2 · 60 fps', '4 imagens paradas + partículas + luz, movidas por curvas')
    frame.save(os.path.join(TMP, f'{i:04d}.png'))
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(FPS), '-i', os.path.join(TMP, '%04d.png'),
                '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-r', str(FPS), OUT], check=True)
print(OUT, n, 'frames')
