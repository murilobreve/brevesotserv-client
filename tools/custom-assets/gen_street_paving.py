"""Draws the streets of Ventera: seamless sandstone flagstones in the arenito colours, 256x256, wrapping on both axes.

The arenito pack (art/source/pisos-templo-cidade-16/cidade/02_arenito) has 16 separate 32x32 drawings whose stones end
at the tile edge, so a street showed a cut every square. This draws one continuous block instead: a jittered grid of
stone centres, each stone the area nearest its centre under a metric between square and round (flat sides, soft
corners), 1px joints, light from the upper left, grain, worn patches and a few cracks. import_floor_pack.py cuts it
into the 8x8 pattern of the street grounds. Run: python3 gen_street_paving.py (writes art/source/ruas-arenito-continuo).
"""
import os

import numpy as np
from PIL import Image

MORTAR = np.array([84, 62, 42]); DARK = np.array([140, 106, 74]); BASE = np.array([190, 150, 105])
LIGHT = np.array([222, 182, 128])

def make(N=256, cell=30, seed=5, out=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'art', 'source', 'ruas-arenito-continuo', 'arenito-256.png')):
    rng = np.random.default_rng(seed)
    g = N // cell
    pts = [((i + 0.5 + rng.uniform(-.38, .38)) * N / g, (j + 0.5 + rng.uniform(-.38, .38)) * N / g, rng.uniform(.75, 1.3))
           for j in range(g) for i in range(g)]
    yy, xx = np.mgrid[:N, :N].astype(float)
    d1 = np.full((N, N), 1e9); d2 = np.full((N, N), 1e9); ids = np.zeros((N, N), int)
    for k, (px, py, ax) in enumerate(pts):
        dx = np.abs(xx - px); dx = np.minimum(dx, N - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, N - dy)
        # between square (Chebyshev) and round: flat-sided flagstones with soft corners
        d = (np.maximum(dx * ax, dy / ax) ** 4 * 0.75 + (dx * dx + dy * dy) ** 2 * 0.25 / 4) ** 0.25
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d)); ids = np.where(closer, k, ids); d1 = np.where(closer, d, d1)
    tone = rng.normal(0, 1, len(pts))
    edge = d2 - d1
    img = BASE + tone[ids][..., None] * 8
    # light from the upper left: a stone is lit where its upper/left neighbour is another stone, shaded at the lower/right
    up = np.roll(ids, 3, 0) != ids; left = np.roll(ids, 3, 1) != ids
    down = np.roll(ids, -2, 0) != ids; right = np.roll(ids, -2, 1) != ids
    img = np.where((up | left)[..., None], LIGHT + tone[ids][..., None] * 5, img)
    img = np.where((down | right)[..., None], DARK + tone[ids][..., None] * 5, img)
    img = np.where((edge < 1.15)[..., None], MORTAR, img)
    stone = edge >= 1.15
    sp = rng.random((N, N))
    img[stone & (sp < 0.06)] -= 13
    img[stone & (sp > 0.965)] += 11
    # worn sandy patches and a few hairline cracks
    for _ in range(18):
        cx, cy, r = rng.integers(0, N), rng.integers(0, N), rng.integers(3, 8)
        dd = np.minimum(abs(yy - cy), N - abs(yy - cy)) ** 2 + np.minimum(abs(xx - cx), N - abs(xx - cx)) ** 2
        m = (dd < r * r) & stone & (rng.random((N, N)) < 0.5)
        img[m] = img[m] * 0.84 + np.array([128, 98, 66]) * 0.16
    for _ in range(10):
        x, y = rng.uniform(0, N), rng.uniform(0, N); a = rng.uniform(0, 6.28); s = ids[int(y), int(x)]
        for _ in range(int(rng.integers(4, 10))):
            xi, yi = int(x) % N, int(y) % N
            if ids[yi, xi] != s or not stone[yi, xi]: break
            img[yi, xi] = DARK * 0.8
            a += rng.uniform(-.7, .7); x += np.cos(a); y += np.sin(a)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(out)

if __name__ == '__main__':
    make()
