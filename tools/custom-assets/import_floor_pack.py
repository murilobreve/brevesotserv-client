"""Copies the chosen floors into the ground art folders.

From the continuous temple pack (art/source/pisos-templo-continuo): one drawing cut into a 4x4 module of 32x32, so the
slabs run across the sprite cuts. The client draws a 4x4 ground by the tile's position (x % 4, y % 4), which is the
fixed origin the pack asks for. The module is the pack's source image (03_placas_mistas) scaled straight to 128x128;
the pack's own 16 PNGs mirror the drawing at the edges and read as a kaleidoscope in game.

  03_placas_mistas/modulo-128.png -> art/obsidian_floor/0..15  (60001, the temple of Ventera and the TP rooms)
  03_placas_mistas/modulo-128.png -> art/obsidian_inlay/0..7   (60002, rows 0-1; no longer on the map)
  05_pavimento_irregular/modulo-128.png  -> art/obsidian_flagstones/0..15 (60006, TP rooms: Iniciantes, Novas Hunts, floor 10)
  04_pavimento_retangular/modulo-128.png -> art/obsidian_bricks/0..15     (60007, TP rooms: Hunts, Quests/Castle)

The 04 source is 1536x1024 and does not repeat top to bottom; its module is the 660x660 square at (134, 320), where the
brick rows and the left and right edges line up best.

From the 16-variation pack (art/source/pisos-templo-cidade-16):

  cidade/02_arenito        -> art/obsidian_city_paving/0..15     (60004, the paved streets of Ventera)
  cidade/02_arenito        -> art/obsidian_irregular_paving/0..15 (60005, the cobbled streets)

The client draws a 4x4 ground by the tile's position (cell x % 4, y % 4), so the 16 drawings repeat every 4 squares.
The pack numbers them from the quietest (01, weight 12%) to the most marked (16, 3%); LAYOUT puts 13..16 on cells two
squares apart and 9..12 on the diagonal between them, so no two of the most marked ever touch, across the repeat
too. The cells are in pattern order (x fastest, then y). A 4x2 ground takes the first 8 cells: its pattern size must not
change, because the sprite ids are sequential and the server appearances.dat would shift. Run: python3 import_floor_pack.py, then build_mounts.py.
"""
import os
import shutil

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art')
PACK = os.path.join(ART, 'source', 'pisos-templo-cidade-16')

LAYOUT = [16, 1, 15, 2,
          3, 12, 4, 11,
          14, 5, 13, 6,
          7, 10, 8, 9]

FLOORS = [('cidade', '02_arenito', 'obsidian_city_paving', 16),
          ('cidade', '02_arenito', 'obsidian_irregular_paving', 16)]

MODULE_PACK = os.path.join(ART, 'source', 'pisos-templo-continuo')
MODULES = [('03_placas_mistas', 'obsidian_floor', 16),
           ('03_placas_mistas', 'obsidian_inlay', 8),
           ('05_pavimento_irregular', 'obsidian_flagstones', 16),
           ('04_pavimento_retangular', 'obsidian_bricks', 16)]


def copy(group, family, folder, cells):
    src = os.path.join(PACK, group, family, 'png')
    dst = os.path.join(ART, folder)
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(dst):
        os.remove(os.path.join(dst, f))
    for cell, drawing in enumerate(LAYOUT[:cells]):
        shutil.copyfile(os.path.join(src, f'{family}_{drawing:02d}.png'), os.path.join(dst, f'{cell}.png'))
    return cells


def cut(family, folder, cells):
    module = Image.open(os.path.join(MODULE_PACK, family, 'modulo-128.png')).convert('RGBA')
    dst = os.path.join(ART, folder)
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(dst):
        os.remove(os.path.join(dst, f))
    for cell in range(cells):
        x, y = cell % 4, cell // 4
        module.crop((x * 32, y * 32, x * 32 + 32, y * 32 + 32)).save(os.path.join(dst, f'{cell}.png'))
    return cells


if __name__ == '__main__':
    for family, folder, cells in MODULES:
        print(cut(family, folder, cells), 'tiles:', family, '->', folder)
    for group, family, folder, cells in FLOORS:
        print(copy(group, family, folder, cells), 'tiles:', family, '->', folder)
