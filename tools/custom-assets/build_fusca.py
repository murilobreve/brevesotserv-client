"""Builds the custom asset pack with the blue Fusca mount.

Usage (needs numpy, scipy, pillow, protobuf):
  protoc --python_out=. -I ../../src/protobuf appearances.proto
  python3 build_fusca.py ../../data/things/custom <server>/data/items/appearances.dat


Writes data/things/custom/ for the client (catalog-content.json, one sprite
sheet, appearances-custom.dat) and adds the outfit to the server's
data/items/appearances.dat (the server only lets a mount use a registered
looktype).
"""
import json, lzma, struct, sys, hashlib
import numpy as np
from PIL import Image
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appearances_pb2 as A  # protoc --python_out=. ../../src/protobuf/appearances.proto
from fusca_render import render

OUTFIT_ID = 2900          # far above the official outfits
FIRST_SPRITE = 1_000_001  # far above the official sprite ids
CLIENT_DIR = sys.argv[1]
SERVER_DAT = sys.argv[2]
DIRS = 'NESW'
BOBS = [0, 0, 1, 1, 0, 0, 1, 1]

SCALE = 1.15
# per direction: where the car's centre sits, so the cabin is under the rider
ANCHOR = {'N': (44, 42), 'E': (38, 47), 'S': (45, 38), 'W': (39, 47)}
frames = []  # order: idle N E S W, then for each moving phase N E S W
for d in DIRS:
    frames.append(render(d, anchor=ANCHOR[d], scale=SCALE))
for phase in range(8):
    for d in DIRS:
        frames.append(render(d, bob=BOBS[phase], wheel_phase=phase * np.pi / 4, anchor=ANCHOR[d], scale=SCALE))
assert len(frames) == 36

# one 384x384 sheet of 64x64 sprites (6 x 6)
sheet = Image.new('RGBA', (384, 384), (255, 0, 255, 255))
for i, f in enumerate(frames):
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
sheet_name = 'sprites-fusca-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma'


def bbox(img):
    b = img.getbbox() or (0, 0, 1, 1)
    return b[0], b[1], b[2] - b[0], b[3] - b[1]


def make_outfit():
    o = A.Appearance()
    o.id = OUTFIT_ID
    o.name = 'Blue Fusca'
    for group, (fixed, start, phases) in enumerate([(A.FIXED_FRAME_GROUP_OUTFIT_IDLE, 0, 1), (A.FIXED_FRAME_GROUP_OUTFIT_MOVING, 4, 8)]):
        fg = o.frame_group.add()
        fg.fixed_frame_group = fixed
        fg.id = group
        si = fg.sprite_info
        si.pattern_width, si.pattern_height, si.pattern_depth, si.layers = 4, 1, 1, 1
        for i in range(phases * 4):
            si.sprite_id.append(FIRST_SPRITE + start + i)
        if phases > 1:
            si.animation.synchronized = False
            si.animation.loop_type = A.ANIMATION_LOOP_TYPE_INFINITE
            for _ in range(phases):
                ph = si.animation.sprite_phase.add()
                ph.duration_min = ph.duration_max = 150
        si.bounding_square = 50
        si.is_opaque = False
        for d in range(4):
            x, y, bw, bh = bbox(frames[start + d])
            bb = si.bounding_box_per_direction.add()
            bb.x, bb.y, bb.width, bb.height = x, y, bw, bh
    o.flags.SetInParent()
    return o


outfit = make_outfit()
custom = A.Appearances()
custom.outfit.append(outfit)
dat_name = 'appearances-custom.dat'

import os
os.makedirs(CLIENT_DIR, exist_ok=True)
for f in os.listdir(CLIENT_DIR):
    if f.startswith('sprites-fusca-'):
        os.remove(os.path.join(CLIENT_DIR, f))
open(os.path.join(CLIENT_DIR, sheet_name), 'wb').write(cip)
open(os.path.join(CLIENT_DIR, dat_name), 'wb').write(custom.SerializeToString())
json.dump([
    {'type': 'appearances', 'file': dat_name},
    {'type': 'sprite', 'file': sheet_name, 'spritetype': 3, 'firstspriteid': FIRST_SPRITE, 'lastspriteid': FIRST_SPRITE + 35, 'area': 64},
], open(os.path.join(CLIENT_DIR, 'catalog-content.json'), 'w'), indent=2)

# server: register the looktype (replace an older copy of it)
srv = A.Appearances()
srv.ParseFromString(open(SERVER_DAT, 'rb').read())
keep = [x for x in srv.outfit if x.id != OUTFIT_ID]
del srv.outfit[:]
srv.outfit.extend(keep)
srv.outfit.append(outfit)
open(SERVER_DAT, 'wb').write(srv.SerializeToString())
print('ok', sheet_name, len(cip), 'bytes')
