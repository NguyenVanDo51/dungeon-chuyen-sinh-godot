class_name Quests
## 2 random quests per run at 1:30 and 4:00 (port of game/quests/*)

const NEIGH: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

class State:
	var kind: String
	## "waiting" at the rune, then "active"
	var phase := "waiting"
	var x: float
	var z: float
	## seconds in the current phase
	var t := 0.0
	## per kind; empty while waiting
	var data := {}

## a point enemies within aggro go for instead of the player (crystal)
class Lure:
	var x: float
	var z: float
	var aggro: float
	var reach: float
	var quest: State
	func touch(w: World, i: int, dt: float) -> void:
		var C: Dictionary = Data.QUESTS.crystal
		quest.data.hp -= C.chip * (C.elite_chip if w.enemies.elite[i] == 1 else 1.0) * dt

static func pick_kinds(rng: Rng) -> Array[String]:
	var left: Array[String] = Data.QUEST_KINDS.duplicate()
	var out: Array[String] = []
	while out.size() < 2 and left.size() > 0:
		var k := rng.rint(0, left.size() - 1)
		out.append(left[k])
		left.remove_at(k)
	return out

## xp worth `levels` levels from the current one (fractional last level)
static func reward_xp(level: int, levels: float = Data.QUESTS.reward_levels) -> float:
	var xp := 0.0
	for k in int(floor(levels)):
		xp += Data.xp_to_next(level + k)
	return xp + fmod(levels, 1.0) * Data.xp_to_next(level + int(floor(levels)))

static func _pick_spot(w: World) -> Variant:
	# random reachable room within max_walk cells, the player's own included
	var reach := []
	for s in Data.SPOTS:
		if s.quest and w.flow.dist[s.cz * w.grid.w + s.cx] >= 0:
			reach.append(s)
	if reach.is_empty():
		return null
	var near := []
	for s in reach:
		if w.flow.dist[s.cz * w.grid.w + s.cx] <= Data.QUESTS.max_walk:
			near.append(s)
	var pool := near if near.size() > 0 else reach
	var s: Dictionary = pool[w.rng.rint(0, pool.size() - 1)]
	return Grid.cell_center(s.cx, s.cz)

static func start(w: World, kind: String) -> void:
	var at = _pick_spot(w)
	if at == null:
		return
	var q := State.new()
	q.kind = kind
	q.x = at.x
	q.z = at.y
	w.quest = q
	w.events.append({ t = "questAppear", kind = kind, x = q.x, z = q.z })

static func end(w: World, success: bool) -> void:
	var q: State = w.quest
	if q == null:
		return
	if not success:
		_abort(w, q)
	w.quest = null
	w.lure = null
	w.quest_log.append({ kind = q.kind, success = success })
	w.events.append({ t = "questEnd", kind = q.kind, success = success })
	if success:
		w.add_xp(reward_xp(w.level))

static func update(w: World, dt: float) -> void:
	if w.boss != null:
		return
	if w.quest == null and w.quest_next < w.quests.size() and w.time >= Data.QUEST_AT[w.quest_next]:
		start(w, w.quests[w.quest_next])
		w.quest_next += 1
	var q: State = w.quest
	if q == null:
		return
	q.t += dt
	if q.phase == "waiting":
		if Vector2(w.player.x - q.x, w.player.z - q.z).length() <= Data.QUESTS.trigger_radius:
			q.phase = "active"
			q.t = 0.0
			_activate(w, q)
			w.events.append({ t = "questStart", kind = q.kind })
		elif q.t > Data.QUESTS.window:
			end(w, false)
		return
	var r = _update(w, q, dt)
	if r != null:
		end(w, r)

# ---------- per kind ----------

static func _activate(w: World, q: State) -> void:
	match q.kind:
		"bounce":
			q.data = { progress = 0, misses = 0, from = Vector2(q.x, q.z), target = _landing(w, q, null), land = Data.QUESTS.bounce.warn }
		"hold":
			q.data = { progress = 0.0 }
		"crystal":
			var C: Dictionary = Data.QUESTS.crystal
			q.data = { hp = C.hp }
			# enemies near the crystal attack it instead of the player
			var l := Lure.new()
			l.x = q.x; l.z = q.z; l.aggro = C.aggro; l.reach = C.radius; l.quest = q
			w.lure = l
		"thief":
			q.data = { uid = _spawn_thief(w, q) }

