#!/usr/bin/env python3
"""The port's own icon, app/icon.png: a golden star over green hills under a blue sky. 240x160, pixel art drawn
at 1/4 size and scaled up, in the style of FakeR36S-Ocarina's tools/icons.py. Plain Python (no Pillow).
  tools/icon.py
"""
import math
import struct
import zlib

W, H, S = 60, 40, 4


def canvas(top, bottom):
    px = [[(0, 0, 0)] * W for _ in range(H)]
    for y in range(H):
        t = y / (H - 1)
        for x in range(W):
            px[y][x] = tuple(int(a + (b - a) * t) for a, b in zip(top, bottom))
    return px


def put(px, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        px[y][x] = c


def hills(px, colors, base, amp, freq, phase):
    for x in range(W):
        top = int(base + amp * math.sin(x / freq + phase))
        for y in range(top, H):
            put(px, x, y, colors[(x + y) % 7 == 0])


def star(px, cx, cy, r_out, r_in, fill, edge):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))

    def inside(x, y):
        c = False
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                c = not c
            j = i
        return c

    for y in range(H):
        for x in range(W):
            if inside(x + 0.5, y + 0.5):
                near_edge = not all(inside(x + 0.5 + dx, y + 0.5 + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                put(px, x, y, edge if near_edge else fill)


def save(px, path):
    rows = b""
    for y in range(H * S):
        row = bytearray([0])
        for x in range(W * S):
            row += bytes(px[y // S][x // S])
        rows += bytes(row)
    png = b"\x89PNG\r\n\x1a\n"
    for tag, data in ((b"IHDR", struct.pack(">IIBBBBB", W * S, H * S, 8, 2, 0, 0, 0)),
                      (b"IDAT", zlib.compress(rows, 9)), (b"IEND", b"")):
        png += struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(png)


px = canvas((64, 120, 224), (150, 200, 248))
for cx, cy in ((6, 5), (44, 3)):
    for dx, dy, w in ((0, 1, 9), (2, 0, 5), (1, 2, 7)):
        for i in range(w):
            put(px, cx + dx + i, cy + dy, (250, 252, 255))
hills(px, ((96, 184, 72), (84, 168, 64)), 27, 3, 7.0, 0.8)
hills(px, ((64, 150, 52), (56, 136, 46)), 32, 2, 5.0, 2.2)
star(px, 30, 18, 14, 6, (252, 214, 60), (200, 140, 20))
save(px, "app/icon.png")
