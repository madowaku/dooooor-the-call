"""Hand-painted-looking low-res textures for the protagonist (scripts/human.gd).
Deterministic (fixed seed). Writes assets/tex/human_*.png.
run: python tools/gen_human_tex.py

UV conventions (must match scripts/human.gd):
  lofted parts: u runs around the part, 0 = back (+Z), 0.25 = right side (+X),
  0.5 = front (-Z), 0.75 = left side, 1 = back again. v runs top -> bottom.
  coat:  v = 0.045 + (0.58 - y) * 0.92 (y in hips space); rows 0..5 = stand collar.
  face:  8 columns at u = 0,.04,.10,.28,.5,.72,.90,.96,1 ; v = 1 - (y - 0.015) / 0.23.
"""
import os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "tex")
os.makedirs(OUT, exist_ok=True)
SEED = 3004


def rng(k):
    return np.random.default_rng(SEED + k)


def col(c):
    return np.array(c, np.float32) / 255.0


def blocky_noise(h, w, cell, k):
    """value noise on a coarse grid, nearest-upscaled then lightly smoothed, wraps horizontally"""
    r = rng(k)
    gh, gw = max(1, h // cell), max(1, w // cell)
    g = r.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((gw * cell, gh * cell), Image.BILINEAR)
    a = np.asarray(img, np.float32)[:h, :w] / 255.0
    if a.shape != (h, w):
        a = np.pad(a, ((0, h - a.shape[0]), (0, w - a.shape[1])), mode="edge")
    return a


def grain(h, w, k, amt):
    return 1.0 + amt * (rng(k).random((h, w)).astype(np.float32) - 0.5)


def base(h, w, c, k, cloth=0.10, mottled=0.12):
    img = np.ones((h, w, 3), np.float32) * col(c)
    m = (1.0 - mottled * 0.5) + mottled * blocky_noise(h, w, 8, k)
    img *= (m * grain(h, w, k + 100, cloth))[..., None]
    return img


class Ink:
    """darken / lighten strokes via a PIL mask, then apply multiplicatively"""

    def __init__(self, h, w):
        self.h, self.w = h, w
        self.dark = Image.new("L", (w, h), 0)
        self.lite = Image.new("L", (w, h), 0)
        self.d = ImageDraw.Draw(self.dark)
        self.l = ImageDraw.Draw(self.lite)

    def line(self, pts, s=110, width=1, lite=False):
        (self.l if lite else self.d).line(pts, fill=s, width=width)

    def rect(self, box, s=110, lite=False, outline=False):
        dr = self.l if lite else self.d
        if outline:
            dr.rectangle(box, outline=s)
        else:
            dr.rectangle(box, fill=s)

    def poly(self, pts, s=110, lite=False, outline=False):
        dr = self.l if lite else self.d
        if outline:
            dr.polygon(pts, outline=s)
        else:
            dr.polygon(pts, fill=s)

    def apply(self, img, dark_k=0.6, lite_k=0.35):
        d = np.asarray(self.dark, np.float32)[..., None] / 255.0
        l = np.asarray(self.lite, np.float32)[..., None] / 255.0
        img = img * (1.0 - dark_k * d)
        img = img + (1.0 - img) * lite_k * l
        return img


def save(name, arr):
    arr = np.clip(arr, 0, 1)
    Image.fromarray((arr * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
    print("wrote", name, arr.shape[1], "x", arr.shape[0])


# ---------------------------------------------------------------- coat (128x128)
def coat_row(y):
    return int(round(128 * (0.045 + (0.58 - y) * 0.92)))


def coat():
    H = W = 128
    img = base(H, W, (178, 156, 116), 1, cloth=0.12, mottled=0.14)
    # soft vertical shading: a little darker toward the hem and on the back
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    uu = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    img *= (1.0 - 0.10 * yy * yy)[..., None]
    img *= (0.94 + 0.06 * (np.abs(uu - 0.5) < 0.3))[..., None]  # back a touch darker than the front
    ink = Ink(H, W)
    r = rng(2)
    # stand collar band rows 0..5 (slightly darker, top edge seam)
    img[0:6] *= 0.86
    ink.line([(0, 5), (W, 5)], 120)
    ink.line([(0, 0), (W, 0)], 90)
    shoulder, chest, belt_t, belt_b = coat_row(0.545), coat_row(0.39), coat_row(0.11), coat_row(0.065)
    hip, hem = coat_row(0.0), coat_row(-0.44)
    fx = 64  # front centre
    # lapels: V from the collar down to the chest, light upper edge, dark outline
    lap_bot = coat_row(0.33)
    for s in (-1, 1):
        pts = [(fx + s * 2, lap_bot), (fx + s * 13, shoulder + 3), (fx + s * 17, shoulder + 9), (fx + s * 6, lap_bot - 2)]
        ink.poly(pts, 60, lite=True)
        ink.line([pts[0], pts[1]], 150)
        ink.line([pts[1], pts[2]], 120)
        ink.line([pts[2], pts[3], pts[0]], 160)
    # shirt / tie V at the throat
    img[shoulder + 1:lap_bot - 2, fx - 4:fx + 5] = col((150, 150, 146))
    ink.poly([(fx - 1, shoulder + 3), (fx + 2, shoulder + 3), (fx + 1, lap_bot - 1), (fx, lap_bot - 1)], 200)  # tie
    # fly front: placket line slightly right of centre (wearer's left over right)
    ink.line([(fx + 2, lap_bot), (fx + 2, hem + 4)], 170)
    ink.line([(fx + 3, lap_bot), (fx + 3, hem + 4)], 50, lite=True)
    # buttons (hidden fly, but two showing under the lapel and one under the belt)
    for by in (lap_bot + 5, lap_bot + 17, belt_b + 9):
        ink.rect([fx - 1, by, fx + 1, by + 1], 200)
        ink.rect([fx - 1, by - 1, fx, by - 1], 70, lite=True)
    # belt with brass buckle at the front
    img[belt_t:belt_b] *= 0.80
    ink.line([(0, belt_t), (W, belt_t)], 120)
    ink.line([(0, belt_b), (W, belt_b)], 150)
    ink.line([(0, belt_t + 1), (W, belt_t + 1)], 50, lite=True)
    img[belt_t + 1:belt_b - 1, fx - 3:fx + 4] = col((150, 120, 60))
    img[belt_t + 2:belt_b - 2, fx - 1:fx + 2] = col((90, 70, 40))
    # belt loops on the sides
    for lx in (34, 94, 4, 124):
        ink.rect([lx, belt_t - 1, lx + 1, belt_b], 90)
    # gathers above and below the belt
    for i in range(16):
        x = int(r.integers(0, W))
        ink.line([(x, belt_t - int(r.integers(3, 7))), (x + int(r.integers(-1, 2)), belt_t)], 70)
        x = int(r.integers(0, W))
        ink.line([(x, belt_b), (x + int(r.integers(-2, 3)), belt_b + int(r.integers(4, 9)))], 70)
    # side seams and back centre seam
    for sx in (32, 96):
        ink.line([(sx, shoulder), (sx, hem)], 80)
    ink.line([(0, shoulder), (0, hem)], 70)
    ink.line([(W - 1, shoulder), (W - 1, hem)], 70)
    # back yoke
    ink.line([(0, shoulder + 12), (30, shoulder + 9)], 90)
    ink.line([(98, shoulder + 9), (W, shoulder + 12)], 90)
    # back vent from the seat down (split hem at the back)
    vent = coat_row(-0.18)
    for vx in (1, 2, W - 2, W - 3):
        ink.line([(vx, vent), (vx, hem + 4)], 170)
    ink.line([(1, vent), (6, vent - 3)], 120)
    # pocket flap on the right hip (u ~0.36) and a plainer one on the left
    py = coat_row(-0.07)
    for cx, s in ((44, 1.0), (84, 0.8)):
        box = [cx - 8, py, cx + 8, py + 5]
        ink.rect(box, int(40 * s), lite=True)
        ink.rect(box, int(170 * s), outline=True)
        ink.line([(cx - 8, py + 6), (cx + 8, py + 6)], int(200 * s))  # shadow under the flap
    # sleeve-shadow / armpit wrinkles on the sides of the chest
    for sx in (32, 96):
        for k in range(4):
            ink.line([(sx - 6 + k * 3, chest - 2 + k), (sx - 2 + k * 3, chest + 10 + k)], 80)
    # chest drape folds
    for s in (-1, 1):
        ink.line([(fx + s * 20, chest + 2), (fx + s * 16, belt_t - 4)], 70)
        ink.line([(fx + s * 26, chest + 6), (fx + s * 24, belt_t - 8)], 60)
    # skirt folds: long diagonal strokes down to the hem
    for i in range(18):
        x = int(r.integers(0, W))
        y0 = int(r.integers(hip, hip + 22))
        ink.line([(x, y0), (x + int(r.integers(-3, 4)), hem - int(r.integers(0, 6)))], int(r.integers(50, 95)))
    # hem: stitched band and a darker bottom edge
    ink.line([(0, hem - 4), (W, hem - 4)], 90)
    img[hem - 1:] *= 0.72
    # wear and grime near the hem and the cuffs of the pockets
    img = ink.apply(img, 0.55, 0.35)
    img[hem - 12:hem] *= (0.95 + 0.05 * blocky_noise(12, W, 4, 3))[..., None]
    save("human_coat", img)


# ---------------------------------------------------------------- sleeve (64x64)
def sleeve():
    H = W = 64
    img = base(H, W, (172, 150, 110), 4, cloth=0.12, mottled=0.14)
    ink = Ink(H, W)
    r = rng(5)
    # v 0..0.47 upper arm, 0.5..1 forearm. Front of the arm is u=0.5.
    ink.line([(0, 0), (W, 0)], 80)
    # shoulder seam / outer seam (u=0.25 is the outside of the right arm, mirrored on the left)
    ink.line([(16, 0), (16, 63)], 70)
    ink.line([(48, 0), (48, 63)], 40)
    # elbow: crease lines on the inside (front, u .5) and a stretched patch on the back (u 0)
    for k in range(5):
        y = 26 + k * 2
        ink.line([(24 + k, y), (40 - k, y + 1)], 120)
    for y in (28, 33):
        ink.line([(0, y), (8, y + 1)], 50)
        ink.line([(56, y + 1), (64, y)], 50)
    # random drape strokes
    for i in range(10):
        x = int(r.integers(0, W))
        y = int(r.integers(2, 54))
        ink.line([(x, y), (x + int(r.integers(-2, 3)), y + int(r.integers(4, 9)))], 60)
    # cuff band: darker turned-back cuff with a button on the outside
    img[54:64] *= 0.82
    ink.line([(0, 54), (W, 54)], 150)
    ink.line([(0, 55), (W, 55)], 50, lite=True)
    ink.line([(0, 63), (W, 63)], 140)
    ink.rect([15, 58, 17, 59], 210)
    img = ink.apply(img, 0.55, 0.3)
    save("human_sleeve", img)


# ---------------------------------------------------------------- trousers (64x64)
def trousers():
    H = W = 64
    img = base(H, W, (60, 60, 66), 6, cloth=0.16, mottled=0.18)
    ink = Ink(H, W)
    r = rng(7)
    # pressed creases down the front and back (u .5 and 0)
    ink.line([(32, 0), (32, 63)], 60, lite=True)
    ink.line([(33, 0), (33, 63)], 90)
    ink.line([(0, 0), (0, 63)], 70)
    ink.line([(16, 0), (16, 63)], 50)
    ink.line([(48, 0), (48, 63)], 50)
    # knee wrinkles (thigh v<.5, shin v>.5; the knee is around the seam)
    for k in range(6):
        y = 27 + k * 2
        ink.line([(22 + int(r.integers(-2, 3)), y), (42 + int(r.integers(-2, 3)), y + int(r.integers(-1, 2)))], 100)
    for k in range(4):
        y = 30 + k * 3
        ink.line([(0, y), (10, y + 1)], 70)
        ink.line([(54, y + 1), (64, y)], 70)
    # break over the shoe
    for k in range(3):
        y = 56 + k * 2
        ink.line([(20, y), (44, y + 1)], 110)
    img[61:] *= 0.75
    img = ink.apply(img, 0.5, 0.25)
    save("human_trousers", img)


# ---------------------------------------------------------------- face (64x64)
FACE_U = [0.0, 0.04, 0.10, 0.28, 0.5, 0.72, 0.90, 0.96, 1.0]


def face_row(y):
    return 64.0 * (1.0 - (y - 0.015) / 0.23)


def face_col(x, hx=0.088):
    # x: character right is +x and maps toward u<0.5 (image left), like looking at the face
    return 64.0 * (0.5 - 0.22 * (x / (hx * 0.7071)))


def face():
    H = W = 64
    skin = (212, 172, 136)
    img = base(H, W, skin, 8, cloth=0.06, mottled=0.10)
    ink = Ink(H, W)
    hair = col((34, 29, 26))
    r_hair_front = int(face_row(0.183))
    # cheek warmth and jaw / stubble shading
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    for cx in (face_col(0.05), face_col(-0.05)):
        g = np.exp(-(((xx - cx) / 4.0) ** 2 + ((yy - face_row(0.10)) / 4.0) ** 2))
        img *= (1.0 - 0.05 * g)[..., None] * np.array([1.0, 0.97, 0.97])[None, None, :] ** g[..., None]
    jaw = (yy > face_row(0.075)) & (np.abs(xx - 32) < 18)
    stub = 0.90 + 0.06 * rng(9).random((H, W)).astype(np.float32)
    img[jaw] *= stub[jaw][:, None] * np.array([0.97, 0.97, 1.0])
    # under-chin shadow
    img[int(face_row(0.035)):] *= 0.85
    # eyes: tired, heavy upper lid, small dark iris, faint bags
    ey = int(round(face_row(0.138)))
    for x in (0.032, -0.032):
        cx = int(round(face_col(x)))
        img[ey - 1:ey + 1, cx - 2:cx + 3] = col((226, 216, 204))      # white
        img[ey - 1:ey + 1, cx - 1:cx + 1] = col((40, 30, 26))         # iris (looks slightly down)
        ink.line([(cx - 3, ey - 2), (cx + 2, ey - 2)], 210)          # heavy upper lid
        ink.line([(cx - 3, ey - 1), (cx - 3, ey - 1)], 160)
        ink.line([(cx - 2, ey + 1), (cx + 2, ey + 1)], 60)           # lower lid
        ink.line([(cx - 2, ey + 2), (cx + 2, ey + 2)], 45)           # bag
        # eyelid shadow
        img[ey - 3:ey - 2, cx - 3:cx + 3] *= 0.9
    # brows: straight, low, a little thick, inner ends raised slightly (worried)
    by = int(round(face_row(0.160)))
    for x, s in ((0.032, 1), (-0.032, -1)):
        cx = int(round(face_col(x)))
        inner = cx + 3 * s
        outer = cx - 4 * s
        ink.line([(outer, by + 1), (inner, by)], 230, width=1)
        ink.line([(outer, by), (inner, by - 1)], 150, width=1)
    # nose: lit ridge, shaded side, nostrils
    nb = int(round(face_row(0.095)))
    ink.line([(32, ey - 1), (32, nb - 2)], 70, lite=True)
    ink.line([(34, ey + 1), (34, nb - 1)], 70)
    ink.line([(30, nb), (34, nb)], 80)
    ink.rect([30, nb, 30, nb], 170)
    ink.rect([34, nb, 34, nb], 170)
    ink.line([(29, nb + 1), (35, nb + 1)], 40)
    # mouth: flat, slightly down at the corners
    my = int(round(face_row(0.062)))
    ink.line([(28, my), (36, my)], 200)
    ink.line([(27, my + 1), (28, my)], 120)
    ink.line([(36, my), (37, my + 1)], 120)
    ink.line([(29, my + 2), (35, my + 2)], 50)   # lower lip shade
    ink.line([(30, my - 3), (34, my - 3)], 40)   # philtrum shade
    # nasolabial lines (tired)
    ink.line([(27, nb + 1), (25, my + 1)], 60)
    ink.line([(37, nb + 1), (39, my + 1)], 60)
    # ears (side columns u .10 / .90)
    for ex in (int(64 * 0.10), int(64 * 0.90)):
        ink.rect([ex - 2, int(face_row(0.15)), ex + 2, int(face_row(0.10))], 50)
        ink.line([(ex, int(face_row(0.145))), (ex, int(face_row(0.105)))], 120)
    img = ink.apply(img, 0.65, 0.3)
    # hair painted under the hair cap edge so the seam never shows skin
    img[:r_hair_front] = hair
    fr = rng(10)
    for x in range(W):
        u = x / 64.0
        if 0.30 < u < 0.70:
            cut = r_hair_front + int(fr.integers(0, 3)) + (2 if abs(u - 0.5) < 0.08 else 0)  # fringe tips
        elif 0.14 < u < 0.86:
            cut = int(face_row(0.165))
        elif 0.05 < u < 0.95:
            cut = int(face_row(0.115))  # sideburns / over the ears
        else:
            cut = int(face_row(0.07))   # back
        img[:cut, x] = hair * (0.9 + 0.25 * fr.random())
    # nape: skin back below the hair, a bit shaded
    save("human_face", img)


# ---------------------------------------------------------------- hair (64x32)
def hair_tex():
    H, W = 32, 64
    img = base(H, W, (36, 31, 28), 11, cloth=0.25, mottled=0.2)
    ink = Ink(H, W)
    r = rng(12)
    for i in range(70):
        x = int(r.integers(0, W))
        y = int(r.integers(0, H - 6))
        ink.line([(x, y), (x + int(r.integers(-2, 3)), y + int(r.integers(4, 10)))], int(r.integers(60, 140)), lite=bool(r.random() < 0.35))
    # dull highlight band on the crown
    img[6:10] *= 1.25
    img = ink.apply(img, 0.5, 0.18)
    img[H - 2:] *= 0.8
    save("human_hair", img)


# ---------------------------------------------------------------- hands (32x32)
def skin_tex():
    H = W = 32
    img = base(H, W, (206, 166, 130), 13, cloth=0.06, mottled=0.1)
    ink = Ink(H, W)
    # back of the hand at u .25 (cols ~8), palm at u .75 (cols ~24); fingers below v .45
    for fx in (5, 8, 11):
        ink.line([(fx, 15), (fx, 31)], 140)
    ink.line([(3, 14), (13, 14)], 70)          # knuckles
    img[:, 18:30] *= np.array([1.03, 0.97, 0.95])
    ink.line([(19, 18), (29, 20)], 90)         # palm crease
    ink.line([(20, 12), (28, 15)], 60)
    img[:3] *= 0.85                            # wrist under the cuff
    img = ink.apply(img, 0.45, 0.2)
    save("human_skin", img)


# ---------------------------------------------------------------- shoes (32x32)
def shoe_tex():
    H = W = 32
    img = base(H, W, (52, 38, 30), 14, cloth=0.12, mottled=0.2)
    ink = Ink(H, W)
    # profile: idx0..5 around -> u columns; sole is the bottom pair (u ~0.33..0.67)
    img[:, 11:21] = col((24, 20, 18)) * (0.9 + 0.1 * blocky_noise(32, 10, 2, 15))[..., None]
    ink.line([(10, 0), (10, 31)], 120)
    ink.line([(21, 0), (21, 31)], 120)
    # laces on the top (u ~0 / 1) over the instep
    for y in range(9, 18, 3):
        ink.line([(0, y), (3, y + 1)], 160)
        ink.line([(28, y + 1), (31, y)], 160)
    ink.line([(0, 8), (31, 8)], 60)   # vamp seam
    # toe cap shine
    ink.rect([2, 24, 8, 28], 60, lite=True)
    ink.rect([24, 24, 30, 28], 60, lite=True)
    img = ink.apply(img, 0.5, 0.25)
    save("human_shoe", img)


if __name__ == "__main__":
    coat()
    sleeve()
    trousers()
    face()
    hair_tex()
    skin_tex()
    shoe_tex()