## true = done, false = failed, null = running
static func _update(w: World, q: State, dt: float) -> Variant:
	var p := w.player
	var d := q.data
	match q.kind:
		"bounce":
			var B: Dictionary = Data.QUESTS.bounce
			d.land -= dt
			if d.land > 0.0:
				return null
			var hit: bool = Vector2(p.x - d.target.x, p.z - d.target.y).length() <= B.radius + Data.BALANCE.player_radius
			if hit: d.progress += 1
			else: d.misses += 1
			w.events.append({ t = "bounceLand", x = d.target.x, z = d.target.y, hit = hit })
			if d.misses >= B.max_miss:
				return false
			if d.progress + d.misses >= B.count:
				return true
			d.from = d.target
			d.target = _landing(w, q, d.target)
			d.land = B.warn
			return null
		"hold":
			var H: Dictionary = Data.QUESTS.hold
			var inside: bool = Vector2(p.x - q.x, p.z - q.z).length() <= H.radius
			d.progress = maxf(0.0, d.progress + (dt if inside else -H.drain * dt))
			if d.progress >= H.need:
				return true
			if q.t > H.timeout:
				return false
			return null
		"crystal":
			if d.hp <= 0.0:
				return false
			if q.t >= Data.QUESTS.crystal.seconds:
				return true
			return null
		"thief":
			return _update_thief(w, q, dt)
	return null

static func _abort(w: World, q: State) -> void:
	if q.kind == "thief" and q.data.has("uid"):
		var i := w.enemies.index_of_uid(q.data.uid) if q.data.uid >= 0 else -1
		if i >= 0:
			w.enemies.kill(i)
		q.data.uid = -1

## edge-arrow target while active (thief), else the rune
static func arrow_target(w: World, q: State) -> Vector2:
	if q.phase == "active" and q.kind == "thief":
		var i := w.enemies.index_of_uid(q.data.uid)
		if i >= 0:
			return Vector2(w.enemies.x[i], w.enemies.z[i])
	return Vector2(q.x, q.z)

static func _landing(w: World, q: State, prev: Variant) -> Vector2:
	var B: Dictionary = Data.QUESTS.bounce
	for k in 30:
		var a := w.rng.next() * TAU
		var dd: float = sqrt(w.rng.next()) * B.roam
		var x: float = q.x + cos(a) * dd
		var z: float = q.z + sin(a) * dd
		if not w.grid.walkable_at(x, z):
			continue
		if prev != null and Vector2(x - prev.x, z - prev.y).length() < B.min_hop:
			continue
		return Vector2(x, z)
	return Vector2(q.x, q.z)

static func _spawn_thief(w: World, q: State) -> int:
	var sx := q.x
	var sz := q.z
	var hs: float = Data.QUESTS.thief.head_start
	for k in 40:
		var a := w.rng.next() * TAU
		var x := q.x + cos(a) * hs
		var z := q.z + sin(a) * hs
		if w.grid.walkable_at(x, z):
			sx = x
			sz = z
			break
	# full pool: drop the farthest normal enemy (no reward) so the thief always exists
	var e := w.enemies
	if e.count >= e.capacity:
		var far := -1
		var far_d := -1.0
		for j in e.count:
			if e.immovable(j):
				continue
			var dd := pow(e.x[j] - w.player.x, 2) + pow(e.z[j] - w.player.z, 2)
			if dd > far_d:
				far_d = dd
				far = j
		if far >= 0:
			e.kill(far)
	var i := e.spawn(Data.T_THIEF, sx, sz, Data.ENEMIES[Data.T_THIEF].hp * w.scale_at(w.zone_at(q.x, q.z)).hp)
	return e.uid[i] if i >= 0 else -1

static func _update_thief(w: World, q: State, dt: float) -> Variant:
	var e := w.enemies
	var p := w.player
	var g := w.grid
	var i := e.index_of_uid(q.data.uid)
	if i < 0:
		return true
	if q.t >= Data.QUESTS.thief.seconds:
		return false
	# flee uphill on the player's flow field: the neighbour cell farthest (walking) from the player
	var x := e.x[i]
	var z := e.z[i]
	var cx := int(floor(x / Grid.CELL))
	var cz := int(floor(z / Grid.CELL))
	var best := w.flow.dist[cz * g.w + cx]
	var tx := x + (x - p.x)
	var tz := z + (z - p.z)
	for dv in NEIGH:
		var nx := cx + dv.x
		var nz := cz + dv.y
		# never flee into the boss room / its doors
		if not g.walkable(nx, nz) or g.boss_room[nz * g.w + nx] == 1 or g.doors.has(nz * g.w + nx):
			continue
		if dv.x != 0 and dv.y != 0 and (not g.walkable(cx + dv.x, cz) or not g.walkable(cx, cz + dv.y)):
			continue
		var dd := w.flow.dist[nz * g.w + nx]
		if dd > best:
			best = dd
			tx = (nx + 0.5) * Grid.CELL
			tz = (nz + 0.5) * Grid.CELL
	var vx := tx - x
	var vz := tz - z
	var l := sqrt(vx * vx + vz * vz)
	if l < 1e-4:
		return null
	var step := minf(l, Data.ENEMIES[Data.T_THIEF].speed * dt)
	var res := Collision.resolve(g, x + (vx / l) * step, z + (vz / l) * step, Data.ENEMIES[Data.T_THIEF].radius)
	if g.in_boss_room(res.x, res.y):
		return null
	e.x[i] = res.x
	e.z[i] = res.y
	e.dir_x[i] = vx / l
	e.dir_z[i] = vz / l
	return null
