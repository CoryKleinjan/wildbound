"""Renders the game's sound effects to assets/sfx/<name>.wav (44.1 kHz, 16-bit).

python3 tools/sfx/make_sfx.py [name ...]

Offline synthesis with proper band-limited oscillators, FM bells, filtered noise, ADSR envelopes,
layered transients and a small room reverb, so the effects sound polished rather than raw beeps.
The Audio autoload plays these files and keeps its procedural sounds as a fallback.
"""
import sys
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
OUT = Path(__file__).resolve().parents[2] / "assets" / "sfx"
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ building blocks
def _n(dur):
	return int(round(dur * SR))


def t_(dur):
	return np.arange(_n(dur)) / SR


def env(n, a=0.002, d=0.05, s=0.6, r=0.05, hold=None):
	"""ADSR over n samples (hold = sustain time; default fills the rest)."""
	a_n, d_n, r_n = _n(a), _n(d), _n(r)
	h_n = n - a_n - d_n - r_n if hold is None else _n(hold)
	h_n = max(0, h_n)
	e = np.concatenate([np.linspace(0, 1, a_n, endpoint=False), np.linspace(1, s, d_n, endpoint=False),
		np.full(h_n, s), np.linspace(s, 0, r_n)])
	return np.pad(e, (0, max(0, n - len(e))))[:n]


def exp_env(n, decay):
	return np.exp(-np.arange(n) / SR / decay)


def phase(freq, dur):
	f = np.broadcast_to(np.asarray(freq, float), (_n(dur),)) if np.ndim(freq) == 0 else np.asarray(freq, float)
	return np.cumsum(f) / SR, f


def _blep(p, dt):
	out = np.zeros_like(p)
	m = p < dt
	x = p[m] / dt[m]
	out[m] = x + x - x * x - 1
	m2 = p > 1 - dt
	x = (p[m2] - 1) / dt[m2]
	out[m2] = x * x + x + x + 1
	return out


def square(freq, dur, duty=0.5):
	ph, f = phase(freq, dur)
	p = ph % 1.0
	dt = np.clip(f / SR, 1e-6, 0.5)
	y = np.where(p < duty, 1.0, -1.0)
	y += _blep(p, dt) - _blep((p - duty) % 1.0, dt)
	return y


def saw(freq, dur):
	ph, f = phase(freq, dur)
	p = ph % 1.0
	return 2 * p - 1 - _blep(p, np.clip(f / SR, 1e-6, 0.5))


def sine(freq, dur):
	ph, _ = phase(freq, dur)
	return np.sin(2 * np.pi * ph)


def tri(freq, dur):
	ph, _ = phase(freq, dur)
	return 2 * np.abs(2 * (ph % 1.0) - 1) - 1


def bell(freq, dur, ratio=3.5, index=2.0, decay=0.35):
	"""FM bell: bright attack that mellows as it decays."""
	n = _n(dur)
	e = exp_env(n, decay)
	ph, _ = phase(freq, dur)
	mod = np.sin(2 * np.pi * ph * ratio) * index * e
	return np.sin(2 * np.pi * ph + mod) * e


def noise(dur):
	return rng.uniform(-1, 1, _n(dur))


def lp(x, fc, q=0.707):
	b, a = signal.iirfilter(2, min(fc, SR * 0.45) / (SR / 2), btype="low", ftype="butter")
	return signal.lfilter(b, a, x)


def hp(x, fc):
	b, a = signal.iirfilter(2, fc / (SR / 2), btype="high", ftype="butter")
	return signal.lfilter(b, a, x)


def bp(x, lo, hi):
	b, a = signal.iirfilter(2, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], btype="band", ftype="butter")
	return signal.lfilter(b, a, x)


