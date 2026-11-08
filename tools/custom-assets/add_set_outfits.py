"""Adds the set outfits (art/set_outfits, drawn by gen_set_outfits.py) to the
custom asset pack, leaving everything else in it as it is.

Usage (needs pillow, numpy, protobuf):
  protoc --python_out=. -I ../../src/protobuf appearances.proto
  python3 add_set_outfits.py ../../data/things/1525 ../../data/things/custom

Each outfit copies the frame groups of its base outfit (animation, timing,
mounted pattern) with one pattern row and one layer: the colours are drawn
in, so the outfit colours do not change it. Running it again replaces them:
their sheets are the sprites-setoutfits-* files.
"""
import hashlib, json, lzma, os, struct, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appearances_pb2 as A

BASE_DIR, CLIENT_DIR = sys.argv[1], sys.argv[2]
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'art', 'set_outfits')
# looktype, name, art file (gen_set_outfits.py: <set>_<base looktype>), base looktype
OUTFITS = [
    (3000, 'Dragon Scale', 'dragon_scale_1288', 1288),
    (3001, 'Dragon Scale', 'dragon_scale_1289', 1289),
    (3002, 'Golden', 'golden_1288', 1288),
    (3003, 'Golden', 'golden_1289', 1289),
    (3004, 'Draken', 'draken_1288', 1288),
    (3005, 'Draken', 'draken_1289', 1289),
    (3006, 'Sortido', 'sortido_1288', 1288),
    (3007, 'Sortido', 'sortido_1289', 1289),
    (3008, 'Demon', 'demon_1288', 1288),
    (3009, 'Demon', 'demon_1289', 1289),
    (3010, 'Crown', 'crown_1288', 1288),
    (3011, 'Crown', 'crown_1289', 1289),
    (3012, 'Magma', 'magma_1288', 1288),
    (3013, 'Magma', 'magma_1289', 1289),
    (3014, 'Lightning', 'lightning_1288', 1288),
    (3015, 'Lightning', 'lightning_1289', 1289),
    (3016, 'Terra', 'terra_1288', 1288),
    (3017, 'Terra', 'terra_1289', 1289),
    (3018, 'Glacier', 'glacier_1288', 1288),
    (3019, 'Glacier', 'glacier_1289', 1289),
    (3020, 'Prismatic', 'prismatic_1288', 1288),
    (3021, 'Prismatic', 'prismatic_1289', 1289),
    (3022, 'Zaoan', 'zaoan_1288', 1288),
    (3023, 'Zaoan', 'zaoan_1289', 1289),
    (3024, 'Falcon', 'falcon_1288', 1288),
    (3025, 'Falcon', 'falcon_1289', 1289),
    (3026, 'Plate', 'plate_1288', 1288),
    (3027, 'Plate', 'plate_1289', 1289),
    (3028, 'Leather', 'leather_1288', 1288),
    (3029, 'Leather', 'leather_1289', 1289),
    (3030, 'Studded', 'studded_1288', 1288),
    (3031, 'Studded', 'studded_1289', 1289),
    (3032, 'Chain', 'chain_1288', 1288),
    (3033, 'Chain', 'chain_1289', 1289),
    (3034, 'Brass', 'brass_1288', 1288),
    (3035, 'Brass', 'brass_1289', 1289),
    (3036, 'Dwarven', 'dwarven_1288', 1288),
    (3037, 'Dwarven', 'dwarven_1289', 1289),
    (3038, 'Gnome', 'gnome_1288', 1288),
    (3039, 'Gnome', 'gnome_1289', 1289),
    (3040, 'Lion', 'lion_1288', 1288),
    (3041, 'Lion', 'lion_1289', 1289),
    (3042, 'Green Demon', 'green_demon_1288', 1288),
    (3043, 'Green Demon', 'green_demon_1289', 1289),
    (3044, 'Norcferatu', 'norcferatu_1288', 1288),
    (3045, 'Norcferatu', 'norcferatu_1289', 1289),
    (3046, 'Yalahari', 'yalahari_1288', 1288),
    (3047, 'Yalahari', 'yalahari_1289', 1289),
    (3048, 'Depth', 'depth_1288', 1288),
    (3049, 'Depth', 'depth_1289', 1289),
    (3050, 'Broken Iks', 'broken_iks_1288', 1288),
    (3051, 'Broken Iks', 'broken_iks_1289', 1289),
    (3052, 'Stoic Iks', 'stoic_iks_1288', 1288),
    (3053, 'Stoic Iks', 'stoic_iks_1289', 1289),
    (3054, 'Leaf', 'leaf_1288', 1288),
    (3055, 'Leaf', 'leaf_1289', 1289),
    (3056, 'Gill', 'gill_1288', 1288),
    (3057, 'Gill', 'gill_1289', 1289),
    (3058, 'Eldritch', 'eldritch_1288', 1288),
    (3059, 'Eldritch', 'eldritch_1289', 1289),
    (3060, 'Fur', 'fur_1288', 1288),
    (3061, 'Fur', 'fur_1289', 1289),
    (3062, 'Pirate', 'pirate_1288', 1288),
    (3063, 'Pirate', 'pirate_1289', 1289),
]
IDS = {o[0] for o in OUTFITS}


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



