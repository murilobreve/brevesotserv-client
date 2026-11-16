"""Monsters drawn with the Tibia 7.4 sprites (the old rotworm, troll, slime...).

Two steps:

  python3 build_creatures74.py extract <Tibia.dat 7.40> <Tibia.spr 7.40>
      writes art/creatures74/<folder>/<direction>_<phase>.png (64x64, the
      creature at the bottom right as the client draws it); a coloured outfit
      (the wild warrior) gets its colours painted in.

  python3 build_creatures74.py build ../../data/things/custom <server>/data/items/appearances.dat
      adds the outfits (looktypes below) to the client's custom pack - its own
      sheets sprites-creatures-*.bmp.lzma after every sprite id in use, the
      outfits in appearances-custom.dat - and registers them in the server's
      appearances.dat. Everything else in both files stays as it is, and a
      second run replaces what the first one added.

Needs pillow, numpy, protobuf and appearances_pb2 (see build_mounts.py).

In 7.4 a creature has one group: phase 0 is standing, the other phases are the
walk. Here phase 0 is the idle group and the rest the moving group.
"""
import hashlib, json, lzma, os, struct, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ART = os.path.join(HERE, 'art', 'creatures74')
DIRS = 'NESW'

# looktype here, outfit of the 7.40 Tibia.dat, folder, colours (head, body, legs, feet)
CREATURES = [
    {'id': 2910, 'old': 26, 'folder': 'rotworm', 'name': 'Ancient Rotworm'},
    {'id': 2911, 'old': 15, 'folder': 'troll', 'name': 'Ancient Troll'},
    {'id': 2912, 'old': 19, 'folder': 'slime', 'name': 'Ancient Slime'},
    {'id': 2913, 'old': 37, 'folder': 'demon_skeleton', 'name': 'Ancient Demon Skeleton'},
    {'id': 2914, 'old': 45, 'folder': 'bug', 'name': 'Ancient Bug'},
    {'id': 2915, 'old': 131, 'folder': 'wild_warrior', 'name': 'Ancient Wild Warrior', 'colors': (57, 57, 57, 57)},
]


# Their corpses, also with the 7.4 sprites (items of the 7.40 Tibia.dat, the
# three looks a corpse goes through; (id, pattern) for an item with patterns,
# such as a splash in one fluid colour). Each monster gets four items from its
# `first` id: A the fresh corpse (10 s, the corpse flag: the loot is the
# killer's), B the same body to loot (10 min), C and D rotting away (10 min
# each, then gone). The server's items.xml has them (name, container size,
# decay) - `python3 build_creatures74.py itemsxml` prints the entries.
CORPSES = [
    {'first': 60030, 'name': 'dead rotworm', 'old': (2824, 2825, 2964), 'size': 10, 'fluid': 'blood', 'weight': 8500},
    {'first': 60034, 'name': 'dead troll', 'old': (2806, 2810, 2811), 'size': 10, 'fluid': 'blood', 'weight': 60000},
    # a slime left a pool of slime: the splash in its slime colour (pattern 4)
    {'first': 60038, 'name': 'remains of a slime', 'old': ((2016, 4), (2017, 4), (2018, 4)), 'size': 10, 'fluid': 'slime', 'weight': 3000},
    {'first': 60042, 'name': 'dead bug', 'old': (2902, 2903, 2904), 'size': 6, 'fluid': 'slime', 'weight': 2000},
    {'first': 60046, 'name': 'slain demon skeleton', 'old': (2809, 2922, 2923), 'size': 10, 'fluid': None, 'weight': 40000},
    {'first': 60050, 'name': 'dead human', 'old': (3058, 3059, 3060), 'size': 10, 'fluid': 'blood', 'weight': 80000},
]
# stage: (look 0-2, seconds, container, corpse flag)
STAGES = [(0, 10, True, True), (0, 600, True, False), (1, 600, False, False), (2, 600, False, False)]


def corpse_png(old, pattern):
    return f'{old}_{pattern}.png' if pattern else f'{old}.png'


def items_xml():
    out = []
    for c in CORPSES:
        for k, (_look, seconds, container, _corpse) in enumerate(STAGES):
            attrs = []
            if c['fluid'] and k < 2:
                attrs.append(('fluidsource', c['fluid']))
            attrs.append(('duration', seconds))
            attrs.append(('decayTo', c['first'] + k + 1 if k + 1 < len(STAGES) else 0))
            if container:
                attrs.append(('containersize', c['size']))
                attrs.append(('weight', c['weight']))
            out.append('\t<item id="%d" article="a" name="%s">' % (c['first'] + k, c['name']))
            out += ['\t\t<attribute key="%s" value="%s"/>' % kv for kv in attrs]
            out.append('\t</item>')
    return '\n'.join(out)


