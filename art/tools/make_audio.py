"""Synthesizes all of Lanternfall's sound effects and music into assets/audio/.

Everything is generated from scratch (sine/FM bells, marimba, plucked
strings, noise), so it's 100% original with no licensing strings.

    python3 art/tools/make_audio.py
"""
import os
import subprocess
import tempfile

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ basics
def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env_ad(n, attack=0.005, decay=0.3):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / max(decay, 1e-4))


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    t = np.arange(n) / SR
    dur = n / SR
    e = np.ones(n) * s
    e[t < a] = t[t < a] / a
    m = (t >= a) & (t < a + d)
    e[m] = 1 - (1 - s) * (t[m] - a) / d
    rel = t > dur - r
    e[rel] *= np.clip((dur - t[rel]) / r, 0, 1)
    return e


def note_hz(n):
    """MIDI note number -> Hz."""
    return 440.0 * 2 ** ((n - 69) / 12)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def place(buf, sig, at):
    i = int(at * SR)
    end = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:end] += sig[: end - i]


def lowpass(x, cutoff):
    # one-pole low-pass, cheap and gentle
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


# ------------------------------------------------------------------ instruments
def marimba(freq, dur=0.6, vel=1.0):
    t = t_axis(dur)
    n = len(t)
    s = np.sin(2 * np.pi * freq * t) * env_ad(n, 0.002, 0.35)
    s += 0.35 * np.sin(2 * np.pi * freq * 4 * t) * env_ad(n, 0.001, 0.05)
    s += 0.15 * np.sin(2 * np.pi * freq * 10 * t) * env_ad(n, 0.001, 0.015)
    return s * vel


def bell(freq, dur=1.2, vel=1.0, ratio=3.5, index=2.0):
    t = t_axis(dur)
    n = len(t)
    mod = index * env_ad(n, 0.001, dur * 0.3) * np.sin(2 * np.pi * freq * ratio * t)
    return np.sin(2 * np.pi * freq * t + mod) * env_ad(n, 0.002, dur * 0.4) * vel


def musicbox(freq, dur=1.0, vel=1.0):
    return mix(bell(freq, dur, vel, ratio=5.0, index=1.2), 0.3 * bell(freq * 2, dur * 0.6, vel, ratio=3.0, index=0.6))


def pluck(freq, dur=0.5, vel=1.0, bright=0.5):
    # Karplus-Strong
    n = int(SR * dur)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    decay = 0.996
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = decay * (bright * buf[i % period] + (1 - bright) * buf[(i + 1) % period])
    return out * vel


def bass(freq, dur=0.4, vel=1.0):
    t = t_axis(dur)
    s = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 2 * t)
    return s * adsr(len(t), 0.005, 0.1, 0.6, 0.08) * vel


def pad(freqs, dur, vel=0.3):
    t = t_axis(dur)
    s = np.zeros(len(t))
    for f in freqs:
        for det in (-0.2, 0.2):
            s += np.sin(2 * np.pi * (f + det) * t + rng.uniform(0, 6))
    return lowpass(s, 1800) * adsr(len(t), 0.3, 0.2, 0.8, 0.4) * vel / len(freqs)


def kick(vel=1.0):
    t = t_axis(0.25)
    f = 120 * np.exp(-t * 25) + 45
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env_ad(len(t), 0.001, 0.12) * vel


def hat(vel=0.3, dur=0.05):
    n = int(SR * dur)
    x = rng.uniform(-1, 1, n)
    x = x - lowpass(x, 6000)
    return x * env_ad(n, 0.0005, dur * 0.3) * vel


def shaker(vel=0.2):
    n = int(SR * 0.08)
    x = rng.uniform(-1, 1, n)
    x = x - lowpass(x, 3000)
    return x * adsr(n, 0.02, 0.02, 0.6, 0.04) * vel


def noise_burst(dur, cutoff, a=0.002, d=0.1):
    n = int(SR * dur)
    return lowpass(rng.uniform(-1, 1, n), cutoff) * env_ad(n, a, d)


