# Original soundtrack for the island intro (60s, 128 BPM, D major, upbeat), synthesized from scratch.
# Music + UI sound effects are timed to the video's beats (see index.html B / S).
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 48000
DUR = 60.0
N = int(SR * DUR)
rng = np.random.default_rng(11)
T = np.arange(N) / SR

def midi(m): return 440.0 * 2 ** ((m - 69) / 12)
def lp(x, fc, order=2): return sosfilt(butter(order, fc, 'low', fs=SR, output='sos'), x)
def hp(x, fc, order=2): return sosfilt(butter(order, fc, 'high', fs=SR, output='sos'), x)
def bp(x, lo, hi): return sosfilt(butter(2, [lo, hi], 'band', fs=SR, output='sos'), x)
def seg(t0, dur): i0 = int(t0 * SR); return i0, min(N, i0 + int(dur * SR))
def env_adsr(n, a, r, sus=1.0):
    e = np.ones(n) * sus
    na, nr = min(n, int(a * SR)), min(n, int(r * SR))
    e[:na] = np.linspace(0, sus, na)
    if nr: e[-nr:] *= np.linspace(1, 0, nr)
    return e
def add(buf, i0, sig):
    i0 = max(0, i0); i1 = min(len(buf), i0 + len(sig))
    if i0 < i1: buf[i0:i1] += sig[:i1 - i0]
def saw(f, n, phase=0.0):
    t = np.arange(n) / SR
    return 2 * ((f * t + phase) % 1.0) - 1
def ramp(t, a, b): return np.clip((t - a) / (b - a), 0, 1)
def smooth(x): return x * x * (3 - 2 * x)

L = np.zeros(N); R = np.zeros(N)

# ---------- grid: 128 BPM, a bar lands exactly on 17.0 (first task finishes) ----------
BPM = 128
BEAT = 60 / BPM
BAR = 4 * BEAT
T0 = 17.0 - 9 * BAR            # bar 9 starts at 17.0
DROP, OUT = 17.0, 17.0 + 20 * BAR   # drums from the drop until ~54.5
def grid(a, b, step, phase=0.0):
    k0 = int(np.ceil((a - T0 - phase) / step))
    return [T0 + phase + k * step for k in range(k0, 10 ** 6) if T0 + phase + k * step < b]

# I–V–vi–IV in D, bright voicings with add9s
PROG = [([62, 66, 69, 76], 38), ([61, 64, 69, 71], 45), ([62, 66, 69, 73], 47), ([59, 62, 67, 69], 43)]
FINAL = ([62, 66, 69, 73, 76], 38)
def chord_at(t):
    if t >= OUT: return FINAL
    k = int(np.floor((t - T0) / BAR))
    return PROG[k % 4]

drums_on = smooth(ramp(T, DROP - 0.05, DROP)) * (1 - smooth(ramp(T, OUT - 0.1, OUT + 0.3)))
intro_perc = smooth(ramp(T, 3.6, 5.5)) * (1 - smooth(ramp(T, OUT, OUT + 0.5)))
music_fade = smooth(ramp(T, 0, 1.2)) * (1 - smooth(ramp(T, 58.0, 60.0)))

kicks = grid(DROP, OUT, BEAT)
duck = np.ones(N)
for kt in kicks:
    i0 = int(kt * SR); n = int(0.22 * SR)
    d = 1 - 0.18 * np.exp(-np.arange(n) / (0.06 * SR))
    i1 = min(N, i0 + n); duck[i0:i1] = np.minimum(duck[i0:i1], d[:i1 - i0])

# ---------- soft pad bed (quiet, bright) ----------
pad = np.zeros((2, N))
bars = grid(0.0, OUT, BAR)
bars = ([0.0] if bars[0] > 0.01 else []) + bars + [OUT]
for si, st in enumerate(bars):
    end = bars[si + 1] if si + 1 < len(bars) else DUR
    notes, _ = chord_at(st + 0.01)
    i0, i1 = seg(st, end - st + 0.5); n = i1 - i0
    e = env_adsr(n, 0.25, 0.6)
    for m in notes:
        for det, pan in ((-0.06, 0.75), (0.06, 0.25)):
            v = saw(midi(m) * 2 ** (det / 12), n, phase=rng.random()) * e * 0.03
            pad[0, i0:i1] += v * (1 - pan); pad[1, i0:i1] += v * pan
