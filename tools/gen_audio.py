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
print("done")