def sweep_filter(x, f0, f1, kind="low", steps=64):
	"""Time-varying filter by processing short overlapping blocks."""
	out = np.zeros_like(x)
	n = len(x)
	blk = max(64, n // steps)
	win = np.hanning(blk * 2)
	for i in range(0, n, blk):
		fc = f0 * (f1 / f0) ** (i / max(1, n))
		seg = x[max(0, i - blk // 2): i + blk + blk // 2]
		y = lp(seg, fc) if kind == "low" else bp(seg, fc * 0.6, fc * 1.6)
		s0 = max(0, i - blk // 2)
		w = np.hanning(len(y))
		out[s0:s0 + len(y)] += y * w
	return out / 1.0


def glide(f0, f1, dur, curve=1.0):
	k = np.linspace(0, 1, _n(dur)) ** curve
	return f0 * (f1 / f0) ** k


def lay(*xs):
	return mix(*[(0, x) for x in xs])


def mix(*parts):
	n = max(len(p[1]) + _n(p[0]) for p in parts)
	out = np.zeros(n)
	for t0, x in parts:
		i = _n(t0)
		out[i:i + len(x)] += x
	return out


def reverb(x, size=0.25, wet=0.18, damp=5000):
	"""Small room: exponentially decaying filtered-noise impulse response."""
	n = _n(size)
	ir = lp(rng.standard_normal(n), damp) * np.exp(-np.arange(n) / SR / (size / 5))
	ir /= np.sqrt((ir ** 2).sum())
	w = signal.fftconvolve(x, ir)
	w = np.pad(w, (0, max(0, len(x) + n - len(w))))[: len(x) + n]
	return np.pad(x, (0, n)) * (1 - wet) + w * wet


def soft(x, drive=1.5):
	return np.tanh(x * drive) / np.tanh(drive)


def note(n):
	return 440.0 * 2 ** ((n - 69) / 12)


def tone(kind, f, dur, a=0.003, d=0.05, s=0.6, r=0.04, vol=1.0, **kw):
	x = {"sq": square, "saw": saw, "sine": sine, "tri": tri}[kind](f, dur, **kw)
	return x * env(len(x), a, d, s, r) * vol


def chorus_sq(f, dur, duty=0.5, cents=8):
	k = 2 ** (cents / 1200)
	return (square(f * k, dur, duty) + square(f / k, dur, duty)) * 0.5


def arp(notes, step, maker, overlap=1.0):
	parts = [(i * step, maker(note(n), step * overlap)) for i, n in enumerate(notes)]
	return mix(*parts)


# ------------------------------------------------------------------ the effects
def lead(f, dur, vol=0.5, duty=0.25):
	x = chorus_sq(f, dur, duty)
	x = lp(x, 6000)
	return x * env(len(x), 0.004, 0.08, 0.55, min(0.12, dur * 0.4)) * vol


def bellnote(f, dur, vol=0.6):
	return (bell(f, dur, 3.5, 1.6, dur * 0.45) * 0.8 + sine(f * 2, dur) * exp_env(_n(dur), dur * 0.2) * 0.2) * vol


def impact(size=1.0, bright=4000):
	n_dur = 0.18 + 0.18 * size
	click = hp(noise(0.012), 2000) * env(_n(0.012), 0.0005, 0.01, 0, 0.001) * 0.9
	body = lp(noise(n_dur), bright) * exp_env(_n(n_dur), 0.035 + 0.04 * size)
	thump = sine(glide(150, 42, 0.22 * (1 + size * 0.5), 0.6), 0.22 * (1 + size * 0.5))
	thump *= exp_env(len(thump), 0.06 + 0.04 * size)
	return soft(mix((0, click), (0, body * 0.9), (0, thump * (0.8 + 0.4 * size))), 1.6 + size)


def fx(name):
	if name == "cursor":
		x = mix((0, sine(1760, 0.05) * exp_env(_n(0.05), 0.012) * 0.5), (0, tri(3520, 0.03) * exp_env(_n(0.03), 0.006) * 0.25))
		return reverb(x, 0.12, 0.12)
	if name == "text":
		return sine(1320, 0.025) * exp_env(_n(0.025), 0.006) * 0.25
	if name == "confirm":
		return reverb(mix((0, bellnote(note(88), 0.18, 0.5)), (0.06, bellnote(note(95), 0.3, 0.55))), 0.2, 0.15)
	if name == "cancel":
		return reverb(mix((0, lead(note(79), 0.07, 0.4, 0.5)), (0.06, lead(note(72), 0.12, 0.4, 0.5))), 0.15, 0.1)
	if name == "error":
		x = mix((0, lp(chorus_sq(185, 0.12, 0.5, 20), 1800) * env(_n(0.12), 0.002, 0.03, 0.8, 0.03)),
			(0.15, lp(chorus_sq(175, 0.18, 0.5, 20), 1800) * env(_n(0.18), 0.002, 0.03, 0.8, 0.06)))
		return x * 0.45
	if name == "bump":
		th = sine(glide(110, 50, 0.14), 0.14) * exp_env(_n(0.14), 0.04)
		return soft(mix((0, th * 0.9), (0, lp(noise(0.05), 900) * exp_env(_n(0.05), 0.012) * 0.5)), 1.4) * 0.8
	if name == "door":
		wh = sweep_filter(noise(0.4), 600, 3500, "band") * env(_n(0.4), 0.08, 0.1, 0.6, 0.2)
		latch = hp(noise(0.02), 1500) * exp_env(_n(0.02), 0.004)
		return reverb(mix((0, latch * 0.5), (0.05, wh * 0.5), (0.36, latch * 0.35)), 0.3, 0.2)
	if name == "encounter":
		notes = [64, 67, 71, 76, 79, 83, 88, 91]
		up = arp(notes * 2, 0.035, lambda f, d: lead(f, d * 1.5, 0.35, 0.25))
		swirl = lead(glide(note(96), note(60), 0.55, 0.7), 0.55, 0.4, 0.5)
		sub = sine(glide(80, 45, 0.9), 0.9) * env(_n(0.9), 0.01, 0.2, 0.5, 0.3) * 0.5
		return reverb(soft(mix((0, up), (0.55, swirl), (0, sub)), 1.2), 0.4, 0.22)
	if name == "hit":
		return reverb(impact(1.0, 3500), 0.18, 0.12) * 0.9
	if name == "hit_super":
		x = mix((0, impact(1.6, 6000)), (0.07, impact(1.2, 2500) * 0.8),
			(0, lp(saw(glide(300, 40, 0.35), 0.35), 1200) * exp_env(_n(0.35), 0.1) * 0.35))
		return reverb(soft(x, 2.2), 0.3, 0.18) * 0.95
	if name == "hit_weak":
		x = hp(impact(0.4, 6000), 400)
		return reverb(x, 0.12, 0.1) * 0.55
	if name == "faint":
		f = glide(note(84), note(40), 0.8, 0.8) * (1 + 0.012 * np.sin(2 * np.pi * 9 * t_(0.8)))
		x = mix((0, lead(f, 0.8, 0.45, 0.5)), (0.7, impact(0.8, 1200) * 0.6))
		return reverb(x, 0.35, 0.2)
	if name == "stat_up":
		x = arp([72, 76, 79, 84, 88, 91, 96], 0.06, lambda f, d: bellnote(f, 0.35, 0.4))
		sh = hp(noise(0.5), 6000) * env(_n(0.5), 0.05, 0.1, 0.3, 0.3) * 0.08
		return reverb(mix((0, x), (0, sh)), 0.4, 0.25)
	if name == "stat_down":
		x = arp([91, 88, 84, 79, 76, 72, 67], 0.06, lambda f, d: lead(f, 0.12, 0.3, 0.5))
		return reverb(lp(x, 3000), 0.35, 0.2)
	if name == "status":
		f = note(70) * (1 + 0.03 * np.sin(2 * np.pi * 14 * t_(0.45)))
		x = lead(f, 0.45, 0.35, 0.5) + bp(noise(0.45), 800, 3000) * env(_n(0.45), 0.05, 0.1, 0.4, 0.2) * 0.12
		return reverb(x, 0.3, 0.2)
	if name == "recover":
		x = arp([67, 71, 74, 79, 83, 86, 91], 0.07, lambda f, d: bellnote(f, 0.5, 0.35))
		pad = sine(note(79), 0.9) * env(_n(0.9), 0.2, 0.2, 0.5, 0.4) * 0.15
		return reverb(mix((0, x), (0, pad)), 0.5, 0.3)
	if name == "send_out":
		pop = impact(0.3, 8000) * 0.5
		wh = sweep_filter(noise(0.3), 3000, 800, "band") * env(_n(0.3), 0.01, 0.1, 0.5, 0.15) * 0.5
		sp = arp([91, 96, 100], 0.04, lambda f, d: bellnote(f, 0.25, 0.3))
		return reverb(mix((0, pop), (0.02, wh), (0.12, sp)), 0.3, 0.2)
	if name == "orb_throw":
		wh = sweep_filter(noise(0.4), 500, 4000, "band") * env(_n(0.4), 0.05, 0.1, 0.7, 0.2)
		# airy whoosh with a low "fwip" body, panned-feeling by sweeping the band up
		body = lp(noise(0.4), 700) * env(_n(0.4), 0.03, 0.1, 0.5, 0.2) * 0.5
		return reverb(mix((0, wh * 0.7), (0, body)), 0.2, 0.12)
	if name == "orb_shake":
		click = lambda: bp(noise(0.03), 1500, 5000) * exp_env(_n(0.03), 0.006)
		wob = sine(glide(260, 200, 0.12), 0.12) * exp_env(_n(0.12), 0.04) * 0.4
		return reverb(mix((0, click() * 0.7), (0, wob), (0.13, click() * 0.5)), 0.15, 0.12)
	if name == "catch":
		cl = bp(noise(0.03), 1500, 6000) * exp_env(_n(0.03), 0.006) * 0.8
		mel = mix(*[(t, lay(lead(note(n), d, 0.4, 0.5), bellnote(note(n + 12), d + 0.3, 0.2))) for t, n, d in
			[(0.25, 72, 0.12), (0.4, 76, 0.12), (0.55, 79, 0.12), (0.72, 84, 0.6)]])
		bass = tone("tri", note(48), 1.0, 0.01, 0.2, 0.6, 0.3, 0.4)
		return reverb(mix((0, cl), (0, mel), (0.72, bass)), 0.45, 0.22)
	if name == "breakout":
		pop = impact(0.8, 7000) * 0.7
		up = lead(glide(note(60), note(84), 0.25), 0.25, 0.3, 0.25)
		return reverb(mix((0, pop), (0.03, up)), 0.3, 0.2)
	if name == "level_up":
		mel = mix(*[(t, lay(lead(note(n), d, 0.38, 0.25), bellnote(note(n + 12), d + 0.25, 0.18))) for t, n, d in
			[(0, 72, 0.1), (0.1, 72, 0.1), (0.2, 72, 0.1), (0.3, 77, 0.45), (0.78, 76, 0.12), (0.9, 77, 0.12), (1.02, 79, 0.5)]])
		bass = mix((0, tone("tri", note(41), 0.75, 0.01, 0.1, 0.7, 0.1, 0.45)), (0.78, tone("tri", note(48), 0.75, 0.01, 0.1, 0.7, 0.2, 0.45)))
		return reverb(mix((0, mel), (0, bass)), 0.45, 0.2)
	if name == "exp":
		f = glide(note(72), note(96), 0.6, 1.0)
		x = lead(f, 0.6, 0.18, 0.125) * (0.6 + 0.4 * (np.sin(2 * np.pi * 30 * t_(0.6)) > 0))
		return reverb(x, 0.15, 0.1)
	if name == "heal":
		mel = mix(*[(t, lay(bellnote(note(n), d + 0.4, 0.45), lead(note(n), d, 0.15, 0.5))) for t, n, d in
			[(0, 76, 0.16), (0.18, 76, 0.16), (0.36, 76, 0.16), (0.54, 72, 0.3), (0.9, 79, 0.16), (1.08, 79, 0.16), (1.26, 84, 0.6)]])
		bass = mix((0, tone("tri", note(48), 0.85, 0.01, 0.1, 0.6, 0.1, 0.35)), (0.9, tone("tri", note(55), 1.0, 0.01, 0.1, 0.6, 0.3, 0.35)))
		return reverb(mix((0, mel), (0, bass)), 0.5, 0.25)
	if name == "evolve_start":
		dur = 1.6
		f = glide(note(48), note(72), dur, 1.5)
		pad = (saw(f, dur) + saw(f * 1.5, dur) * 0.5)
		pad = sweep_filter(pad, 300, 5000) * env(_n(dur), 0.4, 0.3, 0.8, 0.3) * 0.25
		sh = hp(noise(dur), 5000) * env(_n(dur), 0.6, 0.2, 0.5, 0.4) * 0.07
		sp = arp([84, 88, 91, 96, 100, 103], 0.22, lambda f, d: bellnote(f, 0.4, 0.2))
		return reverb(mix((0, pad), (0, sh), (0.3, sp)), 0.6, 0.3)
	if name == "evolve_done":
		chord = [60, 64, 67, 72]
		hits = mix(*[(0, lead(note(n), 1.0, 0.18, 0.5)) for n in chord], *[(0, bellnote(note(n + 12), 1.3, 0.12)) for n in chord])
		run = arp([67, 72, 76, 79], 0.06, lambda f, d: lead(f, 0.1, 0.3, 0.25))
		bass = tone("tri", note(36), 1.2, 0.01, 0.2, 0.6, 0.4, 0.5)
		return reverb(mix((0, run), (0.26, hits), (0.26, bass), (0.26, impact(0.5, 2000) * 0.25)), 0.6, 0.25)
	if name == "run":
		steps = mix(*[(i * 0.07, lp(noise(0.04), 1500 + i * 300) * exp_env(_n(0.04), 0.01) * (0.5 - i * 0.05)) for i in range(5)])
		wh = sweep_filter(noise(0.45), 2000, 600, "band") * env(_n(0.45), 0.02, 0.1, 0.6, 0.25) * 0.3
		return reverb(mix((0, steps), (0, wh)), 0.2, 0.12)
	if name == "low_hp":
		b = lambda: lead(note(88), 0.09, 0.25, 0.5)
		return mix((0, b()), (0.14, b()))
	if name == "save":
		mel = mix(*[(t, bellnote(note(n), 0.5, 0.4)) for t, n in [(0, 79), (0.1, 84), (0.2, 88), (0.3, 91)]])
		return reverb(mel, 0.4, 0.25)
	if name == "badge":
		seq = [(0, 67, 0.12), (0.13, 72, 0.12), (0.26, 76, 0.12), (0.39, 79, 0.3), (0.72, 76, 0.12), (0.85, 79, 0.7)]
		mel = mix(*[(t, lay(lead(note(n), d, 0.35, 0.25), bellnote(note(n + 12), d + 0.3, 0.15))) for t, n, d in seq])
		harm = mix(*[(0.85, lead(note(n), 0.7, 0.14, 0.5)) for n in (64, 67, 72)])
		bass = mix((0, tone("tri", note(43), 0.7, 0.01, 0.1, 0.6, 0.1, 0.45)), (0.72, tone("tri", note(48), 0.9, 0.01, 0.2, 0.6, 0.3, 0.45)))
		return reverb(mix((0, mel), (0, harm), (0, bass), (0.85, impact(0.4, 2500) * 0.2)), 0.6, 0.25)
	if name == "buy":
		cl = bp(noise(0.04), 2000, 8000) * exp_env(_n(0.04), 0.01) * 0.6
		ch = mix((0.03, bellnote(note(96), 0.6, 0.35)), (0.09, bellnote(note(100), 0.7, 0.35)))
		return reverb(mix((0, cl), (0, ch)), 0.3, 0.2)
	if name == "spotted":
		st = mix((0, lead(note(84), 0.07, 0.4, 0.25)), (0.07, lead(note(91), 0.2, 0.45, 0.25)), (0.07, bellnote(note(103), 0.3, 0.2)))
		return reverb(soft(st, 1.3), 0.25, 0.15)
	if name == "ledge":
		up = sine(glide(300, 700, 0.12), 0.12) * env(_n(0.12), 0.005, 0.05, 0.5, 0.05) * 0.3
		return mix((0, up), (0.2, fx("bump") * 0.8))
	raise KeyError(name)


NAMES = [
	"cursor", "confirm", "cancel", "error", "bump", "door", "encounter", "hit", "hit_super", "hit_weak",
	"faint", "stat_up", "stat_down", "status", "recover", "send_out", "orb_throw", "orb_shake", "catch",
	"breakout", "level_up", "exp", "heal", "evolve_start", "evolve_done", "run", "low_hp", "save",
	"badge", "buy", "spotted", "ledge", "text",
]
# Loudness targets (peak, linear): UI blips sit under the music, hits and jingles are punchier.
PEAK = {"cursor": 0.35, "text": 0.2, "exp": 0.35, "low_hp": 0.4}


def write(name: str, x: np.ndarray) -> None:
	x = np.asarray(x, float)
	# trim trailing near-silence, short fade to avoid clicks
	nz = np.nonzero(np.abs(x) > 1e-4)[0]
	x = x[: (nz[-1] + 1) if len(nz) else len(x)]
	fade = min(len(x), _n(0.004))
	x[-fade:] *= np.linspace(1, 0, fade)
	x = hp(x, 30)
	peak = np.abs(x).max() or 1.0
	x = x / peak * PEAK.get(name, 0.7)
	OUT.mkdir(parents=True, exist_ok=True)
	with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


if __name__ == "__main__":
	for n in sys.argv[1:] or NAMES:
		write(n, fx(n))
		print("wrote", n)