def sweep(f0, f1, dur, shape="sine"):
    t = t_axis(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "square":
        return np.sign(np.sin(ph)) * 0.5
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    return np.sin(ph)


# ------------------------------------------------------------------ export
def save(name, x, peak=0.85, ogg_q=5):
    x = norm(x, peak)
    # tiny fade-out to avoid clicks
    f = min(len(x), int(0.005 * SR))
    x[-f:] *= np.linspace(1, 0, f)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".raw", delete=False) as tf:
        tf.write(pcm.tobytes())
        raw = tf.name
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1",
                    "-i", raw, "-c:a", "libvorbis", "-q:a", str(ogg_q), out], check=True)
    os.unlink(raw)
    print("wrote", name, round(len(x) / SR, 2), "s")


# ------------------------------------------------------------------ sound effects
def sfx():
    C5, E5, G5, C6 = (note_hz(n) for n in (72, 76, 79, 84))
    save("ui_click", mix(marimba(note_hz(84), 0.12) * 0.8, noise_burst(0.02, 4000, d=0.006) * 0.2), 0.6)
    save("ui_hover", bell(note_hz(91), 0.12, ratio=2.0, index=0.5), 0.3)
    save("coin", mix(bell(note_hz(88), 0.35, ratio=3.0), np.concatenate([np.zeros(int(0.06 * SR)), bell(note_hz(95), 0.4, ratio=3.0)])), 0.6)
    save("build", mix(kick(0.7)[: int(0.18 * SR)], marimba(note_hz(60), 0.3), noise_burst(0.12, 1500, d=0.04) * 0.5,
                      np.concatenate([np.zeros(int(0.07 * SR)), marimba(note_hz(67), 0.3, 0.7)])), 0.8)
    up = np.zeros(int(0.9 * SR))
    for i, n in enumerate((72, 76, 79, 84, 88)):
        place(up, bell(note_hz(n), 0.5, 0.8), i * 0.07)
    place(up, sweep(600, 2400, 0.4, "tri") * env_ad(int(0.4 * SR), 0.05, 0.2) * 0.15, 0.0)
    save("upgrade", up, 0.75)
    down = np.zeros(int(0.7 * SR))
    for i, n in enumerate((88, 84, 79, 76)):
        place(down, bell(note_hz(n), 0.35, 0.7, ratio=3.0), i * 0.06)
    save("sell", down, 0.6)
    save("shot_pebble", mix(sweep(1400, 500, 0.08, "tri") * env_ad(int(0.08 * SR), 0.001, 0.03), noise_burst(0.03, 3000, d=0.01) * 0.4), 0.45)
    jelly = sweep(220, 520, 0.18, "sine") * env_ad(int(0.18 * SR), 0.005, 0.12)
    jelly *= 1 + 0.4 * np.sin(2 * np.pi * 28 * t_axis(0.18))
    save("shot_jelly", jelly, 0.55)
    save("splat", mix(noise_burst(0.2, 900, d=0.06), sweep(300, 90, 0.15) * env_ad(int(0.15 * SR), 0.001, 0.06) * 0.6), 0.5)
    frost = noise_burst(0.45, 5000, a=0.05, d=0.2) * 0.5
    frost = frost - lowpass(frost, 1500)
    save("shot_frost", mix(frost, bell(note_hz(96), 0.4, 0.3, ratio=4.1), bell(note_hz(100), 0.35, 0.25, ratio=4.1)), 0.4)
    pop = sweep(500, 1600, 0.06) * env_ad(int(0.06 * SR), 0.001, 0.02)
    save("snuffer_pop", mix(pop, noise_burst(0.05, 2500, d=0.012) * 0.5,
                            np.concatenate([np.zeros(int(0.03 * SR)), bell(note_hz(86), 0.25, 0.4, ratio=2.0)])), 0.5)
    leak = sweep(330, 140, 0.6, "tri") * env_ad(int(0.6 * SR), 0.02, 0.3)
    leak *= 1 + 0.3 * np.sin(2 * np.pi * 7 * t_axis(0.6))
    save("leak", leak, 0.6)
    horn = np.zeros(int(1.3 * SR))
    for i, (n, d) in enumerate(((67, 0.18), (72, 0.18), (76, 0.6))):
        t = t_axis(d + 0.25)
        f = note_hz(n)
        s = sum(np.sin(2 * np.pi * f * k * t) / k for k in range(1, 6)) * adsr(len(t), 0.03, 0.08, 0.7, 0.2)
        place(horn, lowpass(s, 2200), (0, 0.2, 0.4)[i])
    place(horn, kick(0.6), 0.0)
    place(horn, kick(0.6), 0.4)
    save("wave_start", horn, 0.7)
    jingle = np.zeros(int(1.4 * SR))
    for i, n in enumerate((72, 76, 79, 84, 79, 84)):
        place(jingle, marimba(note_hz(n), 0.5, 0.9), i * 0.09)
    place(jingle, bell(note_hz(96), 0.9, 0.5), 0.5)
    save("wave_clear", jingle, 0.7)
    growl = sweep(90, 60, 1.2, "square") * adsr(int(1.2 * SR), 0.1, 0.2, 0.8, 0.4)
    growl *= 1 + 0.5 * np.sin(2 * np.pi * 9 * t_axis(1.2))
    save("boss", lowpass(growl, 700) + noise_burst(1.2, 400, a=0.1, d=0.5) * 0.4, 0.75)
    fan = np.zeros(int(2.6 * SR))
    seq = [(72, 0.0), (76, 0.15), (79, 0.3), (84, 0.45), (79, 0.75), (84, 0.9)]
    for n, at in seq:
        place(fan, marimba(note_hz(n), 0.6), at)
        place(fan, bell(note_hz(n + 12), 0.6, 0.35), at)
    place(fan, pad([note_hz(60), note_hz(64), note_hz(67), note_hz(72)], 1.6, 0.8), 0.9)
    for k in range(8):
        place(fan, bell(note_hz(96 + (k % 3) * 4), 0.4, 0.25), 1.0 + k * 0.12)
    save("victory", fan, 0.8)
    sad = np.zeros(int(2.2 * SR))
    for i, n in enumerate((67, 66, 65, 64)):
        d = 0.35 if i < 3 else 1.0
        t = t_axis(d)
        f = note_hz(n - 12)
        if i == 3:
            f = f * (1 + 0.01 * np.sin(2 * np.pi * 5 * t))
            ph = 2 * np.pi * np.cumsum(f) / SR
        else:
            ph = 2 * np.pi * f * t
        s = sum(np.sin(ph * k) / k for k in range(1, 5)) * adsr(len(t), 0.03, 0.05, 0.8, 0.15)
        place(sad, lowpass(s, 1200), i * 0.38)
    save("defeat", sad, 0.6)
    chime = np.zeros(int(1.0 * SR))
    for i, n in enumerate((84, 88, 91, 96)):
        place(chime, bell(note_hz(n), 0.7, 0.6, ratio=2.0, index=1.0), i * 0.05)
    place(chime, sweep(400, 3000, 0.5, "tri") * env_ad(int(0.5 * SR), 0.1, 0.25) * 0.12, 0)
    save("ability", chime, 0.7)
    save("gate", mix(kick(1.0), noise_burst(0.3, 600, d=0.08), marimba(note_hz(43), 0.4, 0.8)), 0.8)
    gift = np.zeros(int(0.8 * SR))
    for i in range(6):
        place(gift, bell(note_hz(84 + i * 2), 0.3, 0.5, ratio=3.0), i * 0.05)
    save("gift", gift, 0.6)
    save("denied", mix(marimba(note_hz(55), 0.2), np.concatenate([np.zeros(int(0.08 * SR)), marimba(note_hz(52), 0.25)])), 0.5)
    save("ready", mix(bell(note_hz(79), 0.5, 0.7, ratio=2.0), np.concatenate([np.zeros(int(0.08 * SR)), bell(note_hz(86), 0.6, 0.7, ratio=2.0)])), 0.55)


