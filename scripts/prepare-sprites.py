#!/usr/bin/env python3
"""Turn bongocat-osu's taiko artwork into the sprites this app bundles.

The source draws the cat on an opaque white desk, and its bongo photo carries a
white background that hugs the drums. Both have to go for the overlay to sit on
the desktop without a panel behind it. Everything here is deterministic, so the
committed PNGs can always be rebuilt:

    git clone --depth 1 https://github.com/kuroni/bongocat-osu /tmp/bongo-osu
    python3 scripts/prepare-sprites.py /tmp/bongo-osu/img/taiko

Requires Pillow (`pip install pillow`) — a build-time tool only, not a runtime
dependency of the app.
"""

import sys
import pathlib
from collections import deque
from PIL import Image

# Every layer shares this crop so the paws stay registered against the body.
CROP = (1, 19, 608, 354)
OUT = pathlib.Path(__file__).resolve().parent.parent / "Sources/BongoKit/Resources/images"

PAWS = [("leftup", "paw-left-up"), ("leftcentre", "paw-left-down"),
        ("rightup", "paw-right-up"), ("rightcentre", "paw-right-down")]


def neighbours(x, y, w, h, diagonal=False):
    steps = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    if diagonal:
        steps += [(1, 1), (-1, -1), (1, -1), (-1, 1)]
    for dx, dy in steps:
        nx, ny = x + dx, y + dy
        if 0 <= nx < w and 0 <= ny < h:
            yield nx, ny


def components(w, h, belongs):
    """Connected regions of pixels satisfying `belongs`."""
    seen = bytearray(w * h)
    found = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or not belongs(sx, sy):
                continue
            comp, queue = [], deque([(sx, sy)])
            seen[sy * w + sx] = 1
            while queue:
                x, y = queue.popleft()
                comp.append((x, y))
                for nx, ny in neighbours(x, y, w, h, diagonal=True):
                    if not seen[ny * w + nx] and belongs(nx, ny):
                        seen[ny * w + nx] = 1
                        queue.append((nx, ny))
            found.append(comp)
    return found


def erase_desk(px, w, h):
    """Flood the opaque white desk away from the bottom edge."""
    def near_white(p):
        return p[3] > 40 and min(p[:3]) >= 242

    seen = bytearray(w * h)
    work = []
    for seed in ((0, h - 1), (w - 1, h - 1), (w // 2, h - 1)):
        if near_white(px[seed]):
            seen[seed[1] * w + seed[0]] = 1
            work.append(seed)
    while work:
        x, y = work.pop()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in neighbours(x, y, w, h):
            if not seen[ny * w + nx] and near_white(px[nx, ny]):
                seen[ny * w + nx] = 1
                work.append((nx, ny))


def erase_table_edge(px, w, h):
    """Drop the table edge: a short run per column with nothing above or below.

    Anything belonging to the cat or a drum sits in a tall run, so run length
    separates them without having to guess at colours.
    """
    opaque = lambda x, y: px[x, y][3] > 30
    for x in range(w):
        y = 0
        while y < h:
            if not opaque(x, y):
                y += 1
                continue
            start = y
            while y < h and opaque(x, y):
                y += 1
            isolated = (start == 0 or not opaque(x, start - 1)) and (y >= h or not opaque(x, y))
            if (y - start) <= 9 and isolated:
                for yy in range(start, y):
                    px[x, yy] = (0, 0, 0, 0)


def erase_photo_background(px, w, h):
    """Remove the bongo photo's white backdrop.

    It survives the desk flood because it is walled in by the drums, and it reads
    as a white halo hugging their silhouette. The cat's body is white too, so the
    largest white region is kept and every other one dropped.
    """
    white = lambda x, y: px[x, y][3] > 30 and min(px[x, y][:3]) >= 225
    regions = sorted(components(w, h, white), key=len, reverse=True)
    for comp in regions[1:]:                       # regions[0] is the cat's body
        for x, y in comp:
            px[x, y] = (0, 0, 0, 0)
    return sum(len(c) for c in regions[1:])


def erase_fringe(px, w, h):
    """Clear the anti-aliased rim the keyed-out backdrop leaves behind."""
    doomed = []
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[3] <= 30 or min(p[:3]) < 200:
                continue
            empty = sum(1 for nx, ny in neighbours(x, y, w, h, diagonal=True) if px[nx, ny][3] <= 30)
            if empty >= 3:
                doomed.append((x, y))
    for x, y in doomed:
        px[x, y] = (0, 0, 0, 0)
    return len(doomed)


def drop_debris(px, w, h, minimum=2500):
    """Discard whatever fragments the table edge left behind."""
    opaque = lambda x, y: px[x, y][3] > 30
    dropped = 0
    for comp in components(w, h, opaque):
        if len(comp) < minimum:
            for x, y in comp:
                px[x, y] = (0, 0, 0, 0)
            dropped += 1
    return dropped


def build_body(source):
    image = Image.open(source / "bg.png").convert("RGBA")
    w, h = image.size
    px = image.load()
    erase_desk(px, w, h)
    erase_table_edge(px, w, h)
    halo = erase_photo_background(px, w, h)
    fringe = erase_fringe(px, w, h)
    debris = drop_debris(px, w, h)
    print(f"body: halo={halo}px fringe={fringe}px debris={debris} regions")
    return image.crop(CROP)


def main():
    source = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/bongo-osu/img/taiko")
    if not (source / "bg.png").exists():
        sys.exit(f"no taiko artwork at {source}")

    OUT.mkdir(parents=True, exist_ok=True)
    for stale in OUT.glob("*.png"):
        stale.unlink()

    build_body(source).save(OUT / "cat.png")
    for name, target in PAWS:
        Image.open(source / f"{name}.png").convert("RGBA").crop(CROP).save(OUT / f"{target}.png")

    for path in sorted(OUT.glob("*.png")):
        print(f"  {path.name:20} {Image.open(path).size}  {path.stat().st_size // 1024}KB")


if __name__ == "__main__":
    main()
