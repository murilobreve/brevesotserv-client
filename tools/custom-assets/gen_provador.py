"""Pictures for the website's Provador (dressing room): the set outfits' body
standing in the 4 directions, male and female, with no armour (plain linen
clothes) and, for every armour piece of a set, a layer with only that part
of the body in the item's colours. The page stacks the body and the layers
of the pieces that are on, so a piece taken off shows the clothes under it.

Usage (pillow, numpy, protobuf; the server's tools/render_sprites.py):
  python3 gen_provador.py ../../data/things/1525 /path/to/brevesotserv/tools OUT_DIR

Writes OUT_DIR/<sex>/base_<dir>.png, OUT_DIR/<sex>/<item id>_<dir>.png and
OUT_DIR/provador.json (the sets, their pieces and the hands' positions).
"""
import json, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROVADOR_OUT = sys.argv[3]
sys.argv = sys.argv[:3]
# the drawing functions of the set outfits (everything before their main loop)
src = open(os.path.join(HERE, 'gen_set_outfits.py')).read()
exec(compile(src[:src.index('for name, looks, addons, colors, items, how, *rest in SETS:')], 'gen_set_outfits', 'exec'))

DIRS = ['north', 'east', 'south', 'west']
SEXES = {'male': BASE[0], 'female': BASE[1]}
# the sets on the Provador: key, name, closed helmet, helmet/armour/legs/boots, weapon, shield
PROVADOR_SETS = [
    ('dragon_scale', 'Dragon Scale Set', True, (3400, 3386, 3363, 10201), 7402, 3416),
]
SLOTS = ['head', 'body', 'legs', 'feet']
# plain linen clothes under the armour, dark to light
LINEN = np.array([[46, 34, 24], [74, 56, 38], [102, 80, 56], [128, 104, 74], [152, 128, 94], [178, 154, 118], [204, 182, 146]], float)


def item_name(iid):
    n = r.objects[iid].name
    n = n.decode('latin-1') if isinstance(n, bytes) else n
    return ' '.join(w if w in ('of', 'the') else w[:1].upper() + w[1:] for w in n.split())


def idle(look):
    """the standing frames (column 0) of the 4 directions on foot: 64x256"""
    a, masked = frames(look, 0, (82, 82, 82, 82))
    return a[:256, :64].copy(), masked[:256, :64].copy()


def skin_of(a, masked):
    on = a[..., 3] > 0
    h = hsv(a[..., :3])
    return on & ~masked & (h[..., 0] > 0.02) & (h[..., 0] < 0.11) & (h[..., 1] > 0.15) & (h[..., 1] < 0.6) & (h[..., 2] > 0.55)


def hands(a, part, skin):
    """where each direction holds the weapon and the shield (pixels in the
    64x64 frame): the hands' skin when it shows, else the sides of the body
    at waist height. From the north and the west the weapon hand is on the
    right of the picture, from the south and the east on the left."""
    out = {}
    for d in range(4):
        sub = a[d * 64:(d + 1) * 64]
        ys, xs = np.nonzero(sub[..., 3] > 0)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        waist = y0 + (y1 - y0) * 0.55
        left, right = [int(x0 + 4), int(waist)], [int(x1 - 9), int(waist - 2)]
        hs = (skin & (part == 2))[d * 64:(d + 1) * 64]
        hy, hx = np.nonzero(hs)
        if len(hx):
            left = [int(hx.min()), int(hy[hx.argmin()])]
        weapon, shield = (right, left) if DIRS[d] in ('north', 'west') else (left, right)
        out[DIRS[d]] = {'weapon': weapon, 'shield': shield}
    return out


def main():
    os.makedirs(PROVADOR_OUT, exist_ok=True)
    manifest = {'sets': [], 'hands': {}}
    for sex, look in SEXES.items():
        os.makedirs(os.path.join(PROVADOR_OUT, sex), exist_ok=True)
        a, masked = idle(look)
        part = body_parts(a, head_mask(look))
        on = a[..., 3] > 0
        L = lum(a[..., :3])
        dark = on & (hsv(a[..., :3])[..., 2] < 0.14)
        skin = skin_of(a, masked)
        # no armour: linen clothes, dark hair on the head
        base = a.copy()
        cloth = on & ~dark & ~skin & (part >= 2)
        base[cloth, :3] = match(L[cloth], LINEN)
        hair = on & ~dark & ~skin & (part == 1)
        base[hair, :3] = np.stack([L[hair] * 0.45 + 20, L[hair] * 0.3 + 12, L[hair] * 0.18 + 6], -1)
        for d in range(4):
            Image.fromarray(base[d * 64:(d + 1) * 64].astype(np.uint8)).save(os.path.join(PROVADOR_OUT, sex, 'base_%s.png' % DIRS[d]))
        manifest['hands'][sex] = hands(a, part, skin)
        for key, name, closed, items, weapon, shield in PROVADOR_SETS:
            full = faithful(a, masked, look, items, closed)
            face = skin & grow(part == 1, 3) & ~grow(part >= 3, 1) if closed else np.zeros_like(skin)
            for k, iid in enumerate(items):
                mine = on & ((part == k + 1) | (face if k == 0 else False))
                if k > 0:
                    mine &= ~face
                layer = np.zeros_like(full)
                layer[mine] = full[mine]
                for d in range(4):
                    Image.fromarray(layer[d * 64:(d + 1) * 64].astype(np.uint8)).save(os.path.join(PROVADOR_OUT, sex, '%d_%s.png' % (iid, DIRS[d])))
    for key, name, closed, items, weapon, shield in PROVADOR_SETS:
        for iid in (weapon, shield):
            icon = r.item(iid).convert('RGBA')
            icon.crop(icon.getbbox()).save(os.path.join(PROVADOR_OUT, 'item_%d.png' % iid))
        pieces = [{'slot': SLOTS[k], 'id': iid, 'name': item_name(iid)} for k, iid in enumerate(items)]
        pieces.append({'slot': 'weapon', 'id': weapon, 'name': item_name(weapon)})
        pieces.append({'slot': 'shield', 'id': shield, 'name': item_name(shield)})
        manifest['sets'].append({'key': key, 'name': name, 'pieces': pieces})
    json.dump(manifest, open(os.path.join(PROVADOR_OUT, 'provador.json'), 'w'), indent=1)
    print('ok', PROVADOR_OUT)


main()