# ------------------------------------------------------------------ music
def song(bpm, bars, chords, melody_fn, groove, name, voice, pad_vel=0.25):
    beat = 60 / bpm
    total = bars * 4 * beat
    buf = np.zeros(int(total * SR) + SR * 2)
    for bar in range(bars):
        root, quality = chords[bar % len(chords)]
        tones = [root, root + (3 if quality == "m" else 4), root + 7]
        t0 = bar * 4 * beat
        place(buf, pad([note_hz(n) for n in tones], 4 * beat, pad_vel), t0)
        groove(buf, t0, beat, root, tones, bar)
        for (n, at, dur, vel) in melody_fn(bar, tones):
            place(buf, voice(note_hz(n), dur * beat + 0.4, vel), t0 + at * beat)
    # make it loop: fold the tail back onto the start
    n = int(total * SR)
    tail = buf[n:]
    buf = buf[:n]
    buf[: len(tail)] += tail
    save(name, buf, 0.7, ogg_q=4)


def melody_maker(seed, scale, density):
    r = np.random.default_rng(seed)
    motifs = []
    for k in range(4):
        steps = []
        pos = 0.0
        while pos < 4:
            dur = r.choice([0.5, 0.5, 1.0, 1.0, 1.5]) if density < 0.6 else r.choice([0.5, 0.5, 0.5, 1.0])
            if r.random() < density:
                steps.append((int(r.integers(0, 5)), pos, min(dur, 4 - pos)))
            pos += dur
        motifs.append(steps)
    form = [0, 1, 0, 2, 0, 1, 3, 2]

    def fn(bar, tones):
        steps = motifs[form[bar % len(form)]]
        out = []
        for (deg, at, dur) in steps:
            # snap melody near chord tones
            target = tones[deg % 3] + 12 * (1 + (deg // 3))
            n = min(scale, key=lambda s: abs(s - target))
            out.append((n, at, dur, 0.55 + 0.2 * (at == 0)))
        return out
    return fn


def music():
    # menu: gentle music box in F, 84 bpm
    F = 65
    scale = [F + i for i in (0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24)]
    chords = [(F - 12, "M"), (F - 12 + 9, "m"), (F - 12 + 5, "M"), (F - 12 + 7, "M")]

    def calm(buf, t0, beat, root, tones, bar):
        place(buf, bass(note_hz(root - 12), 2 * beat, 0.35), t0)
        place(buf, bass(note_hz(root - 12 + 7), 2 * beat, 0.25), t0 + 2 * beat)
        for k in range(8):
            place(buf, pluck(note_hz(tones[k % 3] + 12), 0.5, 0.12, 0.6), t0 + k * 0.5 * beat)

    song(84, 16, chords, melody_maker(3, scale, 0.55), calm, "music_menu", musicbox, 0.22)

    # battle: bouncy marimba in C, 118 bpm
    C = 60
    scale = [C + i for i in (0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24)]
    chords = [(C - 12, "M"), (C - 12 + 7, "M"), (C - 12 + 9, "m"), (C - 12 + 5, "M")]

    def bouncy(buf, t0, beat, root, tones, bar):
        for k in range(4):
            place(buf, kick(0.55), t0 + k * beat)
            place(buf, hat(0.12), t0 + (k + 0.5) * beat)
            if k % 2 == 1:
                place(buf, shaker(0.28), t0 + k * beat)
        for k, off in enumerate((0, 1.5, 2, 3, 3.5)):
            n = root - 12 + (0 if k != 3 else 7)
            place(buf, bass(note_hz(n), 0.45 * beat, 0.5), t0 + off * beat)
        for k in range(8):
            place(buf, pluck(note_hz(tones[(k * 2) % 3] + 12), 0.3, 0.1, 0.4), t0 + k * 0.5 * beat)

    song(118, 16, chords, melody_maker(11, scale, 0.75), bouncy, "music_battle", marimba, 0.15)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sfx()
    music()
