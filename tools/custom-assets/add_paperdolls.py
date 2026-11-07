"""Adds the paperdolls (equipment drawn over a player's outfit) to the custom
asset pack, leaving everything else in it as it is.

Usage (needs pillow, numpy, protobuf):
  protoc --python_out=. -I ../../src/protobuf appearances.proto
  python3 add_paperdolls.py ../../data/things/custom

Each paperdoll is art/paperdolls/<file>.png: 576x256, 64x64 frames, rows
North, East, South, West, columns idle + 8 walking phases, drawn over the
male Citizen (looktype 128). It becomes an outfit (looktype `id`) with the
same frame groups as a player outfit, so the client draws it frame by frame
with the player (modules/game_paperdolls, game_mythos_paperdolls). Running it
again replaces the paperdolls: their sheets are the sprites-paperdolls-* files.
"""
import hashlib, json, lzma, os, struct, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appearances_pb2 as A


# the sheet format of build_mounts.py (BMP 32 bit BGRA bottom-up in CIP's LZMA
# container); not imported from there because that file builds the pack when loaded
def sheet_bytes(chunk, size=64):
    sheet = Image.new('RGBA', (384, 384), (255, 0, 255, 255))
    cols = 384 // size
    for i, f in enumerate(chunk):
        region = Image.new('RGBA', (size, size), (255, 0, 255, 255))
        region.paste(f, (0, 0), f)
        sheet.paste(region, ((i % cols) * size, (i // cols) * size))
    w, h = sheet.size
    arr = np.array(sheet)
    key = (arr[:, :, 0] == 255) & (arr[:, :, 1] == 0) & (arr[:, :, 2] == 255)
    arr[key, 3] = 0
    pixels = arr[::-1, :, [2, 1, 0, 3]].tobytes()
    bmp = b'BM' + struct.pack('<IHHI', 54 + len(pixels), 0, 0, 54)
    bmp += struct.pack('<IiiHHIIiiII', 40, w, h, 1, 32, 0, len(pixels), 2835, 2835, 0, 0)
    bmp += pixels
    alone = lzma.compress(bmp, format=lzma.FORMAT_ALONE, filters=[{'id': lzma.FILTER_LZMA1, 'preset': 9, 'dict_size': 1 << 24}])
    props, dict_size, data = alone[0:1], alone[1:5], alone[13:]
    body = props + dict_size + struct.pack('<Q', len(bmp)) + data
    n, size7 = len(body), bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        size7.append(b | (0x80 if n else 0))
        if not n:
            break
    head = bytes([0x70, 0x0A, 0xFA, 0x80, 0x24]) + bytes(size7)
    return bytes(32 - len(head)) + head + body


def bbox(img):
    b = img.getbbox() or (0, 0, 1, 1)
    return b[0], b[1], b[2] - b[0], b[3] - b[1]

CLIENT_DIR = sys.argv[1]
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'art', 'paperdolls')
PAPERDOLLS = [
    {'id': 3000, 'name': 'Dragon Scale Helmet (paperdoll)', 'file': 'dragon_scale_helmet'},
    {'id': 3001, 'name': 'Dragon Scale Mail (paperdoll)', 'file': 'dragon_scale_mail'},
    {'id': 3002, 'name': 'Dragon Scale Legs (paperdoll)', 'file': 'dragon_scale_legs'},
    {'id': 3003, 'name': 'Dragon Scale Boots (paperdoll)', 'file': 'dragon_scale_boots'},
]
PHASES = 8
IDS = {p['id'] for p in PAPERDOLLS}


def frames_of(p):
    sheet = Image.open(os.path.join(ART, p['file'] + '.png')).convert('RGBA')
    if sheet.size != (64 * (1 + PHASES), 64 * 4):
        raise SystemExit('%s: %s, expected 576x256' % (p['file'], sheet.size))
    cell = lambda col, d: sheet.crop((col * 64, d * 64, col * 64 + 64, d * 64 + 64))
    # sprite order of an outfit frame group: phase, then direction (N E S W)
    return [cell(col, d) for col in range(1 + PHASES) for d in range(4)]


def outfit(p, frames, first):
    o = A.Appearance()
    o.id, o.name = p['id'], p['name']
    for group, (fixed, start, phases) in enumerate([(A.FIXED_FRAME_GROUP_OUTFIT_IDLE, 0, 1), (A.FIXED_FRAME_GROUP_OUTFIT_MOVING, 4, PHASES)]):
        fg = o.frame_group.add()
        fg.fixed_frame_group, fg.id = fixed, group
        si = fg.sprite_info
        si.pattern_width, si.pattern_height, si.pattern_depth, si.layers = 4, 1, 1, 1
        si.sprite_id.extend(range(first + start, first + start + phases * 4))
        if phases > 1:
            si.animation.synchronized = False
            si.animation.loop_type = A.ANIMATION_LOOP_TYPE_INFINITE
            for _ in range(phases):
                ph = si.animation.sprite_phase.add()
                ph.duration_min = ph.duration_max = 150
        si.bounding_square = 50
        si.is_opaque = False
        for d in range(4):
            x, y, w, h = bbox(frames[start + d])
            bb = si.bounding_box_per_direction.add()
            bb.x, bb.y, bb.width, bb.height = x, y, w, h
    # the same shift as every player outfit (Citizen 128 included): without
    # it the piece is drawn 8 pixels right and down of the body
    o.flags.shift.x = 8
    o.flags.shift.y = 8
    return o


catalog = json.load(open(os.path.join(CLIENT_DIR, 'catalog-content.json')))
dat_name = next(e['file'] for e in catalog if e['type'] == 'appearances')
custom = A.Appearances()
custom.ParseFromString(open(os.path.join(CLIENT_DIR, dat_name), 'rb').read())

# drop an earlier run
for e in [e for e in catalog if e['type'] == 'sprite' and e['file'].startswith('sprites-paperdolls-')]:
    catalog.remove(e)
    if os.path.exists(os.path.join(CLIENT_DIR, e['file'])):
        os.remove(os.path.join(CLIENT_DIR, e['file']))
keep = [o for o in custom.outfit if o.id not in IDS]
del custom.outfit[:]
custom.outfit.extend(keep)

first = max(e['lastspriteid'] for e in catalog if e['type'] == 'sprite') + 1
for p in PAPERDOLLS:
    frames = frames_of(p)  # 36 frames: one 384x384 sheet of 64x64
    cip = sheet_bytes(frames)
    name = 'sprites-paperdolls-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma'
    open(os.path.join(CLIENT_DIR, name), 'wb').write(cip)
    catalog.append({'type': 'sprite', 'file': name, 'spritetype': 3, 'firstspriteid': first, 'lastspriteid': first + len(frames) - 1, 'area': 64})
    custom.outfit.append(outfit(p, frames, first))
    first += len(frames)

open(os.path.join(CLIENT_DIR, dat_name), 'wb').write(custom.SerializeToString())
json.dump(catalog, open(os.path.join(CLIENT_DIR, 'catalog-content.json'), 'w'), indent=2)
print('ok', len(PAPERDOLLS), 'paperdolls')
