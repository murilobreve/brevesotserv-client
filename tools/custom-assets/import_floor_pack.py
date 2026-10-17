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

The streets: the designer's sandstone and obsidian block (ventera-sprites, one 256x256 drawing, 8x8 squares, row
major), so the block repeats every 8 squares. gen_street_paving.py drew the earlier arenito-256.png, kept as a fallback.

  ruas-arenito-continuo/ventera-designer-256.png -> art/obsidian_city_paving/0..63     (60004, the paved streets)
  ruas-arenito-continuo/ventera-designer-256.png -> art/obsidian_irregular_paving/0..63 (60005, the cobbled streets; the
                                                    same drawing, so the two meet without a seam)

The 16-variation pack (art/source/pisos-templo-cidade-16) is no longer copied: its drawings end at the tile edge.

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

FLOORS = []

MODULES = [('pisos-templo-continuo/03_placas_mistas/modulo-128.png', 'obsidian_floor', 4, 16),
           ('pisos-templo-continuo/03_placas_mistas/modulo-128.png', 'obsidian_inlay', 4, 8),
           ('pisos-templo-continuo/05_pavimento_irregular/modulo-128.png', 'obsidian_flagstones', 4, 16),
           ('pisos-templo-continuo/04_pavimento_retangular/modulo-128.png', 'obsidian_bricks', 4, 16),
           ('ruas-arenito-continuo/ventera-designer-256.png', 'obsidian_city_paving', 8, 64),
           ('ruas-arenito-continuo/ventera-designer-256.png', 'obsidian_irregular_paving', 8, 64)]


def copy(group, family, folder, cells):
    src = os.path.join(PACK, group, family, 'png')
    dst = os.path.join(ART, folder)
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(dst):
        os.remove(os.path.join(dst, f))
    for cell, drawing in enumerate(LAYOUT[:cells]):
        shutil.copyfile(os.path.join(src, f'{family}_{drawing:02d}.png'), os.path.join(dst, f'{cell}.png'))
    return cells


def cut(source, folder, width, cells):
    module = Image.open(os.path.join(ART, 'source', source)).convert('RGBA')
    dst = os.path.join(ART, folder)
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(dst):
        os.remove(os.path.join(dst, f))
    for cell in range(cells):
        x, y = cell % width, cell // width
        module.crop((x * 32, y * 32, x * 32 + 32, y * 32 + 32)).save(os.path.join(dst, f'{cell}.png'))
    return cells


if __name__ == '__main__':
    for source, folder, width, cells in MODULES:
        print(cut(source, folder, width, cells), 'tiles:', source, '->', folder)
    for group, family, folder, cells in FLOORS:
        print(copy(group, family, folder, cells), 'tiles:', family, '->', folder)
