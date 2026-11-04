class_name Rng
extends RefCounted
## mulberry32, bit-exact port of src/core/rng.ts

const M := 0xFFFFFFFF
var a: int

func _init(seed_value: int) -> void:
	a = seed_value & M

## low 32 bits of x*y (= Math.imul); split so the 64-bit product never overflows
static func imul(x: int, y: int) -> int:
	x &= M
	y &= M
	var xl := x & 0xFFFF
	var xh := x >> 16
	return (xl * y + (((xh * y) & 0xFFFF) << 16)) & M

func next() -> float:
	a = (a + 0x6d2b79f5) & M
	var t := a
	t = imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + imul(t ^ (t >> 7), t | 61)) & M)) & M
	return float((t ^ (t >> 14)) & M) / 4294967296.0

func rint(lo: int, hi_inclusive: int) -> int:
	return lo + int(floor(next() * float(hi_inclusive - lo + 1)))

## weights[i] for items[i]; null if no positive weight
func pick_weighted(items: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, w)
	if total <= 0.0:
		return null
	var r := next() * total
	for i in items.size():
		var w: float = maxf(0.0, weights[i])
		if w <= 0.0:
			continue
		r -= w
		if r < 0.0:
			return items[i]
	for i in range(items.size() - 1, -1, -1):
		if weights[i] > 0.0:
			return items[i]
	return null
