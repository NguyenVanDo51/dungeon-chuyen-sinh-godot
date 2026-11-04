class_name Weapons
## weapon runtimes (port of game/weapons/*): holySword, fireball, thunderSeal, frostRing

class Runtime:
	var id: String
	func update(_w: World, _level: int, _hidden: bool, _dt: float) -> void:
		pass

static func create(id: String) -> Runtime:
	match id:
		"holySword": return HolySword.new()
		"fireball": return Fireball.new()
		"thunderSeal": return ThunderSeal.new()
		"frostRing": return FrostRing.new()
	push_error("unknown weapon " + id)
	return null

static func lv(id: String, level: int) -> Dictionary:
	return Data.WEAPONS[id].levels[level - 1]

class HolySword extends Runtime:
	const HALF_ARC := PI / 3.0
	const WAVE := { speed = 14.0, life = 1.2, radius = 1.2 }
	var timer := 0.0
	func _init() -> void:
		id = "holySword"
	func update(w: World, level: int, hidden: bool, dt: float) -> void:
		timer -= dt
		if timer > 0.0:
			return
		var L := Weapons.lv(id, level)
		timer = L.cooldown * w.mods.cooldown_mul
		var p := w.player
		var e := w.enemies
		# auto-aim: when kiting, facing points away from the swarm and the arc would whiff
		var fx := p.facing_x
		var fz := p.facing_z
		var reach: float = L.area * w.mods.area_mul
		var t := Enemies.nearest_visible(w, p.x, p.z, reach + 1.0)
		if t >= 0:
			var dx := e.x[t] - p.x
			var dz := e.z[t] - p.z
			var d := sqrt(dx * dx + dz * dz)
			if d > 1e-4:
				fx = dx / d
				fz = dz / d
		var damage: float = L.damage * w.mods.damage_mul
		var hits := 0
		for i in range(e.count - 1, -1, -1):
			var dx := e.x[i] - p.x
			var dz := e.z[i] - p.z
			var d := sqrt(dx * dx + dz * dz)
			if d > reach + e.radius(i) or not Enemies.can_reach(w, p.x, p.z, i):
				continue
			if d > 1e-4 and acos(clampf((dx * fx + dz * fz) / d, -1.0, 1.0)) > HALF_ARC:
				continue
			Enemies.damage(w, i, damage)
			hits += 1
		w.weapon_hits("holySword", hits)
		w.events.append({ t = "slash", x = p.x, z = p.z, dir_x = fx, dir_z = fz, radius = reach, hidden = hidden })
		if hidden:
			var v: float = WAVE.speed * w.mods.projectile_speed_mul
			w.projectiles.append(Projectiles.make("swordWave", p.x, p.z, fx * v, fz * v, damage, INF, WAVE.radius, WAVE.life))

class Fireball extends Runtime:
	const BALL := { radius = 0.35, life = 2.0 }
	const METEOR := { every = 1.5, delay = 0.6, radius = 3.0, damage = 60.0 }
	var timer := 0.0
	var meteor_timer := 0.0
	func _init() -> void:
		id = "fireball"
	func update(w: World, level: int, hidden: bool, dt: float) -> void:
		var L := Weapons.lv(id, level)
		var p := w.player
		if hidden:
			meteor_timer -= dt
			if meteor_timer <= 0.0:
				var t := Enemies.random_within(w, p.x, p.z, Data.RANGES.sky)
				if t >= 0:
					meteor_timer = METEOR.every * w.mods.cooldown_mul
					var m := Projectiles.make("meteor", w.enemies.x[t], w.enemies.z[t], 0.0, 0.0, METEOR.damage * w.mods.damage_mul, INF, 0.0, METEOR.delay)
					m.explode_radius = METEOR.radius * w.mods.area_mul
					m.delay = METEOR.delay
					w.projectiles.append(m)
					w.events.append({ t = "meteorWarn", x = m.x, z = m.z, radius = m.explode_radius, delay = m.delay })
		timer -= dt
		if timer > 0.0:
			return
		var t := Enemies.nearest_visible(w, p.x, p.z, Data.RANGES.fireball * w.mods.area_mul)
		if t < 0:
			return
		timer = L.cooldown * w.mods.cooldown_mul
		var base := atan2(w.enemies.z[t] - p.z, w.enemies.x[t] - p.x)
		var v: float = L.speed * w.mods.projectile_speed_mul
		var cnt := int(L.count)
		for k in cnt:
			var a := base + (k - (cnt - 1) / 2.0) * 0.25
			var b := Projectiles.make("fireball", p.x, p.z, cos(a) * v, sin(a) * v, L.damage * w.mods.damage_mul, 1.0, BALL.radius, BALL.life)
			b.explode_radius = L.area * w.mods.area_mul
			w.projectiles.append(b)

