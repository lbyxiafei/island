# Original soundtrack for the island intro (60s, 120 BPM, D major), synthesized from scratch.
# Music + UI sound effects are timed to the video's beats (see index.html B / S).
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 48000
DUR = 60.0
N = int(SR * DUR)
rng = np.random.default_rng(7)
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
    i1 = min(len(buf), i0 + len(sig))
    if i0 < i1: buf[i0:i1] += sig[:i1 - i0]
def saw(f, n, phase=0.0):
    t = np.arange(n) / SR
    return 2 * ((f * t + phase) % 1.0) - 1

L = np.zeros(N); R = np.zeros(N)

# ---------- harmony: bars start at t = 1 + 2k so the downbeat lands on 17.0 ----------
BAR, BEAT = 2.0, 0.5
T0 = 1.0
PROG = [  # (pad voicing, bass root) — Gmaj7, F#m7, Em9, A7sus4
    ([55, 59, 62, 66], 43), ([54, 57, 61, 64], 42), ([52, 55, 59, 62, 66], 40), ([57, 62, 64, 67], 45)]
FINAL = ([50, 57, 62, 64, 66, 69], 38)  # Dmaj9 to resolve on the end card
def chord_at(t):
    if t >= 55.0: return FINAL
    k = int((t - T0) // BAR) if t >= T0 else 0
    return PROG[k % 4]

# section gains over time
def ramp(t, a, b): return np.clip((t - a) / (b - a), 0, 1)
def smooth(x): return x * x * (3 - 2 * x)
drums_on = smooth(ramp(T, 16.6, 17.0)) * (1 - smooth(ramp(T, 54.6, 55.2)))
arp_on = smooth(ramp(T, 4.0, 8.0)) * (1 - smooth(ramp(T, 57.0, 59.5)))
pad_gain = smooth(ramp(T, 0.0, 2.5)) * (1 - smooth(ramp(T, 58.2, 60.0)))

# kick times (4 on the floor from 17 to 55, lighter during settings)
kicks = [t for t in np.arange(17.0, 55.0, BEAT)]
# side-chain envelope for pumping
duck = np.ones(N)
for kt in kicks:
    i0 = int(kt * SR); n = int(0.35 * SR)
    d = 1 - 0.38 * np.exp(-np.arange(n) / (0.11 * SR))
    i1 = min(N, i0 + n); duck[i0:i1] = np.minimum(duck[i0:i1], d[:i1 - i0])

# ---------- pad ----------
pad_L = np.zeros(N); pad_R = np.zeros(N)
starts = [0.0] + list(np.arange(T0, 55.0, BAR)) + [55.0]
for si, st in enumerate(starts):
    end = starts[si + 1] if si + 1 < len(starts) else DUR
    notes, _ = chord_at(st + 0.01)
    i0, i1 = seg(st, end - st + 0.8)
    n = i1 - i0
    e = env_adsr(n, 0.35, 0.9)
    for m in notes:
        f = midi(m)
        for det, pan in ((-0.07, 0.8), (0.0, 0.5), (0.07, 0.2)):
            v = saw(f * 2 ** (det / 12), n, phase=rng.random()) * e * 0.095
            pad_L[i0:i1] += v * (1 - pan); pad_R[i0:i1] += v * pan
pad_L = lp(pad_L, 1400); pad_R = lp(pad_R, 1400)
# slow filter-ish movement: brighten a bit when drums are in
L += pad_L * pad_gain * (0.85 + 0.15 * drums_on) * duck
R += pad_R * pad_gain * (0.85 + 0.15 * drums_on) * duck

# ---------- pluck arpeggio (8th notes) with ping-pong delay ----------
arp = np.zeros(N)
pattern = [0, 2, 1, 3, 2, 1, 3, 2]
for k, t in enumerate(np.arange(T0, 59.0, BEAT / 2)):
    notes, _ = chord_at(t + 0.01)
    m = notes[pattern[k % len(pattern)] % len(notes)] + 12
    f = midi(m); n = int(0.45 * SR)
    tt = np.arange(n) / SR
    v = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(4 * np.pi * f * tt) + 0.12 * np.sin(6 * np.pi * f * tt)) * np.exp(-tt / 0.13)
    v *= 0.165 * (0.8 + 0.2 * (k % 2 == 0))
    add(arp, int(t * SR), v)
