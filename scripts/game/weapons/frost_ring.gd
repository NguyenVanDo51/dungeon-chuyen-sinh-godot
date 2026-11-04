extends WeaponRuntime
## cold aura: slow + damage; hidden: running leaves ice that freezes enemies

const SLOW_SECONDS := 1.0
## Vệt Băng: running leaves ice behind; enemies stepping on it freeze
const TRAIL := { spacing = 0.8, life = 3.0, radius = 1.1, freeze = 1.2, check = 0.1 }
var tick := 0.0
var check := 0.0
var last_x := NAN
var last_z := NAN
func update(w: World, level: int, hidden: bool, dt: float) -> void:
	var L := Items.lv(id, level)
	var e := w.enemies
	var p := w.player
	var r: float = L.area * w.mods.area_mul
	var trail := w.frost_trail
	for k in range(trail.size() - 1, -1, -1):
		trail[k][2] -= dt
		if trail[k][2] <= 0.0:
			trail[k] = trail[trail.size() - 1]
			trail.pop_back()
	if hidden:
		if is_nan(last_x):
			last_x = p.x
			last_z = p.z
		if Vec.hypot(p.x - last_x, p.z - last_z) >= TRAIL.spacing:
			trail.append([p.x, p.z, TRAIL.life])
			w.rng.next()  # TS draws a render seed here; keep the stream aligned
			last_x = p.x
			last_z = p.z
		check -= dt
		if check <= 0.0 and trail.size() > 0:
			check = TRAIL.check
			var tr: float = TRAIL.radius * w.mods.area_mul
			for i in e.count:
				if e.frozen[i] > 0.2:
					continue
				var er := tr + e.radius(i)
				for t in trail:
					var ax: float = e.x[i] - t[0]
					var az: float = e.z[i] - t[1]
					if ax * ax + az * az <= er * er:
						Enemies.freeze(w, i, TRAIL.freeze)
						break
	else:
		last_x = NAN
	tick -= dt
	if tick > 0.0:
		return
	tick = L.cooldown
	var damage: float = L.damage * w.mods.damage_mul
	for i in range(e.count - 1, -1, -1):
		if Vec.hypot(e.x[i] - p.x, e.z[i] - p.z) > r + e.radius(i) or not Enemies.can_reach(w, p.x, p.z, i):
			continue
		Enemies.slow(w, i, SLOW_SECONDS)
		Enemies.damage(w, i, damage)
	w.events.append({ t = "frostPulse", x = p.x, z = p.z, radius = r })
