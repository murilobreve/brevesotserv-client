"""Draws the set outfits: an official outfit (every direction, idle, walking,
on foot and mounted) recoloured with the exact colours of a set's items, so
the outfit looks like the set worn.

Usage (pillow, numpy, protobuf; reads the sprites with the server's
tools/render_sprites.py):
  python3 gen_set_outfits.py ../../data/things/1525 /path/to/brevesotserv/tools

Writes art/set_outfits/<name>_<looktype>.png: 576x512, 64x64 frames, columns
idle + 8 walking phases, rows North, East, South, West on foot, then the same
mounted. add_set_outfits.py puts them in the custom asset pack.
"""
import colorsys, os, sys
import numpy as np
from PIL import Image

ASSETS, SERVER_TOOLS = sys.argv[1], sys.argv[2]
sys.path.insert(0, SERVER_TOOLS)
import render_sprites as rs  # noqa: E402

OUT = os.environ.get('SET_OUTFITS_OUT') or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'art', 'set_outfits')
# Every set is drawn on the same base, Dragon Slayer without addons
# (male 1288, female 1289), so the sets only change the armour's colours.
# name, base looktypes (male, female), addons drawn, base colours, items,
# how the colours are moved: 'hue' (the green scales and the warm gems apart,
# for a green set), 'all' (all the armour, the skin kept), 'parts' (each part
# of the body, helmet, armour, legs and boots, with the colours of its own
# item: for pieces of different sets) or 'mask' (only the pixels the outfit
# colours paint), or 'faithful': each part with its own item's colours, its
# gems with the item's accent colours, the item's texture over the armour,
# a closed helmet over the face (eyes as the dark visor slit), and the
# helmet item's own picture drawn on the head.
# Items are in the order helmet, armour, legs, boots; the last field says
# whether the helmet is closed.
BASE = (1288, 1289)
SETS = [
    ('dragon_scale', BASE, 0, (82, 82, 82, 82), (3400, 3386, 3363, 10201), 'faithful', True),
    ('golden', BASE, 0, (82, 82, 82, 82), (3365, 3360, 3364, 3555), 'faithful', True),
    # Elite Draken Helmet, Royal Draken Mail, Zaoan Legs, Draken Boots
    ('draken', BASE, 0, (82, 82, 82, 82), (11689, 11686, 10387, 4033), 'faithful', False),
    # pieces of different sets: Demon Helmet, Magic Plate Armor, Golden Legs, Boots of Haste
    ('sortido', BASE, 0, (82, 82, 82, 82), (3387, 3366, 3364, 3079), 'faithful', True),
]

r = rs.Renderer(ASSETS)


def hsv(rgb):
    flat = rgb.reshape(-1, 3) / 255.0
    return np.array([colorsys.rgb_to_hsv(*c) for c in flat]).reshape(rgb.shape)


def lum(rgb):
    return rgb[..., 0] * 0.3 + rgb[..., 1] * 0.59 + rgb[..., 2] * 0.11


def match(values, palette):
    """the colour of the same brightness rank in the items' palette"""
    order = np.argsort(np.argsort(values, kind='stable'), kind='stable') / max(1, len(values) - 1)
    return palette[np.clip((order * (len(palette) - 1)).round().astype(int), 0, len(palette) - 1)]


def frames(look, addons, colors):
    """the outfit as one sheet, and where its colourable (masked) pixels are"""
    sheet = Image.new('RGBA', (576, 512))
    masked = Image.new('L', (576, 512))
    for group in (0, 1):
        info = r.outfits[look].frame_group[group].sprite_info
        phases = len(info.animation.sprite_phase) if info.HasField('animation') else 1
        for z in range(2):
            for d in range(4):
                for ph in range(phases):
                    col = 0 if group == 0 else ph + 1
                    for y in range(info.pattern_height):
                        if y > 0 and not (addons & (1 << (y - 1))):
                            continue
                        base = r.sprites.get(r.sprite_at(info, 0, d, y, z, ph))
                        if base is None:
                            continue
                        base = base.convert('RGBA')
                        pos = (col * 64 + 64 - base.width, (z * 4 + d) * 64 + 64 - base.height)
                        mask = r.sprites.get(r.sprite_at(info, 1, d, y, z, ph)) if info.layers > 1 else None
                        here = Image.new('L', base.size, 0)
                        if mask is not None:
                            mask = mask.convert('RGBA')
                            base = rs.colorize(base, mask, colors)
                            here = mask.split()[3].point(lambda v: 255 if v else 0)
                        # this layer hides what is under it, its mask included
                        cover = base.split()[3].point(lambda v: 255 if v else 0)
                        cur = masked.crop((pos[0], pos[1], pos[0] + base.width, pos[1] + base.height))
                        cur.paste(here, (0, 0), cover)
                        masked.paste(cur, pos)
                        sheet.alpha_composite(base, pos)
    return np.array(sheet).astype(float), np.array(masked) > 0


