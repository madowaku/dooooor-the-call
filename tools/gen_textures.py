"""Procedural low-resolution textures for DOOOOOR: THE CALL.
All images are generated from code (no external image sources).
run: python tools/gen_textures.py
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "tex")
FONT = os.path.join(ROOT, "assets", "font", "DotGothic16-Regular.ttf")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(2004)


def noise(h, w, cell, seed=None):
    r = np.random.default_rng(seed) if seed is not None else rng
    gh, gw = max(2, h // cell + 2), max(2, w // cell + 2)
    g = r.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((gw * cell, gh * cell), Image.BICUBIC)
    a = np.asarray(img, dtype=np.float32)[:h, :w] / 255.0
    return a


def fbm(h, w, base=32, octaves=4):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    c = base
    for _ in range(octaves):
        out += noise(h, w, max(1, c)) * amp
        tot += amp
        amp *= 0.5
        c //= 2
    return out / tot


def tile_noise(h, w, base=32, octaves=4):
    """horizontally tileable fbm"""
    a = fbm(h, w * 2, base, octaves)
    t = np.linspace(0, 1, w, dtype=np.float32)[None, :]
    return a[:, :w] * t + a[:, w:] * (1 - t)


def col(c):
    return np.array(c, np.float32)[None, None, :] / 255.0


def save(name, arr):
    arr = np.clip(arr, 0, 1)
    Image.fromarray((arr * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))


def stains(h, w, strength=0.25):
    n = tile_noise(h, w, 48, 3)
    drip = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None] ** 2
    return 1.0 - strength * np.clip(n * 1.6 - 0.55, 0, 1) - 0.08 * drip * tile_noise(h, w, 8, 2)


def wall(name, paper, pattern, wains, rail, base_c, split=0.64, stain=0.25, wains_planks=True):
    H = W = 128
    img = np.zeros((H, W, 3), np.float32)
    y_m = int(H * 0.05)
    y_r = int(H * split)
    y_b = int(H * 0.955)
    yy, xx = np.mgrid[0:H, 0:W]
    grain = tile_noise(H, W, 4, 2)
    # wallpaper
    p = np.ones((H, W, 3), np.float32) * col(paper)
    p *= (0.93 + 0.14 * grain)[..., None]
    p = pattern(p, yy, xx)
    p *= stains(H, W, stain)[..., None]
    img[:] = p
    # wainscot
    wz = np.ones((H, W, 3), np.float32) * col(wains)
    if wains_planks:
        pl = ((xx % 16) < 1).astype(np.float32)
        streak = noise(H, W, 2)[:, :1] * 0 + tile_noise(H, W, 3, 1)
        wz *= (0.85 + 0.25 * np.repeat(noise(1, W, 2), H, 0) * 0.6 + 0.12 * streak)[..., None]
        wz *= (1 - 0.45 * pl)[..., None]
    else:
        wz *= (0.9 + 0.2 * grain)[..., None]
    scuff = 1 - 0.3 * np.clip(tile_noise(H, W, 24, 3) * 2 - 1.0, 0, 1) * (yy > H * 0.8)
    wz *= scuff[..., None]
    img[y_r:] = wz[y_r:]
    # rail, moulding, baseboard
    img[y_r - 3:y_r + 1] = col(rail) * (0.9 + 0.2 * grain[y_r - 3:y_r + 1])[..., None]
    img[y_r + 1:y_r + 2] *= 0.6
    img[:y_m] = col(rail) * (0.8 + 0.2 * grain[:y_m])[..., None]
    img[y_m:y_m + 2] *= 0.7
    img[y_b:] = col(base_c) * (0.85 + 0.2 * grain[y_b:])[..., None]
    save(name, img)


def pat_stripes(p, yy, xx):
    s = ((xx % 16) < 6).astype(np.float32)
    p *= (1 - 0.07 * s)[..., None]
    d = (((xx % 16) == 11) & ((yy % 12) < 3)).astype(np.float32)
    p *= (1 - 0.18 * d)[..., None]
    return p


def pat_plain(p, yy, xx):
    return p


def pat_damask(p, yy, xx):
    u = (xx % 32) - 16
    v = (yy % 32) - 16
    d = (np.abs(u) + np.abs(v) < 9) & (np.abs(u) + np.abs(v) > 5)
    d2 = (np.abs(((xx + 16) % 32) - 16) + np.abs(((yy + 16) % 32) - 16)) < 3
    p *= (1 - 0.16 * d.astype(np.float32) - 0.22 * d2.astype(np.float32))[..., None]
    return p


def pat_tile(p, yy, xx):
    g = ((xx % 16) == 0) | ((yy % 16) == 0)
    p *= (1 - 0.3 * g.astype(np.float32))[..., None]
    hl = ((xx % 16) == 1) | ((yy % 16) == 1)
    p *= (1 + 0.06 * hl.astype(np.float32))[..., None]
    band = (yy >= 32) & (yy < 48)
    p[band] *= np.array([0.45, 0.8, 0.82], np.float32)
    return p


def pat_juraku(p, yy, xx):
    sp = (noise(128, 128, 1) > 0.93).astype(np.float32)
    p *= (1 - 0.15 * sp)[..., None]
    return p


def pat_planks(p, yy, xx):
    pl = ((xx % 21) < 1).astype(np.float32)
    v = np.repeat(noise(1, 128, 3), 128, 0)
    p *= (0.8 + 0.3 * v)[..., None]
    p *= (1 - 0.5 * pl)[..., None]
    return p


def floors():
    H = W = 128
    yy, xx = np.mgrid[0:H, 0:W]
    g = fbm(H, W, 16, 3)
    # green/cream checker linoleum
    c = (((xx // 32) + (yy // 32)) % 2).astype(np.float32)[..., None]
    img = col((70, 104, 88)) * (1 - c) + col((168, 160, 128)) * c
    img *= (0.86 + 0.22 * g)[..., None]
    seam = ((xx % 32) == 0) | ((yy % 32) == 0)
    img *= (1 - 0.25 * seam.astype(np.float32))[..., None]
    img *= (1 - 0.25 * np.clip(fbm(H, W, 40, 2) * 2 - 1, 0, 1))[..., None]
    save("floor_lino", img)
    # mustard corridor vinyl with worn centre
    img = np.ones((H, W, 3), np.float32) * col((132, 110, 66))
    img *= (0.85 + 0.25 * g)[..., None]
    img *= (1 - 0.2 * (((xx % 64) == 0)).astype(np.float32))[..., None]
    sp = (noise(H, W, 1) > 0.9).astype(np.float32)
    img *= (1 - 0.12 * sp)[..., None]
    save("floor_vinyl", img)
    # wine carpet with small motif
    img = np.ones((H, W, 3), np.float32) * col((104, 38, 44))
    m = ((np.abs((xx % 16) - 8) + np.abs((yy % 16) - 8)) < 3).astype(np.float32)
    img = img * (1 - m[..., None]) + col((150, 110, 60)) * m[..., None]
    img *= (0.8 + 0.35 * noise(H, W, 1))[..., None]
    img *= (0.9 + 0.2 * g)[..., None]
    save("floor_carpet", img)
    # small white/teal mosaic tiles
    t = (((xx // 8) + (yy // 8)) % 2).astype(np.float32)[..., None]
    img = col((176, 186, 178)) * (1 - t) + col((84, 132, 136)) * t
    gr = ((xx % 8) == 0) | ((yy % 8) == 0)
    img *= (1 - 0.35 * gr.astype(np.float32))[..., None]
    img *= (0.85 + 0.25 * g)[..., None]
    save("floor_tile", img)
    # dark wood boards
    v = np.repeat(noise(H, 1, 3), W, 1)
    img = np.ones((H, W, 3), np.float32) * col((92, 62, 38))
    img *= (0.75 + 0.4 * v)[..., None]
    img *= (0.9 + 0.2 * fbm(H, W, 4, 2))[..., None]
    img *= (1 - 0.5 * ((yy % 16) == 0).astype(np.float32))[..., None]
    img *= (1 - 0.4 * (((xx + (yy // 16) * 37) % 96) == 0).astype(np.float32))[..., None]
    save("floor_wood", img)
    # tatami: two mats per tile with dark cloth border
    img = np.ones((H, W, 3), np.float32) * col((150, 148, 92))
    weave = ((yy % 2) == 0).astype(np.float32)
    img *= (0.9 + 0.1 * weave)[..., None]
    img *= (0.88 + 0.2 * g)[..., None]
    border = (yy < 5) | ((yy >= 62) & (yy < 67)) | (yy > 123)
    img[border] = (col((38, 52, 44)) * np.ones((H, W, 3), np.float32))[border] * (0.8 + 0.3 * noise(H, W, 1))[border][..., None]
    save("floor_tatami", img)
    # concrete
    img = np.ones((H, W, 3), np.float32) * col((112, 110, 104))
    img *= (0.7 + 0.5 * fbm(H, W, 32, 5))[..., None]
    crack = np.abs(fbm(H, W, 32, 2) - 0.5) < 0.012
    img *= (1 - 0.4 * crack.astype(np.float32))[..., None]
    save("floor_concrete", img)
    # ceiling: perforated acoustic panels
    img = np.ones((H, W, 3), np.float32) * col((176, 170, 150))
    dots = (((xx % 8) == 4) & ((yy % 8) == 4)).astype(np.float32)
    img *= (1 - 0.45 * dots)[..., None]
    seam = ((xx % 64) < 1) | ((yy % 64) < 1)
    img *= (1 - 0.4 * seam.astype(np.float32))[..., None]
    img *= (1 - 0.35 * np.clip(fbm(H, W, 40, 3) * 2.2 - 1.1, 0, 1))[..., None]
    save("ceil_panel", img)
    # ceiling: dark boards
    v = np.repeat(noise(1, W, 3), H, 0)
    img = np.ones((H, W, 3), np.float32) * col((84, 64, 46))
    img *= (0.75 + 0.4 * v)[..., None]
    img *= (1 - 0.5 * ((xx % 16) == 0).astype(np.float32))[..., None]
    save("ceil_wood", img)


def wood(name, base, w=64, h=64, vertical=True, dark=0.35):
    if vertical:
        v = np.repeat(noise(1, w, 2), h, 0)
    else:
        v = np.repeat(noise(h, 1, 2), w, 1)
    img = np.ones((h, w, 3), np.float32) * col(base)
    img *= (1 - dark / 2 + dark * v)[..., None]
    img *= (0.92 + 0.16 * fbm(h, w, 8, 2))[..., None]
    save(name, img)
    return img


def door():
    W, H = 64, 128
    yy, xx = np.mgrid[0:H, 0:W]
    v = np.repeat(noise(1, W, 2), H, 0)
    base = np.ones((H, W, 3), np.float32) * col((116, 84, 52))
    base *= (0.78 + 0.34 * v)[..., None]
    base *= (0.9 + 0.2 * fbm(H, W, 16, 3))[..., None]

    def panels(img):
        img = img.copy()
        for (y0, y1) in ((10, 56), (66, 118)):
            for (x0, x1) in ((8, 56),):
                img[y0:y1, x0:x1] *= 0.88
                img[y0:y0 + 2, x0:x1] *= 0.6
                img[y0:y1, x0:x0 + 2] *= 0.65
                img[y1 - 2:y1, x0:x1] *= 1.25
                img[y0:y1, x1 - 2:x1] *= 1.2
        # grime near the floor and the hand height
        img *= (1 - 0.3 * np.clip((yy - 108) / 20.0, 0, 1))[..., None]
        return img

    blank = panels(base)
    # a pale rectangle where a plate once was? no: the blank side never had one.
    save("door_blank", blank)
    sock = panels(base)
    # brass escutcheon plate on the free-edge side (u close to 1), at knob height
    cx, cy = 52, 68
    plate = (np.abs(xx - cx) < 6) & (np.abs(yy - cy) < 13)
    brass = col((170, 138, 62)) * np.ones((H, W, 3), np.float32) * (0.8 + 0.4 * noise(H, W, 2))[..., None]
    sock[plate] = brass[plate]
    edge = plate & ((np.abs(xx - cx) >= 5) | (np.abs(yy - cy) >= 12))
    sock[edge] *= 0.55
    rr = (xx - cx) ** 2 + (yy - (cy - 3)) ** 2
    sock[rr < 14] = np.array([0.03, 0.025, 0.02], np.float32)
    ring = (rr >= 14) & (rr < 22)
    sock[ring] *= 0.6
    for sy in (cy - 10, cy + 10):
        s = (xx - cx) ** 2 + (yy - sy) ** 2 < 2
        sock[s] *= 0.4
    # worn wood around the plate: decades of hands
    wear = np.exp(-(((xx - cx) / 14.0) ** 2 + ((yy - cy) / 20.0) ** 2))
    sock = sock * (1 + 0.18 * wear[..., None] * (~plate)[..., None])
    save("door_socket", sock)


def misc():
    # face 32x32 (front of head). simple, slightly blank stare.
    H = W = 32
    img = np.ones((H, W, 3), np.float32) * col((214, 176, 140))
    img *= (0.95 + 0.08 * noise(H, W, 4))[..., None]
    img[:9] = col((30, 26, 24))          # fringe
    img[9:11, :6] = col((30, 26, 24))
    img[9:11, 26:] = col((30, 26, 24))
    for ex in (9, 21):
        img[15:17, ex - 1:ex + 2] = col((24, 20, 20))
        img[13:14, ex - 2:ex + 3] = col((90, 64, 48))
    img[19:22, 15:17] *= 0.88
    img[25:26, 12:20] = col((140, 84, 76))
    save("face", img)
    # coat fabric
    img = np.ones((32, 32, 3), np.float32) * col((176, 150, 104))
    img *= (0.85 + 0.25 * noise(32, 32, 1))[..., None]
    save("coat", img)
    img = np.ones((32, 32, 3), np.float32) * col((44, 46, 60))
    img *= (0.8 + 0.3 * noise(32, 32, 1))[..., None]
    save("trousers", img)
    # rotary dial 32x32
    H = W = 32
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.hypot(xx - 15.5, yy - 15.5)
    img = np.ones((H, W, 3), np.float32) * col((14, 14, 16))
    img[r < 15] = col((196, 190, 170))
    img[r < 12.5] = col((22, 22, 24))
    for k in range(10):
        a = np.radians(60 + k * 30)
        hx, hy = 15.5 + 9.3 * np.cos(a), 15.5 - 9.3 * np.sin(a)
        img[np.hypot(xx - hx, yy - hy) < 1.9] = col((204, 198, 180))
    img[r < 4.5] = col((210, 204, 184))
    save("dial", img)
    # blob shadow
    r = np.hypot(xx - 15.5, yy - 15.5) / 15.5
    a = np.clip(1 - r, 0, 1) ** 1.5
    rgba = np.zeros((H, W, 4), np.float32)
    rgba[..., 3] = a * 0.75
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "blob.png"))
    # floor arrow (door swing indicator), white with alpha
    H = W = 64
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(32, 4), (56, 34), (40, 34), (40, 60), (24, 60), (24, 34), (8, 34)], fill=(255, 244, 200, 255))
    im.save(os.path.join(OUT, "arrow.png"))
    # grime/plaster for pillars & trims
    wood("wood_dark", (70, 48, 32))
    wood("wood_mid", (120, 88, 56))
    # metal bars
    img = np.ones((16, 16, 3), np.float32) * col((54, 52, 50))
    img *= (0.7 + 0.5 * noise(16, 16, 2))[..., None]
    save("iron", img)
    img = np.ones((16, 16, 3), np.float32) * col((196, 156, 66))
    img *= (0.8 + 0.4 * noise(16, 16, 2))[..., None]
    save("brass", img)


def text_img(text, size, fg, bg, pad=4, scale=1, colors=None):
    """render text char by char on a generous canvas, then crop to what was really drawn"""
    f = ImageFont.truetype(FONT, size)
    w = int(f.getlength(text)) + size * 2
    h = size * 3
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    x = float(size)
    for i, ch in enumerate(text):
        d.text((int(round(x)), size), ch, font=f, fill=(colors[i] if colors else fg))
        x += f.getlength(ch)
    box = im.getbbox()
    im = im.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad))
    out = Image.new("RGBA", im.size, bg)
    out.alpha_composite(im)
    if scale != 1:
        out = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
    return out


def signs():
    # enamel room plates
    for name, text in (("sign_phone", "電話室"), ("sign_lobby", "ロビー"), ("sign_wash", "洗面所"), ("sign_store", "物置")):
        im = text_img(text, 16, (20, 22, 30, 255), (214, 208, 186, 255), pad=5)
        a = np.asarray(im, np.float32) / 255.0
        a[..., :3] *= (0.86 + 0.2 * noise(a.shape[0], a.shape[1], 3))[..., None]
        a[:1] *= 0.5; a[-1:] *= 0.5; a[:, :1] *= 0.5; a[:, -1:] *= 0.5
        Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    # vending machine front 64x128
    W, H = 64, 128
    img = np.ones((H, W, 3), np.float32) * col((196, 60, 48))
    img[8:74, 5:59] = col((232, 236, 214))
    r = np.random.default_rng(7)
    cols = [(210, 70, 50), (60, 110, 190), (236, 196, 60), (70, 150, 90), (240, 240, 240), (90, 60, 40)]
    for row in range(3):
        for i in range(6):
            c = cols[int(r.integers(0, len(cols)))]
            x0, y0 = 8 + i * 8, 12 + row * 21
            img[y0:y0 + 13, x0:x0 + 6] = np.array(c, np.float32) / 255.0
            img[y0 + 15:y0 + 17, x0 + 1:x0 + 5] = np.array((70, 200, 110) if r.random() > 0.3 else (220, 60, 50), np.float32) / 255.0
    img[82:92, 40:58] = col((20, 22, 24))
    img[98:118, 10:54] = col((30, 28, 28))
    img *= (0.92 + 0.12 * noise(H, W, 4))[..., None]
    save("vending", img)
    # notice board paper
    img = np.ones((48, 64, 3), np.float32) * col((70, 96, 70))
    for (x0, y0, w, h) in ((4, 5, 20, 26), (28, 4, 14, 18), (46, 8, 14, 20), (30, 26, 22, 16)):
        img[y0:y0 + h, x0:x0 + w] = col((226, 220, 196)) * (0.9 + 0.1 * noise(h, w, 3))[..., None]
        for ly in range(y0 + 3, y0 + h - 2, 3):
            img[ly, x0 + 2:x0 + w - 2 - int(rng.integers(0, 5))] *= 0.55
    save("board", img)
    # wall clock face
    H = W = 48
    yy, xx = np.mgrid[0:H, 0:W]
    r_ = np.hypot(xx - 23.5, yy - 23.5)
    rgba = np.zeros((H, W, 4), np.float32)
    rgba[r_ < 23] = (0.16, 0.12, 0.09, 1)
    rgba[r_ < 20] = (0.9, 0.87, 0.76, 1)
    for k in range(12):
        a = np.radians(k * 30)
        px, py = 23.5 + 17 * np.sin(a), 23.5 - 17 * np.cos(a)
        rgba[np.hypot(xx - px, yy - py) < 1.3] = (0.1, 0.1, 0.1, 1)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "clock.png"))


def exterior():
    # building facade for the title shot: stained mortar, grid of dark windows, one lit.
    W, H = 256, 256
    yy, xx = np.mgrid[0:H, 0:W]
    img = np.ones((H, W, 3), np.float32) * col((104, 100, 92))
    img *= (0.7 + 0.45 * fbm(H, W, 64, 5))[..., None]
    streak = np.repeat(noise(1, W, 6), H, 0) * np.linspace(0.2, 1, H, dtype=np.float32)[:, None]
    img *= (1 - 0.25 * streak)[..., None]
    emis = np.zeros((H, W, 3), np.float32)
    for row in range(4):
        for c in range(5):
            x0, y0 = 14 + c * 48, 18 + row * 58
            w, h = 34, 36
            img[y0 - 2:y0 + h + 2, x0 - 2:x0 + w + 2] = col((60, 58, 54))
            glass = col((16, 20, 28)) * np.ones((h, w, 3), np.float32) * (0.7 + 0.6 * noise(h, w, 8))[..., None]
            lit = (row == 1 and c == 3)
            if lit:
                glass = col((236, 176, 84)) * np.ones((h, w, 3), np.float32) * (0.8 + 0.3 * noise(h, w, 10))[..., None]
            img[y0:y0 + h, x0:x0 + w] = glass
            img[y0:y0 + h, x0 + w // 2 - 1:x0 + w // 2 + 1] = col((60, 58, 54))
            img[y0 + h // 2 - 1:y0 + h // 2 + 1, x0:x0 + w] = col((60, 58, 54))
            if lit:
                emis[y0:y0 + h, x0:x0 + w] = img[y0:y0 + h, x0:x0 + w]
            img[y0 + h + 2:y0 + h + 14, x0:x0 + w] *= 0.8
    save("facade", img)
    save("facade_emit", emis)
    # entrance door (knobless) for the title shot
    img = np.ones((96, 64, 3), np.float32) * col((70, 52, 38))
    img *= (0.8 + 0.3 * np.repeat(noise(1, 64, 2), 96, 0))[..., None]
    img[6:44, 8:56] = col((20, 24, 30))
    img[6:44, 31:33] = col((70, 52, 38))
    save("entrance", img)
    # asphalt
    img = np.ones((64, 64, 3), np.float32) * col((40, 40, 44))
    img *= (0.7 + 0.5 * noise(64, 64, 1))[..., None]
    save("asphalt", img)


def logo():
    # title logo: DOOOOOR in heavy dot lettering, O's become knob holes
    scale = 3
    pale = (232, 222, 190, 255)
    brass = (214, 168, 70, 255)
    im = text_img("DOOOOOR", 16, pale, (0, 0, 0, 0), pad=2, scale=scale, colors=[pale, pale, pale, brass, pale, pale, pale])
    im.save(os.path.join(OUT, "logo_main.png"))
    im = text_img("THE CALL", 16, (196, 156, 66, 255), (0, 0, 0, 0), pad=2, scale=1)
    im.save(os.path.join(OUT, "logo_sub.png"))
    # knob icon for the HUD 24x24
    H = W = 24
    yy, xx = np.mgrid[0:H, 0:W]
    rgba = np.zeros((H, W, 4), np.float32)
    r = np.hypot(xx - 10.5, yy - 10.5)
    rgba[r < 8.5] = (0.35, 0.26, 0.1, 1)
    rgba[r < 7.5] = (0.78, 0.6, 0.24, 1)
    rgba[np.hypot(xx - 8.5, yy - 8.0) < 3.0] = (0.96, 0.86, 0.5, 1)
    stem = (np.abs((xx - 10.5) - (yy - 10.5)) < 3) & (xx > 14) & (yy > 14) & (xx < 22)
    rgba[stem] = (0.5, 0.38, 0.15, 1)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "knob_icon.png"))
    ghost = rgba.copy()
    ghost[..., :3] = 0.5
    ghost[..., 3] *= 0.35
    Image.fromarray((ghost * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "knob_icon_off.png"))


def landmarks():
    """things that let a player say "I have been here": painted doors with number plates, an exit lamp, stains."""
    paints = {1: (96, 128, 104), 2: (150, 74, 58), 3: (190, 150, 70), 4: (92, 112, 140)}
    r = np.random.default_rng(404)
    for kind in ("door_socket", "door_blank"):
        src = np.asarray(Image.open(os.path.join(OUT, kind + ".png")).convert("RGB"), np.float32) / 255.0
        H, W = src.shape[:2]
        yy, xx = np.mgrid[0:H, 0:W]
        lum = src.mean(axis=2)
        lum = lum / lum.mean()
        for i, pc in paints.items():
            rr = np.random.default_rng(500 + i)
            paint = np.ones((H, W, 3), np.float32) * col(pc) * (0.55 + 0.45 * lum)[..., None]
            chip = noise(H, W, 6, seed=600 + i) * 0.7 + noise(H, W, 2, seed=700 + i) * 0.3
            worn = chip + 0.35 * np.clip((yy - 96) / 32.0, 0, 1) + 0.25 * np.clip((6 - np.minimum(xx, W - 1 - xx)) / 6.0, 0, 1)
            keep = worn > 0.72
            img = np.where(keep[..., None], src * 0.9, paint)
            if kind == "door_socket":
                plate = (np.abs(xx - 52) < 9) & (np.abs(yy - 68) < 16)
                img = np.where(plate[..., None], src, img)
            # enamel number plate in the upper panel
            num = text_img(str(i), 16, (24, 24, 30, 255), (0, 0, 0, 0), pad=0)
            px0, py0, pw, ph = 23, 14, 18, 22
            img[py0:py0 + ph, px0:px0 + pw] = col((222, 216, 196)) * (0.9 + 0.12 * rr.random((ph, pw)).astype(np.float32))[..., None]
            img[py0, px0:px0 + pw] *= 0.5; img[py0 + ph - 1, px0:px0 + pw] *= 0.5
            img[py0:py0 + ph, px0] *= 0.5; img[py0:py0 + ph, px0 + pw - 1] *= 0.5
            na = np.asarray(num, np.float32) / 255.0
            nh, nw = na.shape[:2]
            oy, ox = py0 + (ph - nh) // 2, px0 + (pw - nw) // 2
            # "m": the face of the leaf whose texture is seen mirrored in the game gets a pre-mirrored digit
            for suffix, digit in (("", na), ("m", na[:, ::-1])):
                out = img.copy()
                a = digit[..., 3:4]
                out[oy:oy + nh, ox:ox + nw] = out[oy:oy + nh, ox:ox + nw] * (1 - a) + digit[..., :3] * a
                save("%s_%d%s" % (kind, i, suffix), out)
    # emergency exit lamp
    im = text_img("非常口", 16, (236, 248, 236, 255), (26, 120, 70, 255), pad=5)
    im.save(os.path.join(OUT, "sign_exit.png"))
    # east corridor wall: cold blue-grey plaster over navy boards, so it is never mistaken for the west one
    wall("wall_east", (150, 164, 176), pat_plain, (54, 66, 92), (40, 48, 66), (30, 34, 44), wains_planks=True, stain=0.3)
    # soft dark floor / ceiling stain with alpha
    H = W = 64
    yy, xx = np.mgrid[0:H, 0:W]
    rad = np.hypot(xx - 31.5, yy - 31.5) / 31.5
    blob = np.clip(1.15 - rad - 0.5 * noise(H, W, 10, seed=41), 0, 1)
    rgba = np.zeros((H, W, 4), np.float32)
    rgba[..., :3] = (0.05, 0.045, 0.035)
    rgba[..., 3] = np.clip(blob * 1.6, 0, 1) * 0.62
    ring_ = np.clip(1 - np.abs(blob - 0.12) * 14, 0, 1) * 0.25
    rgba[..., 3] = np.clip(rgba[..., 3] + ring_, 0, 0.8)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "stain.png"))
    # a faded safety poster and a calendar
    img = np.ones((48, 32, 3), np.float32) * col((212, 200, 160))
    img[4:22, 4:28] = col((176, 64, 52))
    img[8:18, 12:20] = col((232, 220, 180))
    for ly in range(27, 44, 4):
        img[ly:ly + 2, 5:27 - int(r.integers(0, 8))] *= 0.5
    img *= (0.85 + 0.2 * noise(48, 32, 4, seed=43))[..., None]
    save("poster", img)
    img = np.ones((48, 32, 3), np.float32) * col((226, 224, 210))
    img[2:16, 2:30] = col((70, 110, 150))
    for gy in range(5):
        for gx in range(7):
            img[20 + gy * 5:23 + gy * 5, 3 + gx * 4:6 + gx * 4] *= 0.6 if (gx + gy) % 7 else 0.3
    img *= (0.9 + 0.12 * noise(48, 32, 4, seed=44))[..., None]
    save("calendar", img)


if __name__ == "__main__":
    wall("wall_start", (176, 160, 112), pat_stripes, (88, 62, 40), (64, 44, 30), (40, 30, 24), stain=0.35)
    wall("wall_green", (190, 186, 158), pat_plain, (86, 122, 104), (60, 84, 72), (44, 50, 46), wains_planks=False, stain=0.3)
    wall("wall_north", (150, 140, 122), pat_stripes, (70, 52, 38), (54, 40, 30), (34, 28, 24), stain=0.4)
    wall("wall_lobby", (128, 58, 54), pat_damask, (84, 58, 38), (60, 42, 28), (36, 28, 22), stain=0.2)
    wall("wall_tile", (206, 212, 204), pat_tile, (206, 212, 204), (120, 150, 150), (70, 90, 90), split=0.9, wains_planks=False, stain=0.2)
    wall("wall_wood", (96, 70, 46), pat_planks, (74, 54, 36), (50, 36, 26), (30, 24, 20), stain=0.15)
    wall("wall_juraku", (170, 150, 104), pat_juraku, (160, 142, 98), (72, 50, 32), (60, 42, 28), split=0.8, wains_planks=False, stain=0.12)
    wall("wall_concrete", (130, 128, 120), pat_plain, (118, 116, 108), (96, 94, 88), (70, 70, 66), wains_planks=False, stain=0.45)
    floors()
    door()
    misc()
    signs()
    exterior()
    logo()
    print("textures ->", OUT, len(os.listdir(OUT)))
    landmarks()
