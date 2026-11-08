"""Redraws pixel art at 4x its size (Scale2x twice: each pixel becomes 4x4
and the diagonals and curves follow their neighbours instead of turning
into big steps), with the dark lines thinned back to 1-2 px and a fresh
1 px dark outline: a bigger sprite drawn from the game sprite."""
import numpy as np
from PIL import Image
def scale2x(a):
    """EPX / Scale2x on an RGBA array: each pixel becomes 2x2, corners follow the neighbours' edges"""
    h, w = a.shape[:2]
    P = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode='edge')
    E = P[1:-1, 1:-1]; A = P[:-2, 1:-1]; B = P[1:-1, 2:]; C = P[1:-1, :-2]; D = P[2:, 1:-1]
    eq = lambda x, y: np.all(x == y, axis=-1)
    o = np.zeros((h * 2, w * 2, a.shape[2]), a.dtype)
    c1 = eq(C, A) & ~eq(C, D) & ~eq(A, B)
    c2 = eq(A, B) & ~eq(A, C) & ~eq(B, D)
    c3 = eq(D, C) & ~eq(D, B) & ~eq(C, A)
    c4 = eq(B, D) & ~eq(B, A) & ~eq(D, C)
    o[0::2, 0::2] = np.where(c1[..., None], A, E)
    o[0::2, 1::2] = np.where(c2[..., None], B, E)
    o[1::2, 0::2] = np.where(c3[..., None], C, E)
    o[1::2, 1::2] = np.where(c4[..., None], D, E)
    return o
def outline(a, col=(14, 12, 10, 255)):
    """a fresh 1 px dark outline around the drawn pixels at the new size"""
    on = a[..., 3] > 0
    edge = ~on & (np.roll(on, 1, 0) | np.roll(on, -1, 0) | np.roll(on, 1, 1) | np.roll(on, -1, 1))
    o = a.copy(); o[edge] = col
    return o
def thin_dark(a, keep=1, passes=2):
    """the old 1 px outlines grew 4 px thick: dark pixels deep inside a dark
    band take the colour of the nearest lighter pixel, so lines end ~1-2 px"""
    o = a.copy()
    for _ in range(passes):
        on = o[..., 3] > 0
        L = o[..., :3].astype(float).mean(-1)
        dark = on & (L < 40)
        light = on & ~dark
        inner = dark.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            inner &= np.roll(np.roll(dark | ~on, dy, 0), dx, 1)
        # only bands that touch a light pixel two steps away (inside the figure, not the outer edge)
        near_light = np.zeros_like(dark)
        for dy, dx in ((2, 0), (-2, 0), (0, 2), (0, -2)):
            near_light |= np.roll(np.roll(light, dy, 0), dx, 1)
        cand = inner & near_light
        src = np.zeros_like(o)
        got = np.zeros(dark.shape, bool)
        for dy, dx in ((2, 0), (-2, 0), (0, 2), (0, -2)):
            sh = np.roll(np.roll(o, dy, 0), dx, 1); sl = np.roll(np.roll(light, dy, 0), dx, 1)
            take = cand & sl & ~got
            src[take] = sh[take]; got |= take
        o[got, :3] = (src[got, :3].astype(float) * 0.55).astype(o.dtype)
    return o

def redraw(a):
    return outline(thin_dark(scale2x(scale2x(a))))
