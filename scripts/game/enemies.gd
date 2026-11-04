class_name Enemies
## enemy AI, damage, crowd control, targeting (port of game/enemies.ts + targeting.ts)

## max speed (units/s) at which crowded enemies push apart; frame-rate independent
const SEPARATION_SPEED := 6.0

static var _near := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

## force: item freeze also catches elites (never cc-immune types)
static func freeze(w: World, i: int, seconds: float, force := false) -> void:
	var e := w.enemies
	if EnemyPool.CC_IMMUNE[e.type[i]] or (not force and e.immovable(i)):
		return
	e.frozen[i] = maxf(e.frozen[i], seconds)

static func slow(w: World, i: int, seconds: float) -> void:
	var e := w.enemies
	if EnemyPool.CC_IMMUNE[e.type[i]]:
		return
	e.slow[i] = maxf(e.slow[i], seconds)

static func hurt_player(w: World, raw: float) -> void:
	var p := w.player
	p.hp -= raw * (1.0 - Data.KNIGHT.damage_reduction)
	p.invuln = Data.BALANCE.invuln_seconds
	w.hurt_this_tick = true
	w.since_hurt = 0.0
	w.events.append({ t = "playerHurt" })

static func _touch_player(w: World, i: int, x: float, z: float, radius: float, damage: float) -> void:
	var p := w.player
	if p.invuln > 0.0 or Vector2(p.x - x, p.z - z).length() >= radius + Data.BALANCE.player_radius:
		return
	hurt_player(w, damage)
	w.last_hurt_by = w.enemies.uid[i]

static func update(w: World, dt: float) -> void:
	var e := w.enemies
	var p := w.player
	var g := w.grid
	w.refresh_flow_field()
	w.enemy_hash.clear()
	var ex := e.x
	var ez := e.z
	for i in e.count:
		w.enemy_hash.insert(i, ex[i], ez[i])

	var pcx := int(floor(p.x / Grid.CELL))
	var pcz := int(floor(p.z / Grid.CELL))
	var lure := w.lure
	var dmg_by_zone: Array[float] = [w.scale_at(0).dmg, w.scale_at(1).dmg, w.scale_at(2).dmg]
	var pr: float = Data.BALANCE.player_radius
	for i in e.count:
		var def: Dictionary = Data.ENEMIES[e.type[i]]
		if e.hit_flash[i] > 0.0:
			e.hit_flash[i] = maxf(0.0, e.hit_flash[i] - dt)
		if e.frozen[i] > 0.0:
			e.frozen[i] = maxf(0.0, e.frozen[i] - dt)
			continue
		var radius := e.radius(i)
		var x := ex[i]
		var z := ez[i]
		if EnemyPool.SCRIPTED[e.type[i]]:
			if def.damage > 0.0:
				_touch_player(w, i, x, z, radius, def.damage)
			continue
		var dx := p.x - x
		var dz := p.z - z
		var d_player := sqrt(dx * dx + dz * dz)

		# close range: steer straight at the player; otherwise follow the flow field around walls
		var ecx := int(floor(x / Grid.CELL))
		var ecz := int(floor(z / Grid.CELL))
		var dir := Vector2.ZERO
		var lx := 0.0
		var lz := 0.0
		var d_lure := INF
		if lure:
			lx = lure.x - x
			lz = lure.z - z
			d_lure = sqrt(lx * lx + lz * lz)
		if lure and d_lure <= lure.aggro:
			if d_lure <= radius + lure.reach:
				lure.touch(w, i, dt)
			else:
				dir = Vector2(lx / d_lure, lz / d_lure)
		elif absi(pcx - ecx) <= 1 and absi(pcz - ecz) <= 1 and d_player > 1e-4:
			dir = Vector2(dx / d_player, dz / d_player)
		else:
			dir = w.flow.direction(g, x, z)

		# separation
		var sx := 0.0
		var sz := 0.0
		var n := w.enemy_hash.query(x, z, 1.2, _near)
		var min_d := radius * 2.0
		for k in n:
			var j := _near[k]
			if j == i:
				continue
			var ox := x - ex[j]
			var oz := z - ez[j]
			var d2 := ox * ox + oz * oz
			if d2 > 1e-8 and d2 < min_d * min_d:
				var d := sqrt(d2)
				sx += (ox / d) * (min_d - d)
				sz += (oz / d) * (min_d - d)
		var s_len := sqrt(sx * sx + sz * sz)
		var s_max := SEPARATION_SPEED * dt
		if s_len > s_max:
			sx *= s_max / s_len
			sz *= s_max / s_len
		var speed: float = def.speed * (0.5 if e.slow[i] > 0.0 else 1.0)
		var nx := x + dir.x * speed * dt + sx
		var nz := z + dir.y * speed * dt + sz
		# enemies stop at the player's body instead of piling on top of it
		var min_p := radius + pr
		var qx := nx - p.x
		var qz := nz - p.z
		var qd := sqrt(qx * qx + qz * qz)
		if qd < min_p * 0.9 and qd > 1e-4:
			nx = p.x + (qx / qd) * min_p * 0.9
			nz = p.z + (qz / qd) * min_p * 0.9
		var res := Collision.resolve(g, nx, nz, radius)
		ex[i] = res.x
		ez[i] = res.y
		if dir != Vector2.ZERO:
			e.dir_x[i] = dir.x
			e.dir_z[i] = dir.y
		if e.slow[i] > 0.0:
			e.slow[i] = maxf(0.0, e.slow[i] - dt)
		var zi: int = mini(e.zone[i], 2)
		_touch_player(w, i, res.x, res.y, radius, def.damage * (Data.ELITE.damage_mul if e.elite[i] == 1 else 1.0) * dmg_by_zone[zi])

