class_name LaserSfx
extends RefCounted

## the laser's sounds are synthesised once and cached, not loaded from disk. the zap lasts exactly as
## long as the bolt and the charge exactly as long as the eyes take to fill, because both are made
## from the same numbers; and there is no asset to import, to mis-import or to go missing. a sweep
## down is a shot, a sweep up is a charge, a hum with a wobble is a beam.

const RATE := 22050

static var _cache := {}


## short, bright, falling: the sound of one bolt.
static func zap() -> AudioStreamWAV:
	if not _cache.has("zap"):
		var n := int(RATE * 0.16)
		var out := PackedFloat32Array()
		out.resize(n)
		var phase := 0.0
		for i in n:
			var u := float(i) / float(n)
			var f := 2600.0 * pow(0.12, u)
			phase += TAU * f / RATE
			var env := exp(-u * 5.0) * (1.0 - u)
			out[i] = tanh((sin(phase) * 0.9 + (randf() * 2.0 - 1.0) * 0.25) * env * 1.6)
		_cache["zap"] = Tone.wav(out)
	return _cache["zap"]


## rising and quickening for as long as the charge takes, so the ear knows when the beam is due.
static func charge(duration: float) -> AudioStreamWAV:
	var key := "charge_%.2f" % duration
	if not _cache.has(key):
		var n := int(RATE * maxf(duration, 0.1))
		var out := PackedFloat32Array()
		out.resize(n)
		var phase := 0.0
		var trem_phase := 0.0
		for i in n:
			var u := float(i) / float(n)
			var f := 160.0 + 1400.0 * u * u
			phase += TAU * f / RATE
			trem_phase += TAU * (3.0 + 24.0 * u) / RATE
			var trem := 1.0 - 0.45 * (0.5 + 0.5 * sin(trem_phase))
			var env := (0.18 + 0.82 * u * u) * trem
			out[i] = tanh((sin(phase) + 0.4 * sin(2.0 * phase)) * env * 1.1)
		_cache[key] = Tone.wav(out)
	return _cache[key]


## a hum that loops without a seam: every frequency in it fits a whole number of cycles in the loop.
static func beam() -> AudioStreamWAV:
	if not _cache.has("beam"):
		var n := int(RATE * 0.5)
		var out := PackedFloat32Array()
		out.resize(n)
		for i in n:
			var t := float(i) / RATE
			var v := 0.0
			for k in range(1, 7):
				v += sin(TAU * 96.0 * k * t) / float(k) * (1.0 if k % 2 == 1 else -1.0)
			v += 0.5 * sin(TAU * 192.0 * t)
			var wobble := 0.7 + 0.3 * sin(TAU * 26.0 * t)
			out[i] = tanh((v * 0.45 + (randf() * 2.0 - 1.0) * 0.08) * wobble * 1.3)
		_cache["beam"] = Tone.wav(out, true)
	return _cache["beam"]


## the player's side of a hit: a thump with a crackle, heard in the head rather than in the world.
static func hit() -> AudioStreamWAV:
	if not _cache.has("hit"):
		var n := int(RATE * 0.14)
		var out := PackedFloat32Array()
		out.resize(n)
		for i in n:
			var t := float(i) / RATE
			var u := float(i) / float(n)
			var env := exp(-u * 7.0)
			out[i] = tanh(((randf() * 2.0 - 1.0) * 0.7 + sin(TAU * 70.0 * t) * 0.9) * env * 1.4)
		_cache["hit"] = Tone.wav(out)
	return _cache["hit"]
