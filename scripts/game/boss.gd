class_name Boss
## Lich: warning at 7:57, arena at 8:00, 6 attacks, enrage after 2 min; plus hostile shots / zones

class State:
	var uid: int
	var age := 0.0
	var enraged := false
	## seconds left frozen in place, no casting (holy wrath)
	var stagger := 0.0
	## seconds until attacks[k] fires
	var t: Array[float] = []
	## spiral still pouring out: {left, acc, ang, spec}
	var channel = null

class Shot:
	var x: float
	var z: float
	var vx: float
	var vz: float
	var r: float
	var damage: float
	var life: float

class Zone:
	var x: float
	var z: float
	var r: float
	var delay: float
	var damage: float
	var max_delay: float

static func _shot(w: World, x: float, z: float, a: float, speed: float, r: float, damage: float, life: float) -> void:
	var s := Shot.new()
	s.x = x; s.z = z; s.vx = cos(a) * speed; s.vz = sin(a) * speed; s.r = r; s.damage = damage; s.life = life
	w.hostile_shots.append(s)

static func _zone(w: World, x: float, z: float, r: float, delay: float, damage: float) -> void:
	var zn := Zone.new()
	zn.x = x; zn.z = z; zn.r = r; zn.delay = delay; zn.max_delay = delay; zn.damage = damage
	w.hostile_zones.append(zn)

static func _dmg_mul(w: World, b: State) -> float:
	return (Data.LICH.enrage.damage_mul if b.enraged else 1.0)

static func _cast(w: World, b: State, a: Dictionary, at: Vector2) -> void:
	var D := Data.LICH
	match a.kind:
		"volley":
			var n := roundi(a.count * (D.enrage.count_mul if b.enraged else 1.0))
			for k in n:
				var ang: float = b.age * 0.7 + (TAU * k) / n
				_shot(w, at.x, at.y, ang, a.speed, a.radius, a.damage * _dmg_mul(w, b), a.life)
		"summon":
			var m: int = D.minion
			var last := Data.ZONE_TYPES.size() - 1
			for k in a.n:
				var ang: float = (TAU * k) / a.n
				var sx: float = at.x + cos(ang) * a.ring
				var sz: float = at.y + sin(ang) * a.ring
				if not w.grid.walkable_at(sx, sz):
					sx = at.x
					sz = at.y
				w.enemies.spawn(m, sx, sz, Data.ENEMIES[m].hp * w.scale_at(last).hp, false, 0)
		"spiral":
			b.channel = { left = a.duration, acc = 0.0, ang = b.age, spec = a }
		"cage":
			var p := w.player
			var a0 := w.rng.next() * TAU
			for k in a.n:
				var ang: float = a0 + (TAU * k) / a.n
				_zone(w, p.x + cos(ang) * a.ring, p.z + sin(ang) * a.ring, a.radius, a.delay, a.damage * _dmg_mul(w, b))
		"adds":
			var last := Data.ZONE_TYPES.size() - 1
			var pool: Array = Data.ZONE_TYPES[last]
			var p := w.player
			var g := w.grid
			# flow field = where the player can walk: in a sealed arena that is the room itself
			var cells: Array[int] = []
			for i in g.w * g.h:
				if w.flow.dist[i] < 0:
					continue
				var c := Grid.cell_center(i % g.w, i / g.w)
				if Vector2(c.x - p.x, c.y - p.z).length() >= a.min_dist:
					cells.append(i)
			if cells.is_empty():
				return
			var n := roundi(a.n * (D.enrage.count_mul if b.enraged else 1.0))
			for k in n:
				var i := cells[w.rng.rint(0, cells.size() - 1)]
				var c := Grid.cell_center(i % g.w, i / g.w)
				var t: int = pool[w.rng.rint(0, pool.size() - 1)]
				w.enemies.spawn(t, c.x, c.y, Data.ENEMIES[t].hp * w.scale_at(last).hp, false, last)
		"nova":
			var p := w.player
			for k in a.n:
				var ang := w.rng.next() * TAU
				var r: float = w.rng.next() * a.spread
				_zone(w, p.x + cos(ang) * r, p.z + sin(ang) * r, a.radius, a.delay, a.damage * _dmg_mul(w, b))

