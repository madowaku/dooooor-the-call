"""Procedural textures for chapters 2-4 of DOOOOOR: THE CALL.
All images are generated from code (no external image sources).
run: python tools/gen_textures2.py

Chapter 2  宿直棟 / 渡り廊下 (rain)  : dull mustard, wet grey-brown wood, cream tile + mint paint, quarry red
Chapter 3  地下 浴場 / ボイラー室    : blue-green mosaic, raw concrete with rust and red band, whitewashed brick
Chapter 4  旧館 最上階              : mauve-brown faded floral paper, near-black-brown panelling, dusty boards

Walls are 128x128, tile horizontally, v=0 is the top of the wall (2.8 m), v=1 the floor.
Floors and ceilings are 128x128 (same as the stage-1 floor_*/ceil_*) and tile both ways.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw

import gen_textures as g

OUT = g.OUT
H = W = 128
WALL_H = 2.8


def y_at(m):
    """texture row for a height of m metres above the floor"""
    return int(round((1 - m / WALL_H) * H))


# ---------------------------------------------------------------- periodic noise
def pnoise(h, w, cell, seed):
    """value noise that wraps in both directions (h, w must be multiples of cell)"""
    r = np.random.default_rng(seed)
    gh, gw = max(1, h // cell), max(1, w // cell)
    grid = r.random((gh, gw)).astype(np.float32)
    y = np.arange(h, dtype=np.float32) / cell
    x = np.arange(w, dtype=np.float32) / cell
    y0 = np.floor(y).astype(int); x0 = np.floor(x).astype(int)
    fy = y - y0; fx = x - x0
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    y0 %= gh; x0 %= gw
    y1 = (y0 + 1) % gh; x1 = (x0 + 1) % gw
    a = grid[y0][:, x0]; b = grid[y0][:, x1]
    c = grid[y1][:, x0]; d = grid[y1][:, x1]
    fx = fx[None, :]; fy = fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def pfbm(h, w, base, octaves, seed):
    out = np.zeros((h, w), np.float32)
    amp = tot = 0.0
    amp = 1.0
    c = base
    for i in range(octaves):
        out += pnoise(h, w, max(1, c), seed + i * 17) * amp
        tot += amp
        amp *= 0.5
        c = max(1, c // 2)
    return out / tot


def colv(c):
    return g.col(c)


def full(c, h=H, w=W):
    return np.ones((h, w, 3), np.float32) * colv(c)


def mul(img, m):
    img *= m[..., None] if m.ndim == 2 else m
    return img


def mix(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return a * (1 - t) + b * t


def grain_cols(w, seed, cell=2):
    """per-column wood streaks, wraps horizontally"""
    return pnoise(1, w, cell, seed)[0]


def wood_boards(h, w, base, board, seed, gap=0.5, along_y=True, stagger=None, tones=(0.82, 1.12)):
    """boards of width `board` px; grain runs along y (vertical boards) unless along_y is False"""
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    if not along_y:
        img = wood_boards(w, h, base, board, seed, gap, True, stagger, tones)
        return np.transpose(img, (1, 0, 2)).copy()
    img = full(base, h, w)
    n_b = max(1, w // board)
    tone = r.uniform(tones[0], tones[1], n_b).astype(np.float32)
    bi = (xx // board) % n_b
    img = mul(img, tone[bi])
    streak = np.repeat(pnoise(1, w, 1, seed + 1), h, 0)
    wav = pnoise(h, w, 16, seed + 2)
    img = mul(img, 0.86 + 0.18 * streak + 0.1 * wav)
    img = mul(img, 0.94 + 0.1 * pfbm(h, w, 8, 2, seed + 3))
    edge = (xx % board) == 0
    img = mul(img, 1 - gap * edge.astype(np.float32))
    img = mul(img, 1 + 0.15 * ((xx % board) == 1).astype(np.float32))  # lit edge
    if stagger:
        for b in range(n_b):
            yj = int(r.integers(0, h))
            sel = (bi == b) & (((yy - yj) % stagger) == 0)
            img[sel] *= 1 - gap
    return img


def save_rgba(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))


def wall_frame(img, top_c, base_c, seed, y_top=6, y_base=122):
    """the same top moulding and skirting as the stage-1 walls"""
    gr = pnoise(H, W, 4, seed) * 0.5 + pnoise(H, W, 2, seed + 1) * 0.5
    if top_c is not None:
        img[:y_top] = colv(top_c) * (0.8 + 0.2 * gr[:y_top])[..., None]
        img[y_top:y_top + 2] *= 0.7
    if base_c is not None:
        img[y_base:] = colv(base_c) * (0.85 + 0.2 * gr[y_base:])[..., None]
        img[y_base - 1:y_base] *= 0.75
    return img


def water_marks(h, w, seed, top=0.0, strength=0.22):
    """tide-ringed water blooms: returns (darken factor, ring mask)"""
    f = pfbm(h, w, 32, 4, seed)
    yy = np.arange(h, dtype=np.float32)[:, None] / h
    bias = np.clip(1.0 - np.abs(yy - top) * 2.2, 0, 1) * 0.18
    v = f + bias
    inside = np.clip((v - 0.58) * 8, 0, 1)
    ring = np.clip(1 - np.abs(v - 0.58) * 60, 0, 1)
    return 1 - strength * inside - 0.25 * ring, ring


def drips(h, w, seed, n=10, y0=0, length=(20, 60), width=(1, 3), strength=0.3):
    """vertical run streaks starting at y0 (wraps horizontally)"""
    r = np.random.default_rng(seed)
    m = np.zeros((h, w), np.float32)
    for _ in range(n):
        x = int(r.integers(0, w))
        L = int(r.integers(*length))
        wd = int(r.integers(*width))
        ys = int(y0 + r.integers(-3, 4))
        for y in range(max(0, ys), min(h, ys + L)):
            t = 1 - (y - ys) / L
            for dx in range(wd):
                m[y, (x + dx) % w] = max(m[y, (x + dx) % w], t * (0.6 + 0.4 * r.random()))
            if r.random() < 0.08:
                x = (x + int(r.integers(-1, 2))) % w
    return m * strength


# ================================================================= chapter 2
def wall_duty():
    yy, xx = np.mgrid[0:H, 0:W]
    y_r = int(H * 0.64)
    img = full((146, 118, 58))                          # mustard plaster gone dull
    img = mul(img, 0.88 + 0.2 * pfbm(H, W, 16, 4, 201))
    img = mul(img, 1 - 0.1 * (pnoise(H, W, 1, 202) > 0.86).astype(np.float32))   # sand in the plaster
    wm, ring = water_marks(H, W, 203, top=0.1, strength=0.16)
    wm = 1 - (1 - wm) * 0.6
    img = mul(img, wm)
    img = mix(img, img * colv((150, 120, 90)) * 1.3, ring * 0.3)   # brown tide lines
    img = mul(img, 1 - drips(H, W, 204, n=9, y0=14, length=(18, 55), strength=0.22))
    img = mul(img, 1 - 0.18 * np.clip(1 - yy / 30.0, 0, 1))       # dull top near the ceiling
    # thin picture rail
    img[13:15] = colv((70, 48, 30)) * (0.9 + 0.2 * pnoise(2, W, 2, 205))[..., None]
    img[15:16] *= 0.7
    # dark brown board wainscot
    wz = wood_boards(H, W, (78, 52, 34), 16, 206, gap=0.5)
    wz = mul(wz, 1 - 0.25 * np.clip(pfbm(H, W, 32, 3, 207) * 2.2 - 1.2, 0, 1) * (yy > 100))
    img[y_r:] = wz[y_r:]
    img[y_r - 3:y_r + 1] = colv((66, 44, 28)) * (0.9 + 0.2 * pnoise(4, W, 2, 208))[..., None]
    img[y_r - 3] *= 1.25
    img[y_r + 1:y_r + 2] *= 0.6
    img = wall_frame(img, (72, 50, 32), (44, 32, 24), 209)
    g.save("wall_duty", img)


def wall_walk():
    """covered walkway: weathered vertical boards, silvered low where rain blows in"""
    yy, xx = np.mgrid[0:H, 0:W]
    y_r = int(H * 0.64)
    img = wood_boards(H, W, (104, 92, 78), 16, 211, gap=0.55, stagger=None)
    # boards are not all equal: a narrow batten over each seam
    bat = ((xx % 32) >= 30) | ((xx % 32) < 2)
    img[bat] *= 0.9
    img[(xx % 32) == 2] *= 0.7
    lowt = np.clip((yy - 70) / 50.0, 0, 1) ** 1.2
    bleach = full((132, 130, 124))
    tex = 0.85 + 0.25 * pfbm(H, W, 8, 3, 212)
    img = mix(img, bleach * tex[..., None] * (0.9 + 0.15 * np.repeat(pnoise(1, W, 1, 213), H, 0))[..., None], lowt * 0.75)
    # rain splash: darker wet band right at the bottom and green algae
    wet = np.clip((yy - 108) / 14.0, 0, 1) * (0.6 + 0.4 * pfbm(H, W, 8, 2, 214))
    img = mul(img, 1 - 0.35 * wet)
    alg = np.clip(pfbm(H, W, 16, 3, 215) * 2 - 0.9, 0, 1) * np.clip((yy - 96) / 30.0, 0, 1)
    img = mix(img, img * colv((120, 160, 90)) * 1.25, alg * 0.6)
    img = mul(img, 1 - drips(H, W, 216, n=14, y0=y_r + 2, length=(10, 40), strength=0.25))
    img = mul(img, 1 - drips(H, W, 217, n=8, y0=8, length=(20, 60), strength=0.15))
    # horizontal rail (a nuki beam) with shadow and nails
    rail = wood_boards(8, W, (92, 78, 62), 64, 218, gap=0.3, along_y=False)
    img[y_r - 4:y_r + 2] = rail[:6]
    img[y_r - 4] *= 1.3
    img[y_r + 2:y_r + 4] *= 0.6
    for x in range(8, W, 16):
        img[y_r - 2, x] = colv((50, 40, 36))
    # eave beam at the top, dark and damp
    img = wall_frame(img, (58, 50, 44), None, 219, y_top=8)
    img[122:] = img[122:] * 0.7
    g.save("wall_walk", img)


def wall_kitchen():
    r = np.random.default_rng(221)
    yy, xx = np.mgrid[0:H, 0:W]
    T = 16
    y_t0 = 58                                    # 4 rows of 16 px tiles down to the floor (~60 % of the wall)
    y_cap = 54
    # pale green painted plaster above
    img = full((150, 172, 140))
    img = mul(img, 0.9 + 0.16 * pfbm(H, W, 16, 4, 222))
    img = mul(img, 1 - 0.08 * (pnoise(H, W, 1, 223) > 0.9).astype(np.float32))
    grease = np.clip(1 - (yy - 6) / 40.0, 0, 1) ** 1.1 * (0.55 + 0.6 * pfbm(H, W, 32, 3, 224))
    img = mix(img, img * colv((120, 96, 52)), np.clip(grease * 1.3, 0, 1) * 0.85)
    img = mul(img, 1 - drips(H, W, 225, n=6, y0=10, length=(10, 30), strength=0.18))
    # cream tiles
    tiles = full((198, 188, 156))
    ti = (xx // T) + (np.clip(yy - y_t0, 0, None) // T) * 8
    tone = r.uniform(0.9, 1.06, 64).astype(np.float32)
    tiles = mul(tiles, tone[ti % 64])
    tiles = mul(tiles, 0.93 + 0.1 * pfbm(H, W, 8, 2, 226))
    lx, ly = xx % T, (yy - y_t0) % T
    tiles[(lx == 1) | (ly == 1)] *= 1.06                 # glaze catch-light
    tiles[(lx == T - 1) | (ly == T - 1)] *= 0.9
    grout = (lx == 0) | (ly == 0)
    tiles[grout] = colv((70, 64, 54)) * (0.8 + 0.3 * pnoise(H, W, 2, 227))[grout][..., None]
    # cracked tiles: a jagged line across a few tiles
    for k in range(4):
        cx, cy = int(r.integers(0, 8)), int(r.integers(0, 4))
        x0, y0 = cx * T + 1, y_t0 + cy * T + int(r.integers(2, 14))
        y = float(y0)
        slope = r.uniform(-0.8, 0.8)
        for x in range(x0, x0 + T - 1):
            y += slope + r.uniform(-0.7, 0.7)
            yi = int(np.clip(y, y_t0 + cy * T + 1, y_t0 + cy * T + T - 1))
            tiles[yi, x % W] *= 0.45
            if r.random() < 0.3:
                tiles[min(yi + 1, H - 1), x % W] *= 0.7
        if k == 0:   # one tile chipped at its corner
            tiles[y_t0 + cy * T + 1:y_t0 + cy * T + 5, cx * T + 1:cx * T + 5] = colv((120, 112, 98))
    tiles = mul(tiles, 1 - 0.28 * np.clip(pfbm(H, W, 32, 3, 228) * 2 - 1.1, 0, 1) * (yy > 100))
    img[y_cap:] = tiles[y_cap:]
    # bullnose cap row
    img[y_cap:y_t0] = colv((186, 176, 146)) * (0.95 + 0.1 * pnoise(4, W, 2, 229))[..., None]
    img[y_cap] *= 1.15
    img[y_t0 - 1] *= 0.6
    img[y_cap - 1] *= 0.75
    img = wall_frame(img, (110, 120, 100), (70, 60, 50), 230)
    g.save("wall_kitchen", img)


def floor_boards():
    yy, xx = np.mgrid[0:H, 0:W]
    img = wood_boards(H, W, (108, 106, 100), 16, 231, gap=0.0, along_y=False)
    img = mul(img, 0.9 + 0.12 * pfbm(H, W, 4, 2, 232))
    # dark gaps between boards (outdoor boards are spaced)
    ly = yy % 16
    img[ly <= 1] = colv((34, 34, 34)) * (0.8 + 0.4 * pnoise(H, W, 2, 233))[ly <= 1][..., None]
    img[ly == 2] *= 0.8
    img[ly == 15] *= 0.85
    # board ends, staggered per board
    r = np.random.default_rng(234)
    for b in range(8):
        xe = int(r.integers(0, W))
        for x in (xe, (xe + 64) % W):
            img[b * 16 + 2:b * 16 + 16, x] *= 0.45
            img[b * 16 + 5, (x + 3) % W] *= 0.5    # nail heads
            img[b * 16 + 12, (x + 3) % W] *= 0.5
    # damp: dark cool patches
    wet = np.clip(pfbm(H, W, 32, 4, 235) * 2.2 - 0.95, 0, 1)
    img = mix(img, img * colv((150, 160, 175)) * 0.75, wet)
    g.save("floor_boards", img)


def floor_kitchen():
    r = np.random.default_rng(241)
    yy, xx = np.mgrid[0:H, 0:W]
    T = 16
    img = full((138, 66, 50))
    ti = (xx // T) + (yy // T) * 8
    tone = r.uniform(0.82, 1.1, 64).astype(np.float32)
    hue = r.uniform(-0.06, 0.06, 64).astype(np.float32)
    img = mul(img, tone[ti])
    img[..., 1] *= 1 + hue[ti]
    img = mul(img, 0.88 + 0.2 * pfbm(H, W, 4, 2, 242))
    lx, ly = xx % T, yy % T
    # worn, slightly paler centres
    cdist = np.maximum(np.abs(lx - 7.5), np.abs(ly - 7.5)) / 7.5
    img = mul(img, 1 + 0.06 * (1 - cdist))
    img[(lx == 2) | (ly == 2)] *= 1.08
    img[(lx == T - 1) | (ly == T - 1)] *= 0.85
    gr = (lx <= 1) | (ly <= 1)
    img[gr] = colv((72, 66, 58)) * (0.85 + 0.3 * pnoise(H, W, 2, 243))[gr][..., None]
    img = mul(img, 1 - 0.3 * np.clip(pfbm(H, W, 32, 3, 244) * 2.2 - 1.15, 0, 1))  # grease/traffic
    # two chipped tiles
    for _ in range(2):
        cx, cy = int(r.integers(0, 8)), int(r.integers(0, 8))
        img[cy * T + 2:cy * T + 6, cx * T + 9:cx * T + 15] = colv((96, 82, 70))
    g.save("floor_kitchen", img)


def ceil_tin():
    """underside of a corrugated tin roof on wooden purlins (walkway)"""
    yy, xx = np.mgrid[0:H, 0:W]
    P = 8
    ph = np.sin(xx * 2 * np.pi / P)
    img = full((122, 124, 120))
    img = mul(img, 0.82 + 0.22 * (ph * 0.5 + 0.5))
    img = mul(img, 0.88 + 0.2 * pfbm(H, W, 16, 3, 251))
    # rust: blooms in the troughs and along the sheet overlap
    rust = np.clip(pfbm(H, W, 32, 4, 252) * 2.3 - 1.05, 0, 1) * (0.6 + 0.4 * (ph < 0))
    lap = (np.abs(xx - 63.5) < 4).astype(np.float32)
    rust = np.clip(rust + lap * 0.35 * pnoise(H, W, 4, 253), 0, 1)
    img = mix(img, colv((118, 70, 40)) * (0.8 + 0.3 * pnoise(H, W, 2, 254))[..., None], rust * 0.8)
    img[:, 63] *= 0.6
    # wooden purlins across the corrugations
    for y0 in (0, 64):
        b = wood_boards(10, W, (88, 70, 52), 128, 255 + y0, gap=0.0, along_y=False)
        img[y0:y0 + 10] = b
        img[y0] *= 1.2
        img[y0 + 9] *= 0.7
        img[y0 + 10:y0 + 13] *= 0.65
        for x in range(4, W, 16):   # hook bolts
            img[y0 + 4:y0 + 6, x:x + 2] = colv((70, 60, 54))
    g.save("ceil_tin", img)


# ================================================================= chapter 3
def wall_bath():
    r = np.random.default_rng(301)
    yy, xx = np.mgrid[0:H, 0:W]
    T = 4
    nx, ny = W // T, H // T
    pal = np.array([(70, 138, 132), (84, 150, 140), (60, 124, 126), (96, 156, 146), (74, 132, 140)], np.float32) / 255.0
    cell = r.integers(0, len(pal), (ny, nx))
    img = pal[cell][yy // T, xx // T].astype(np.float32)
    img = mul(img, r.uniform(0.9, 1.08, (ny, nx)).astype(np.float32)[yy // T, xx // T])
    # darker band at shoulder height (~1.35 - 1.55 m)
    yb0 = (y_at(1.6) // 4) * 4
    yb1 = yb0 + 12
    band = (yy >= yb0) & (yy < yb1)
    bpal = np.array([(30, 62, 76), (36, 70, 84), (26, 56, 70)], np.float32) / 255.0
    bc = bpal[r.integers(0, 3, (ny, nx))][yy // T, xx // T]
    img[band] = bc[band]
    lx, ly = xx % T, yy % T
    img[(lx == 1) & (ly == 1)] *= 1.12                 # glaze glint
    # grout, getting black with mould towards the floor
    gr = (lx == 0) | (ly == 0)
    mould_y = np.clip((yy - 70) / 52.0, 0, 1)
    grout = full((132, 136, 128)) * (1 - 0.75 * mould_y)[..., None]
    grout = mul(grout, 0.85 + 0.3 * pnoise(H, W, 2, 302))
    img[gr] = grout[gr]
    # black mould creeping up from the bottom
    m = np.clip(pfbm(H, W, 16, 4, 303) * 1.4 + (yy - 100) / 26.0 - 0.7, 0, 1)
    img = mix(img, full((26, 34, 30)), m * 0.85)
    sp = (pnoise(H, W, 1, 304) > 0.8) & (yy > 84)
    img[sp] *= 0.55
    # a few missing tiles: grey mortar bed with a shadow on the top/left edge
    for _ in range(7):
        cx, cy = int(r.integers(0, nx)), int(r.integers(4, ny - 3))
        x0, y0 = cx * T, cy * T
        hole = colv((100, 98, 90))[0, 0] * (0.8 + 0.3 * r.random())
        for dy in range(T + 1):
            for dx in range(T + 1):
                img[(y0 + dy) % H, (x0 + dx) % W] = hole * (0.55 if (dy == 0 or dx == 0) else 1.0)
        if r.random() < 0.5:   # sometimes two in a row
            for dy in range(T + 1):
                for dx in range(T + 1):
                    img[(y0 + dy) % H, (x0 + T + dx) % W] = hole * (0.55 if dy == 0 else 1.0)
    # soap-scum dullness in the middle, top a little darker
    img = mul(img, 0.9 + 0.14 * pfbm(H, W, 32, 3, 305))
    img = mul(img, 1 - 0.12 * np.clip(1 - yy / 20.0, 0, 1))
    img[:4] = colv((54, 92, 94)) * 0.9                # cove tile under the ceiling
    img[4:5] *= 0.6
    g.save("wall_bath", img)


def concrete(h, w, base, seed, form=16):
    """raw concrete with horizontal form-board impressions and tie holes"""
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.random.default_rng(seed)
    img = full(base, h, w)
    img = mul(img, 0.82 + 0.3 * pfbm(h, w, 32, 5, seed + 1))
    if form:
        rows = h // form
        tone = r.uniform(0.93, 1.07, rows).astype(np.float32)
        img = mul(img, tone[(yy // form) % rows])
        img = mul(img, 0.96 + 0.06 * np.repeat(pnoise(1, w, 2, seed + 3), h, 0))
        img[(yy % form) == 0] *= 0.82
        img[(yy % form) == 1] *= 1.05
        # form tie holes
        tie = (((xx + 16) % 64) < 2) & (((yy + form // 2) % (form * 2)) < 2)
        img[tie] *= 0.55
    bug = pnoise(h, w, 1, seed + 4) > 0.9    # pinholes
    img[bug] *= 0.8
    return img


def wall_boiler():
    r = np.random.default_rng(311)
    yy, xx = np.mgrid[0:H, 0:W]
    img = concrete(H, W, (122, 120, 114), 312, form=16)
    # bolts with rust running down from them
    rust = np.zeros((H, W), np.float32)
    bolts = [(14, 24), (78, 24), (46, 50), (110, 50)]
    for (bx, by) in bolts:
        L = int(r.integers(40, 75))
        wid = r.uniform(2.5, 4.0)
        for y in range(by, min(H, by + L)):
            t = 1 - (y - by) / L
            off = 1.2 * np.sin(y * 0.3 + bx)
            for x in range(bx - 4, bx + 5):
                d = abs(x - bx - off) / (wid * (0.5 + 0.5 * t))
                rust[y, x % W] = max(rust[y, x % W], np.clip(1 - d, 0, 1) * t)
    rust *= 0.6 + 0.6 * pnoise(H, W, 2, 313)
    img = mix(img, colv((116, 62, 32)) * np.ones_like(img), np.clip(rust, 0, 1) * 0.8)
    for (bx, by) in bolts:
        img[by - 2:by + 2, bx - 2:bx + 2] = colv((70, 52, 40))
        img[by - 2, bx - 2:bx + 2] *= 1.4
        img[by + 1, bx - 2:bx + 2] *= 0.6
    # painted dark red band at 1 m, chipped
    yb = y_at(1.0)
    band = (yy >= yb - 3) & (yy < yb + 4)
    chip = pnoise(H, W, 2, 314) * 0.6 + pnoise(H, W, 8, 315) * 0.4
    paint = colv((96, 32, 30)) * (0.9 + 0.15 * pnoise(H, W, 1, 316))[..., None]
    sel = band & (chip < 0.64)
    img[sel] = paint[sel]
    img[yb - 4] *= 0.85
    # oil stains low on the wall
    oil = np.clip(pfbm(H, W, 16, 4, 317) * 1.8 + (yy - 104) / 22.0 - 0.9, 0, 1)
    img = mix(img, img * colv((70, 60, 40)) * 0.9, oil * 0.85)
    img = mul(img, 1 - drips(H, W, 318, n=8, y0=6, length=(30, 80), strength=0.15))
    img = wall_frame(img, None, (78, 76, 72), 319, y_base=123)
    img[:3] *= 0.75
    g.save("wall_boiler", img)


def wall_cellar():
    r = np.random.default_rng(321)
    yy, xx = np.mgrid[0:H, 0:W]
    BH, BW = 8, 32
    row = yy // BH
    sx = (xx + (row % 2) * (BW // 2)) % W
    bid = (sx // BW) + row * 4
    brick = full((128, 70, 54))
    brick = mul(brick, r.uniform(0.8, 1.15, 64).astype(np.float32)[bid % 64])
    brick = mul(brick, 0.85 + 0.25 * pnoise(H, W, 2, 322))
    joint = ((yy % BH) == 0) | ((sx % BW) == 0)
    brick[joint] = colv((92, 86, 76))[0, 0]
    # whitewash follows the bricks (thinner on the faces, pooled in the joints)
    wash = full((168, 164, 150))
    wash = mul(wash, 0.9 + 0.12 * pfbm(H, W, 8, 3, 323))
    wash = mul(wash, 1 - 0.1 * ((yy % BH) == 1).astype(np.float32))
    wash[joint] *= 0.72
    wash = mul(wash, 1 - 0.04 * r.uniform(0, 1, 64).astype(np.float32)[bid % 64])
    # flaking: whitewash gone in patches, thin (brick showing through) at the edges
    fl = pfbm(H, W, 16, 4, 324) * 0.6 + pfbm(H, W, 64, 2, 329) * 0.4
    gone = np.clip((fl - 0.62) * 14, 0, 1)
    thin = np.clip((fl - 0.5) * 6, 0, 1) * 0.3
    img = mix(wash, brick, np.clip(gone + thin, 0, 1))
    edge = (np.abs(fl - 0.62) < 0.01) & ~joint
    img[edge] *= 1.12
    # damp: darker, greenish below a wavy tide mark
    tide = 96 + 6 * (pnoise(1, W, 32, 325)[0] - 0.5) * 2 + 3 * (pnoise(1, W, 8, 326)[0] - 0.5)
    below = np.clip((yy - tide[None, :]) / 3.0, 0, 1)
    img = mix(img, img * colv((150, 152, 138)) * 0.8, below)
    line = np.clip(1 - np.abs(yy - tide[None, :]) / 1.5, 0, 1)
    img = mix(img, img * colv((150, 110, 70)) * 0.9, line * 0.8)
    salt = (pnoise(H, W, 1, 327) > 0.86) & (np.abs(yy - tide[None, :] + 4) < 4)
    img[salt] *= 1.15
    img = mul(img, 1 - 0.3 * np.clip((yy - 112) / 16.0, 0, 1))
    img = wall_frame(img, (96, 90, 80), None, 328)
    g.save("wall_cellar", img)


def floor_bath():
    r = np.random.default_rng(331)
    yy, xx = np.mgrid[0:H, 0:W]
    T = 4
    n = W // T
    img = full((172, 176, 166))
    cell_t = r.uniform(0.9, 1.06, (n, n)).astype(np.float32)
    img = mul(img, cell_t[yy // T, xx // T])
    blue = r.random((n, n)) < 0.12
    img[blue[yy // T, xx // T]] *= colv((150, 180, 190))[0, 0] * 1.25
    lx, ly = xx % T, yy % T
    img[(lx == 0) | (ly == 0)] = colv((112, 112, 104))[0, 0]
    img[((lx == 0) | (ly == 0))] *= (0.85 + 0.3 * pnoise(H, W, 2, 332))[((lx == 0) | (ly == 0))][..., None]
    # stains drawn towards a drain at the centre of each tile (periodic distance)
    dx = ((xx - 64 + 64) % 128) - 64
    dy = ((yy - 64 + 64) % 128) - 64
    d = np.hypot(dx, dy) / 64.0
    ang = np.arctan2(dy, dx)
    rays = 0.5 + 0.5 * np.sin(ang * 5 + 4 * pnoise(H, W, 32, 333) * np.pi)
    st = np.clip(1 - d, 0, 1) ** 2 * (0.55 + 0.45 * rays) * 0.8 + np.clip(0.2 - d, 0, 1) * 1.5
    st *= 0.7 + 0.5 * pfbm(H, W, 8, 3, 334)
    img = mix(img, img * colv((150, 124, 90)) * 0.85, np.clip(st, 0, 1) * 0.6)
    img = mul(img, 0.9 + 0.12 * pfbm(H, W, 32, 3, 335))
    g.save("floor_bath", img)


def floor_boiler():
    yy, xx = np.mgrid[0:H, 0:W]
    img = full((80, 78, 72))
    img = mul(img, 0.78 + 0.4 * pfbm(H, W, 32, 5, 341))
    img = mul(img, 1 - 0.1 * (pnoise(H, W, 1, 342) > 0.85).astype(np.float32))
    oil = np.clip(pfbm(H, W, 32, 4, 343) * 2.4 - 1.05, 0, 1)
    img = mix(img, img * colv((90, 80, 60)) * 0.75, oil)
    sheen = np.clip(1 - np.abs(pfbm(H, W, 32, 4, 343) - 0.62) * 40, 0, 1) * 0.12
    img = mul(img, 1 + sheen)
    # painted yellow edge line, worn through by feet and trolleys
    band = (yy >= 104) & (yy < 112)
    wear = pnoise(H, W, 2, 344) * 0.5 + pnoise(H, W, 16, 345) * 0.5
    sel = band & (wear < 0.62)
    yel = colv((176, 146, 46)) * (0.8 + 0.25 * pnoise(H, W, 1, 346))[..., None]
    img[sel] = mix(img, yel, np.full((H, W), 0.85, np.float32))[sel]
    img[band & (wear >= 0.62) & (wear < 0.67)] *= 1.15
    cf = pfbm(H, W, 32, 3, 347)
    crack = (np.abs(cf - 0.5) < 0.004) & (pfbm(H, W, 64, 1, 348) > 0.5)
    img[crack] *= 0.6
    g.save("floor_boiler", img)


def pipe_shade(h):
    """cross-section shading of a horizontal cylinder h px tall, lit from above"""
    t = (np.arange(h, dtype=np.float32) + 0.5) / h * 2 - 1
    n = np.sqrt(np.clip(1 - t * t, 0, 1))
    return 0.45 + 0.55 * np.clip(n * 0.8 - t * 0.35, 0, 1) + 0.18 * np.exp(-((t + 0.45) / 0.15) ** 2)


def ceil_pipes():
    yy, xx = np.mgrid[0:H, 0:W]
    img = concrete(H, W, (116, 114, 108), 351, form=32)
    img = mul(img, 1 - 0.25 * np.clip(pfbm(H, W, 32, 3, 352) * 2.2 - 1.2, 0, 1))
    for (y0, hh, pc, seed) in ((26, 14, (190, 178, 140), 353), (82, 10, (76, 104, 92), 356)):
        # soot shadow along the pipe
        img[y0 - 3:y0 + hh + 4] *= (1 - 0.25 * np.exp(-((np.arange(y0 - 3, y0 + hh + 4) - (y0 + hh / 2)) / (hh * 0.7)) ** 2))[:, None, None]
        paint = full(pc, hh, W) * pipe_shade(hh)[:, None, None]
        paint = mul(paint, 0.92 + 0.12 * pnoise(hh, W, 2, seed))
        chips = (pnoise(hh, W, 2, seed + 1) * 0.6 + pnoise(hh, W, 8, seed + 2) * 0.4) > 0.7
        paint[chips] = (colv((112, 64, 38)) * (0.8 + 0.3 * pnoise(hh, W, 1, seed + 3))[..., None])[chips] * pipe_shade(hh)[:, None, None].repeat(W, 1)[chips]
        img[y0:y0 + hh] = paint
        img[y0 + hh:y0 + hh + 2] *= 0.6
        # flange joint and strap brackets
        for x in (20, 84):
            img[y0 - 2:y0 + hh + 2, x:x + 3] = colv((60, 58, 54)) * pipe_shade(hh + 4)[:, None, None].repeat(3, 1)
        for x in (52, 116):
            img[y0 - 3:y0 + hh + 3, x:x + 2] = colv((84, 80, 74))
            img[y0 - 3:y0 - 1, x - 2:x + 4] = colv((70, 68, 64))
    g.save("ceil_pipes", img)


# ================================================================= chapter 4
def wall_attic():
    r = np.random.default_rng(401)
    yy, xx = np.mgrid[0:H, 0:W]
    y_r = int(H * 0.64)
    paper = full((146, 128, 116))
    paper = mul(paper, 0.9 + 0.14 * pfbm(H, W, 16, 3, 402))
    # small repeating flowers, half-drop repeat on a 16 px grid
    px = xx % 16
    py = (yy + 8 * ((xx // 16) % 2)) % 16
    cx, cy = px - 7.5, py - 7.5
    rr = np.hypot(cx, cy)
    ang = np.arctan2(cy, cx)
    petal = (rr < 3.6 + 1.2 * np.cos(ang * 5)) & (rr > 1.2)
    centre = rr <= 1.2
    leaf = (np.abs(cx - 3) + np.abs(cy - 5) * 0.6 < 1.6) | (np.abs(cx + 4) + np.abs(cy + 4) * 0.6 < 1.4)
    flower = full((124, 100, 94))                # rose, faded to brown-grey
    paper = mix(paper, flower, petal * 0.65)
    paper[centre] = colv((150, 124, 80))[0, 0]
    paper = mix(paper, full((104, 108, 88)), leaf * 0.6)
    tiny = ((xx % 16) == 0) & (((yy + 8 * ((xx // 16) % 2) + 8) % 16) == 0)
    paper[tiny] *= 0.8
    # fading: paler where the light reached, browner low
    paper = mul(paper, 1 - 0.12 * np.clip(pfbm(H, W, 32, 3, 403) * 2 - 0.9, 0, 1))
    paper = mix(paper, paper * colv((150, 128, 100)) * 1.2, np.clip((yy - 30) / 50.0, 0, 1) * 0.25)
    paper[(xx % 64) == 40] *= 0.82                # roll seams
    wm, ring = water_marks(H, W, 404, top=0.15, strength=0.15)
    paper = mul(paper, wm)
    # peeling: plaster showing through with a lifted, lighter paper edge and a shadow under it
    plaster = full((168, 160, 142)) * (0.85 + 0.2 * pfbm(H, W, 8, 3, 405))[..., None]
    plaster = mul(plaster, 1 - 0.08 * (pnoise(H, W, 1, 406) > 0.85).astype(np.float32))
    f = pfbm(H, W, 32, 5, 407)
    tear = f + 0.25 * np.clip((30 - yy) / 30.0, 0, 1) - 0.1 * (yy > 60)   # more peeling up high
    gone = tear > 0.66
    curl = (tear > 0.62) & ~gone
    img = paper.copy()
    img[gone] = plaster[gone]
    img[curl] = img[curl] * 1.18 * colv((220, 210, 190))[0, 0] / 0.85
    sh = np.roll(gone, 1, axis=0) & np.roll(gone, 1, axis=1) & ~np.roll(gone, -1, axis=0)
    under = gone & ~np.roll(gone, 2, axis=0)
    img[under] *= 0.65
    # dark panelled wainscot
    wz = full((66, 44, 38))
    wz = mul(wz, 0.85 + 0.25 * np.repeat(pnoise(1, W, 1, 408), H, 0) + 0.08 * pnoise(H, W, 8, 409))
    lx = xx % 32
    pan = (lx >= 5) & (lx < 28) & (yy >= y_r + 6) & (yy < 118)
    wz[pan] *= 0.88
    wz[pan & (lx == 5)] *= 0.6
    wz[pan & (yy == y_r + 6)] *= 0.6
    wz[pan & (lx == 27)] *= 1.3
    wz[pan & (yy == 117)] *= 1.3
    wz = mul(wz, 1 - 0.2 * np.clip(pfbm(H, W, 32, 3, 410) * 2 - 1, 0, 1))
    img[y_r:] = wz[y_r:]
    img[y_r - 4:y_r + 1] = colv((58, 40, 34)) * (0.9 + 0.2 * pnoise(5, W, 2, 411))[..., None]
    img[y_r - 4] *= 1.35                        # dust on the rail
    img[y_r + 1:y_r + 3] *= 0.6
    img = wall_frame(img, (64, 46, 40), (40, 30, 28), 412)
    g.save("wall_attic", img)


def wall_old():
    yy, xx = np.mgrid[0:H, 0:W]
    base = (66, 46, 36)
    img = full(base)
    img = mul(img, 0.85 + 0.25 * np.repeat(pnoise(1, W, 1, 421), H, 0) + 0.1 * pnoise(H, W, 16, 422))
    img = mul(img, 0.95 + 0.08 * pfbm(H, W, 4, 2, 423))
    # panel layout: two bays per tile, stile 6 px, rails at top, chair height and skirting
    rails = [(6, 12), (78, 86), (118, 128)]
    panels = [(12, 78), (86, 118)]
    lx = xx % 64
    for (y0, y1) in panels:
        p = (lx >= 6) & (lx < 64) & (yy >= y0) & (yy < y1)
        g2 = np.repeat(pnoise(1, W, 1, 424 + y0), H, 0)
        img[p] = (full(base) * (0.8 + 0.3 * g2 + 0.1 * pnoise(H, W, 8, 425))[..., None])[p] * 0.92
        img[p & (lx == 6)] *= 0.55
        img[p & (yy == y0)] *= 0.55
        img[p & (lx == 63)] *= 1.3
        img[p & (yy == y1 - 1)] *= 1.35
        # bevel ring
        inner = p & ((lx == 9) | (lx == 60)) & (yy >= y0 + 3) & (yy < y1 - 3)
        inner |= p & ((yy == y0 + 3) | (yy == y1 - 4)) & (lx >= 9) & (lx <= 60)
        img[inner] *= 0.8
    for (y0, y1) in rails:
        img[y0:y1] = full((60, 42, 32), y1 - y0, W) * (0.9 + 0.2 * np.repeat(pnoise(1, W, 1, 426 + y0), y1 - y0, 0))[..., None]
        img[y0] *= 1.35                           # dusty top edge
        img[min(y1, H - 1)] *= 0.7
    img[:6] = colv((52, 36, 28)) * 0.9
    img[6:7] *= 0.7
    # lighter rectangles where pictures once hung (sun- and smoke-darkening stopped at their edges)
    for (x0, y0, w, h) in ((14, 26, 40, 28), (84, 20, 22, 34)):
        sel = (xx >= x0) & (xx < x0 + w) & (yy >= y0) & (yy < y0 + h)
        img[sel] *= 1.5
        img[sel & ((xx == x0) | (yy == y0))] *= 0.92
        img[sel & ((yy == y0 + h - 1))] *= 0.85   # a dust line along the old frame's bottom
        nx = x0 + w // 2
        img[y0 - 7, nx] = colv((30, 24, 20))   # nail hole
        img[y0 - 6, nx] = colv((42, 34, 28))
    # dust: grey haze, heavier low
    dust = 0.12 + 0.1 * pfbm(H, W, 16, 3, 427) + 0.1 * np.clip((yy - 80) / 48.0, 0, 1)
    img = mix(img, full((120, 114, 104)), dust)
    g.save("wall_old", img)


def floor_old():
    yy, xx = np.mgrid[0:H, 0:W]
    img = wood_boards(H, W, (78, 56, 40), 32, 431, gap=0.55, stagger=128, tones=(0.92, 1.05))
    img = mul(img, 0.92 + 0.12 * pfbm(H, W, 4, 2, 432))
    # pegs at board ends
    r = np.random.default_rng(433)
    for b in range(4):
        yj = int(r.integers(0, H))
        for x in (b * 32 + 6, b * 32 + 25):
            img[(yj + 3) % H, x:x + 2] = colv((46, 34, 26))
    # worn lighter path down the middle (the boards run along the corridor)
    cx = np.abs(xx - 63.5) / 26.0
    wobble = 0.5 * (pnoise(H, 1, 64, 434) - 0.5) + 0.15 * pfbm(H, W, 8, 2, 437)
    path = np.clip(1 - (cx + wobble) ** 2, 0, 1) ** 1.5
    lum = img.mean(axis=2, keepdims=True)
    worn = mix(img, lum, 0.4) * colv((210, 186, 156)) * 2.3
    img = mix(img, worn, path * 0.85)
    # dust everywhere else, collecting in the gaps
    dust = (1 - path) ** 2 * (0.34 + 0.14 * pfbm(H, W, 16, 3, 435))
    img = mix(img, full((112, 110, 104)) * (0.9 + 0.15 * pnoise(H, W, 1, 436))[..., None], dust)
    g.save("floor_old", img)


def ceil_old():
    yy, xx = np.mgrid[0:H, 0:W]
    # narrow boards run across, between heavy beams that run along x every 64 px
    img = wood_boards(H, W, (86, 64, 48), 8, 441, gap=0.45)
    img = mul(img, 1 - 0.3 * np.clip(pfbm(H, W, 32, 3, 442) * 2.2 - 1.2, 0, 1))
    for y0 in (0, 64):
        bh = 16
        beam = wood_boards(bh, W, (60, 42, 30), 128, 443 + y0, gap=0.0, along_y=False)
        beam *= np.linspace(1.2, 0.7, bh, dtype=np.float32)[:, None, None]
        beam = mul(beam, 1 - 0.3 * (np.abs(np.arange(bh) - bh / 2)[:, None] < 0.5).astype(np.float32) * 0)
        crack = (np.abs(pnoise(bh, W, 32, 444 + y0) - 0.5) < 0.03)
        beam[crack] *= 0.6
        img[y0:y0 + bh] = beam
        img[y0 + bh:y0 + bh + 3] *= np.array([0.5, 0.65, 0.8], np.float32)[:, None, None]
        img[(y0 - 2) % H] *= 0.7
        img[(y0 - 1) % H] *= 0.55
    img = mix(img, full((110, 104, 96)), 0.1 + 0.08 * pfbm(H, W, 16, 2, 445))   # cobweb dust
    g.save("ceil_old", img)


# ================================================================= signs & extras
def signs():
    """enamel room plates: same path as gen_textures.signs()"""
    items = (("sign_duty", "宿直室"), ("sign_kitchen", "配膳室"), ("sign_walk", "渡り廊下"),
             ("sign_bath", "浴場"), ("sign_boiler", "ボイラー室"), ("sign_cellar", "倉庫"),
             ("sign_old", "旧館"), ("sign_ext", "内線"))
    for i, (name, text) in enumerate(items):
        im = g.text_img(text, 16, (20, 22, 30, 255), (214, 208, 186, 255), pad=5)
        a = np.asarray(im, np.float32) / 255.0
        a[..., :3] *= (0.86 + 0.2 * g.noise(a.shape[0], a.shape[1], 3, seed=800 + i))[..., None]
        a[:1] *= 0.5; a[-1:] *= 0.5; a[:, :1] *= 0.5; a[:, -1:] *= 0.5
        save_rgba(name, a)


def duct():
    S = 32
    yy, xx = np.mgrid[0:S, 0:S]
    img = full((132, 134, 130), S, S)
    img = mul(img, 0.9 + 0.15 * pnoise(S, S, 4, 501))
    # frame
    fr = (xx < 3) | (xx >= S - 3) | (yy < 3) | (yy >= S - 3)
    img[fr] *= 1.05
    img[(xx == 0) | (yy == 0)] *= 1.2
    img[(xx == S - 1) | (yy == S - 1)] *= 0.6
    img[((xx == 3) | (yy == 3)) & ~fr] *= 0.5
    # louvred slats: lit top lip, dark gap below
    inside = ~fr
    ly = (yy - 3) % 4
    slat = np.select([ly == 0, ly == 1, ly == 2, ly == 3], [1.25, 1.0, 0.8, 0.22])
    img[inside] *= slat[inside][..., None]
    img[inside & (ly == 3)] = colv((22, 22, 24))[0, 0] * 1.3
    # dust on slat lips, a rust tear
    dust = (pnoise(S, S, 2, 502) > 0.6) & inside & (ly == 0)
    img[dust] = img[dust] * 0.6 + colv((150, 140, 120))[0, 0] * 0.4
    rust = (pnoise(S, S, 4, 503) > 0.84)
    img[rust] = img[rust] * 0.5 + colv((110, 62, 34))[0, 0] * 0.5
    for (x, y) in ((1, 1), (S - 2, 1), (1, S - 2), (S - 2, S - 2), (S // 2, 1), (S // 2, S - 2)):
        img[y, x] = colv((60, 60, 58))[0, 0]
        img[max(0, y - 1), x] = colv((190, 190, 184))[0, 0]
    g.save("duct", img)


def pipe():
    S = 16
    img = full((184, 172, 138), S, S)
    img = mul(img, 0.9 + 0.12 * pnoise(S, S, 4, 511) + 0.05 * pnoise(S, S, 1, 512))
    chips = (pnoise(S, S, 1, 513) * 0.7 + pnoise(S, S, 4, 514) * 0.3) > 0.8
    img[chips] = colv((112, 62, 34))[0, 0] * (0.8 + 0.4 * pnoise(S, S, 1, 515))[chips][..., None]
    edge = np.roll(chips, -1, 0) & ~chips
    img[edge] *= 0.75
    g.save("pipe", img)


def rain():
    w, h = 32, 64
    r = np.random.default_rng(521)
    im = Image.new("RGBA", (w * 3, h * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    streaks = []
    for _ in range(9):
        x, y = r.uniform(0, w), r.uniform(0, h)
        L = r.uniform(8, 16)
        a = int(r.uniform(70, 150))
        streaks.append((x, y, L, a))
    for (x, y, L, a) in streaks:
        for ox in (0, w, 2 * w):
            for oy in (0, h, 2 * h):
                x0, y0 = x + ox, y + oy
                d.line([(x0, y0), (x0 - L * 0.28, y0 + L)], fill=(200, 212, 224, a), width=1)
    im = im.crop((w, h, 2 * w, 2 * h))
    im.save(os.path.join(OUT, "rain.png"))


if __name__ == "__main__":
    wall_duty(); wall_walk(); wall_kitchen()
    floor_boards(); floor_kitchen(); ceil_tin()
    wall_bath(); wall_boiler(); wall_cellar()
    floor_bath(); floor_boiler(); ceil_pipes()
    wall_attic(); wall_old(); floor_old(); ceil_old()
    signs(); duct(); pipe(); rain()
    print("chapter 2-4 textures ->", os.path.abspath(OUT))
