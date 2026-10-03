"""Blue Fusca (VW Beetle convertible) rendered as Tibia mount sprites.

A signed-distance model in car space (u forward, v left, h up, 1 unit = 1
pixel) is voxelised at SS x resolution, projected with Tibia's oblique view
(height moves a point up and left by the same amount), shaded, downsampled
and outlined.
"""
import numpy as np
from PIL import Image

SS = 4  # supersampling

# material ids
BODY, TYRE, HUB, CHROME, GLASS, SEAT, HOOD, LAMP, TAIL, DARK, RIM = range(1, 12)

PALETTE = {
    # dark -> light tones
    # the turquoise of the reference Fusca
    BODY: [(8, 74, 112), (16, 118, 168), (34, 162, 210), (78, 196, 234), (168, 232, 250)],
    TYRE: [(14, 14, 16), (30, 30, 34), (52, 52, 58), (78, 78, 86)],
    HUB: [(110, 112, 120), (165, 168, 176), (220, 222, 228)],
    CHROME: [(96, 100, 110), (160, 166, 176), (225, 230, 238), (255, 255, 255)],
    GLASS: [(28, 40, 56), (58, 80, 104), (120, 150, 176)],
    RIM: [(170, 174, 180), (222, 226, 230), (250, 252, 255)],
    SEAT: [(60, 34, 22), (96, 58, 36), (134, 86, 52)],
    HOOD: [(120, 106, 80), (170, 152, 116), (214, 198, 160)],
    LAMP: [(200, 190, 120), (250, 245, 200), (255, 255, 240)],
    TAIL: [(120, 20, 20), (200, 40, 36), (255, 110, 90)],
    DARK: [(10, 12, 22), (22, 26, 40)],
}
OUTLINE = {BODY: (6, 40, 64), TYRE: (0, 0, 0), HUB: (20, 20, 24)}
OUTLINE_DEFAULT = (12, 14, 24)


def sd_ellipsoid(p, c, r):
    q = [(p[i] - c[i]) / r[i] for i in range(3)]
    k = np.sqrt(q[0] ** 2 + q[1] ** 2 + q[2] ** 2)
    return (k - 1.0) * min(r)


def sd_round_box(p, c, b, rad):
    q = [np.abs(p[i] - c[i]) - (b[i] - rad) for i in range(3)]
    outside = np.sqrt(sum(np.maximum(qi, 0) ** 2 for qi in q))
    inside = np.minimum(np.maximum(q[0], np.maximum(q[1], q[2])), 0)
    return outside + inside - rad


def sd_box(p, lo, hi):
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    b = [(hi[i] - lo[i]) / 2 for i in range(3)]
    return sd_round_box(p, c, b, 0.0)