static func _emit_spiral(w: World, b: State, at: Vector2, dt: float) -> void:
	var ch = b.channel
	if ch == null:
		return
	var S: Dictionary = ch.spec
	ch.acc += S.rate * dt
	while ch.acc >= 1.0:
		ch.acc -= 1.0
		for k in S.arms:
			_shot(w, at.x, at.y, ch.ang + (TAU * k) / S.arms, S.speed, S.radius, S.damage * _dmg_mul(w, b), S.life)
	ch.ang += S.turn * dt
	ch.left -= dt
	if ch.left <= 0.0:
		b.channel = null

static func _spawn(w: World) -> void:
	var e := w.enemies
	w.enter_arena()
	var at := w.grid.boss_spawn if w.grid.has_boss_spawn else w.grid.start
	var i := e.spawn(Data.LICH.enemy, at.x, at.y, Data.LICH.hp)
	if i < 0:
		return
	var b := State.new()
	b.uid = e.uid[i]
	for a in Data.LICH.attacks:
		b.t.append(a.first)
	w.boss = b
	w.events.append({ t = "bossSpawn" })

static func update(w: World, dt: float) -> void:
	var D := Data.LICH
	if w.boss == null:
		if w.boss_defeated:
			return
		if not w.boss_warned and w.time >= Data.BOSS_AT - D.warn_seconds:
			w.boss_warned = true
			w.events.append({ t = "bossWarn" })
		if w.time >= Data.BOSS_AT:
			_spawn(w)
		return
	var b: State = w.boss
	var e := w.enemies
	var p := w.player
	var i := w.boss_index()
	if i < 0:
		return
	b.age += dt
	if not b.enraged and b.age >= D.enrage_after:
		b.enraged = true
		w.events.append({ t = "enrage" })
	var cd: float = D.enrage.cd_mul if b.enraged else 1.0
	if b.stagger > 0.0:
		b.stagger = maxf(0.0, b.stagger - dt)
		return
	# walk toward the player, keep a little distance to cast
	var x := e.x[i]
	var z := e.z[i]
	var dx := p.x - x
	var dz := p.z - z
	var d := sqrt(dx * dx + dz * dz)
	var def: Dictionary = Data.ENEMIES[D.enemy]
	if d > D.keep_distance:
		var dir := w.flow.direction(w.grid, x, z)
		if dir == Vector2.ZERO and d > 1e-4:
			dir = Vector2(dx / d, dz / d)
		var speed: float = def.speed * (D.enrage.speed_mul if b.enraged else 1.0)
		var res := Collision.resolve(w.grid, x + dir.x * speed * dt, z + dir.y * speed * dt, def.radius)
		e.x[i] = res.x
		e.z[i] = res.y
	if d > 1e-4:
		e.dir_x[i] = dx / d
		e.dir_z[i] = dz / d
	var at := Vector2(e.x[i], e.z[i])
	for k in D.attacks.size():
		b.t[k] -= dt
		if b.t[k] > 0.0:
			continue
		var a: Dictionary = D.attacks[k]
		b.t[k] = a.every * cd
		_cast(w, b, a, at)
		w.events.append({ t = "bossCast", kind = a.kind })
	_emit_spiral(w, b, at, dt)

static func update_hostile(w: World, dt: float) -> void:
	var p := w.player
	var pr: float = Data.BALANCE.player_radius
	var shots := w.hostile_shots
	for k in range(shots.size() - 1, -1, -1):
		var s: Shot = shots[k]
		s.x += s.vx * dt
		s.z += s.vz * dt
		s.life -= dt
		var dead := s.life <= 0.0 or not w.grid.walkable_at(s.x, s.z)
		if not dead and p.invuln <= 0.0 and Vector2(p.x - s.x, p.z - s.z).length() < s.r + pr:
			Enemies.hurt_player(w, s.damage)
			dead = true
		if dead:
			shots[k] = shots[shots.size() - 1]
			shots.pop_back()
	var zones := w.hostile_zones
	for k in range(zones.size() - 1, -1, -1):
		var zn: Zone = zones[k]
		zn.delay -= dt
		if zn.delay > 0.0:
			continue
		if p.invuln <= 0.0 and Vector2(p.x - zn.x, p.z - zn.z).length() <= zn.r + pr:
			Enemies.hurt_player(w, zn.damage)
		w.events.append({ t = "explode", x = zn.x, z = zn.z, radius = zn.r, kind = "nova" })
		zones[k] = zones[zones.size() - 1]
		zones.pop_back()