pad = np.stack([lp(pad[0], 2600), lp(pad[1], 2600)])
L += pad[0] * duck * music_fade; R += pad[1] * duck * music_fade

# ---------- off-beat chord stabs (the bounce) ----------
stab = np.zeros(N)
for t in grid(5.0, OUT, BEAT, phase=BEAT / 2):
    notes, _ = chord_at(t)
    n = int(0.16 * SR); tt = np.arange(n) / SR
    v = sum(saw(midi(m + 12), n, rng.random()) for m in notes) * np.exp(-tt / 0.05) * 0.028
    add(stab, int(t * SR), v)
stab = lp(hp(stab, 400), 5500) * smooth(ramp(T, 5.0, 9.0)) * (0.75 + 0.25 * drums_on)
pre = 1 + 0.5 * (1 - drums_on) * (T < DROP)   # the intro carries the tune on its own
L += stab * 0.9 * pre; R += stab * 1.1 * pre

# ---------- marimba-ish 16th arpeggio ----------
arp = np.zeros(N)
pattern = [0, 1, 2, 3, 2, 1, 3, 2, 0, 2, 1, 3, 2, 3, 1, 2]
for k, t in enumerate(grid(1.0, 59.0, BEAT / 2)):
    notes, _ = chord_at(t + 0.01)
    m = notes[pattern[k % 16] % len(notes)] + 12
    f = midi(m); n = int(0.3 * SR); tt = np.arange(n) / SR
    v = (np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * 4 * f * tt) * np.exp(-tt / 0.02)) * np.exp(-tt / 0.09)
    v *= 0.12 * (1.0 if k % 2 == 0 else 0.72)
    add(arp, int(t * SR), v)
arp *= smooth(ramp(T, 0.6, 3.0)) * (1 - smooth(ramp(T, 57.0, 59.5)))
dl = int(BEAT * 0.75 * SR)
arpL, arpR = arp.copy(), arp * 0.9
arpR[dl:] += arp[:-dl] * 0.3; arpL[2 * dl:] += arp[:-2 * dl] * 0.16
L += arpL * pre; R += arpR * pre

# ---------- bouncing octave bass (8ths) ----------
bass = np.zeros(N)
for k, t in enumerate(grid(DROP, OUT, BEAT / 2)):
    _, root = chord_at(t + 0.01)
    m = root + (12 if k % 2 else 0)
    f = midi(m); n = int(BEAT / 2 * 0.9 * SR); tt = np.arange(n) / SR
    v = (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt)) * env_adsr(n, 0.004, 0.05) * np.exp(-tt / 0.18) * 0.2
    add(bass, int(t * SR), np.tanh(v * 1.4))
bass = lp(bass, 1400) * duck
L += bass; R += bass

# ---------- drums & percussion ----------
def kick():
    n = int(0.3 * SR); tt = np.arange(n) / SR
    f = 50 + 110 * np.exp(-tt / 0.025)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.1) * 0.36 + np.exp(-tt / 0.003) * rng.standard_normal(n) * 0.04
def clap():
    n = int(0.22 * SR); tt = np.arange(n) / SR
    burst = sum(np.exp(-np.clip(tt - d, 0, None) / 0.01) * (tt >= d) for d in (0, 0.011, 0.022))
    return bp(rng.standard_normal(n), 1100, 5200) * (burst * 0.5 + np.exp(-tt / 0.08) * 0.4) * 0.26
def snap():
    n = int(0.08 * SR); tt = np.arange(n) / SR
    return bp(rng.standard_normal(n), 1800, 6500) * np.exp(-tt / 0.012) * 0.22
def shaker(g):
    n = int(0.07 * SR); tt = np.arange(n) / SR
    e = np.minimum(tt / 0.012, 1) * np.exp(-tt / 0.03)
    return hp(rng.standard_normal(n), 6000) * e * 0.06 * g
def ohat():
    n = int(0.2 * SR); tt = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7000) * np.exp(-tt / 0.06) * 0.07
