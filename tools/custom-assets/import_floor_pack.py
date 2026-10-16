"""Copies the chosen floors of the 16-variation pack (art/source/pisos-templo-cidade-16) into the ground art folders.

  templo/01_placas_pretas  -> art/obsidian_floor/0..15        (60001, the temple hall of Ventera)
  cidade/04_pedra_grafite  -> art/obsidian_city_paving/0..15  (60004, the streets of Ventera)

The client draws a 4x4 ground by the tile's position (cell x % 4, y % 4), so the 16 drawings repeat every 4 squares.
The pack numbers them from the quietest (01, weight 12%) to the most marked (16, 3%); LAYOUT puts 13..16 on cells two
squares apart and 9..12 on the diagonal between them, so no two of the most marked ever touch, across the repeat
too. The cells are in pattern order (x fastest, then y). Run: python3 import_floor_pack.py, then build_mounts.py.
"""
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art')
PACK = os.path.join(ART, 'source', 'pisos-templo-cidade-16')

LAYOUT = [16, 1, 15, 2,
          3, 12, 4, 11,
          14, 5, 13, 6,
          7, 10, 8, 9]

FLOORS = [('templo', '01_placas_pretas', 'obsidian_floor'),
          ('cidade', '04_pedra_grafite', 'obsidian_city_paving')]


def copy(group, family, folder):
    src = os.path.join(PACK, group, family, 'png')
    dst = os.path.join(ART, folder)
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(dst):
        os.remove(os.path.join(dst, f))
    for cell, drawing in enumerate(LAYOUT):
        shutil.copyfile(os.path.join(src, f'{family}_{drawing:02d}.png'), os.path.join(dst, f'{cell}.png'))
    return len(LAYOUT)


if __name__ == '__main__':
    for group, family, folder in FLOORS:
        print(copy(group, family, folder), 'tiles:', family, '->', folder)
