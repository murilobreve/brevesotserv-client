"""Builds the custom asset pack with the server's own mounts (cars).

Usage (needs numpy, scipy, pillow, protobuf):
  protoc --python_out=. -I ../../src/protobuf appearances.proto
  python3 build_mounts.py ../../data/things/custom <server>/data/items/appearances.dat


Writes data/things/custom/ for the client (catalog-content.json, the sprite
sheets, appearances-custom.dat) and adds the outfits to the server's
data/items/appearances.dat (the server only lets a mount use a registered
looktype).
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
# (the Fusca is open with a saddle, the rider sits on top). Outfit ids are far
# above the official.
MOUNTS = [
    {'id': 2900, 'name': 'Blue Fusca', 'folder': 'fusca',
     'offset': {'N': (0, 0), 'E': (0, 0), 'S': (0, 0), 'W': (0, 0)},
     'cut': {'N': 64, 'E': 64, 'S': 64, 'W': 64}},
    {'id': 2901, 'name': 'Uno with Ladder', 'folder': 'uno',
     'offset': {'N': (-5, 0), 'E': (-2, 0), 'S': (-3, 0), 'W': (2, 0)},
     'cut': {'N': 48, 'E': 45, 'S': 41, 'W': 45}},
    {'id': 2902, 'name': 'Gol Bolinha', 'folder': 'gol',
     'offset': {'N': (-3, 0), 'E': (-1, 0), 'S': (-3, 0), 'W': (-4, 0)},
     'cut': {'N': 44, 'E': 45, 'S': 40, 'W': 45}},
]
FRAMES_PER_MOUNT = 8 * (1 + PHASES)


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
    assert len(frames) == FRAMES_PER_MOUNT
    return frames


def sheet_bytes(chunk):
    sheet = Image.new('RGBA', (384, 384), (255, 0, 255, 255))
    for i, f in enumerate(chunk):
        x, y = (i % 6) * 64, (i // 6) * 64
        region = Image.new('RGBA', (64, 64), (255, 0, 255, 255))
        region.paste(f, (0, 0), f)
        sheet.paste(region, (x, y))
    # BMP (32 bit BGRA, bottom-up) wrapped in CIP's LZMA container
    w, h = sheet.size
    pixels = np.array(sheet)[::-1, :, [2, 1, 0, 3]].tobytes()
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


frames, outfits = [], []
for mount in MOUNTS:
    mf = mount_frames(mount)
    outfits.append(make_outfit(mount, mf, FIRST_SPRITE + len(frames)))
    frames += mf

sheets = []
for first in range(0, len(frames), 36):
    cip = sheet_bytes(frames[first:first + 36])
    sheets.append(('sprites-mounts-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma', cip, FIRST_SPRITE + first, FIRST_SPRITE + min(first + 36, len(frames)) - 1))

custom = A.Appearances()
custom.outfit.extend(outfits)
dat_name = 'appearances-custom.dat'

os.makedirs(CLIENT_DIR, exist_ok=True)
for f in os.listdir(CLIENT_DIR):
    if f.startswith('sprites-'):
        os.remove(os.path.join(CLIENT_DIR, f))
for name, cip, first, last in sheets:
    open(os.path.join(CLIENT_DIR, name), 'wb').write(cip)
open(os.path.join(CLIENT_DIR, dat_name), 'wb').write(custom.SerializeToString())
json.dump([{'type': 'appearances', 'file': dat_name}] + [
    {'type': 'sprite', 'file': name, 'spritetype': 3, 'firstspriteid': first, 'lastspriteid': last, 'area': 64}
    for name, cip, first, last in sheets
], open(os.path.join(CLIENT_DIR, 'catalog-content.json'), 'w'), indent=2)

# server: register the looktypes (replace older copies of them)
srv = A.Appearances()
srv.ParseFromString(open(SERVER_DAT, 'rb').read())
ids = {m['id'] for m in MOUNTS}
keep = [x for x in srv.outfit if x.id not in ids]
del srv.outfit[:]
srv.outfit.extend(keep)
srv.outfit.extend(outfits)
open(SERVER_DAT, 'wb').write(srv.SerializeToString())
print('ok', len(outfits), 'mounts,', len(frames), 'sprites,', ', '.join(f'{n} ({len(c)} bytes)' for n, c, _, _ in sheets))
