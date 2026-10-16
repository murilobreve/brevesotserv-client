"""Builds the custom asset pack with the server's own mounts (cars) and items
(the ruby coin).

Usage (needs numpy, scipy, pillow, protobuf):
  protoc --python_out=. -I ../../src/protobuf appearances.proto
  python3 build_mounts.py ../../data/things/custom <server>/data/items/appearances.dat


Writes data/things/custom/ for the client (catalog-content.json, the sprite
sheets, appearances-custom.dat) and adds the outfits to the server's
data/items/appearances.dat (the server only lets a mount use a registered
looktype, and reads the items' flags from there).
"""
import json, lzma, struct, sys, hashlib
import numpy as np
from PIL import Image
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appearances_pb2 as A  # protoc --python_out=. ../../src/protobuf/appearances.proto

FIRST_SPRITE = 1_000_001  # far above the official sprite ids
CLIENT_DIR = sys.argv[1]
SERVER_DAT = sys.argv[2]
DIRS = 'NESW'
NAMES = {'N': 'norte', 'E': 'leste', 'S': 'sul', 'W': 'oeste'}
PHASES = 8
BOBS = [0, 0, 1, 1, 0, 0, 1, 1]
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'art')

# Each car is art/<folder>/<direction>.png, one 64x64 frame per direction in
# Tibia's angle. It goes in two layers: y pattern 0 is the whole car, under
# the rider; y pattern 1 is the part from `cut` down (doors, hood, rear), which
# the client draws over the rider so he sits in the car. `offset` moves the
# art so the seat is under the rider; a cut of 64 leaves the front layer empty
# (the cars are open with a saddle, the rider sits on top). Outfit ids are far
# above the official.
MOUNTS = [
    {'id': 2900, 'name': 'Blue Fusca', 'folder': 'fusca',
     'offset': {'N': (0, 0), 'E': (0, 0), 'S': (0, 0), 'W': (0, 0)},
     'cut': {'N': 64, 'E': 64, 'S': 64, 'W': 64}},
    {'id': 2901, 'name': 'Uno with Ladder', 'folder': 'uno',
     'offset': {'N': (0, 0), 'E': (0, 0), 'S': (0, 0), 'W': (0, 0)},
     'cut': {'N': 64, 'E': 64, 'S': 64, 'W': 64}},
    {'id': 2902, 'name': 'Gol Bolinha', 'folder': 'gol',
     'offset': {'N': (0, 0), 'E': (0, 0), 'S': (0, 0), 'W': (0, 0)},
     'cut': {'N': 64, 'E': 64, 'S': 64, 'W': 64}},
]
FRAMES_PER_MOUNT = 8 * (1 + PHASES)

# Stackable items: art/<folder>/0.png .. 7.png, 32x32, one per stack size
# (1, 2, 3, 4, 5, 6-10, 11-25, 26+), drawn like the official coins.
COINS = [
    {'id': 60000, 'name': 'ruby coin', 'folder': 'ruby_coin',
     # the crystal coin's boxes: the art is the crystal coin recoloured
     'boxes': [(1, 11, 30, 15), (5, 7, 24, 16), (2, 7, 29, 19), (1, 6, 31, 22)]},
]


# Grounds (art_obsidian.py draws them): art/<folder>/<i>.png, 32x32, in the
# order of their pattern (x fastest), then the animation phases. The flags are
# the white temple marble's (id 409): walkable at speed 100, fills the tile.
GROUNDS = [
    {'id': 60001, 'name': 'obsidian floor', 'folder': 'obsidian_floor', 'pattern': (4, 4), 'phases': 1},
    {'id': 60002, 'name': 'inlaid obsidian floor', 'folder': 'obsidian_inlay', 'pattern': (4, 2), 'phases': 1},
    # the arrival point of the temple: a soft violet light like the old flame slab
    {'id': 60003, 'name': 'obsidian rune', 'folder': 'obsidian_rune', 'pattern': (1, 1), 'phases': 4, 'duration': 450,
     'light': (3, 125)},
    # city streets, from the obsidian city sprite pack (art/source/obsidian-city-sprites)
    {'id': 60004, 'name': 'obsidian paving', 'folder': 'obsidian_city_paving', 'pattern': (4, 4), 'phases': 1},
    {'id': 60005, 'name': 'obsidian cobbles', 'folder': 'obsidian_irregular_paving', 'pattern': (4, 4), 'phases': 1},
    # the TP rooms of the temple, from the continuous temple pack (art/source/pisos-templo-continuo)
    {'id': 60006, 'name': 'obsidian flagstones', 'folder': 'obsidian_flagstones', 'pattern': (4, 4), 'phases': 1},
    {'id': 60007, 'name': 'obsidian bricks', 'folder': 'obsidian_bricks', 'pattern': (4, 4), 'phases': 1},
]


