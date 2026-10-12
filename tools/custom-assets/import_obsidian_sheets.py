"""Cuts the two obsidian floor sheets in art/source/ into 32x32 ground tiles.

  obsidian_gold_sheet.png   4x4 cells: black obsidian with gold glints, the
                            temple hall floor (art/obsidian_floor/0..15)
  obsidian_purple_sheet.png 4x2 cells: black and violet obsidian, the shrine
                            and the teleport walkway (art/obsidian_inlay/0..7)

Each cell sits between black gutters; the cell is averaged down to 32x32,
in pattern order (x fastest, then y). Run: python3 import_obsidian_sheets.py
"""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art')


def spans(profile, threshold=12):
    """The bright spans between the dark gutters of one axis."""
    out, start = [], None
    for i, bright in enumerate(profile >= threshold):
        if bright and start is None:
            start = i
        if not bright and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(profile)))
    return [s for s in out if s[1] - s[0] > 32]


def cut(sheet, folder, columns, rows):
    img = Image.open(os.path.join(ART, 'source', sheet)).convert('RGB')
    grey = np.asarray(img.convert('L'), float)
    xs, ys = spans(grey.mean(axis=0)), spans(grey.mean(axis=1))
    assert len(xs) == columns and len(ys) == rows, (sheet, xs, ys)
    path = os.path.join(ART, folder)
    os.makedirs(path, exist_ok=True)
    for f in os.listdir(path):
        os.remove(os.path.join(path, f))
    i = 0
    for y0, y1 in ys:
        for x0, x1 in xs:
            img.crop((x0, y0, x1, y1)).resize((32, 32), Image.BOX).convert('RGBA').save(os.path.join(path, f'{i}.png'))
            i += 1
    return i


if __name__ == '__main__':
    print(cut('obsidian_gold_sheet.png', 'obsidian_floor', 4, 4), 'floor tiles')
    print(cut('obsidian_purple_sheet.png', 'obsidian_inlay', 4, 2), 'inlay tiles')