arp = lp(arp, 5200) * arp_on
dl = int(0.375 * SR)
arpL, arpR = arp.copy(), arp.copy() * 0.85
for i, g in enumerate((0.42, 0.26, 0.15)):
    sh = dl * (i + 1)
    tgt = arpR if i % 2 == 0 else arpL
    tgt[sh:] += arp[:-sh] * g
L += arpL; R += arpR

# ---------- bass ----------
bass = np.zeros(N)
for k, t in enumerate(np.arange(17.0, 55.0, BAR)):
    _, root = chord_at(t + 0.01)
    for off, ln in ((0.0, 0.9), (1.25, 0.45), (1.5, 0.45)):
        f = midi(root); n = int(ln * SR); tt = np.arange(n) / SR
        v = (np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)) * env_adsr(n, 0.01, 0.12) * 0.2
        add(bass, int((t + off) * SR), np.tanh(v * 1.6) * 0.6)
bass = lp(bass, 900) * duck
L += bass; R += bass

# ---------- drums ----------
def kick():
    n = int(0.42 * SR); tt = np.arange(n) / SR
    f = 44 + 90 * np.exp(-tt / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-tt / 0.14) * 0.42 + np.exp(-tt / 0.004) * rng.standard_normal(n) * 0.05
def snare():
    n = int(0.25 * SR); tt = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * tt) * np.exp(-tt / 0.05) * 0.12
    noise = bp(rng.standard_normal(n), 1400, 7000) * np.exp(-tt / 0.07) * 0.2
    return body + noise
def hat(open_=False):
    n = int((0.18 if open_ else 0.06) * SR); tt = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7500) * np.exp(-tt / (0.06 if open_ else 0.018)) * 0.07
K = kick(); SN = snare()
dr = np.zeros(N)
for kt in kicks:
    lighter = 0.7 if 42.3 < kt < 50.0 else 1.0
    add(dr, int(kt * SR), K * lighter)
for t in np.arange(17.5, 55.0, 1.0):          # backbeat on 2 and 4
    add(dr, int(t * SR), SN)
hats = np.zeros(N)
for k, t in enumerate(np.arange(8.0, 55.0, BEAT / 2)):
    if t < 17.0 and k % 2 == 0: continue           # sparse before the drop
    add(hats, int((t + 0.25 * BEAT * 0.12) * SR), hat(open_=(k % 8 == 5)))
hats *= smooth(ramp(T, 8.0, 12.0)) * (1 - smooth(ramp(T, 54.6, 55.2)))
L += dr * drums_on + hats * 0.9; R += dr * drums_on + hats * 1.1
# riser into the drop
i0, i1 = seg(14.6, 2.4)
tt = np.arange(i1 - i0) / SR
rise = hp(rng.standard_normal(i1 - i0), 900) * (tt / tt[-1]) ** 2.2 * 0.09
L[i0:i1] += rise; R[i0:i1] += rise

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

# ---------- space: short plate-ish reverb on everything musical ----------
irn = int(1.6 * SR); ti = np.arange(irn) / SR
ir = rng.standard_normal(irn) * np.exp(-ti / 0.45)
ir = lp(ir, 6000); ir /= np.sqrt(np.sum(ir ** 2))
wetL = fftconvolve(L - sfx, ir)[:N] * 0.16
wetR = fftconvolve(R - sfx, ir[::-1][::-1] * 1.0)[:N] * 0.16
L = L + wetL; R = R + wetR

# ---------- master: gentle glue + fade + limiter ----------
fade = smooth(ramp(T, 0, 0.3)) * (1 - smooth(ramp(T, 58.6, 60.0)))
L *= fade; R *= fade
peak = max(np.abs(L).max(), np.abs(R).max())
L = np.tanh(L / peak * 1.2) / np.tanh(1.2) * 0.72
R = np.tanh(R / peak * 1.2) / np.tanh(1.2) * 0.72
out = (np.stack([L, R], axis=1) * 32767).astype(np.int16)

import wave
with wave.open('music.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(out.tobytes())
print('wrote music.wav', out.shape)
