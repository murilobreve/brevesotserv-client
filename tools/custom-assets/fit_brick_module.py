"""Makes the designer's brick street (ventera-tijolinhos, 256x256, 8x8 squares) wrap top to bottom.

Its brick rows are about 19 px tall, so 256 px hold 13.2 of them: the module ends on a 7 px sliver of a row, which
showed as a thin row of bricks every 8 squares. Left to right it already wraps. This keeps the 12 whole rows at their
size (from one mortar line to the next), adds one of them again, slid sideways (the module wraps sideways, so the
slide keeps that seam) to where its joints are farthest from the joints of the rows above and below, and makes up the
last few pixels by repeating one row of brick body (no mortar) in rows spread down the module. Nothing is scaled, so
the pixel art stays sharp.

Run: python3 fit_brick_module.py SOURCE.png OUT.png
"""
import sys

from PIL import Image

SIZE = 256


def mortar_lines(img):
    """The darkest row of each horizontal mortar line, top to bottom (the faint line under the cut row at the
    edge is not one)."""
    lum = img.convert('L').load()
    profile = [sum(lum[x, y] for x in range(SIZE)) / SIZE for y in range(SIZE)]
    mean = sum(profile) / SIZE
    lines = []
    for y in range(SIZE):
        if profile[y] < mean - 20 and profile[y] <= profile[y - 1] and profile[y] <= profile[(y + 1) % SIZE]:
            if lines and y - lines[-1] < 12:
                if profile[y] < profile[lines[-1]]:
                    lines[-1] = y
            else:
                lines.append(y)
    return lines


def joints(img, top, bottom):
    """Where the vertical mortar of a row is, from its middle line."""
    px = img.convert('L').load()
    mid = (top + bottom) // 2
    dark = [x for x in range(SIZE) if px[x, mid] < 105]
    groups = []
    for x in dark:
        if groups and x - groups[-1][-1] <= 2:
            groups[-1].append(x)
        else:
            groups.append([x])
    return [(g[0] + g[-1]) // 2 for g in groups]


def gap(a, b):
    d = abs(a - b) % SIZE
    return min(d, SIZE - d)


def fit(source, out):
    img = Image.open(source).convert('RGB')
    lines = mortar_lines(img)
    rows = [(lines[i], lines[i + 1]) for i in range(len(lines) - 1)]
    whole = sum(b - a for a, b in rows)
    above, below = joints(img, *rows[-1]), joints(img, *rows[0])
    # the extra row: the one, and the slide, whose joints stay farthest from its neighbours'
    best = None
    for index, (a, b) in enumerate(rows):
        if whole + (b - a) > SIZE:
            continue
        own = joints(img, a, b)
        for slide in range(SIZE):
            near = min(gap(j + slide, k) for j in own for k in above + below)
            if not best or near > best[0]:
                best = (near, index, slide)
    _, extra, slide = best
    strips = [img.crop((0, a, SIZE, b)) for a, b in rows]
    a, b = rows[extra]
    piece = img.crop((0, a, SIZE, b))
    rolled = Image.new('RGB', piece.size)
    rolled.paste(piece.crop((SIZE - slide, 0, SIZE, piece.height)), (0, 0))
    rolled.paste(piece.crop((0, 0, SIZE - slide, piece.height)), (slide, 0))
    strips.append(rolled)
    # the missing pixels: one body row repeated in rows spread down the module
    missing = SIZE - sum(s.height for s in strips)
    for n in range(missing):
        i = (n * len(strips)) // missing + len(strips) // (2 * missing)
        s = strips[i]
        body = s.height // 2
        grown = Image.new('RGB', (SIZE, s.height + 1))
        grown.paste(s.crop((0, 0, SIZE, body + 1)), (0, 0))
        grown.paste(s.crop((0, body, SIZE, s.height)), (0, body + 1))
        strips[i] = grown
    module = Image.new('RGB', (SIZE, SIZE))
    y = 0
    for s in strips:
        module.paste(s, (0, y))
        y += s.height
    assert y == SIZE, y
    module.save(out)
    print(f'{len(rows)} rows of {whole} px, row {extra} again slid {slide} px (joints {best[0]} px apart), '
          f'{missing} body rows repeated -> {out}')


if __name__ == '__main__':
    fit(sys.argv[1], sys.argv[2])
