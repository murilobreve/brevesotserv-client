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

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'art', 'set_outfits')
# Every set is drawn on the same base, Dragon Slayer without addons
# (male 1288, female 1289), so the sets only change the armour's colours.
# name, base looktypes (male, female), addons drawn, base colours, items,
# how the colours are moved: 'hue' (the green scales and the warm gems apart,
# for a green set), 'all' (all the armour, the skin kept), 'parts' (each part
# of the body, helmet, armour, legs and boots, with the colours of its own
# item: for pieces of different sets) or 'mask' (only the pixels the outfit
# colours paint). Items are in the order helmet, armour, legs, boots.
BASE = (1288, 1289)
SETS = [
    ('dragon_scale', BASE, 0, (82, 82, 82, 82), (3400, 3386, 3363, 10201), 'hue'),
    ('golden', BASE, 0, (82, 82, 82, 82), (3365, 3360, 3364, 3555), 'all'),
    # Elite Draken Helmet, Royal Draken Mail, Zaoan Legs, Draken Boots
    ('draken', BASE, 0, (82, 82, 82, 82), (11689, 11686, 10387, 4033), 'parts'),
    # pieces of different sets: Demon Helmet, Magic Plate Armor, Golden Legs, Boots of Haste
    ('sortido', BASE, 0, (82, 82, 82, 82), (3387, 3366, 3364, 3079), 'parts'),
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


for name, looks, addons, colors, items, how in SETS:
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