def make_ground(ground, first):
    o = A.Appearance()
    o.id = ground['id']
    o.name = ground['name']
    fg = o.frame_group.add()
    si = fg.sprite_info
    pw, ph = ground['pattern']
    si.pattern_width, si.pattern_height, si.pattern_depth, si.layers = pw, ph, 1, 1
    count = pw * ph * ground['phases']
    si.sprite_id.extend(range(first, first + count))
    if ground['phases'] > 1:
        si.animation.synchronized = True
        si.animation.loop_type = A.ANIMATION_LOOP_TYPE_INFINITE
        for _ in range(ground['phases']):
            phase = si.animation.sprite_phase.add()
            phase.duration_min = phase.duration_max = ground.get('duration', 300)
    si.is_opaque = True
    o.flags.bank.waypoints = 100
    o.flags.unmove = True
    o.flags.fullbank = True
    o.flags.automap.color = 129
    if 'light' in ground:
        o.flags.light.brightness, o.flags.light.color = ground['light']
    return o, count


# Walls and counters (art/obsidian_walls, from the obsidiana-nativa pack): the
# Tibia pieces recoloured pixel for pixel, so each copies the flags of the
# piece it was drawn from (blocking, sight, hooks, height). Several files make
# a pattern: the client picks the variation by the tile position.
REF_ITEMS = [
    {'id': 60010, 'name': 'obsidian wall', 'ref': 49282, 'files': ['horizontal_01', 'horizontal_02', 'horizontal_03'], 'pattern': (3, 1)},
    {'id': 60011, 'name': 'obsidian wall', 'ref': 49288, 'files': ['vertical_01', 'vertical_02', 'vertical_03'], 'pattern': (1, 3)},
    {'id': 60012, 'name': 'obsidian wall', 'ref': 49294, 'files': ['canto']},
    {'id': 60013, 'name': 'obsidian pillar', 'ref': 49297, 'files': ['ponta']},
    {'id': 60014, 'name': 'low obsidian wall', 'ref': 49298, 'files': ['horizontal_baixo']},
    {'id': 60015, 'name': 'low obsidian wall', 'ref': 49299, 'files': ['vertical_baixo']},
    {'id': 60016, 'name': 'obsidian window', 'ref': 49655, 'files': ['janela_horizontal']},
    {'id': 60017, 'name': 'obsidian counter', 'ref': 2317, 'files': ['balcao_vertical']},
    {'id': 60018, 'name': 'obsidian counter', 'ref': 2318, 'files': ['balcao_horizontal']},
    {'id': 60019, 'name': 'obsidian counter', 'ref': 2320, 'files': ['balcao_ponta_a']},
    {'id': 60020, 'name': 'obsidian counter', 'ref': 2321, 'files': ['balcao_ponta_b']},
]
SPRITE_TYPES = {(32, 32): 0, (32, 64): 1, (64, 32): 2, (64, 64): 3}


def make_ref_item(item, ref, sprite_ids):
    o = A.Appearance()
    o.CopyFrom(ref)
    o.id = item['id']
    o.name = item['name']
    si = o.frame_group[0].sprite_info
    del si.sprite_id[:]
    si.sprite_id.extend(sprite_ids)
    pw, ph = item.get('pattern', (1, 1))
    si.pattern_width, si.pattern_height, si.pattern_depth, si.layers = pw, ph, 1, 1
    return o


def car(mount, d, bob=0):
    art = np.array(Image.open(os.path.join(ART, mount['folder'], NAMES[d] + '.png')).convert('RGBA'))
    back, front = np.zeros_like(art), np.zeros_like(art)
    dx, dy = mount['offset'][d][0], mount['offset'][d][1] - bob
    for y, x in np.argwhere(art[..., 3] > 0):
        X, Y = x + dx, y + dy
        if 0 <= X < 64 and 0 <= Y < 64:
            back[Y, X] = art[y, x]
            if y >= mount['cut'][d]:
                front[Y, X] = art[y, x]
    return [Image.fromarray(back), Image.fromarray(front)]


def mount_frames(mount):
    """idle (y0: N E S W, y1: N E S W), then the same for each moving phase"""
    frames = []
    for bob in [0] + BOBS:
        layers = {d: car(mount, d, bob) for d in DIRS}
        for y in range(2):
            for d in DIRS:
                frames.append(layers[d][y])
    if len(frames) != FRAMES_PER_MOUNT:
        raise ValueError(f'{len(frames)} frames, expected {FRAMES_PER_MOUNT}')
    return frames


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


