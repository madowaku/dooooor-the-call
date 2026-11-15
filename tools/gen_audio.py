"""Synthesised sound effects for DOOOOOR: THE CALL (no samples, pure numpy).
run: python tools/gen_audio.py
"""
import os
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1964)


def save(name, x, peak=0.89):
    x = np.asarray(x, np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    pcm = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("%-18s %.2fs" % (name, len(x) / SR))


def t(n):
    return np.arange(n) / SR


def onepole_lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def fft_filter(x, lo=None, hi=None, slope=4):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** (2 * slope))
    if lo:
        g *= 1 - 1 / np.sqrt(1 + (f / lo) ** (2 * slope))
    return np.fft.irfft(X * g, len(x))


def modes(n, freqs, amps, decays, phase=None):
    tt = t(n)
    y = np.zeros(n)
    for i, (f, a, d) in enumerate(zip(freqs, amps, decays)):
        ph = 0.0 if phase is None else phase[i]
        y += a * np.sin(2 * np.pi * f * tt + ph) * np.exp(-tt / d)
    return y


def noise(n):
    return rng.standard_normal(n)


# ---------------------------------------------------------------- telephone bell
GONG_A = dict(f=[1318.0, 3162.0, 5410.0, 7890.0, 2104.0], a=[1.0, 0.42, 0.2, 0.08, 0.16], d=[0.50, 0.26, 0.14, 0.08, 0.30])
GONG_B = dict(f=[1568.0, 3760.0, 6270.0, 8930.0, 2498.0], a=[0.9, 0.40, 0.18, 0.07, 0.15], d=[0.46, 0.24, 0.13, 0.07, 0.28])


def strike(gong, level, n):
    return level * modes(n, gong["f"], gong["a"], gong["d"])


def bell(ring_len=1.0, total=3.0, rate=32.0):
    """two brass gongs hit alternately by one clapper driven at 16 Hz: 32 strikes a second."""
    n = int(total * SR)
    y = np.zeros(n)
    k = 0
    tt = 0.012
    while tt < ring_len:
        i = int(tt * SR)
        g = GONG_A if k % 2 == 0 else GONG_B
        lvl = 0.55 + 0.45 * rng.random()
        if k < 2:
            lvl *= 0.6          # the clapper needs a moment to get going
        seg = strike(g, lvl, min(n - i, int(1.6 * SR)))
        y[i:i + len(seg)] += seg
        # the dull tick of the clapper itself, and the bakelite body answering
        c = int(0.004 * SR)
        y[i:i + c] += 0.5 * lvl * noise(c) * np.exp(-np.arange(c) / (0.0012 * SR))
        b = int(0.03 * SR)
        y[i:i + b] += 0.12 * lvl * np.sin(2 * np.pi * 410 * t(b)) * np.exp(-t(b) / 0.008)
        tt += (1.0 / rate) * (1 + 0.03 * rng.standard_normal())
        k += 1
    y = fft_filter(y, lo=500, hi=6800, slope=2)
    return y


ring = bell()
save("bell_ring", ring, 0.8)
# what is left of the ring when the hook switch cuts the current: gongs decay alone
n = int(1.4 * SR)
tail = strike(GONG_A, 0.7, n) + np.roll(strike(GONG_B, 0.5, n), int(0.02 * SR))
tail[: int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
save("bell_tail", fft_filter(tail, lo=500, hi=6000, slope=2), 0.5)


# ---------------------------------------------------------------- knob & latch
def click(n, f, d, lvl=1.0, nz=0.5):
    y = lvl * modes(n, [f, f * 2.31, f * 3.9], [1, 0.5, 0.25], [d, d * 0.6, d * 0.4])
    c = min(n, int(0.003 * SR))
    y[:c] += nz * noise(c) * np.exp(-np.arange(c) / (0.0008 * SR))
    return y


def place(buf, seg, at):
    i = int(at * SR)
    seg = seg[: max(0, len(buf) - i)]
    buf[i:i + len(seg)] += seg


# gacha... an empty latch: the spindle hole rattles, nothing catches
n = int(1.1 * SR)
y = np.zeros(n)
for at, lv in ((0.02, 0.9), (0.075, 0.6), (0.13, 0.75), (0.42, 0.8), (0.47, 0.5), (0.54, 0.65)):
    place(y, click(int(0.12 * SR), 860 + 120 * rng.random(), 0.018, lv, 0.9), at)
    place(y, click(int(0.1 * SR), 2350 + 300 * rng.random(), 0.01, lv * 0.4, 0.3), at + 0.006)
    place(y, 0.5 * lv * np.sin(2 * np.pi * 150 * t(int(0.08 * SR))) * np.exp(-t(int(0.08 * SR)) / 0.02), at)
save("rattle", fft_filter(y, lo=120, hi=7000, slope=2), 0.75)

# knob insert: brass spindle scraping into the square hole, then seating
n = int(0.9 * SR)
y = np.zeros(n)
sc = int(0.22 * SR)
scr = fft_filter(noise(sc), lo=2500, hi=9000, slope=2) * np.linspace(0.2, 1, sc) ** 2
scr *= 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 70 * t(sc) ** 1.2))
place(y, 0.35 * scr, 0.02)
place(y, click(int(0.5 * SR), 1980, 0.11, 1.0, 1.2), 0.25)
place(y, click(int(0.3 * SR), 3340, 0.07, 0.5, 0.3), 0.252)
place(y, 0.9 * np.sin(2 * np.pi * 120 * t(int(0.1 * SR))) * np.exp(-t(int(0.1 * SR)) / 0.025), 0.25)
save("knob_insert", y, 0.8)

