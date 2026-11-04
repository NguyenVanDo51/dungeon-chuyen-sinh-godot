extends SceneTree
## synth sfx the Kenney packs lack -> assets/sfx/default/<slot>/synth_<n>.wav (3 variants each)
## run: godot --headless --path . -s tools/gen_sfx.gd

const SR := 44100
const OUT := "res://assets/sfx/default/"
var rng := RandomNumberGenerator.new()

class Svf:
	var low := 0.0
	var band := 0.0
	## Chamberlin state-variable filter; returns [low, band, high]
	func step(x: float, fc: float, damp: float) -> Array:
		var f := 2.0 * sin(PI * minf(fc, 7000.0) / 44100.0)
		var high := x - low - damp * band
		band += f * high
		low += f * band
		return [low, band, high]

func _init() -> void:
	for v in 3:
		rng.seed = 1000 + v
		var j := 1.0 + (v - 1) * 0.06
		_save("swing", v, _swing(false, j))
		_save("swing_holy", v, _swing(true, j))
		_save("bow", v, _bow(j))
		_save("fire_cast", v, _fire_cast(j))
		_save("explode", v, _explode(1.0, j, false))
		_save("meteor", v, _explode(1.7, j * 0.85, false))
		_save("nova", v, _explode(1.3, j * 0.8, true))
		_save("thunder", v, _thunder(false, j))
		_save("thunder_big", v, _thunder(true, j))
		_save("beam", v, _beam(j))
		_save("arrow_rain", v, _arrow_rain())
		_save("boss_cast", v, _boss_cast(j))
		if v == 0:
			_save("meteor_warn", v, _whistle())
			_save("holy_wrath", v, _holy_wrath())
			_save("level_up", v, _arp([523.25, 659.25, 783.99, 1046.5], 0.07, 1.3, 0.35))
			_save("hidden_unlock", v, _unlock())
			_save("boss_roar", v, _roar(1.0, 2.0))
			_save("enrage", v, _roar(1.35, 1.5))
			_save("boss_bell", v, _bell(98.0, 3.5))
			_save("win", v, _fanfare())
			_save("lose", v, _lose())
			_save("heartbeat", v, _heartbeat())
	quit()

# ---------- primitives ----------
func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * SR))
	return b

func _n() -> float:
	return rng.randf() * 2.0 - 1.0

static func _saw(ph: float) -> float:
	return 2.0 * (ph - floorf(ph + 0.5))

## mix src into dst starting at sec
static func _add(dst: PackedFloat32Array, src: PackedFloat32Array, sec: float, gain := 1.0) -> void:
	var o := int(sec * SR)
	for i in src.size():
		if o + i < dst.size():
			dst[o + i] += src[i] * gain

static func _drive(b: PackedFloat32Array, k: float) -> void:
	for i in b.size():
		b[i] = tanh(b[i] * k)

## Schroeder/freeverb-ish tail: 4 damped combs + 2 allpasses
static func _reverb(b: PackedFloat32Array, wet: float, room := 0.84) -> void:
	var combs := [1557, 1617, 1491, 1422]
	var aps := [556, 441]
	var out := PackedFloat32Array()
	out.resize(b.size())
	for d in combs:
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		var lp := 0.0
		for i in b.size():
			var y := line[idx]
			lp = y * 0.8 + lp * 0.2
			line[idx] = b[i] * 0.015 + lp * room
			idx = (idx + 1) % d
			out[i] += y
	for d in aps:
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		for i in out.size():
			var y := line[idx]
			var x := out[i]
			line[idx] = x + y * 0.5
			out[i] = y - x * 0.5
			idx = (idx + 1) % d
	for i in b.size():
		b[i] += out[i] * wet * 4.0

