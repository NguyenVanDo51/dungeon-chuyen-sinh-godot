class_name Vec
## float64 helpers: Vector2 is float32 in Godot, the TS sim runs in doubles (keeps runs bit-comparable)

## = V8 Math.hypot (scale by max, Kahan sum): plain sqrt(a²+b²) can differ in the last bit
static func hypot(a: float, b: float) -> float:
	a = absf(a)
	b = absf(b)
	var m := maxf(a, b)
	if m == 0.0 or is_inf(m):
		return m
	var na := a / m
	var nb := b / m
	var sum := na * na
	var summand := nb * nb
	var pre := sum + summand
	# compensation from the first term is 0, so the Kahan loop reduces to one step
	return sqrt(pre) * m