# knob remove: reverse feeling, a pull and a small ring of brass in the hand
n = int(0.7 * SR)
y = np.zeros(n)
place(y, click(int(0.1 * SR), 900, 0.015, 0.7, 1.0), 0.02)
sc = int(0.16 * SR)
scr = fft_filter(noise(sc), lo=2500, hi=9000, slope=2) * np.linspace(1, 0.1, sc)
place(y, 0.3 * scr, 0.05)
place(y, click(int(0.45 * SR), 2620, 0.16, 0.6, 0.2), 0.2)
save("knob_remove", y, 0.7)

# knob turn: latch bolt drawn back - two clicks
n = int(0.45 * SR)
y = np.zeros(n)
place(y, click(int(0.1 * SR), 1250, 0.012, 0.7, 1.0), 0.01)
place(y, click(int(0.15 * SR), 760, 0.03, 1.0, 1.0), 0.12)
place(y, 0.8 * np.sin(2 * np.pi * 95 * t(int(0.1 * SR))) * np.exp(-t(int(0.1 * SR)) / 0.03), 0.12)
save("knob_turn", y, 0.7)

# palm on the blank side of a door
n = int(0.5 * SR)
tt = t(n)
y = np.sin(2 * np.pi * (78 + 40 * np.exp(-tt / 0.02)) * tt) * np.exp(-tt / 0.07)
y += 0.4 * np.sin(2 * np.pi * 212 * tt) * np.exp(-tt / 0.03)
y[: int(0.004 * SR)] += 0.6 * noise(int(0.004 * SR))
save("thud", fft_filter(y, hi=1800), 0.8)


# ---------------------------------------------------------------- heavy door
def door_move(dur=2.3):
    n = int(dur * SR)
    tt = t(n)
    env = np.sin(np.pi * np.clip(tt / dur, 0, 1)) ** 0.7
    rumble = fft_filter(noise(n), lo=28, hi=150, slope=3) * 7.0
    roll = fft_filter(noise(n), lo=180, hi=700, slope=2) * (0.6 + 0.4 * np.sin(2 * np.pi * 7.5 * tt)) * 1.2
    # stick-slip groan of the pivot: a sawtooth whose pitch wanders with the speed of the leaf
    f = 58 + 46 * env + 6 * np.sin(2 * np.pi * 0.9 * tt)
    ph = 2 * np.pi * np.cumsum(f) / SR
    groan = np.zeros(n)
    for h in range(1, 9):
        groan += np.sin(h * ph) / h
    groan = fft_filter(groan, lo=90, hi=1300, slope=2) * (0.35 + 0.65 * (np.sin(2 * np.pi * 2.3 * tt + 1) > -0.2))
    y = env * (rumble + roll + 0.75 * groan)
    return y


save("door_move", door_move(), 0.85)

n = int(0.9 * SR)
tt = t(n)
y = np.sin(2 * np.pi * (52 + 50 * np.exp(-tt / 0.03)) * tt) * np.exp(-tt / 0.16)
y += 0.5 * fft_filter(noise(n), lo=200, hi=2400, slope=2) * np.exp(-tt / 0.035)
place(y, click(int(0.2 * SR), 690, 0.04, 0.5, 0.8), 0.09)
place(y, 0.25 * fft_filter(noise(int(0.5 * SR)), lo=60, hi=300) * np.exp(-t(int(0.5 * SR)) / 0.2), 0.05)
save("door_seat", y, 0.9)


# ---------------------------------------------------------------- receiver
n = int(1.3 * SR)
y = np.zeros(n)
place(y, click(int(0.08 * SR), 1500, 0.006, 0.8, 1.2), 0.03)
place(y, click(int(0.1 * SR), 980, 0.012, 1.0, 1.0), 0.085)
place(y, 0.7 * np.sin(2 * np.pi * 240 * t(int(0.06 * SR))) * np.exp(-t(int(0.06 * SR)) / 0.012), 0.085)
ru = int(0.35 * SR)
place(y, 0.1 * fft_filter(noise(ru), lo=900, hi=5000) * np.hanning(ru), 0.2)   # handset brushing the cradle
save("receiver_lift", y, 0.7)


# ---------------------------------------------------------------- loops
def loop_noise(n, lo, hi, slope=2):
    x = fft_filter(noise(n * 2), lo=lo, hi=hi, slope=slope)
    w = np.linspace(0, 1, n)
    return x[:n] * np.sqrt(w) + x[n:] * np.sqrt(1 - w)


n = 8 * SR
tt = t(n)
tone = 0.50 * np.sin(2 * np.pi * 50 * tt) + 0.22 * np.sin(2 * np.pi * 100 * tt + 0.4) + 0.06 * np.sin(2 * np.pi * 150 * tt + 1.1)
air = 1.4 * loop_noise(n, 30, 420, 2) + 0.25 * loop_noise(n, 900, 3200, 1)
breath = 0.85 + 0.15 * np.sin(2 * np.pi * tt / 8.0)
save("room_tone", (0.16 * tone + air) * breath, 0.5)

