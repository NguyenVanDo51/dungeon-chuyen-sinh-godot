class_name Boss
## boss fight (port of game/boss.ts + hostile.ts): survival wakes it on the clock, a dungeon when the player
## enters the boss room (or the time limit pulls them in); attacks from Bosses.DEFS; plus hostile shots / zones

class State:
	var uid: int
	## hp at spawn (HUD bar)
	var max_hp := 1.0
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

## hostile damage: enrage × the mode's boss difficulty
static func _dmg_mul(w: World, b: State) -> float:
	return (w.boss_def.enrage.damage_mul if b.enraged else 1.0) * w.rules.boss_difficulty

static func _cast(w: World, b: State, a: Dictionary, at: Vector2) -> void:
	var D := w.boss_def
	match a.kind:
		"volley":
			var n := roundi(a.count * (D.enrage.count_mul if b.enraged else 1.0))
			for k in n:
				var ang: float = b.age * 0.7 + (TAU * k) / n
				_shot(w, at.x, at.y, ang, a.speed, a.radius, a.damage * _dmg_mul(w, b), a.life)
		"summon":
			var m := Monsters.idx(D.minion)
			var last := w.last_zone()
			for k in a.n:
				var ang: float = (TAU * k) / a.n
				var sx: float = at.x + cos(ang) * a.ring
				var sz: float = at.y + sin(ang) * a.ring
				if not w.grid.walkable_at(sx, sz):
					sx = at.x
					sz = at.y
				w.enemies.spawn(m, sx, sz, Monsters.DEFS[m].hp * w.scale_at(last).hp, false, last if w.rules.spawn == "depth" else 0)
		"spiral":
			b.channel = { left = a.duration, acc = 0.0, ang = b.age, spec = a }
		"cage":
			var p := w.player
			var a0 := w.rng.next() * TAU
			for k in a.n:
				var ang: float = a0 + (TAU * k) / a.n
				_zone(w, p.x + cos(ang) * a.ring, p.z + sin(ang) * a.ring, a.radius, a.delay, a.damage * _dmg_mul(w, b))
		"adds":
			var last := w.last_zone()
			var pool: Array = w.zone_types[last]
			var p := w.player
			var g := w.grid
			# flow field = where the player can walk: in a sealed arena that is the room itself
			var cells: Array[int] = []
			for i in g.w * g.h:
				if w.flow.dist[i] < 0:
					continue
				var c := Grid.cell_center(i % g.w, i / g.w)
				if Vec.hypot(c.x - p.x, c.y - p.z) >= a.min_dist:
					cells.append(i)
			if cells.is_empty():
				return
			var n := roundi(a.n * (D.enrage.count_mul if b.enraged else 1.0))
			for k in n:
				var i := cells[w.rng.rint(0, cells.size() - 1)]
				var c := Grid.cell_center(i % g.w, i / g.w)
				var t: int = pool[w.rng.rint(0, pool.size() - 1)]
				w.enemies.spawn(t, c.x, c.y, Monsters.DEFS[t].hp * w.scale_at(last).hp, false, last)
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

static func _spawn(w: World, pull := false) -> void:
	var e := w.enemies
	var D := w.boss_def
	w.enter_arena(pull)
	var at := w.grid.boss_spawn if w.grid.has_boss_spawn else w.grid.start
	var i := e.spawn(Monsters.idx(D.enemy), at.x, at.y, D.hp * w.rules.boss_difficulty)
	if i < 0:
		return
	var b := State.new()
	b.uid = e.uid[i]
	b.max_hp = D.hp * w.rules.boss_difficulty
	for a in D.attacks:
		b.t.append(a.first)
	w.boss = b
	w.events.append({ t = "bossSpawn" })

static func update(w: World, dt: float) -> void:
	var D := w.boss_def
	if w.boss == null:
		if w.boss_defeated:
			return
		if w.rules.boss == "enterRoom":
			_update_room(w, dt)
			return
		var at: float = w.rules.boss_at
		if not w.boss_warned and w.time >= at - D.warn_seconds:
			w.boss_warned = true
			w.events.append({ t = "bossWarn", pull = false })
		if w.time >= at:
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
	var d := Vec.hypot(dx, dz)
	var def: Dictionary = Monsters.DEFS[Monsters.idx(D.enemy)]
	if d > D.keep_distance:
		w.flow.direction(w.grid, x, z)
		var dirx := FlowField.ox
		var dirz := FlowField.oz
		if dirx == 0.0 and dirz == 0.0 and d > 1e-4:
			dirx = dx / d
			dirz = dz / d
		var speed: float = def.speed * (D.enrage.speed_mul if b.enraged else 1.0)
		Collision.resolve(w.grid, x + dirx * speed * dt, z + dirz * speed * dt, def.radius)
		e.x[i] = Collision.rx
		e.z[i] = Collision.rz
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

## dungeon: standing in the boss room for warn_seconds wakes it; the time limit drags an outside player in
static func _update_room(w: World, dt: float) -> void:
	var D := w.boss_def
	var p := w.player
	var lim: float = w.rules.boss_at
	var inside := w.grid.in_boss_room(p.x, p.z)
	# a player already inside gets the walk-in warning only, never both
	if not w.limit_warned and not inside and not w.boss_warned and w.time >= lim - D.warn_seconds:
		w.limit_warned = true
		w.events.append({ t = "bossWarn", pull = true })
	if w.time >= lim:
		# time is up: drop an outside player into the room, then seal it like a walk-in
		if not inside:
			var c: Vector2
			if w.map.has("arena_entry"):
				c = Grid.cell_center(w.map.arena_entry.x, w.map.arena_entry.y)
			else:
				c = w.grid.boss_spawn if w.grid.has_boss_spawn else w.grid.start
			p.x = c.x
			p.z = c.y
		_spawn(w, not inside)
		return
	# stepping out during the warning re-arms it, so the doors never seal with the player outside
	if not inside:
		w.boss_warned = false
		w.boss_warn_t = 0.0
		return
	if not w.boss_warned:
		w.boss_warned = true
		w.boss_warn_t = 0.0
		if not w.limit_warned:
			w.events.append({ t = "bossWarn", pull = false })
	w.boss_warn_t += dt
	if w.boss_warn_t >= D.warn_seconds:
		_spawn(w)

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
		if not dead and p.invuln <= 0.0 and Vec.hypot(p.x - s.x, p.z - s.z) < s.r + pr:
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
		if p.invuln <= 0.0 and Vec.hypot(p.x - zn.x, p.z - zn.z) <= zn.r + pr:
			Enemies.hurt_player(w, zn.damage)
		w.events.append({ t = "explode", x = zn.x, z = zn.z, radius = zn.r, kind = "nova" })
		zones[k] = zones[zones.size() - 1]
		zones.pop_back()