perc = np.zeros(N); dr = np.zeros(N)
K, C = kick(), clap()
for kt in kicks: add(dr, int(kt * SR), K)
for t in grid(DROP, OUT, 2 * BEAT, phase=BEAT): add(dr, int(t * SR), C)
for t in grid(DROP, OUT, BEAT, phase=BEAT / 2): add(dr, int(t * SR), ohat())
for t in grid(5.0, DROP, 2 * BEAT, phase=BEAT): add(perc, int(t * SR), snap())       # finger snaps in the intro
for k, t in enumerate(grid(5.0, OUT, BEAT / 4)): add(perc, int(t * SR), shaker(1.0 if k % 2 else 0.55))
fill = grid(DROP - BAR / 2, DROP, BEAT / 4)                                           # snare-ish fill into the drop
for i, t in enumerate(fill): add(perc, int(t * SR), clap() * (0.25 + 0.6 * i / len(fill)))
L += dr * drums_on + perc * intro_perc * 0.9 * pre; R += dr * drums_on + perc * intro_perc * 1.1 * pre

# ---------- UI sound effects ----------
sfx = np.zeros(N)
def pop(t, pitch=1.0):          # island drops down
    n = int(0.32 * SR); tt = np.arange(n) / SR
    f = 740 * pitch * (1 + 0.5 * (1 - np.exp(-tt / 0.03)))
    v = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.09) * 0.22
    v += np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR) * np.exp(-tt / 0.06) * 0.08
    add(sfx, int(t * SR), v * env_adsr(n, 0.004, 0.05))
def click(t, g=1.0):            # trackpad click
    n = int(0.05 * SR); tt = np.arange(n) / SR
    v = bp(rng.standard_normal(n), 1800, 6000) * np.exp(-tt / 0.006) * 0.25 + np.sin(2 * np.pi * 150 * tt) * np.exp(-tt / 0.01) * 0.2
    add(sfx, int(t * SR), v * g)
def key(t, g=1.0):              # keyboard tap
    n = int(0.06 * SR); tt = np.arange(n) / SR
    v = bp(rng.standard_normal(n), 900, 4500) * np.exp(-tt / 0.012) * 0.16 + np.sin(2 * np.pi * 220 * tt) * np.exp(-tt / 0.015) * 0.1
    add(sfx, int(t * SR), v * g)
def typing(a, b, chars, g=0.55):
    for k in range(chars):
        key(a + (b - a) * k / max(1, chars - 1) + rng.uniform(-0.015, 0.015), g * rng.uniform(0.7, 1.0))

# beats from index.html
pop(17.0); pop(19.5, 1.12); pop(21.5, 1.26)
typing(4.7, 6.1, 44); key(6.25, 0.8)
typing(6.6, 7.9, 46); key(8.05, 0.8)
typing(9.0, 10.3, 38); key(10.45, 0.8)
typing(12.1, 13.3, 30); key(13.45, 0.8)
typing(15.2, 17.4, 40, 0.4)
click(24.3)
for kt0 in (28.25,): [key(kt0 + .2 + i * .07, 1.1) for i in range(3)]   # ⌃⌘,
typing(29.6, 30.2, 3); key(30.9, 0.9)
for i in range(2): key(33.6 + .2 + i * .07, 1.1)                         # ⌘⇥
for i in range(3): key(37.95 + .2 + i * .07, 1.1)                        # ⌃⌘,
for i in range(2): key(39.2 + .2 + i * .07, 1.1)                         # ⌘1
for t in (42.95, 43.8, 44.55, 45.7, 46.1, 47.75, 48.55, 49.2): click(t, 0.9)
for i in range(2): key(44.85 + .2 + i * .07, 1.1)                        # ⌥Space
key(48.1, 0.8)
pop(46.55, 0.9); pop(47.0, 1.0); pop(47.45, 0.9)                         # theme preview flips
L += sfx; R += sfx

# ---------- a little room (less than before, keeps it crisp) ----------
irn = int(1.1 * SR); ti = np.arange(irn) / SR
ir = rng.standard_normal(irn) * np.exp(-ti / 0.3)
ir = lp(ir, 7000); ir /= np.sqrt(np.sum(ir ** 2))
L = L + fftconvolve(L - sfx, ir)[:N] * 0.09
R = R + fftconvolve(R - sfx, ir)[:N] * 0.09

# ---------- master ----------
fade = smooth(ramp(T, 0, 0.2)) * (1 - smooth(ramp(T, 58.8, 60.0)))
L *= fade; R *= fade
peak = max(np.abs(L).max(), np.abs(R).max())
L = np.tanh(L / peak * 1.25) / np.tanh(1.25) * 0.8
R = np.tanh(R / peak * 1.25) / np.tanh(1.25) * 0.8
out = (np.stack([L, R], axis=1) * 32767).astype(np.int16)
import wave
with wave.open('music-raw.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(out.tobytes())
print('wrote music-raw.wav')