n = 4 * SR
tt = t(n)
bz = np.zeros(n)
for h in range(1, 28):
    bz += np.sin(2 * np.pi * 100 * h * tt + rng.random() * 6.28) / (h ** 0.75)
bz *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * tt)
bz = fft_filter(bz, lo=350, hi=5200, slope=1) + 0.03 * loop_noise(n, 2000, 8000, 1)
save("fluoro_buzz", bz, 0.4)

n = 2 * SR
y = np.zeros(n)
place(y, click(int(0.06 * SR), 2900, 0.005, 1.0, 1.4), 0.0)
place(y, click(int(0.06 * SR), 2300, 0.006, 0.8, 1.2), 1.0)
place(y, 0.2 * np.sin(2 * np.pi * 420 * t(int(0.05 * SR))) * np.exp(-t(int(0.05 * SR)) / 0.01), 0.0)
place(y, 0.2 * np.sin(2 * np.pi * 360 * t(int(0.05 * SR))) * np.exp(-t(int(0.05 * SR)) / 0.01), 1.0)
save("clock_tick", y, 0.5)

n = 6 * SR
hum = np.zeros(n)
tt = t(n)
for f, a in ((50, 1.0), (100, 0.5), (200, 0.2), (300, 0.12), (117, 0.25)):
    hum += a * np.sin(2 * np.pi * f * tt)
hum += 1.2 * loop_noise(n, 100, 900, 2)
save("vending_hum", hum, 0.5)

# start: one low soft bell, like a console waking
n = int(1.8 * SR)
tt = t(n)
y = np.sin(2 * np.pi * 220 * tt + 2.2 * np.exp(-tt / 0.25) * np.sin(2 * np.pi * 440 * tt)) * np.exp(-tt / 0.5)
y += 0.5 * np.sin(2 * np.pi * 329.6 * tt) * np.exp(-tt / 0.7)
y[:200] *= np.linspace(0, 1, 200)
save("ui_start", y, 0.6)

# a small ring of brass: the knob catching the light
n = int(0.9 * SR)
save("knob_ting", modes(n, [2620, 6040, 9100], [1, 0.4, 0.15], [0.22, 0.12, 0.06]), 0.35)
# the same ring as it arrives through a wall: no brass left, only the clapper drumming on the
# bakelite body and the table. same length and timing as bell_ring so the two loops stay locked.
env = fft_filter(np.abs(ring), hi=70, slope=2)
env = np.clip(env, 0, None)
nn = len(ring)
tt = t(nn)
body = 0.8 * np.sin(2 * np.pi * 205 * tt) + 0.5 * np.sin(2 * np.pi * 131 * tt + 0.7) + 0.35 * np.sin(2 * np.pi * 322 * tt + 1.9)
body += 1.2 * fft_filter(noise(nn), lo=90, hi=380, slope=3)
wallb = fft_filter(env * body, lo=70, hi=430, slope=3)
save("bell_wall", wallb, 0.7)

# ---------------------------------------------------------------- our own hinge squeal (replaces a third-party sample)
n = int(2.2 * SR)
tt = t(n)
wander = fft_filter(noise(n), hi=2.5, slope=2)
wander /= np.max(np.abs(wander)) + 1e-9
f = 760 + 420 * wander + 90 * np.sin(2 * np.pi * 0.7 * tt)
ph = 2 * np.pi * np.cumsum(f) / SR
sq = np.zeros(n)
for h in range(1, 7):
    sq += np.sin(h * ph + 0.3 * h) / h ** 1.2
grip = fft_filter(noise(n), hi=7, slope=2)
grip /= np.max(np.abs(grip)) + 1e-9
gate = np.clip(grip * 2.2 + 0.25, 0, 1) ** 2
sq = fft_filter(sq * gate, lo=520, hi=5200, slope=2) * np.sin(np.pi * np.clip(tt / 2.2, 0, 1)) ** 0.6
save("door_squeak", sq, 0.5)

# ---------------------------------------------------------------- the line, after the receiver is lifted
# nobody speaks. a rotary dial is wound and let go, twice. then, through the earpiece, another bell.
n = int(23 * SR)
tt = t(n)
line = 0.05 * fft_filter(noise(n), lo=300, hi=3400, slope=2) * np.clip(tt / 1.2, 0, 1)
line += 0.012 * np.sin(2 * np.pi * 150 * tt) + 0.008 * np.sin(2 * np.pi * 250 * tt + 1.0)


def dial(buf, digit, at):
    w = 0.14 + 0.07 * digit
    k = int(w * SR)
    wind = fft_filter(noise(k), lo=900, hi=3000, slope=2) * np.linspace(0.3, 1, k) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t(k)))
    place(buf, 0.22 * wind, at)
    place(buf, click(int(0.05 * SR), 1500, 0.006, 0.6, 1.0), at + w)
    r0 = at + w + 0.16
    k = int((digit * 0.1 + 0.12) * SR)
    place(buf, 0.10 * fft_filter(noise(k), lo=1500, hi=3200, slope=2), r0)
    for i in range(digit):
        place(buf, click(int(0.04 * SR), 1900 + 60 * rng.random(), 0.004, 0.8, 1.2), r0 + 0.05 + i * 0.1)
    place(buf, click(int(0.06 * SR), 900, 0.01, 0.7, 1.0), r0 + digit * 0.1 + 0.1)


