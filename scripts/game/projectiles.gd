class_name Projectiles
## player projectiles: arrow, fireball, sword wave, meteor (delayed sky strike)

class Shot:
	var kind: String
	var x: float
	var z: float
	var vx: float
	var vz: float
	var damage: float
	var pierce: float
	var radius: float
	var life: float
	var hit_ids := {}
	var explode_radius := 0.0
	var delay := 0.0

static func make(kind: String, x: float, z: float, vx: float, vz: float, damage: float, pierce: float, radius: float, life: float) -> Shot:
	var s := Shot.new()
	s.kind = kind; s.x = x; s.z = z; s.vx = vx; s.vz = vz
	s.damage = damage; s.pierce = pierce; s.radius = radius; s.life = life
	return s

static func explode(w: World, x: float, z: float, radius: float, damage: float, kind: String) -> void:
	var e := w.enemies
	w.events.append({ t = "explode", x = x, z = z, radius = radius, kind = kind })
	for i in range(e.count - 1, -1, -1):
		var r := radius + e.radius(i)
		if Vec.hypot(e.x[i] - x, e.z[i] - z) <= r and Enemies.can_reach(w, x, z, i):
			Enemies.damage(w, i, damage)

static func update(w: World, dt: float) -> void:
	var e := w.enemies
	var list := w.projectiles
	for k in range(list.size() - 1, -1, -1):
		var p: Shot = list[k]
		var dead := false
		if p.kind == "meteor":
			p.delay -= dt
			if p.delay <= 0.0:
				explode(w, p.x, p.z, p.explode_radius, p.damage, "meteor")
				dead = true
		else:
			p.x += p.vx * dt
			p.z += p.vz * dt
			p.life -= dt
			if p.life <= 0.0:
				dead = true
			elif not w.grid.walkable_at(p.x, p.z):
				if p.kind == "fireball":
					explode(w, p.x - p.vx * dt, p.z - p.vz * dt, p.explode_radius, p.damage, "fireball")
				dead = true
			else:
				var i := e.count - 1
				while i >= 0 and not dead:
					var u := e.uid[i]
					if not p.hit_ids.has(u):
						var r := p.radius + e.radius(i)
						if Vec.hypot(e.x[i] - p.x, e.z[i] - p.z) <= r:
							if p.kind == "fireball":
								explode(w, p.x, p.z, p.explode_radius, p.damage, "fireball")
								dead = true
							else:
								p.hit_ids[u] = true
								Enemies.damage(w, i, p.damage)
								# each wave heals at most one swing's worth
								if p.kind == "swordWave" and p.hit_ids.size() * Characters.LEECH.per_hit <= Characters.LEECH.max_per_swing:
									w.weapon_hits("holySword", 1)
								p.pierce -= 1.0
								if p.pierce <= 0.0:
									dead = true
					i -= 1
		if dead:
			list[k] = list[list.size() - 1]
			list.pop_back()