def sd_cyl_v(p, c, r, half):
    # cylinder whose axis is the v (left/right) axis
    d_r = np.sqrt((p[0] - c[0]) ** 2 + (p[2] - c[2]) ** 2) - r
    d_a = np.abs(p[1] - c[1]) - half
    outside = np.sqrt(np.maximum(d_r, 0) ** 2 + np.maximum(d_a, 0) ** 2)
    return outside + np.minimum(np.maximum(d_r, d_a), 0)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def model(p, wheel_phase=0.0):
    """Cartoon Beetle (closed roof). Returns (distance, material)."""
    u, v, h = p
    # big round roof dome over the cabin
    dome = sd_ellipsoid(p, (-1.5, 0, 11.0), (11.5, 8.2, 10.5))
    # lower body: short rounded tub
    lower = sd_round_box(p, (0, 0, 7.0), (17.0, 8.0, 3.2), 3.0)
    # front trunk: low rounded nose
    nose = sd_ellipsoid(p, (9.5, 0, 7.6), (9.5, 7.6, 5.0))
    # rear engine lid: long round slope
    tail = sd_ellipsoid(p, (-10.0, 0, 8.4), (9.0, 7.8, 6.8))
    body = smin(smin(smin(lower, nose, 3.0), tail, 3.0), dome, 3.5)
    # separate, bulging fenders (the beetle signature)
    fenders = None
    for fu in (11.0, -10.5):
        for fv in (7.6, -7.6):
            f = sd_ellipsoid(p, (fu, fv, 6.4), (6.4, 3.4, 5.4))
            fenders = f if fenders is None else np.minimum(fenders, f)
    body = smin(body, fenders, 1.2)
    # wheel arches
    arches = None
    for fu in (11.0, -10.5):
        a = sd_cyl_v(p, (fu, 0, 3.8), 4.9, 20)
        arches = a if arches is None else np.minimum(arches, a)
    body = np.maximum(body, -np.maximum(arches, -(h - 1.0) * 10))

    d = body
    mat = np.full(u.shape, BODY, np.int8)

    def put(dd, m):
        nonlocal d, mat
        take = dd < d
        d = np.where(take, dd, d)
        mat = np.where(take, m, mat)

    # windows: a band around the dome, just under the roof
    win = np.maximum(dome - 0.6, np.maximum(np.abs(h - 15.0) - 3.2, -(dome + 0.9)))
    # pillars between the side windows and at the corners
    pillar = (np.abs(u + 1.5) < 0.9) & (np.abs(v) > 4)
    put(np.where(pillar, 1e3, win), GLASS)
    # chrome running boards
    for rv in (8.4, -8.4):
        put(sd_round_box(p, (0.3, rv, 3.2), (5.2, 1.4, 0.5), 0.4), CHROME)
    # chrome bumpers
    for bu in (18.4, -18.4):
        put(sd_round_box(p, (bu, 0, 4.0), (0.9, 9.2, 0.9), 0.6), CHROME)
    # round headlights on the front fenders, taillights on the rear ones
    for lv in (7.8, -7.8):
        put(sd_ellipsoid(p, (15.8, lv, 8.6), (1.8, 1.8, 1.8)), LAMP)
        put(sd_ellipsoid(p, (-15.4, lv, 8.0), (1.3, 1.4, 1.8)), TAIL)
    # engine lid louvers
    for k in range(3):
        put(sd_round_box(p, (-15.2 + k * 0.2, 0, 10.4 - k * 1.1), (0.5, 3.0, 0.25), 0.2), DARK)
    # wheels: dark tyres, white rims, chrome hubcaps, a turning mark
    for wu in (11.0, -10.5):
        for wv in (8.2, -8.2):
            tyre = sd_cyl_v(p, (wu, wv, 3.8), 3.9, 1.8)
            ang = np.arctan2(h - 3.8, u - wu)
            tread = np.cos(4 * ang + wheel_phase) > 0.6
            put(np.where(tread, 1e3, tyre), TYRE)
            put(np.where(tread, tyre, 1e3), DARK)
            side = np.sign(wv)
            put(sd_cyl_v(p, (wu, wv + side * 0.5, 3.8), 2.5, 1.5), RIM)
            put(sd_cyl_v(p, (wu, wv + side * 0.9, 3.8), 1.2, 1.3), HUB)
    return d, mat


def world_to_local(direction, x, y):
    # x east, y south -> u forward, v left
    if direction == 'E':
        return x, -y
    if direction == 'W':
        return -x, y
    if direction == 'S':
        return y, x
    return -y, -x  # N