dial(line, 3, 1.3)
dial(line, 7, 2.9)
FAR_A = dict(f=[988.0, 2370.0, 4050.0, 1580.0], a=[1.0, 0.4, 0.15, 0.2], d=[0.62, 0.3, 0.16, 0.36])
FAR_B = dict(f=[1175.0, 2820.0, 4700.0, 1880.0], a=[0.9, 0.38, 0.14, 0.18], d=[0.58, 0.28, 0.15, 0.33])
k = int(2.8 * SR)
one = np.zeros(k)
at = 0.01
j = 0
while at < 1.0:
    seg = strike(FAR_A if j % 2 == 0 else FAR_B, 0.6 + 0.4 * rng.random(), k - int(at * SR))
    one[int(at * SR):] += seg[: k - int(at * SR)]
    at += (1.0 / 22.0) * (1 + 0.04 * rng.standard_normal())
    j += 1
ir = noise(int(1.1 * SR)) * np.exp(-t(int(1.1 * SR)) / 0.28)
N2 = k + len(ir)
wet = np.fft.irfft(np.fft.rfft(one, N2) * np.fft.rfft(ir, N2), N2)[:k]
one = one / (np.max(np.abs(one)) + 1e-9) + 0.9 * wet / (np.max(np.abs(wet)) + 1e-9)
for r in range(6):
    place(line, 0.34 * one, 5.8 + 3.0 * r)
line = np.tanh(2.2 * fft_filter(line, lo=320, hi=3100, slope=3))
save("line_next", line, 0.6)
n = int(0.3 * SR)
y = np.zeros(n)
place(y, click(int(0.08 * SR), 1250, 0.008, 1.0, 1.4), 0.01)
place(y, 0.6 * np.sin(2 * np.pi * 110 * t(int(0.12 * SR))) * np.exp(-t(int(0.12 * SR)) / 0.03), 0.01)
save("line_cut", y, 0.45)


# ================================================================ chapters 2-4
# appended below everything else on purpose: the one seeded rng above must stay in step so the
# chapter-1 sounds come out bit-identical. add new sounds only after this point.

def fade_tail(y, a, b):
    """cosine fade from a to b seconds and true silence after: the loop ends where it starts."""
    i0, i1 = int(a * SR), int(b * SR)
    y = y.copy()
    y[i0:i1] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, i1 - i0))
    y[i1:] = 0
    return y


def fade_end(y, sec):
    k = int(sec * SR)
    y = y.copy()
    y[-k:] *= np.linspace(1, 0, k)
    return y


def wall_of(ring_x, body_tones, lo, hi):
    """a ring as it arrives through walls: only its envelope drumming on a dull body."""
    env = np.clip(fft_filter(np.abs(ring_x), hi=70, slope=2), 0, None)
    nn = len(ring_x)
    tt = t(nn)
    body = np.zeros(nn)
    for f, a, p in body_tones:
        body += a * np.sin(2 * np.pi * f * tt + p)
    body += 1.2 * fft_filter(noise(nn), lo=lo, hi=hi, slope=3)
    return fft_filter(env * body, lo=lo, hi=hi, slope=3)


def cconv(x, h):
    """circular convolution: whatever rings past the end comes back in at the start."""
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h, len(x)), len(x))


def lconv(x, h):
    N2 = len(x) + len(h)
    return np.fft.irfft(np.fft.rfft(x, N2) * np.fft.rfft(h, N2), N2)[: len(x)]


# ---------------------------------------------------------------- ch2: pink public telephone
# a cheaper electric ringer: one small gong and a second slightly detuned one, a lighter clapper,
# and a thin plastic case that chatters against its screws.
GONG2_A = dict(f=[1046.0, 2391.0, 3934.0, 5620.0, 1709.0], a=[1.0, 0.5, 0.26, 0.1, 0.22], d=[0.34, 0.17, 0.09, 0.05, 0.2])
GONG2_B = dict(f=[1081.0, 2466.0, 4071.0, 5790.0, 1765.0], a=[0.85, 0.46, 0.24, 0.09, 0.2], d=[0.32, 0.16, 0.09, 0.05, 0.19])


def bell2(ring_len=1.0, total=3.0, rate=25.0):
    n = int(total * SR)
    y = np.zeros(n)
    k = 0
    at = 0.010
    while at < ring_len:
        i = int(at * SR)
        g = GONG2_A if k % 2 == 0 else GONG2_B
        lvl = 0.6 + 0.4 * rng.random()
        if k < 2:
            lvl *= 0.55
        seg = strike(g, lvl, min(n - i, int(1.4 * SR)))
        y[i:i + len(seg)] += seg
        c = int(0.005 * SR)
        y[i:i + c] += 0.7 * lvl * noise(c) * np.exp(-np.arange(c) / (0.0015 * SR))
        r = int(0.03 * SR)
        rat = fft_filter(noise(r), lo=900, hi=3800, slope=2) * np.exp(-t(r) / 0.007)
        rat *= np.sin(2 * np.pi * 190 * t(r)) > 0          # the case lid chattering on and off its seat
        place(y, 0.35 * lvl * rat, at + 0.004 + 0.004 * rng.random())
        b = int(0.04 * SR)
        y[i:i + b] += 0.18 * lvl * np.sin(2 * np.pi * 560 * t(b)) * np.exp(-t(b) / 0.012)
        at += (1.0 / rate) * (1 + 0.035 * rng.standard_normal())
        k += 1
    y = fft_filter(y, lo=420, hi=6200, slope=2)
    y = np.tanh(1.7 * y / (np.max(np.abs(y)) + 1e-9))   # the cheap ringer's harsh edge
    return fade_tail(y, 1.9, 2.4)