def frames_of(art):
    sheet = Image.open(os.path.join(ART, art + '.png')).convert('RGBA')
    if sheet.size != (576, 512):
        raise SystemExit('%s: %s, expected 576x512' % (art, sheet.size))
    # cell (column, z, direction); column 0 idle, 1-8 walking
    return lambda col, z, d: sheet.crop((col * 64, (z * 4 + d) * 64, col * 64 + 64, (z * 4 + d) * 64 + 64))


def load(path):
    a = A.Appearances()
    a.ParseFromString(open(path, 'rb').read())
    return a


base_catalog = json.load(open(os.path.join(BASE_DIR, 'catalog-content.json')))
base = load(os.path.join(BASE_DIR, next(e['file'] for e in base_catalog if e['type'] == 'appearances')))
base_outfits = {o.id: o for o in base.outfit}

catalog = json.load(open(os.path.join(CLIENT_DIR, 'catalog-content.json')))
dat_name = next(e['file'] for e in catalog if e['type'] == 'appearances')
custom = load(os.path.join(CLIENT_DIR, dat_name))

# drop an earlier run
for e in [e for e in catalog if e['type'] == 'sprite' and e['file'].startswith('sprites-setoutfits-')]:
    catalog.remove(e)
    if os.path.exists(os.path.join(CLIENT_DIR, e['file'])):
        os.remove(os.path.join(CLIENT_DIR, e['file']))
keep = [o for o in custom.outfit if o.id not in IDS]
del custom.outfit[:]
custom.outfit.extend(keep)

first = max(e['lastspriteid'] for e in catalog if e['type'] == 'sprite') + 1
for looktype, name, art, base_look in OUTFITS:
    cell = frames_of(art)
    o = A.Appearance()
    o.CopyFrom(base_outfits[base_look])
    o.id, o.name = looktype, name
    frames = []
    for fg in o.frame_group:
        si = fg.sprite_info
        phases = len(si.animation.sprite_phase) if si.HasField('animation') else 1
        depth = max(1, si.pattern_depth)
        ids = []
        # sprite order: phase, then mounted (z), then direction (x)
        for ph in range(phases):
            col = 0 if fg.fixed_frame_group == A.FIXED_FRAME_GROUP_OUTFIT_IDLE else ph + 1
            for z in range(depth):
                for d in range(4):
                    ids.append(first + len(frames))
                    frames.append(cell(col, z, d))
        si.pattern_height, si.layers = 1, 1
        del si.sprite_id[:]
        si.sprite_id.extend(ids)
    for start in range(0, len(frames), 36):  # 36 frames of 64x64 a sheet
        chunk = frames[start:start + 36]
        cip = sheet_bytes(chunk)
        fname = 'sprites-setoutfits-' + hashlib.sha256(cip).hexdigest()[:16] + '.bmp.lzma'
        open(os.path.join(CLIENT_DIR, fname), 'wb').write(cip)
        catalog.append({'type': 'sprite', 'file': fname, 'spritetype': 3, 'firstspriteid': first + start,
                        'lastspriteid': first + start + len(chunk) - 1, 'area': 64})
    custom.outfit.append(o)
    first += len(frames)
    print(looktype, name, len(frames), 'frames')

open(os.path.join(CLIENT_DIR, dat_name), 'wb').write(custom.SerializeToString())
json.dump(catalog, open(os.path.join(CLIENT_DIR, 'catalog-content.json'), 'w'), indent=2)
print('ok', len(OUTFITS), 'set outfits')