# ---------------------------------------------------------------- extract
PARAM_740 = {0: 2, 7: 2, 8: 2, 16: 4, 19: 2, 21: 4, 22: 2}  # flag -> bytes of its value


def load_dat(path):
    d = open(path, 'rb').read()
    p = 4
    counts = struct.unpack_from('<4H', d, p)
    p += 8
    things = {}
    for tid in range(100, sum(counts) + 1):
        while True:
            f = d[p]
            p += 1
            if f == 0xFF:
                break
            p += PARAM_740.get(f, 0)
        w, h = d[p], d[p + 1]
        p += 2
        if w > 1 or h > 1:
            p += 1
        layers, px, py, ph = d[p:p + 4]
        p += 4
        n = w * h * layers * px * py * ph
        things[tid] = dict(w=w, h=h, layers=layers, px=px, py=py, ph=ph, spr=struct.unpack_from('<%dH' % n, d, p))
        p += 2 * n
    if p != len(d):
        raise ValueError('not a 7.40 Tibia.dat')
    return counts[0], things


class Spr:
    def __init__(self, path):
        self.d = open(path, 'rb').read()
        self.n = struct.unpack_from('<H', self.d, 4)[0]

    def get(self, i):
        img = np.zeros((32, 32, 4), np.uint8)
        if i == 0 or i > self.n:
            return img
        a = struct.unpack_from('<I', self.d, 6 + (i - 1) * 4)[0]
        if not a:
            return img
        d = self.d
        p, end, idx = a + 5, a + 5 + (d[a + 3] | d[a + 4] << 8), 0
        flat = img.reshape(-1, 4)
        while p < end:
            t, c = struct.unpack_from('<HH', d, p)
            p += 4
            idx += t
            for _ in range(c):
                flat[idx] = (d[p], d[p + 1], d[p + 2], 255)
                p += 3
                idx += 1
        return img


