"""Draws the obsidian temple floors into art/obsidian_*/.

  (now from import_obsidian_sheets.py instead)
  obsidian_floor/  16 tiles (4x4 pattern): four polished 64x64 slabs, each
                   made of 2x2 tiles, with violet veins and a glassy sheen
  obsidian_inlay/  1 tile: a darker slab with a thin violet inlay and gem
                   studs, for the shrine and the teleport walkway
  obsidian_rune/   4 tiles (animation phases): the arrival medallion, a
                   halo ring that breathes slowly

Light comes from the top left, like every Tibia sprite.
Run: python3 art_obsidian.py
"""
import math
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art')
rng = np.random.default_rng(1525)

BASE = np.array([20, 13, 31], float)      # obsidian
DEEP = np.array([9, 5, 15], float)
VEIN = np.array([118, 86, 214], float)
GLINT = np.array([206, 186, 255], float)
GROOVE = np.array([5, 3, 9], float)
BEVEL = np.array([62, 46, 98], float)


def smooth_noise(size, scale, octaves=4):
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = max(2, int(size / scale * 2 ** o))
        grid = rng.random((n + 1, n + 1))
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
        out += amp * (np.asarray(img, float) / 255)
        total += amp
        amp *= 0.5
    return out / total


def veins(size, count):
    """Thin meandering lines: brightness 0..1."""
    v = np.zeros((size, size))
    for _ in range(count):
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        ang = rng.uniform(0, math.tau)
        strength = rng.uniform(0.3, 0.55)
        for _step in range(int(size * 1.6)):
            ang += rng.normal(0, 0.12)
            x += math.cos(ang) * 0.7
            y += math.sin(ang) * 0.7
            if not (0 <= x < size and 0 <= y < size):
                break
            v[int(y), int(x)] = max(v[int(y), int(x)], strength)
            strength *= 0.997
    # a faint halo around each vein
    halo = np.asarray(Image.fromarray((v * 255).astype(np.uint8)).resize((size // 2, size // 2), Image.BILINEAR)
                      .resize((size, size), Image.BILINEAR), float) / 255
    return v, halo


def slab(seed_shift):
    """One 64x64 polished slab as an RGB float array."""
    s = 64
    n = smooth_noise(s, 20)
    col = DEEP[None, None, :] + (BASE - DEEP)[None, None, :] * (0.55 + 0.9 * n[..., None])
    # conchoidal swirls: soft lighter bands, like glass that broke in curves
    yy, xx = np.mgrid[0:s, 0:s]
    cx, cy = rng.uniform(10, 54, 2)
    rad = np.hypot(xx - cx, yy - cy)
    swirl = (np.sin(rad / rng.uniform(4.5, 7.5) + n * 4) * 0.5 + 0.5) ** 6
    col += swirl[..., None] * np.array([10, 7, 20])
    v, halo = veins(s, rng.integers(2, 4))
    col = col * (1 - halo[..., None] * 0.35) + VEIN * halo[..., None] * 0.35
    col = col * (1 - v[..., None] * 0.6) + VEIN * v[..., None] * 0.6
    # glints where the veins are brightest
    spark = (v > 0.5) & (rng.random((s, s)) < 0.02)
    col[spark] = GLINT
    # glass sheen: a soft diagonal band from the top left
    d = (xx + yy) / (2 * s)
    sheen = np.exp(-((d - 0.30) / 0.14) ** 2) * 0.12 + np.exp(-((d - 0.34) / 0.025) ** 2) * 0.05
    col = col + (np.array([150, 130, 210]) - col) * sheen[..., None]
    # slab edges: light bevel top and left, dark groove right and bottom
    col[0, :] = col[0, :] * 0.4 + BEVEL * 0.6
    col[:, 0] = col[:, 0] * 0.4 + BEVEL * 0.6
    col[1, 1:] = col[1, 1:] * 0.75 + BEVEL * 0.25
    col[1:, 1] = col[1:, 1] * 0.75 + BEVEL * 0.25
    col[-1, :] = GROOVE
    col[:, -1] = GROOVE
    col[-2, :-1] *= 0.7
    col[:-1, -2] *= 0.7
    return col


def to_img(arr):
    a = np.clip(arr, 0, 255).astype(np.uint8)
    rgba = np.dstack([a, np.full(a.shape[:2], 255, np.uint8)])
    return Image.fromarray(rgba, 'RGBA')


def save_tiles(folder, tiles):
    path = os.path.join(ART, folder)
    os.makedirs(path, exist_ok=True)
    for f in os.listdir(path):
        os.remove(os.path.join(path, f))
    for i, t in enumerate(tiles):
        t.save(os.path.join(path, f'{i}.png'))


def floor():
    # 128x128 macro: four different slabs; tile (px, py) of the 4x4 pattern
    macro = np.zeros((128, 128, 3))
    for k in range(4):
        sx, sy = (k % 2) * 64, (k // 2) * 64
        macro[sy:sy + 64, sx:sx + 64] = slab(k)
    img = to_img(macro)
    tiles = []
    # sprite order of a 4x4 ground pattern: x fastest, then y
    for py in range(4):
        for px in range(4):
            tiles.append(img.crop((px * 32, py * 32, px * 32 + 32, py * 32 + 32)))
    save_tiles('obsidian_floor', tiles)


def inlay():
    s = 32
    n = smooth_noise(s, 12)
    col = DEEP[None, None, :] + (BASE - DEEP)[None, None, :] * (0.35 + 0.7 * n[..., None])
    yy, xx = np.mgrid[0:s, 0:s]
    d = (xx + yy) / (2 * s)
    col += (np.array([120, 100, 180]) - col) * (np.exp(-((d - 0.3) / 0.1) ** 2) * 0.16)[..., None]
    # the inlay: a thin violet square 4 px in, a darker channel each side
    for i in range(4, 28):
        for (x, y) in ((i, 4), (i, 27), (4, i), (27, i)):
            col[y, x] = VEIN * 0.6 + col[y, x] * 0.4
    for i in range(5, 27):
        for (x, y) in ((i, 3), (i, 28), (3, i), (28, i), (i, 5), (i, 26), (5, i), (26, i)):
            col[y, x] *= 0.55
    # gem studs in the corners of the inlay
    for (x, y) in ((4, 4), (27, 4), (4, 27), (27, 27)):
        col[y, x] = GLINT
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            col[y + dy, x + dx] = VEIN * 0.7
    col[0, :] = col[0, :] * 0.4 + BEVEL * 0.6
    col[:, 0] = col[:, 0] * 0.4 + BEVEL * 0.6
    col[-1, :] = GROOVE
    col[:, -1] = GROOVE
    save_tiles('obsidian_inlay', [to_img(col)])


def rune():
    s = 32
    tiles = []
    n = smooth_noise(s, 12)
    yy, xx = np.mgrid[0:s, 0:s]
    cx = cy = 15.5
    r = np.hypot(xx - cx, yy - cy)
    ang = np.arctan2(yy - cy, xx - cx)
    for phase in range(4):
        glow = 0.75 + 0.25 * math.sin(phase / 4 * math.tau)
        col = DEEP[None, None, :] + (BASE - DEEP)[None, None, :] * (0.4 + 0.7 * n[..., None])
        # halo ring: a bright thin ring with a soft glow inside and out
        ring = np.exp(-((r - 11.0) / 0.9) ** 2)
        soft = np.exp(-((r - 11.0) / 3.2) ** 2) * 0.35
        # eight small notches around the ring, like a dial
        notch = (np.abs(((ang / math.tau * 8) % 1) - 0.5) < 0.06) & (r > 12.5) & (r < 14.2)
        light = (ring + soft) * glow
        col = col + (VEIN - col) * np.clip(light, 0, 1)[..., None]
        col = col + (GLINT - col) * (np.clip(ring - 0.55, 0, 1) * glow)[..., None]
        col[notch] = VEIN * glow
        # four-point star in the centre
        star = np.exp(-(np.abs(xx - cx) * np.abs(yy - cy)) / 1.6) * np.exp(-r / 5.5)
        col = col + (GLINT - col) * np.clip(star * 1.6 * glow, 0, 1)[..., None]
        col[0, :] = col[0, :] * 0.4 + BEVEL * 0.6
        col[:, 0] = col[:, 0] * 0.4 + BEVEL * 0.6
        col[-1, :] = GROOVE
        col[:, -1] = GROOVE
        tiles.append(to_img(col))
    save_tiles('obsidian_rune', tiles)


if __name__ == '__main__':
    # the hall floor and the inlaid floor now come from the hand-made sheets
    # (import_obsidian_sheets.py); floor() and inlay() stay for reference
    rune()
    print('ok')
