extends WeaponRuntime
## arrows at the nearest enemy, fanning out with level; hidden: arrow rain on the densest crowd

const FAN_STEP := 12.0 * PI / 180.0
const ARROW := { radius = 0.3, life = 1.6 }
const RAIN := { every = 3.0, arrows = 12, radius = 3.0, hit_radius = 1.4, duration = 0.6, fall = 0.2, sample = 30, crowd_radius = 3.0 }

var timer := 0.0
var rain_timer := 0.0
## pending strikes of the current rain: [t, x, z, damage]
var strikes: Array = []

## enemy (sampled) with the most neighbours: where a rain of arrows does the most work
func _crowd_centre(w: World) -> int:
	var e := w.enemies
	var p := w.player
	var best := -1
	var best_n := -1
	var seen := 0
	for i in e.count:
		if seen >= RAIN.sample:
			break
		if Vec.hypot(e.x[i] - p.x, e.z[i] - p.z) > Data.RANGES.sky or not w.on_screen(e.x[i], e.z[i]):
			continue
		seen += 1
		var n := 0
		for j in e.count:
			if Vec.hypot(e.x[j] - e.x[i], e.z[j] - e.z[i]) <= RAIN.crowd_radius:
				n += 1
		if n > best_n:
			best_n = n
			best = i
	return best

func update(w: World, level: int, hidden: bool, dt: float) -> void:
	var L := Items.lv(id, level)
	var e := w.enemies
	var p := w.player
	for k in range(strikes.size() - 1, -1, -1):
		var s: Array = strikes[k]
		s[0] -= dt
		if s[0] > 0.0:
			continue
		for i in range(e.count - 1, -1, -1):
			if Vec.hypot(e.x[i] - s[1], e.z[i] - s[2]) <= RAIN.hit_radius + e.radius(i):
				Enemies.damage(w, i, s[3])
		strikes[k] = strikes[strikes.size() - 1]
		strikes.pop_back()
	if hidden:
		rain_timer -= dt
		if rain_timer <= 0.0:
			var c := _crowd_centre(w)
			if c >= 0:
				rain_timer = RAIN.every * w.mods.cooldown_mul
				var cx := e.x[c]
				var cz := e.z[c]
				var r: float = RAIN.radius * w.mods.area_mul
				var damage: float = L.damage * w.mods.damage_mul
				# damage lands after the arrow's fall, so the visual and the hit line up
				var arrows: Array = []
				for k in RAIN.arrows:
					var a := w.rng.next() * TAU
					var d := sqrt(w.rng.next()) * r
					var s := [RAIN.fall + (RAIN.duration * k) / RAIN.arrows, cx + cos(a) * d, cz + sin(a) * d, damage]
					strikes.append(s)
					arrows.append(Vector3(s[1], s[2], s[0]))
				w.events.append({ t = "arrowRain", x = cx, z = cz, r = r, fall = RAIN.fall, arrows = arrows })
	timer -= dt
	if timer > 0.0:
		return
	var t := Enemies.nearest_visible(w, p.x, p.z, Data.RANGES.elvenBow * w.mods.area_mul)
	# stay ready until something is in range
	if t < 0:
		return
	timer = L.cooldown * w.mods.cooldown_mul
	var aim := atan2(e.z[t] - p.z, e.x[t] - p.x)
	var damage: float = L.damage * w.mods.damage_mul
	var v: float = Items.lv(id, 1).speed * w.mods.projectile_speed_mul
	var n := int(L.count)
	for k in n:
		var a := aim + (k - (n - 1) / 2.0) * FAN_STEP
		w.projectiles.append(Projectiles.make("arrow", p.x, p.z, cos(a) * v, sin(a) * v, damage, L.pierce, ARROW.radius, ARROW.life))
	w.events.append({ t = "shot" })