static func damage(w: World, i: int, amount: float) -> void:
	var e := w.enemies
	if i < 0 or i >= e.count:
		return
	e.hp[i] -= amount
	e.hit_flash[i] = 0.1
	w.events.append({ t = "hit", x = e.x[i], z = e.z[i], amount = amount })
	if e.hp[i] <= 0.0:
		var t := e.type[i]
		var role: String = Data.ENEMIES[t].role
		if role == "boss":
			e.kill(i)
			w.on_boss_killed()
			return
		# quests see it gone → success; puff but no loot / kill count
		w.events.append({ t = "kill", x = e.x[i], z = e.z[i], type = t })
		if role == "quest":
			e.kill(i)
			return
		w.kills += 1
		w.on_enemy_killed(e.x[i], e.z[i], t, e.elite[i] == 1, e.zone[i])
		e.kill(i)

# ---------- targeting ----------

## ground effects only reach enemies with a clear line from their centre
static func can_reach(w: World, x0: float, z0: float, i: int) -> bool:
	return w.grid.line_of_sight(x0, z0, w.enemies.x[i], w.enemies.z[i])

static func random_within(w: World, x: float, z: float, max_dist: float) -> int:
	var e := w.enemies
	var picks: Array[int] = []
	for i in e.count:
		if Vector2(e.x[i] - x, e.z[i] - z).length() <= max_dist and w.on_screen(e.x[i], e.z[i]):
			picks.append(i)
	return picks[w.rng.rint(0, picks.size() - 1)] if picks.size() > 0 else -1

## nearest enemy the player can actually shoot (no wall in between)
static func nearest_visible(w: World, x: float, z: float, max_dist: float) -> int:
	var e := w.enemies
	var cand: Array[Vector2] = []
	var max2 := max_dist * max_dist
	for i in e.count:
		var dx := e.x[i] - x
		var dz := e.z[i] - z
		var d := dx * dx + dz * dz
		if d < max2 and w.on_screen(e.x[i], e.z[i]):
			cand.append(Vector2(d, i))
	cand.sort()
	for c in cand:
		var i := int(c.y)
		if w.grid.line_of_sight(x, z, e.x[i], e.z[i]):
			return i
	return -1