def head_mask(look):
    """where the outfit's head colour (yellow in the mask) paints, per frame: the hood"""
    sheet = Image.new('L', (576, 512))
    for group in (0, 1):
        info = r.outfits[look].frame_group[group].sprite_info
        phases = len(info.animation.sprite_phase) if info.HasField('animation') else 1
        for z in range(2):
            for d in range(4):
                for ph in range(phases):
                    col = 0 if group == 0 else ph + 1
                    m = r.sprites.get(r.sprite_at(info, 1, d, 0, z, ph))
                    if m is None:
                        continue
                    a = np.array(m.convert('RGBA'))
                    yellow = (a[..., 0] > 0) & (a[..., 1] > 0) & (a[..., 2] == 0) & (a[..., 3] > 0)
                    sheet.paste(Image.fromarray(yellow.astype(np.uint8) * 255), (col * 64 + 64 - m.width, (z * 4 + d) * 64 + 64 - m.height))
    return np.array(sheet) > 0


def body_parts(a, head):
    """per pixel: 0 nothing, 1 helmet, 2 armour, 3 legs, 4 boots. The hood is
    the helmet; the rest is cut along the slant of the body, head to feet"""
    out = np.zeros(a.shape[:2], int)
    for fy in range(a.shape[0] // 64):
        for fx in range(a.shape[1] // 64):
            sl = (slice(fy * 64, fy * 64 + 64), slice(fx * 64, fx * 64 + 64))
            on = a[sl][..., 3] > 0
            if on.sum() < 3:
                continue
            ys, xs = np.nonzero(on)
            pts = np.stack([xs, ys], 1).astype(float)
            c = pts.mean(0)
            axis = np.linalg.eigh(np.cov((pts - c).T))[1][:, 1]
            if axis[1] < 0:
                axis = -axis
            proj = (pts - c) @ axis
            t = (proj - proj.min()) / max(1e-6, proj.max() - proj.min())
            sub = np.zeros(on.shape, int)
            sub[ys, xs] = np.where(t > 0.86, 4, np.where(t > 0.58, 3, 2))
            sub[head[sl] & on] = 1
            out[sl] = sub
    return out


def palettes(items):
    main, accent = [], []
    for iid in items:
        a = np.array(r.item(iid).convert('RGBA')).astype(float)
        px = a[a[..., 3] > 0][:, :3]
        px = px[lum(px) > 30]
        h = hsv(px)
        warm = ((h[:, 0] < 0.15) | (h[:, 0] > 0.9)) & (h[:, 1] > 0.3)
        main.append(px)
        accent.append(px[warm])
    main, accent = np.concatenate(main), np.concatenate(accent)
    return main[np.argsort(lum(main))], accent[np.argsort(lum(accent))]


def item_look(iid):
    """an item's colours: the main material (sorted dark to light), its
    accents (gems, trims: another hue than the material), and the texture
    (brightness minus its local average) with where the item is drawn"""
    a = np.array(r.item(iid).convert('RGBA')).astype(float)
    on = a[..., 3] > 0
    rgb = a[..., :3]
    L = lum(rgb)
    h = hsv(rgb)
    ok = on & (L > 30)
    sat = ok & (h[..., 1] > 0.25)
    if sat.sum() > ok.sum() * 0.3:
        # the material's hue: the most common hue among the coloured pixels
        hist, edges = np.histogram(h[sat][:, 0], bins=24, range=(0, 1))
        hue = (edges[hist.argmax()] + edges[hist.argmax() + 1]) / 2
        dist = np.minimum(abs(h[..., 0] - hue), 1 - abs(h[..., 0] - hue))
        accent = ok & (h[..., 1] > 0.4) & (dist > 0.1)
    else:  # grey metal: the accents are the coloured bits
        accent = ok & (h[..., 1] > 0.4)
    main = rgb[ok & ~accent]
    acc = rgb[accent]
    pad = np.pad(np.where(on, L, 0), 1, mode='edge')
    cnt = np.pad(on.astype(float), 1)
    box = sum(np.roll(np.roll(pad, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1))[1:-1, 1:-1]
    num = sum(np.roll(np.roll(cnt, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1))[1:-1, 1:-1]
    detail = np.where(on, L - box / np.maximum(num, 1), 0)
    ys, xs = np.nonzero(on)
    detail = detail[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return main[np.argsort(lum(main))], acc[np.argsort(lum(acc))] if len(acc) else acc, detail


def grow(mask, n):
    out = mask.copy()
    for _ in range(n):
        g = out.copy()
        g[1:] |= out[:-1]; g[:-1] |= out[1:]; g[:, 1:] |= out[:, :-1]; g[:, :-1] |= out[:, 1:]
        out = g
    return out


def faithful(a, masked, look, items, closed):
    out = a.copy()
    on = a[..., 3] > 0
    rgb = a[..., :3]
    h = hsv(rgb)
    L = lum(rgb)
    dark = on & (h[..., 2] < 0.14)
    skin = on & ~masked & (h[..., 0] > 0.02) & (h[..., 0] < 0.11) & (h[..., 1] > 0.15) & (h[..., 1] < 0.6) & (h[..., 2] > 0.55)
    gem = on & ~dark & ~skin & ((h[..., 0] < 0.15) | (h[..., 0] > 0.9)) & (h[..., 1] > 0.6)
    part = body_parts(a, head_mask(look))
    if closed:
        # the face under a closed helmet: helmet, its darkest pixels the visor slit
        face = skin & grow(part == 1, 3) & ~grow(part >= 3, 1)
        part[face] = 1
        skin = skin & ~face
    for k, iid in enumerate(items):
        main, acc, detail = item_look(iid)
        mine = on & ~dark & ~skin & (part == k + 1)
        if not mine.any():
            continue
        # the item's texture over the armour, the same spot of the item on the
        # same spot of the part in every frame
        tex = np.zeros(L.shape)
        dh, dw = detail.shape
        for fy in range(a.shape[0] // 64):
            for fx in range(a.shape[1] // 64):
                y0, x0 = fy * 64, fx * 64
                sub = mine[y0:y0 + 64, x0:x0 + 64]
                if not sub.any():
                    continue
                ys, xs = np.nonzero(sub)
                ty = (ys - ys.min()) % dh
                tx = (xs - xs.min()) % dw
                tex[y0 + ys, x0 + xs] = detail[ty, tx]
        armour = mine & ~gem
        # an item with a lot of a second colour (Royal Draken Mail: gold and
        # red) keeps both on the armour, by brightness
        both = len(acc) > 0.25 * (len(acc) + len(main))
        material = np.concatenate([main, acc]) if both else main
        material = material[np.argsort(lum(material))]
        out[armour, :3] = match(L[armour] + tex[armour] * 0.8, material)
        g = mine & gem
        if g.any():
            out[g, :3] = match(L[g], acc if len(acc) else main[len(main) // 2:])
        if closed and k == 0:
            face = mine & grow(skin | (part == 1), 0) & (h[..., 0] > 0.02) & (h[..., 0] < 0.11) & ~masked
            slit = face & (L < np.percentile(L[face], 40) if face.any() else face)
            # the visor in the item's accent (the Demon Helmet's gold T), or dark
            out[slit, :3] = acc[len(acc) // 2] if len(acc) > 8 else main[0] * 0.45
    return out


HELMET_HEIGHT = 17  # the helmet's height on the head, in pixels


def helmet_back(icon):
    """the helmet seen from behind: its visor and face opening filled with the shell"""
    a = np.array(icon).astype(float)
    on = a[..., 3] > 0
    L = lum(a[..., :3])
    shell = on & (L > np.percentile(L[on], 35))
    edge = on & ~(np.roll(on, 1, 0) & np.roll(on, -1, 0) & np.roll(on, 1, 1) & np.roll(on, -1, 1))
    fill = on & ~shell & ~edge
    a[fill, :3] = a[shell][:, :3].mean(0) * 0.8
    return Image.fromarray(a.astype(np.uint8))


def put_helmets(out, part, iid):
    """the helmet item's own picture on the head of every frame: front from
    the south, its back from the north, narrower from the sides"""
    icon = r.item(iid).convert('RGBA')
    icon = icon.crop(icon.getbbox())
    back = helmet_back(icon)
    for fy in range(out.shape[0] // 64):
        d = fy % 4  # North, East, South, West
        for fx in range(out.shape[1] // 64):
            y0, x0 = fy * 64, fx * 64
            ys, xs = np.nonzero(part[y0:y0 + 64, x0:x0 + 64] == 1)
            if len(ys) < 4:
                continue
            top = ys.min()
            xs = xs[ys < top + 10]  # the head: the top rows of the hood
            pic = back if d == 0 else icon
            h = HELMET_HEIGHT
            w = max(1, int(round(h * pic.width / pic.height * (0.8 if d in (1, 3) else 1))))
            pic = pic.resize((w, h), Image.NEAREST)
            if d == 3:
                pic = pic.transpose(Image.FLIP_LEFT_RIGHT)
            tile = Image.fromarray(out[y0:y0 + 64, x0:x0 + 64].astype(np.uint8))
            tile.alpha_composite(pic, (int(round((xs.min() + xs.max()) / 2 - w / 2)), int(top) - 1))
            out[y0:y0 + 64, x0:x0 + 64] = np.array(tile)
    return out


for name, looks, addons, colors, items, how, *rest in SETS:
    if how == 'faithful':
        for look in looks:
            a, masked = frames(look, addons, colors)
            out = faithful(a, masked, look, items, rest and rest[0])
            out = put_helmets(out, body_parts(a, head_mask(look)), items[0])
            Image.fromarray(out.astype(np.uint8)).save(os.path.join(OUT, '%s_%d.png' % (name, look)))
            print('wrote', name, look)
        continue
    main, accent = palettes(items)
    if how == 'hue':  # the green of the scales without the gems' orange
        h = hsv(main)
        main = main[(h[:, 0] > 0.18) & (h[:, 0] < 0.55)]
    for look in looks:
        a, masked = frames(look, addons, colors)
        on = a[..., 3] > 0
        rgb = a[..., :3]
        out = a.copy()
        if how == 'hue':
            h = hsv(rgb)
            dark = on & (h[..., 2] < 0.14)
            green = on & ~dark & (h[..., 0] > 0.18) & (h[..., 0] < 0.55) & (h[..., 1] > 0.2)
            warm = on & ~dark & ((h[..., 0] < 0.15) | (h[..., 0] > 0.9)) & (h[..., 1] > 0.45) & (h[..., 2] > 0.35)
            out[green, :3] = match(lum(rgb)[green], main)
            out[warm, :3] = match(lum(rgb)[warm], accent)
        elif how == 'parts':
            h = hsv(rgb)
            dark = on & (h[..., 2] < 0.14)
            skin = on & ~masked & (h[..., 0] > 0.02) & (h[..., 0] < 0.11) & (h[..., 1] > 0.15) & (h[..., 1] < 0.6) & (h[..., 2] > 0.55)
            part = body_parts(a, head_mask(look))
            for k, iid in enumerate(items):
                pmain, _ = palettes([iid])
                sel = on & ~dark & ~skin & (part == k + 1)
                if sel.any():
                    out[sel, :3] = match(lum(rgb)[sel], pmain)
        elif how == 'all':
            h = hsv(rgb)
            dark = on & (h[..., 2] < 0.14)
            skin = on & ~masked & (h[..., 0] > 0.02) & (h[..., 0] < 0.11) & (h[..., 1] > 0.15) & (h[..., 1] < 0.6) & (h[..., 2] > 0.55)
            gem = on & ~dark & ~skin & ((h[..., 0] < 0.15) | (h[..., 0] > 0.9)) & (h[..., 1] > 0.6)
            armour = on & ~dark & ~skin & ~gem
            out[armour, :3] = match(lum(rgb)[armour], main)
            if len(accent):
                out[gem, :3] = match(lum(rgb)[gem], accent)
        else:
            mat = on & masked & (lum(rgb) > 25)
            out[mat, :3] = match(lum(rgb)[mat], main)
        Image.fromarray(out.astype(np.uint8)).save(os.path.join(OUT, '%s_%d.png' % (name, look)))
        print('wrote', name, look)