def render(direction, bob=0, wheel_phase=0.0, anchor=(44, 46), scale=1.0):
    n = 64 * SS
    # world box around the origin, in pixels
    rng = np.arange(-30, 30, 1.0 / SS)
    hr = np.arange(0, 26, 1.0 / SS)
    X, Y, H = np.meshgrid(rng, rng, hr, indexing='ij')
    U, V = world_to_local(direction, X, Y)
    d, mat = model((U / scale, V / scale, H / scale), wheel_phase)
    inside = d < 0
    # surface voxels: inside with an outside neighbour
    out = ~inside
    surf = inside & (np.roll(out, 1, 0) | np.roll(out, -1, 0) | np.roll(out, 1, 1) | np.roll(out, -1, 1) | np.roll(out, 1, 2) | np.roll(out, -1, 2))
    xs, ys, hs = X[surf], Y[surf], H[surf] + bob
    ms = mat[surf]
    # normals from the distance field (central differences in world space)
    e = 0.35
    def dist(px, py, ph):
        uu, vv = world_to_local(direction, px, py)
        return model((uu / scale, vv / scale, ph / scale), wheel_phase)[0]
    hs0 = H[surf]
    nx = dist(xs + e, ys, hs0) - dist(xs - e, ys, hs0)
    ny = dist(xs, ys + e, hs0) - dist(xs, ys - e, hs0)
    nh = dist(xs, ys, hs0 + e) - dist(xs, ys, hs0 - e)
    nl = np.sqrt(nx ** 2 + ny ** 2 + nh ** 2) + 1e-9
    nx, ny, nh = nx / nl, ny / nl, nh / nl
    light = np.array([-0.55, -0.45, 0.70])
    light /= np.linalg.norm(light)
    diff = np.clip(nx * light[0] + ny * light[1] + nh * light[2], 0, 1)
    # specular-ish highlight towards the viewer (south east, above)
    view = np.array([0.45, 0.45, 0.77])
    half = light + view
    half /= np.linalg.norm(half)
    spec = np.clip(nx * half[0] + ny * half[1] + nh * half[2], 0, 1) ** 18
    shade = 0.22 + 0.78 * diff + 0.55 * spec
    # projection
    sx = ((xs - hs) + anchor[0]) * SS
    sy = ((ys - hs) + anchor[1]) * SS
    depth = xs + ys + hs
    order = np.argsort(depth)
    zbuf = np.full((n, n), -1e9)
    shadebuf = np.zeros((n, n))
    matbuf = np.zeros((n, n), np.int8)
    ix = sx[order].astype(int)
    iy = sy[order].astype(int)
    ok = (ix >= 0) & (ix < n) & (iy >= 0) & (iy < n)
    for i, j, s, m in zip(ix[ok], iy[ok], shade[order][ok], ms[order][ok]):
        zbuf[j, i] = 1
        shadebuf[j, i] = s
        matbuf[j, i] = m
    # smooth the shading inside each material so tones form clean bands
    from scipy.ndimage import gaussian_filter
    sm = np.zeros_like(shadebuf)
    for m in np.unique(matbuf[matbuf > 0]):
        w = (matbuf == m).astype(float)
        num = gaussian_filter(shadebuf * w, SS * 0.9)
        den = gaussian_filter(w, SS * 0.9) + 1e-9
        sm = np.where(matbuf == m, num / den, sm)
    shadebuf = sm
    # downsample: majority material and mean shade per pixel
    img = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
    px = img.load()
    mask = np.zeros((64, 64), bool)
    pmat = np.zeros((64, 64), np.int8)
    for y in range(64):
        for x in range(64):
            blk = matbuf[y * SS:(y + 1) * SS, x * SS:(x + 1) * SS]
            filled = blk[blk > 0]
            if filled.size < SS * SS * 0.45:
                continue
            vals, counts = np.unique(filled, return_counts=True)
            m = vals[np.argmax(counts)]
            sh = shadebuf[y * SS:(y + 1) * SS, x * SS:(x + 1) * SS][blk == m].mean()
            tones = PALETTE[m]
            k = int(np.clip(round(sh * (len(tones) - 1) * 0.95), 0, len(tones) - 1))
            px[x, y] = tones[k] + (255,)
            mask[y, x] = True
            pmat[y, x] = m
    # outline: transparent pixels touching the shape become dark
    out_img = img.copy()
    op = out_img.load()
    for y in range(64):
        for x in range(64):
            if mask[y, x]:
                continue
            neigh = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= x + dx < 64 and 0 <= y + dy < 64 and mask[y + dy, x + dx]]
            if neigh:
                m = pmat[neigh[0][1], neigh[0][0]]
                op[x, y] = OUTLINE.get(m, OUTLINE_DEFAULT) + (255,)
    return out_img


if __name__ == '__main__':
    import sys
    sheet = Image.new('RGBA', (64 * 4, 64), (60, 90, 60, 255))
    for i, dname in enumerate('NESW'):
        sp = render(dname)
        sheet.alpha_composite(sp, (i * 64, 0))
    sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save(sys.argv[1] if len(sys.argv) > 1 else '/tmp/claude-0/fusca/preview.png')