def outfit_color(color):
    """Tibia's outfit palette (19 hues x 7 shades)"""
    steps = 19
    if color >= steps * 7:
        color = 0
    if color % steps:
        hue = (color % steps) / 18.0
        sat, val = {0: (0.25, 1.0), 1: (0.25, 0.75), 2: (0.5, 0.75), 3: (0.667, 0.75),
                    4: (1.0, 1.0), 5: (1.0, 0.75), 6: (1.0, 0.5)}[color // steps]
    else:
        hue, sat, val = 0, 0, 1 - (color // steps) / 7.0
    if val == 0:
        return (0, 0, 0)
    if sat == 0:
        v = int(val * 255)
        return (v, v, v)
    low = val * (1 - sat)
    if hue < 1 / 6:
        r, b = val, low; g = b + (val - b) * 6 * hue
    elif hue < 2 / 6:
        g, b = val, low; r = g - (val - b) * (6 * hue - 1)
    elif hue < 3 / 6:
        g, r = val, low; b = r + (val - r) * (6 * hue - 2)
    elif hue < 4 / 6:
        b, r = val, low; g = b - (val - r) * (6 * hue - 3)
    elif hue < 5 / 6:
        b, g = val, low; r = g + (val - g) * (6 * hue - 4)
    else:
        r, g = val, low; b = r - (val - g) * (6 * hue - 5)
    return (int(r * 255), int(g * 255), int(b * 255))


def frame(t, spr, d, phase, colors):
    out = np.zeros((64, 64, 4), np.uint8)
    for hh in range(t['h']):
        for ww in range(t['w']):
            def tile(layer):
                idx = ((((phase * t['py']) * t['px'] + d) * t['layers'] + layer) * t['h'] + hh) * t['w'] + ww
                return spr.get(t['spr'][idx])
            base = tile(0).astype(np.float32)
            if colors and t['layers'] > 1:
                mask = tile(1)
                for key, c in zip([(255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255)], colors):
                    sel = (mask[..., 0] == key[0]) & (mask[..., 1] == key[1]) & (mask[..., 2] == key[2]) & (mask[..., 3] > 0)
                    base[sel, :3] = base[sel, :3] * np.array(outfit_color(c), np.float32) / 255
            y, x = 32 - hh * 32, 32 - ww * 32
            region = out[y:y + 32, x:x + 32]
            solid = base[..., 3] > 0
            region[solid] = base[solid].astype(np.uint8)
    return Image.fromarray(out)


def extract(dat, spr_path):
    items, things = load_dat(dat)
    spr = Spr(spr_path)
    for c in CREATURES:
        t = things[items + c['old']]
        folder = os.path.join(ART, c['folder'])
        os.makedirs(folder, exist_ok=True)
        for f in os.listdir(folder):
            os.remove(os.path.join(folder, f))
        for phase in range(t['ph']):
            for d in range(4):
                frame(t, spr, d, phase, c.get('colors')).save(os.path.join(folder, f'{DIRS[d]}_{phase}.png'))
        print(c['folder'], t['ph'], 'phases')
    folder = os.path.join(ART, 'corpses')
    os.makedirs(folder, exist_ok=True)
    for c in CORPSES:
        for old in c['old']:
            old, pattern = old if isinstance(old, tuple) else (old, 0)
            t = things[old]
            px, py = pattern % t['px'], pattern // t['px']
            tile = spr.get(t['spr'][(py * t['px'] + px) * t['layers'] * t['w'] * t['h']])
            Image.fromarray(tile).save(os.path.join(folder, corpse_png(old, pattern)))


# ---------------------------------------------------------------- build
# the sheet format of build_mounts.py (CIP's LZMA-wrapped BMP)
def sheet_bytes(chunk, size=64):
    sheet = Image.new('RGBA', (384, 384), (255, 0, 255, 255))
    cols = 384 // size
    for i, f in enumerate(chunk):
        x, y = (i % cols) * size, (i // cols) * size
        region = Image.new('RGBA', (size, size), (255, 0, 255, 255))
        region.paste(f, (0, 0), f)
        sheet.paste(region, (x, y))
    return sheet_bytes_from(sheet)


def sheet_bytes_from(sheet):
    # BMP (32 bit BGRA, bottom-up) wrapped in CIP's LZMA container
    w, h = sheet.size
    arr = np.array(sheet.convert('RGBA'))
    # empty space is magenta; also make it fully transparent, since the game
    # client keys out magenta but map editors only look at the alpha channel
    key = (arr[:, :, 0] == 255) & (arr[:, :, 1] == 0) & (arr[:, :, 2] == 255)
    arr[key, 3] = 0
    pixels = arr[::-1, :, [2, 1, 0, 3]].tobytes()
    bmp = b'BM' + struct.pack('<IHHI', 54 + len(pixels), 0, 0, 54)
    bmp += struct.pack('<IiiHHIIiiII', 40, w, h, 1, 32, 0, len(pixels), 2835, 2835, 0, 0)
    bmp += pixels
    alone = lzma.compress(bmp, format=lzma.FORMAT_ALONE, filters=[{'id': lzma.FILTER_LZMA1, 'preset': 9, 'dict_size': 1 << 24}])
    # alone = props(1) dict(4) size(8) data; CIP keeps props+dict, writes its own sizes
    props, dict_size, data = alone[0:1], alone[1:5], alone[13:]
    body = props + dict_size + struct.pack('<Q', len(bmp)) + data
    n = len(body)
    size7 = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        size7.append(b | (0x80 if n else 0))
        if not n:
            break
    head = bytes([0x70, 0x0A, 0xFA, 0x80, 0x24]) + bytes(size7)
    cip = bytes(32 - len(head)) + head + body
    return cip


def bbox(img):
    b = img.getbbox() or (0, 0, 1, 1)
    return b[0], b[1], b[2] - b[0], b[3] - b[1]


def build(client_dir, server_dat):
    import appearances_pb2 as A

    catalog_path = os.path.join(client_dir, 'catalog-content.json')
    catalog = json.load(open(catalog_path))
    old = [e for e in catalog if e.get('type') == 'sprite' and e['file'].startswith('sprites-creatures-')]
    catalog = [e for e in catalog if e not in old]
    for e in old:
        if os.path.exists(os.path.join(client_dir, e['file'])):
            os.remove(os.path.join(client_dir, e['file']))
    first = max(e.get('lastspriteid', 0) for e in catalog) + 1

    frames, outfits = [], []
    for c in CREATURES:
        folder = os.path.join(ART, c['folder'])
        phases = len([f for f in os.listdir(folder) if f.startswith('N_')])
        imgs = [[Image.open(os.path.join(folder, f'{d}_{p}.png')).convert('RGBA') for d in DIRS] for p in range(phases)]
        o = A.Appearance()
        o.id = c['id']
        o.name = c['name']
        walk = list(range(1, phases)) if phases > 1 else [0]
        for gid, (fixed, group) in enumerate([(A.FIXED_FRAME_GROUP_OUTFIT_IDLE, [0]), (A.FIXED_FRAME_GROUP_OUTFIT_MOVING, walk)]):
            fg = o.frame_group.add()
            fg.fixed_frame_group = fixed
            fg.id = gid
            si = fg.sprite_info
            si.pattern_width, si.pattern_height, si.pattern_depth, si.layers = 4, 1, 1, 1
            for p in group:
                for d in range(4):
                    si.sprite_id.append(first + len(frames))
                    frames.append(imgs[p][d])
            if len(group) > 1:
                si.animation.synchronized = False
                si.animation.loop_type = A.ANIMATION_LOOP_TYPE_INFINITE
                for _ in group:
                    ph = si.animation.sprite_phase.add()
                    ph.duration_min = ph.duration_max = 150
            si.bounding_square = 64
            si.is_opaque = False
            for d in range(4):
                x, y, w, h = bbox(imgs[group[0]][d])
                bb = si.bounding_box_per_direction.add()
                bb.x, bb.y, bb.width, bb.height = x, y, w, h
        o.flags.SetInParent()
        outfits.append(o)

    # the corpses: 32x32 sprites after the creatures'
    small = []
    objects = []
    first_small = first + len(frames)
    for c in CORPSES:
        looks = [first_small + len(small) + i for i in range(3)]
        small += [Image.open(os.path.join(ART, 'corpses', corpse_png(*(old if isinstance(old, tuple) else (old, 0))))).convert('RGBA') for old in c['old']]
        for k, (look, _seconds, container, corpse) in enumerate(STAGES):
            o = A.Appearance()
            o.id = c['first'] + k
            o.name = c['name']
            si = o.frame_group.add().sprite_info
            si.pattern_width = si.pattern_height = si.pattern_depth = si.layers = 1
            si.sprite_id.append(looks[look])
            si.is_opaque = False
            x, y, w, h = bbox(small[looks[look] - first_small])
            bb = si.bounding_box_per_direction.add()
            bb.x, bb.y, bb.width, bb.height = x, y, w, h
            o.flags.SetInParent()
            if container:
                o.flags.container = True
                o.flags.usable = True
            if corpse:
                o.flags.forceuse = True
                o.flags.unmove = True
                o.flags.corpse = True
            objects.append(o)

    entries = []
    for i in range(0, len(small), 144):
        cip = sheet_bytes(small[i:i + 144], 32)
        name = 'sprites-creatures-corpses-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma'
        with open(os.path.join(client_dir, name), 'wb') as f:
            f.write(cip)
        entries.append({'type': 'sprite', 'file': name, 'spritetype': 0, 'firstspriteid': first_small + i,
                        'lastspriteid': first_small + min(i + 144, len(small)) - 1, 'area': 32})
    for i in range(0, len(frames), 36):
        cip = sheet_bytes(frames[i:i + 36])
        name = 'sprites-creatures-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma'
        with open(os.path.join(client_dir, name), 'wb') as f:
            f.write(cip)
        entries.append({'type': 'sprite', 'file': name, 'spritetype': 3, 'firstspriteid': first + i,
                        'lastspriteid': first + min(i + 36, len(frames)) - 1, 'area': 64})
    with open(catalog_path, 'w') as f:
        json.dump(catalog + entries, f, indent=2)

    ids = {c['id'] for c in CREATURES}
    object_ids = {o.id for o in objects}
    for path in [os.path.join(client_dir, 'appearances-custom.dat'), server_dat]:
        a = A.Appearances()
        a.ParseFromString(open(path, 'rb').read())
        keep = [x for x in a.outfit if x.id not in ids]
        del a.outfit[:]
        a.outfit.extend(keep)
        a.outfit.extend(outfits)
        keep = [x for x in a.object if x.id not in object_ids]
        del a.object[:]
        a.object.extend(keep)
        a.object.extend(objects)
        with open(path, 'wb') as f:
            f.write(a.SerializeToString())
    print('ok', len(outfits), 'outfits,', len(objects), 'corpse items,', len(frames) + len(small), 'sprites from', first, ',', ', '.join(e['file'] for e in entries))


if __name__ == '__main__':
    if sys.argv[1] == 'extract':
        extract(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'itemsxml':
        print(items_xml())
    else:
        build(sys.argv[2], sys.argv[3])