class ThunderSeal extends Runtime:
	const STORM := { strikes = 10, damage_mul = 1.5 }
	var timer := 0.0
	func _init() -> void:
		id = "thunderSeal"
	func update(w: World, level: int, hidden: bool, dt: float) -> void:
		timer -= dt
		if timer > 0.0:
			return
		var L := Weapons.lv(id, level)
		var e := w.enemies
		var p := w.player
		var first := Enemies.nearest_visible(w, p.x, p.z, Data.RANGES.thunderSeal * w.mods.area_mul)
		if first < 0:
			return
		timer = L.cooldown * w.mods.cooldown_mul
		var damage: float = L.damage * w.mods.damage_mul
		var chain: Array[int] = [first]
		var in_chain := { first: true }
		var points := PackedVector2Array([Vector2(p.x, p.z), Vector2(e.x[first], e.z[first])])
		var area2: float = L.area * L.area
		while chain.size() < int(L.count):
			var from := chain[chain.size() - 1]
			var best := -1
			var best_d := area2
			for i in e.count:
				if in_chain.has(i):
					continue
				var d := pow(e.x[i] - e.x[from], 2) + pow(e.z[i] - e.z[from], 2)
				if d <= best_d and Enemies.can_reach(w, e.x[from], e.z[from], i):
					best_d = d
					best = i
			if best < 0:
				break
			chain.append(best)
			in_chain[best] = true
			points.append(Vector2(e.x[best], e.z[best]))
		w.events.append({ t = "bolt", points = points, big = false })
		var storm: Array[int] = []
		if hidden:
			var pool: Array[int] = []
			for i in e.count:
				if not in_chain.has(i) and Vector2(e.x[i] - p.x, e.z[i] - p.z).length() <= Data.RANGES.sky and w.on_screen(e.x[i], e.z[i]):
					pool.append(i)
			while storm.size() < STORM.strikes and pool.size() > 0:
				var k := w.rng.rint(0, pool.size() - 1)
				storm.append(pool[k])
				pool[k] = pool[pool.size() - 1]
				pool.pop_back()
			for i in storm:
				w.events.append({ t = "bolt", points = PackedVector2Array([Vector2(e.x[i], e.z[i]), Vector2(e.x[i], e.z[i])]), big = true })
		# kills swap-remove: hitting in descending index order keeps every pending index valid
		var hits: Array[Vector2] = []
		for i in chain:
			hits.append(Vector2(i, damage))
		for i in storm:
			hits.append(Vector2(i, damage * STORM.damage_mul))
		hits.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
		for h in hits:
			Enemies.damage(w, int(h.x), h.y)

class FrostRing extends Runtime:
	const SLOW_SECONDS := 1.0
	## Vệt Băng: running leaves ice behind; enemies stepping on it freeze
	const TRAIL := { spacing = 0.8, life = 3.0, radius = 1.1, freeze = 1.2, check = 0.1 }
	var tick := 0.0
	var check := 0.0
	var last_x := NAN
	var last_z := NAN
	func _init() -> void:
		id = "frostRing"
	func update(w: World, level: int, hidden: bool, dt: float) -> void:
		var L := Weapons.lv(id, level)
		var e := w.enemies
		var p := w.player
		var r: float = L.area * w.mods.area_mul
		var trail := w.frost_trail
		for k in range(trail.size() - 1, -1, -1):
			trail[k].z -= dt
			if trail[k].z <= 0.0:
				trail[k] = trail[trail.size() - 1]
				trail.pop_back()
		if hidden:
			if is_nan(last_x):
				last_x = p.x
				last_z = p.z
			if Vector2(p.x - last_x, p.z - last_z).length() >= TRAIL.spacing:
				trail.append(Vector3(p.x, p.z, TRAIL.life))
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
						if pow(e.x[i] - t.x, 2) + pow(e.z[i] - t.y, 2) <= er * er:
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
			if Vector2(e.x[i] - p.x, e.z[i] - p.z).length() > r + e.radius(i) or not Enemies.can_reach(w, p.x, p.z, i):
				continue
			Enemies.slow(w, i, SLOW_SECONDS)
			Enemies.damage(w, i, damage)
		w.events.append({ t = "frostPulse", x = p.x, z = p.z, radius = r })