ring2 = bell2()
save("bell2_ring", ring2, 0.78)
save("bell2_wall", wall_of(ring2, ((160, 0.8, 0.0), (108, 0.5, 0.7), (262, 0.35, 1.9)), 80, 400), 0.7)
n = int(1.4 * SR)
tl = strike(GONG2_A, 0.7, n)
place(tl, strike(GONG2_B, 0.5, n), 0.02)
tl[: int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
save("bell2_tail", fade_end(fft_filter(tl, lo=420, hi=6000, slope=2), 0.15), 0.5)


# ---------------------------------------------------------------- ch3: wall bell in the basement bath
# one large gong (a split doublet on the fundamental for a slow warble), slow heavy clapper.
GONG3 = dict(f=[742.0, 745.6, 1183.0, 1611.0, 2167.0, 2604.0, 3472.0],
             a=[1.0, 0.55, 0.45, 0.3, 0.2, 0.12, 0.06],
             d=[0.55, 0.52, 0.4, 0.28, 0.19, 0.13, 0.08])


def bell3(ring_len=1.0, total=3.0, rate=14.0):
    n = int(total * SR)
    y = np.zeros(n)
    k = 0
    at = 0.012
    while at < ring_len:
        i = int(at * SR)
        lvl = 0.7 + 0.3 * rng.random()
        if k < 1:
            lvl *= 0.7
        seg = strike(GONG3, lvl, min(n - i, int(2.4 * SR)))
        y[i:i + len(seg)] += seg
        c = int(0.005 * SR)
        y[i:i + c] += 0.6 * lvl * noise(c) * np.exp(-np.arange(c) / (0.0015 * SR))
        b = int(0.05 * SR)
        y[i:i + b] += 0.25 * lvl * np.sin(2 * np.pi * 310 * t(b)) * np.exp(-t(b) / 0.015)
        at += (1.0 / rate) * (1 + 0.03 * rng.standard_normal())
        k += 1
    y = fft_filter(y, lo=300, hi=7000, slope=2)
    return fade_tail(y, 2.35, 2.95)


ring3 = bell3()
save("bell3_ring", ring3, 0.8)
save("bell3_wall", wall_of(ring3, ((96, 1.0, 0.0), (148, 0.6, 0.7), (231, 0.35, 1.9)), 60, 330), 0.7)
n = int(1.8 * SR)
tl = strike(GONG3, 0.8, n)
tl[: int(0.015 * SR)] *= np.linspace(0, 1, int(0.015 * SR))
save("bell3_tail", fade_end(fft_filter(tl, lo=300, hi=6500, slope=2), 0.2), 0.5)

# the same bell at the mouth of a long sheet-metal duct: tube modes every 148 Hz (so the 742 Hz
# fundamental sits on the 5th), a flutter echo off the far bend, a springy boing after each hit.
N = len(ring3)
X = np.fft.rfft(ring3)
fq = np.fft.rfftfreq(N, 1 / SR)
tube = (1 - 0.86) / (1 - 0.86 * np.exp(-2j * np.pi * fq / 148.0))
flut = (1 - 0.55) / (1 - 0.55 * np.exp(-2j * np.pi * fq * 0.023))
piped = np.fft.irfft(X * (0.15 + 0.7 * tube + 0.3 * flut), N)
k = int(0.16 * SR)
tk = t(k)
boing = np.sin(2 * np.pi * (350 * tk + (1300 - 350) * 0.03 * (1 - np.exp(-tk / 0.03)))) * np.exp(-tk / 0.05)
bo = cconv(piped, boing)
bo *= np.sqrt(np.mean(piped ** 2) / (np.mean(bo ** 2) + 1e-12))
piped = fft_filter(piped + 0.45 * bo, lo=200, hi=2600, slope=3)
piped = np.tanh(1.4 * piped / (np.max(np.abs(piped)) + 1e-9))
save("bell3_pipe", piped, 0.85)


# ---------------------------------------------------------------- ch4: knocking on a heavy wooden door
def knock(lvl, kind="air"):
    if kind == "wall":
        n = int(0.6 * SR)
        tt = t(n)
        y = np.sin(2 * np.pi * (60 * tt + 40 * 0.035 * (1 - np.exp(-tt / 0.035)))) * np.exp(-tt / 0.12)
        y += 0.45 * np.sin(2 * np.pi * 118 * tt) * np.exp(-tt / 0.08)
        y += 0.5 * fft_filter(noise(n), lo=50, hi=160, slope=3) * np.exp(-tt / 0.07)
    else:
        n = int(0.35 * SR)
        tt = t(n)
        y = np.sin(2 * np.pi * (105 * tt + 45 * 0.012 * (1 - np.exp(-tt / 0.012)))) * np.exp(-tt / 0.045)
        y += modes(n, [196, 243, 412, 618], [0.55, 0.35, 0.22, 0.12], [0.035, 0.026, 0.016, 0.01])
        c = int(0.02 * SR)
        y[:c] += 0.55 * fft_filter(noise(c), lo=1000, hi=3000, slope=2) * np.exp(-t(c) / 0.0035)
        y += 0.25 * modes(n, [1720, 2460], [1.0, 0.6], [0.006, 0.004])
    r = int(0.0015 * SR)
    y[:r] *= np.linspace(0, 1, r)
    return lvl * y


KNOCKS = ((0.00, 1.0), (0.42, 0.9), (0.84, 0.72))
n = 4 * SR
kn = np.zeros(n)
knw = np.zeros(n)
for at, lv in KNOCKS:
    lv *= 0.95 + 0.1 * rng.random()
    place(kn, knock(lv, "air"), at)
    place(knw, knock(lv, "wall"), at)
k = int(0.5 * SR)
ir = fft_filter(noise(k), lo=150, hi=2500, slope=2) * np.exp(-t(k) / 0.08)
wet = cconv(kn, ir)
kn = kn + 0.3 * wet * np.sqrt(np.mean(kn ** 2) / (np.mean(wet ** 2) + 1e-12))
# no whole-buffer filtering here: a zero-phase high-pass would smear a pre-swell in front of the
# knock at 0.00 s and wrap it onto the loop end. the parts are band-limited inside knock() already.
save("knock_ring", kn, 0.85)
save("knock_wall", knw, 0.8)

n = int(0.4 * SR)
y = np.zeros(n)
place(y, click(int(0.25 * SR), 2870, 0.03, 1.0, 1.0), 0.01)
place(y, 0.5 * modes(int(0.3 * SR), [1930, 4410, 6720], [1, 0.5, 0.25], [0.05, 0.025, 0.012]), 0.01)
place(y, click(int(0.2 * SR), 3150, 0.02, 0.45, 0.6), 0.048)           # the pipe settling in its bracket
place(y, 0.3 * np.sin(2 * np.pi * 180 * t(int(0.1 * SR))) * np.exp(-t(int(0.1 * SR)) / 0.02), 0.01)
save("pipe_tick", fade_end(fft_filter(y, lo=150, hi=9000, slope=2), 0.05), 0.6)


# ---------------------------------------------------------------- water
def plink(scale=1.0, n=None):
    """the drop's bubble: a sine gliding upward as it rings."""
    n = n or int(0.25 * SR)
    tt = t(n)
    f = scale * (820 + 900 * (1 - np.exp(-tt / 0.02)))
    ph = 2 * np.pi * (np.cumsum(f) - f[0]) / SR
    return np.sin(ph) * np.exp(-tt / 0.035)


n = int(0.6 * SR)
y = np.zeros(n)
place(y, 0.4 * click(int(0.05 * SR), 2100, 0.003, 0.5, 0.8), 0.028)
place(y, 0.9 * plink(1.0), 0.03)
place(y, 0.25 * modes(int(0.5 * SR), [512, 1345, 2620], [1, 0.5, 0.25], [0.16, 0.09, 0.05]), 0.028)   # the bucket
k = int(0.4 * SR)
ir = noise(k) * np.exp(-t(k) / 0.09)
wet = lconv(y, ir)
y = y + 0.25 * wet * np.max(np.abs(y)) / (np.max(np.abs(wet)) + 1e-9)
save("drip", fade_end(fft_filter(y, lo=120, hi=9000, slope=2), 0.05), 0.5)


# ---------------------------------------------------------------- the lines of chapters 2 and 3
def line_base(n):
    tt = t(n)
    ln = 0.05 * fft_filter(noise(n), lo=300, hi=3400, slope=2) * np.clip(tt / 1.2, 0, 1)
    ln += 0.012 * np.sin(2 * np.pi * 150 * tt) + 0.008 * np.sin(2 * np.pi * 250 * tt + 1.0)
    return ln


def line_drips(ln):
    """a tap dripping in the caller's room."""
    at = 0.35 + 0.5 * rng.random()
    while at < len(ln) / SR - 0.3:
        place(ln, 0.09 * (0.7 + 0.3 * rng.random()) * plink(0.85 + 0.3 * rng.random()), at)
        at += 1.1 + 0.5 * rng.random()


n = int(23 * SR)
l2 = line_base(n)
line_drips(l2)
dial(l2, 5, 1.3)
dial(l2, 2, 3.1)
k = int(2.9 * SR)
one3 = np.zeros(k)
at = 0.01
while at < 1.0:
    i = int(at * SR)
    one3[i:] += strike(GONG3, 0.6 + 0.4 * rng.random(), k - i)
    at += (1.0 / 14.0) * (1 + 0.03 * rng.standard_normal())
ir = noise(int(1.6 * SR)) * np.exp(-t(int(1.6 * SR)) / 0.45)   # tiles
wet = lconv(one3, ir)
one3 = 0.5 * one3 / (np.max(np.abs(one3)) + 1e-9) + wet / (np.max(np.abs(wet)) + 1e-9)
one3 = fade_end(fft_filter(one3, lo=600, hi=2600, slope=2), 0.4)
for r in range(6):
    place(l2, 0.3 * one3 / (np.max(np.abs(one3)) + 1e-9), 5.8 + 3.0 * r)
l2 = np.tanh(2.2 * fft_filter(l2, lo=320, hi=3100, slope=3))
save("line2", l2, 0.6)

l3 = line_base(n)
line_drips(l3)
dial(l3, 4, 1.3)
dial(l3, 4, 3.1)
for r in range(5):
    for dt, lv in KNOCKS:
        kk = knock(lv * (0.95 + 0.1 * rng.random()), "air")
        place(l3, 0.6 * np.tanh(4.0 * kk), 5.8 + 4.0 * r + dt)    # close to the mouthpiece: it overloads
l3 = np.tanh(2.2 * fft_filter(l3, lo=320, hi=3100, slope=3))
save("line3", l3, 0.6)


# ---------------------------------------------------------------- the dial, heard in the room
n = int(0.55 * SR)
y = np.zeros(n)
place(y, click(int(0.06 * SR), 1100, 0.01, 0.5, 0.8), 0.005)          # fingertip into the hole
k = int(0.44 * SR)
tk = t(k)
wind = fft_filter(noise(k), lo=700, hi=5200, slope=2) * np.linspace(0.35, 1, k) * (0.55 + 0.45 * np.sin(2 * np.pi * 42 * tk) ** 2)
place(y, 0.45 * wind, 0.03)
place(y, 0.12 * np.sin(2 * np.pi * 130 * tk) * np.linspace(0.3, 1, k), 0.03)   # the spring tightening
for i in range(int(0.44 * 44)):
    place(y, click(int(0.01 * SR), 2600 + 200 * rng.random(), 0.0015, 0.12, 0.3), 0.03 + i / 44.0)
place(y, click(int(0.1 * SR), 820, 0.02, 1.0, 1.0), 0.48)            # finger stop
place(y, 0.5 * np.sin(2 * np.pi * 160 * t(int(0.06 * SR))) * np.exp(-t(int(0.06 * SR)) / 0.02), 0.48)
save("dial_wind", fade_end(fft_filter(y, lo=90, hi=9000, slope=2), 0.02), 0.7)

n = int(1.0 * SR)
y = np.zeros(n)
k = int(0.72 * SR)
tk = t(k)
whirr = fft_filter(noise(k), lo=1300, hi=4200, slope=2) * (0.7 + 0.3 * np.sin(2 * np.pi * 55 * tk))
whirr *= np.minimum(1, tk / 0.02) * np.linspace(1, 0.6, k)
place(y, 0.18 * whirr, 0.03)                                          # the governor spinning
for i in range(6):
    place(y, click(int(0.04 * SR), 1900 + 60 * rng.random(), 0.004, 0.8, 1.2), 0.08 + i * 0.1)
place(y, click(int(0.12 * SR), 640, 0.025, 0.7, 0.4), 0.75)          # soft stop
place(y, 0.4 * np.sin(2 * np.pi * 120 * t(int(0.1 * SR))) * np.exp(-t(int(0.1 * SR)) / 0.03), 0.75)
place(y, click(int(0.06 * SR), 700, 0.01, 0.2, 0.2), 0.79)
save("dial_return", fade_end(fft_filter(y, lo=90, hi=9000, slope=2), 0.03), 0.7)


# ---------------------------------------------------------------- finale: the first bell, far inside the building
n = 6 * SR
fb = np.zeros(n)
place(fb, ring, 0.3)
place(fb, ring, 3.3)
fb = fft_filter(fb, hi=900, slope=4)
k = int(2.2 * SR)
ir = fft_filter(noise(k), hi=1400, slope=2) * np.exp(-t(k) / 0.55)
wet = lconv(fb, ir)
far = 0.35 * fb / (np.max(np.abs(fb)) + 1e-9) + wet / (np.max(np.abs(wet)) + 1e-9)
save("far_bell1", fade_end(fft_filter(far, lo=60, hi=900, slope=4), 0.5), 0.3)


# ---------------------------------------------------------------- ambience loops
def drops(rate, n):
    imp = np.zeros(n)
    cnt = rng.poisson(rate * n / SR)
    np.add.at(imp, rng.integers(0, n, cnt), rng.random(cnt) ** 2)
    return imp


n = 8 * SR
tt = t(n)
hiss = 0.35 * loop_noise(n, 1800, 9000, 1) + 0.5 * loop_noise(n, 250, 1200, 2)
tin1 = modes(int(0.05 * SR), [3150, 4720, 6900], [1, 0.6, 0.3], [0.006, 0.004, 0.003])
tin2 = modes(int(0.05 * SR), [2480, 3890, 5600], [1, 0.5, 0.3], [0.007, 0.004, 0.003])
board = modes(int(0.06 * SR), [380, 610, 1150], [1, 0.6, 0.3], [0.012, 0.008, 0.005])
rain = 0.5 * cconv(drops(220, n), tin1) + 0.5 * cconv(drops(220, n), tin2) + 0.4 * cconv(drops(400, n), board)
swell = 1 + 0.08 * np.sin(2 * np.pi * tt / 8.0) + 0.05 * np.sin(2 * np.pi * 3 * tt / 8.0 + 1.0)
save("rain_loop", fft_filter((hiss + rain) * swell, lo=120, hi=10000, slope=2), 0.45)

n = 6 * SR
tt = t(n)
throb = 1 + 0.25 * np.sin(2 * np.pi * 0.5 * tt) + 0.1 * np.sin(2 * np.pi * tt / 3.0 + 1.0)
burn = 1 + 0.15 * np.sin(2 * np.pi * 12.5 * tt)
tone = 0.6 * np.sin(2 * np.pi * 50 * tt) + 0.35 * np.sin(2 * np.pi * 75 * tt + 0.3) + 0.3 * np.sin(2 * np.pi * 100 * tt + 1.0) + 0.12 * np.sin(2 * np.pi * 117.5 * tt)
rumble = 2.0 * loop_noise(n, 45, 125, 3)
save("boiler_hum", (0.25 * tone + rumble * burn) * throb + 0.06 * loop_noise(n, 2500, 8000, 1), 0.5)
# ---------------------------------------------------------------- the lines again, each carrying one digit
# what the caller dials is a number, one digit per telephone: 5, 0, 5. a rotary dial says a digit as
# that many pulses (ten for zero), so the number can be counted by ear without anybody speaking.
PULSE_GAP = 0.14


def dial_num(buf, digit, at):
    """one slow, deliberate turn of the dial. returns the time of the first pulse."""
    npulse = 10 if digit == 0 else digit
    w = 0.25 + 0.09 * npulse
    k = int(w * SR)
    wind = fft_filter(noise(k), lo=900, hi=3000, slope=2) * np.linspace(0.3, 1, k) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t(k)))
    place(buf, 0.2 * wind, at)
    place(buf, click(int(0.05 * SR), 1500, 0.006, 0.6, 1.0), at + w)
    r0 = at + w + 0.25
    k = int((npulse * PULSE_GAP + 0.1) * SR)
    place(buf, 0.07 * fft_filter(noise(k), lo=1500, hi=3200, slope=2), r0 - 0.04)
    for i in range(npulse):
        place(buf, 1.25 * click(int(0.05 * SR), 1750 + 40 * rng.random(), 0.006, 0.9, 1.4), r0 + i * PULSE_GAP)
        place(buf, 0.5 * np.sin(2 * np.pi * 420 * t(int(0.03 * SR))) * np.exp(-t(int(0.03 * SR)) / 0.006), r0 + i * PULSE_GAP)
    place(buf, click(int(0.06 * SR), 900, 0.01, 0.7, 1.0), r0 + npulse * PULSE_GAP + 0.06)
    # somebody is close to the mouthpiece while the dial runs: not a voice, only air
    k = int((npulse * PULSE_GAP + 1.2) * SR)
    air_ = fft_filter(noise(k), lo=420, hi=1300, slope=2) * np.hanning(k) ** 1.5
    place(buf, 0.045 * air_, r0 - 0.6)
    return r0