def make_outfit(mount, frames, first):
    o = A.Appearance()
    o.id = mount['id']
    o.name = mount['name']
    for group, (fixed, start, phases) in enumerate([(A.FIXED_FRAME_GROUP_OUTFIT_IDLE, 0, 1), (A.FIXED_FRAME_GROUP_OUTFIT_MOVING, 8, PHASES)]):
        fg = o.frame_group.add()
        fg.fixed_frame_group = fixed
        fg.id = group
        si = fg.sprite_info
        si.pattern_width, si.pattern_height, si.pattern_depth, si.layers = 4, 2, 1, 1
        for i in range(phases * 8):
            si.sprite_id.append(first + start + i)
        if phases > 1:
            si.animation.synchronized = False
            si.animation.loop_type = A.ANIMATION_LOOP_TYPE_INFINITE
            for _ in range(phases):
                ph = si.animation.sprite_phase.add()
                ph.duration_min = ph.duration_max = 150
        si.bounding_square = 50
        si.is_opaque = False
        for d in range(4):
            whole = frames[start + d].copy()
            whole.alpha_composite(frames[start + 4 + d])
            x, y, bw, bh = bbox(whole)
            bb = si.bounding_box_per_direction.add()
            bb.x, bb.y, bb.width, bb.height = x, y, bw, bh
    o.flags.SetInParent()
    return o


def make_coin(coin, first):
    o = A.Appearance()
    o.id = coin['id']
    o.name = coin['name']
    fg = o.frame_group.add()
    si = fg.sprite_info
    si.pattern_width, si.pattern_height, si.pattern_depth, si.layers = 4, 2, 1, 1
    si.sprite_id.extend(range(first, first + 8))
    si.is_opaque = False
    for x, y, w, h in coin['boxes']:
        bb = si.bounding_box_per_direction.add()
        bb.x, bb.y, bb.width, bb.height = x, y, w, h
    o.flags.cumulative = True
    o.flags.usable = True
    o.flags.multiuse = True
    o.flags.take = True
    return o


frames, outfits = [], []
for mount in MOUNTS:
    mf = mount_frames(mount)
    outfits.append(make_outfit(mount, mf, FIRST_SPRITE + len(frames)))
    frames += mf

sheets = []
for first in range(0, len(frames), 36):
    cip = sheet_bytes(frames[first:first + 36])
    sheets.append(('sprites-mounts-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma', cip, FIRST_SPRITE + first, FIRST_SPRITE + min(first + 36, len(frames)) - 1))

# the items go on 32x32 sheets after the mount sprites
small, objects = [], []
first_small = FIRST_SPRITE + len(frames)
for coin in COINS:
    objects.append(make_coin(coin, first_small + len(small)))
    small += [Image.open(os.path.join(ART, coin['folder'], f'{i}.png')).convert('RGBA') for i in range(8)]
small_sheets = []
for first in range(0, len(small), 144):
    cip = sheet_bytes(small[first:first + 144], 32)
    small_sheets.append(('sprites-items-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma', cip, first_small + first, first_small + min(first + 144, len(small)) - 1))

# effects added to the pack by hand (the Last Stand text) are kept as they
# are: their appearances, sheet files and sprite ids
old_catalog = []
if os.path.exists(os.path.join(CLIENT_DIR, 'catalog-content.json')):
    old_catalog = json.load(open(os.path.join(CLIENT_DIR, 'catalog-content.json')))
kept_sheets = [e for e in old_catalog if e.get('type') == 'sprite' and e['file'].startswith('sprites-effects-')]
old_custom = A.Appearances()
if os.path.exists(os.path.join(CLIENT_DIR, 'appearances-custom.dat')):
    old_custom.ParseFromString(open(os.path.join(CLIENT_DIR, 'appearances-custom.dat'), 'rb').read())

# grounds go on their own 32x32 sheet after every sprite id in use
last_used = max([last for _n, _c, _f, last in sheets + small_sheets] + [e['lastspriteid'] for e in kept_sheets])
ground_tiles = []
for ground in GROUNDS:
    obj, count = make_ground(ground, last_used + 1 + len(ground_tiles))
    objects.append(obj)
    ground_tiles += [Image.open(os.path.join(ART, ground['folder'], f'{i}.png')).convert('RGBA') for i in range(count)]
