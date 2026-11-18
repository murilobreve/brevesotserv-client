# Reduz um carro (base + frente) ao tamanho medio das montarias oficiais,
# em volta do centro do personagem, e assenta as rodas no chao.
import sys, os
import numpy as np
from PIL import Image
SRC, DST, SCALE = sys.argv[1], sys.argv[2], float(sys.argv[3])
DIRS = ['norte', 'leste', 'sul', 'oeste']
# centro do personagem montado (citizen) em cada direcao e onde as rodas tocam o chao
RIDER = {'norte': (38, 36), 'leste': (30, 41), 'sul': (41, 30), 'oeste': (36, 38)}
GROUND = 62

def palette(imgs):
    cols = set()
    for im in imgs:
        a = np.array(im)
        for p in a[a[..., 3] > 0][:, :3]:
            cols.add(tuple(int(v) for v in p))
    return np.array(sorted(cols), dtype=np.int32)

def shrink(im, pal, scale, cx, cy, dy):
    big = im.resize((64 * 8, 64 * 8), Image.NEAREST)
    a = np.array(big).astype(np.float64)
    a[..., :3] *= a[..., 3:4] / 255.0
    pre = Image.fromarray(a.clip(0, 255).astype(np.uint8), 'RGBA')
    n = max(1, round(64 * scale))
    small = np.array(pre.resize((n, n), Image.BOX)).astype(np.float64)
    alpha = small[..., 3]
    rgb = np.where(alpha[..., None] > 0, small[..., :3] * 255.0 / np.maximum(alpha[..., None], 1), 0)
    keep = alpha >= 110
    flat = rgb[keep].astype(np.int32)
    d = ((flat[:, None, :] - pal[None, :, :]) ** 2).sum(-1)
    snapped = pal[d.argmin(1)]
    out = np.zeros((n, n, 4), np.uint8)
    out[keep, :3] = snapped
    out[keep, 3] = 255
    frame = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
    ox = round(cx - cx * scale)
    oy = round(cy - cy * scale) + dy
    frame.paste(Image.fromarray(out, 'RGBA'), (ox, oy), Image.fromarray(out, 'RGBA'))
    return frame

os.makedirs(DST, exist_ok=True)
for d in DIRS:
    base = Image.open(f'{SRC}/{d}.png').convert('RGBA')
    front_path = f'{SRC}/{d}_frente.png'
    front = Image.open(front_path).convert('RGBA') if os.path.exists(front_path) else None
    pal = palette([base] + ([front] if front else []))
    cx, cy = RIDER[d]
    # the wheels go back to the ground line after the shrink
    bottom = base.getbbox()[3]
    new_bottom = round(cy + (bottom - cy) * SCALE)
    dy = max(0, min(GROUND, bottom) - new_bottom)
    b2 = shrink(base, pal, SCALE, cx, cy, dy)
    b2.save(f'{DST}/{d}.png')
    if front:
        shrink(front, pal, SCALE, cx, cy, dy).save(f'{DST}/{d}_frente.png')
    print(d, 'bbox', b2.getbbox(), 'area', int((np.array(b2)[..., 3] > 0).sum()), 'dy', dy)