n = int(23 * SR)
la = line_base(n)
print("pulse start line_a1 %.3f" % dial_num(la, 5, 1.5))
for r in range(6):
    place(la, 0.34 * one, 5.8 + 3.0 * r)
save("line_a1", np.tanh(2.2 * fft_filter(la, lo=320, hi=3100, slope=3)), 0.6)

lb = line_base(n)
line_drips(lb)
print("pulse start line_a2 %.3f" % dial_num(lb, 0, 1.5))
for r in range(6):
    place(lb, 0.3 * one3 / (np.max(np.abs(one3)) + 1e-9), 5.8 + 3.0 * r)
save("line_a2", np.tanh(2.2 * fft_filter(lb, lo=320, hi=3100, slope=3)), 0.6)

lc = line_base(n)
line_drips(lc)
print("pulse start line_a3 %.3f" % dial_num(lc, 5, 1.5))
for r in range(5):
    for dt, lv in KNOCKS:
        place(lc, 0.6 * np.tanh(4.0 * knock(lv * (0.95 + 0.1 * rng.random()), "air")), 5.8 + 4.0 * r + dt)
save("line_a3", np.tanh(2.2 * fft_filter(lc, lo=320, hi=3100, slope=3)), 0.6)

# the hint for a wrong number: the three digits again, as pulses, on a dead line
n = int(9.5 * SR)
lh = line_base(n) * 0.6
at_ = 0.5
for dg in (5, 0, 5):
    r0_ = dial_num(lh, dg, at_)
    at_ = r0_ + (10 if dg == 0 else dg) * PULSE_GAP + 0.75
print("hint length used %.2f" % at_)
save("line_hint", np.tanh(2.2 * fft_filter(lh, lo=320, hi=3100, slope=3)), 0.55)
# a number that does not exist
n = int(1.6 * SR)
tt = t(n)
dead = np.sin(2 * np.pi * 400 * tt) * (np.sin(2 * np.pi * 2.0 * tt) > 0) * 0.5
save("line_dead", fft_filter(dead + 0.03 * noise(n), lo=320, hi=3100, slope=3), 0.3)
print("done")