func _save(slot: String, v: int, b: PackedFloat32Array) -> void:
	var peak := 0.0001
	for x in b:
		peak = maxf(peak, absf(x))
	var g := 0.9 / peak
	var fade := int(0.012 * SR)
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		var k := minf(1.0, float(b.size() - 1 - i) / fade)
		bytes.encode_s16(i * 2, int(clampf(b[i] * g * k, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + slot))
	var path := ProjectSettings.globalize_path("%s%s/synth_%d.wav" % [OUT, slot, v])
	var err := s.save_to_wav(path)
	print("%s %s %.2fs" % ["ok" if err == OK else "ERR", path.get_file(), b.size() / float(SR)])

# ---------- sounds ----------
func _swing(holy: bool, j: float) -> PackedFloat32Array:
	var dur := 0.3 if holy else 0.22
	var b := _buf(1.0 if holy else dur + 0.05)
	var f := Svf.new()
	for i in int(dur * SR):
		var p := i / (dur * SR)
		var env := p / 0.25 if p < 0.25 else exp(-(p - 0.25) * 6.0)
		var fc := ((350.0 + 1700.0 * sin(PI * p)) if holy else (500.0 + 2600.0 * sin(PI * p))) * j
		b[i] = f.step(_n(), fc, 0.6)[1] * env
	if holy:
		for fr in [1046.5, 1318.5, 1568.0]:
			for i in range(int(0.05 * SR), b.size()):
				var t := i / float(SR) - 0.05
				b[i] += sin(TAU * fr * j * t) * exp(-t * 5.0) * 0.12
		_reverb(b, 0.35)
	return b

func _bow(j: float) -> PackedFloat32Array:
	var b := _buf(0.4)
	# Karplus-Strong string
	var n := int(SR / (190.0 * j))
	var ks := PackedFloat32Array()
	ks.resize(n)
	for i in n:
		ks[i] = _n()
	for i in b.size():
		var k := i % n
		var nxt := ks[(k + 1) % n]
		var y := ks[k]
		ks[k] = 0.5 * (y + nxt) * 0.993
		b[i] = y * 0.6
	var f := Svf.new()
	for i in int(0.16 * SR):
		var t := i / float(SR)
		var hp: float = f.step(_n(), 2500.0, 1.0)[2]
		b[i] += hp * exp(-t * 70.0) * 0.8
	var g := Svf.new()
	for i in int(0.15 * SR):
		var p := i / (0.15 * SR)
		b[i] += g.step(_n(), (3500.0 - 1800.0 * p) * j, 0.3)[1] * sin(PI * p) * 0.35
	return b

func _fire_cast(j: float) -> PackedFloat32Array:
	var b := _buf(0.5)
	var f := Svf.new()
	var c := Svf.new()
	for i in int(0.42 * SR):
		var p := i / (0.42 * SR)
		var t := i / float(SR)
		var env := p / 0.12 if p < 0.12 else exp(-(p - 0.12) * 4.0)
		var fc := (400.0 + 1500.0 * sin(PI * minf(1.0, p * 1.4))) * j
		var crack := _n() if rng.randf() < 0.004 else 0.0
		b[i] = f.step(_n(), fc, 0.8)[0] * env + c.step(crack, 3000.0, 1.2)[1] * 0.9 + sin(TAU * 85.0 * t) * exp(-t * 9.0) * 0.4
	return b

func _explode(size: float, j: float, dark: bool) -> PackedFloat32Array:
	var dur := 0.9 * size
	var b := _buf(dur + 0.8)
	var f := Svf.new()
	var g := Svf.new()
	var ph := 0.0
	var sp := 0.0
	for i in int(dur * SR):
		var t := i / float(SR)
		var fr := (35.0 + 60.0 * exp(-t * 14.0)) * j
		ph += fr / SR
		var thump := sin(TAU * ph) * exp(-t * 7.0 / size)
		var fc := 3200.0 * exp(-t * 5.0 / size) + 140.0
		var noise: float = f.step(_n(), fc * j, 0.9)[0] * exp(-t * 3.5 / size)
		b[i] = thump + noise * 1.4
		if dark:
			sp += (150.0 * exp(-t * 2.0) + 45.0) / SR
			b[i] += g.step(_saw(sp), 400.0, 0.5)[1] * exp(-t * 2.5) * 0.8
	_drive(b, 1.8)
	_reverb(b, 0.25 + 0.1 * size)
	return b

func _whistle() -> PackedFloat32Array:
	var b := _buf(0.9)
	var ph := 0.0
	for i in int(0.8 * SR):
		var t := i / float(SR)
		var p := t / 0.8
		var fr := 1800.0 * pow(500.0 / 1800.0, p) * (1.0 + 0.03 * sin(TAU * 6.0 * t))
		ph += fr / SR
		var env := minf(1.0, t / 0.1) * (1.0 - p * 0.4)
		b[i] = sin(TAU * ph) * env * 0.4 + _n() * env * 0.04
	return b

func _thunder(big: bool, j: float) -> PackedFloat32Array:
	var rum := 1.6 if big else 0.7
	var b := _buf(rum + 0.9)
	var hp := Svf.new()
	var lp := Svf.new()
	var cr := Svf.new()
	for i in int(rum * SR):
		var t := i / float(SR)
		var crack: float = hp.step(_n(), 3000.0 * j, 1.0)[2] * exp(-t * 90.0) * 1.3
		var spike := _n() * 1.2 if rng.randf() < 0.02 * exp(-t * 12.0) else 0.0
		var env := minf(1.0, t / 0.04) * exp(-t * 3.0 / rum)
		var rumble: float = lp.step(_n(), (180.0 if big else 260.0) * j, 0.7)[0] * env * 2.2
		b[i] = crack + cr.step(spike, 2200.0, 1.0)[1] + rumble
	_drive(b, 1.6)
	_reverb(b, 0.4 if big else 0.28)
	return b

func _beam(j: float) -> PackedFloat32Array:
	var b := _buf(0.5)
	var f := Svf.new()
	var h := Svf.new()
	var a := 0.0
	var c := 0.0
	for i in int(0.38 * SR):
		var t := i / float(SR)
		var fr := (1400.0 * exp(-t * 8.0) + 180.0) * j * (1.0 + 0.05 * sin(TAU * 35.0 * t))
		a += fr / SR
		c += fr * 1.5 / SR
		var x := _saw(a) + 0.5 * _saw(c)
		var env := minf(1.0, t / 0.01) * exp(-t * 7.0)
		b[i] = f.step(x, 2200.0 * exp(-t * 4.0) + 500.0, 0.5)[1] * env + h.step(_n(), 5000.0, 1.0)[2] * env * 0.15
	_reverb(b, 0.2)
	return b

func _arrow_rain() -> PackedFloat32Array:
	var b := _buf(1.1)
	for k in 10:
		var w := _buf(0.3)
		var f := Svf.new()
		var lp := Svf.new()
		var top := 3500.0 + rng.randf() * 1500.0
		for i in int(0.12 * SR):
			var p := i / (0.12 * SR)
			w[i] = f.step(_n(), top - 2000.0 * p, 0.3)[1] * sin(PI * p) * 0.5
		for i in range(int(0.12 * SR), int(0.2 * SR)):
			var t := i / float(SR) - 0.12
			w[i] = lp.step(_n(), 500.0, 0.8)[0] * exp(-t * 50.0) * 0.8
		_add(b, w, rng.randf() * 0.65, 0.6 + rng.randf() * 0.4)
	return b

func _holy_wrath() -> PackedFloat32Array:
	var b := _explode(1.3, 0.9, false)
	var tail := _buf(2.0)
	for fr in [523.25, 659.25, 783.99, 1046.5]:
		for i in tail.size():
			var t := i / float(SR)
			tail[i] += sin(TAU * fr * t * (1.0 + 0.004 * sin(TAU * 5.0 * t))) * minf(1.0, t / 0.05) * exp(-t * 1.8) * 0.18
	var out := _buf(2.2)
	_add(out, b, 0.0)
	_add(out, tail, 0.02)
	_reverb(out, 0.3)
	return out

## bell-ish notes in sequence, last one rings
func _arp(notes: Array, gap: float, dur: float, wet: float) -> PackedFloat32Array:
	var b := _buf(dur)
	for k in notes.size():
		var fr: float = notes[k]
		var o := int(k * gap * SR)
		for i in range(o, b.size()):
			var t := (i - o) / float(SR)
			b[i] += (sin(TAU * fr * t) + 0.45 * sin(TAU * fr * 2.76 * t) * exp(-t * 14.0) + 0.25 * sin(TAU * fr * 2.0 * t)) * exp(-t * (4.0 if k < notes.size() - 1 else 2.2)) * 0.3
	_reverb(b, wet)
	return b

func _unlock() -> PackedFloat32Array:
	var b := _buf(2.6)
	_add(b, _explode(0.8, 0.7, false), 0.0, 0.7)
	_add(b, _arp([392.0, 493.88, 587.33, 783.99, 987.77, 1174.66, 1567.98], 0.06, 2.4, 0.0), 0.05, 0.9)
	for fr in [392.0, 493.88, 587.33, 783.99]:
		var o := int(0.4 * SR)
		for i in range(o, b.size()):
			var t := (i - o) / float(SR)
			b[i] += sin(TAU * fr * t * (1.0 + 0.003 * sin(TAU * 5.5 * t))) * minf(1.0, t / 0.3) * exp(-t * 1.2) * 0.12
	_reverb(b, 0.45)
	return b

func _roar(pitch: float, dur: float) -> PackedFloat32Array:
	var b := _buf(dur + 0.9)
	var f1 := Svf.new()
	var f2 := Svf.new()
	var ph := 0.0
	for i in int(dur * SR):
		var t := i / float(SR)
		var p := t / dur
		var fr := (62.0 + 18.0 * sin(TAU * 2.5 * t) + 10.0 * sin(PI * p)) * pitch
		ph += fr / SR
		var x := _saw(ph) * (0.75 + 0.25 * sin(TAU * 27.0 * t)) + _n() * 0.35
		var env := minf(1.0, t / 0.15) * (1.0 if p < 0.65 else 1.0 - (p - 0.65) / 0.35)
		b[i] = (f1.step(x, 520.0 * pitch, 0.4)[1] + f2.step(x, 950.0 * pitch, 0.5)[1] * 0.7 + x * 0.25) * env
	_drive(b, 3.0)
	_reverb(b, 0.4)
	return b

func _boss_cast(j: float) -> PackedFloat32Array:
	var b := _buf(1.6)
	var f := Svf.new()
	var ph := 0.0
	var dur := 0.7
	for i in int(dur * SR):
		var t := i / float(SR)
		var p := t / dur
		var fr := 150.0 * pow(5.0, p) * j
		ph += fr / SR
		var env := p * p
		b[i] = (sin(TAU * ph) * 0.5 + _saw(ph * 0.5) * 0.2) * env + f.step(_n(), 300.0 + 2800.0 * p, 0.5)[1] * env * 0.7
	var hit := _explode(0.4, 1.4, true)
	_add(b, hit, dur - 0.02, 0.6)
	_reverb(b, 0.25)
	return b

## inharmonic toll; partial ratios of a church bell
func _bell(f0: float, dur: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var parts := [[0.5, 1.0, 0.6], [1.0, 0.8, 0.9], [1.19, 0.5, 1.4], [1.56, 0.45, 1.8], [2.0, 0.35, 2.2], [2.51, 0.25, 3.0], [3.01, 0.2, 3.5]]
	for pr in parts:
		for i in b.size():
			var t := i / float(SR)
			b[i] += sin(TAU * f0 * pr[0] * t) * pr[1] * exp(-t * pr[2]) * minf(1.0, t / 0.004)
	var f := Svf.new()
	for i in int(0.05 * SR):
		b[i] += f.step(_n(), 2000.0, 1.0)[1] * exp(-i / float(SR) * 80.0) * 0.6
	_reverb(b, 0.4)
	return b

func _brass(fr: float, dur: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var f := Svf.new()
	var ph := 0.0
	for i in b.size():
		var t := i / float(SR)
		ph += fr * (1.0 + 0.004 * sin(TAU * 5.0 * t)) / SR
		var env := minf(1.0, t / 0.04) * exp(-t * 1.2)
		b[i] = f.step(_saw(ph), 600.0 + 2200.0 * env, 0.6)[0] * env * 0.35
	return b

func _fanfare() -> PackedFloat32Array:
	var b := _buf(3.0)
	var notes := [261.63, 329.63, 392.0, 523.25]
	for k in notes.size():
		_add(b, _brass(notes[k], 0.5), k * 0.14)
	for fr in [261.63, 329.63, 392.0, 523.25, 659.25]:
		_add(b, _brass(fr, 2.2), 0.6, 0.8)
	_add(b, _explode(0.6, 0.8, false), 0.6, 0.5)
	_reverb(b, 0.35)
	return b

func _lose() -> PackedFloat32Array:
	var b := _buf(4.2)
	var notes := [440.0, 349.23, 293.66, 220.0]
	for k in notes.size():
		_add(b, _brass(notes[k] * 0.5, 1.2 if k < 3 else 2.2), k * 0.38, 1.0)
	_add(b, _bell(73.4, 2.5), 1.1, 0.5)
	_reverb(b, 0.4)
	return b

func _heartbeat() -> PackedFloat32Array:
	var b := _buf(0.55)
	for beat in [[0.0, 52.0, 1.0], [0.17, 62.0, 0.7]]:
		var o := int(beat[0] * SR)
		var ph := 0.0
		for i in range(o, o + int(0.25 * SR)):
			var t := (i - o) / float(SR)
			ph += beat[1] * (1.0 + exp(-t * 30.0)) / SR
			b[i] += sin(TAU * ph) * exp(-t * 16.0) * beat[2]
	_drive(b, 1.5)
	return b