for first in range(0, len(ground_tiles), 144):
    cip = sheet_bytes(ground_tiles[first:first + 144], 32)
    small_sheets.append(('sprites-grounds-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma', cip, last_used + 1 + first, last_used + min(first + 144, len(ground_tiles))))

# walls and counters: one sheet per sprite size, after the grounds
srv_ref = A.Appearances()
with open(SERVER_DAT, 'rb') as f:
    srv_ref.ParseFromString(f.read())
refs = {o.id: o for o in srv_ref.object}
next_id = max([last for _n, _c, _f, last in sheets + small_sheets] + [e['lastspriteid'] for e in kept_sheets]) + 1
by_size = {}
for item in REF_ITEMS:
    imgs = [Image.open(os.path.join(ART, 'obsidian_walls', f + '.png')).convert('RGBA') for f in item['files']]
    by_size.setdefault(imgs[0].size, []).append((item, imgs))
sized_sheets = []
for size, entries in sorted(by_size.items()):
    w, h = size
    per_sheet = (384 // w) * (384 // h)
    frames_here = []
    for item, imgs in entries:
        ids = list(range(next_id + len(frames_here), next_id + len(frames_here) + len(imgs)))
        objects.append(make_ref_item(item, refs[item['ref']], ids))
        frames_here += imgs
    for first in range(0, len(frames_here), per_sheet):
        chunk = frames_here[first:first + per_sheet]
        sheet = Image.new('RGBA', (384, 384), (255, 0, 255, 255))
        cols = 384 // w
        for k, f in enumerate(chunk):
            region = Image.new('RGBA', (w, h), (255, 0, 255, 255))
            region.paste(f, (0, 0), f)
            sheet.paste(region, ((k % cols) * w, (k // cols) * h))
        cip = sheet_bytes_from(sheet)
        sized_sheets.append(('sprites-walls-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma', cip,
                             next_id + first, next_id + first + len(chunk) - 1, SPRITE_TYPES[size]))
    next_id += len(frames_here)

custom = A.Appearances()
custom.effect.extend(old_custom.effect)
custom.outfit.extend(outfits)
custom.object.extend(objects)
dat_name = 'appearances-custom.dat'

os.makedirs(CLIENT_DIR, exist_ok=True)
for f in os.listdir(CLIENT_DIR):
    if f.startswith('sprites-') and not f.startswith('sprites-effects-'):
        os.remove(os.path.join(CLIENT_DIR, f))
for name, cip, _first, _last, _t in sized_sheets:
    with open(os.path.join(CLIENT_DIR, name), 'wb') as f:
        f.write(cip)
for name, cip, _first, _last in sheets + small_sheets:
    with open(os.path.join(CLIENT_DIR, name), 'wb') as f:
        f.write(cip)
with open(os.path.join(CLIENT_DIR, dat_name), 'wb') as f:
    f.write(custom.SerializeToString())
with open(os.path.join(CLIENT_DIR, 'catalog-content.json'), 'w') as f:
    json.dump([{'type': 'appearances', 'file': dat_name}] + [
        {'type': 'sprite', 'file': name, 'spritetype': 3, 'firstspriteid': first, 'lastspriteid': last, 'area': 64}
        for name, cip, first, last in sheets
    ] + [
        {'type': 'sprite', 'file': name, 'spritetype': 0, 'firstspriteid': first, 'lastspriteid': last, 'area': 32}
        for name, cip, first, last in small_sheets
    ] + [
        {'type': 'sprite', 'file': name, 'spritetype': t, 'firstspriteid': first, 'lastspriteid': last, 'area': 64}
        for name, cip, first, last, t in sized_sheets
    ] + kept_sheets, f, indent=2)

# server: register the looktypes (replace older copies of them)
srv = A.Appearances()
with open(SERVER_DAT, 'rb') as f:
    srv.ParseFromString(f.read())
ids = {m['id'] for m in MOUNTS}
keep = [x for x in srv.outfit if x.id not in ids]
del srv.outfit[:]
srv.outfit.extend(keep)
srv.outfit.extend(outfits)
ids = {c['id'] for c in COINS} | {g['id'] for g in GROUNDS} | {r['id'] for r in REF_ITEMS}
keep = [x for x in srv.object if x.id not in ids]
del srv.object[:]
srv.object.extend(keep)
srv.object.extend(objects)
with open(SERVER_DAT, 'wb') as f:
    f.write(srv.SerializeToString())
print('ok', len(outfits), 'mounts,', len(objects), 'items,', len(frames) + len(small), 'sprites,', ', '.join(f'{n} ({len(c)} bytes)' for n, c, _, _ in sheets + small_sheets))
