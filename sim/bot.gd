class_name Bot
extends RefCounted
## port of scripts/sim/balance.sim.ts kite bot (also drives the in-game autoplay)

const MELEE_REACH := 2.5

var w: World
var do_quests: bool
## dungeon: dive toward the boss room once the zone's budget is spent
var dungeon := false
var _route_key := -1
var _route_ff: FlowField
var _stuck := { x = 0.0, z = 0.0, n = 0, dir = 0.0 }
var _prog := { t = 0.0, d = 1e9, until = -1.0 }

func _init(world: World, quests_on: bool) -> void:
	w = world
	do_quests = quests_on

func pick(offers: Array[Dictionary]) -> int:
	var bi := 0
	for i in offers.size():
		if _score(offers[i]) > _score(offers[bi]):
			bi = i
	return bi

func _score(o: Dictionary) -> float:
	if o.type == "heal":
		return 0.0
	if Items.is_weapon(o.id):
		var has := w.build.has(Items.WEAPONS[o.id].paired)
		return (5.0 if o.type == "upgrade" else 3.0) + (2.0 if has else 0.0)
	var pairs := 0
	for id in Items.WEAPONS:
		if Items.WEAPONS[id].paired == o.id and w.build.has(id):
			pairs += 1
	return (4.0 if o.type == "new" else 1.5) + pairs * 2.0

## [x, z] walking direction to a goal (float64)
func _route(gx: float, gz: float) -> Array:
	var p := w.player
	var cx := int(floor(gx / Grid.CELL))
	var cz := int(floor(gz / Grid.CELL))
	var k := cz * w.grid.w + cx
	if k != _route_key or _route_ff == null:
		_route_key = k
		_route_ff = FlowField.make(w.grid, cx, cz)
	_route_ff.direction(w.grid, p.x, p.z)
	var out := [FlowField.ox, FlowField.oz]
	# same cell as the goal (or the field gives nothing): head straight for it
	if out[0] == 0.0 and out[1] == 0.0 and w.grid.line_of_sight(p.x, p.z, gx, gz):
		var d := Vec.hypot(gx - p.x, gz - p.z)
		if d == 0.0:
			d = 1.0
		out = [(gx - p.x) / d, (gz - p.z) / d]
	return out

## {x, z, r} or {} = no goal
func _quest_goal() -> Dictionary:
	var q := w.quest
	if q == null:
		return {}
	if q.phase == "waiting":
		return { x = q.x, z = q.z, r = 0.5 }
	match q.kind:
		"bounce": return { x = q.data.target.x, z = q.data.target.z, r = 1.2 }
		"hold": return { x = q.x, z = q.z, r = 2.4 }
		"crystal": return { x = q.x, z = q.z, r = 3.0 }
		"thief":
			var i := w.enemies.index_of_uid(q.data.uid)
			return { x = w.enemies.x[i], z = w.enemies.z[i], r = 0.0 } if i >= 0 else {}
	return {}

## [x, z] move input (float64 like the TS bot)
func input(t: float) -> Array:
	var p := w.player
	var e := w.enemies
	var rx := 0.0
	var rz := 0.0
	for i in e.count:
		var dx := p.x - e.x[i]
		var dz := p.z - e.z[i]
		var d2 := dx * dx + dz * dz
		if d2 < 100.0 and d2 > 1e-4:
			rx += dx / d2
			rz += dz / d2
	for s in w.hostile_shots:
		var dx: float = p.x - s.x
		var dz: float = p.z - s.z
		var d2 := dx * dx + dz * dz
		if d2 < 16.0 and d2 > 1e-4:
			rx += (dx / d2) * 2.0
			rz += (dz / d2) * 2.0
	for zn in w.hostile_zones:
		var dx: float = p.x - zn.x
		var dz: float = p.z - zn.z
		var d := Vec.hypot(dx, dz)
		if d < zn.r + 1.5 and d > 1e-4:
			rx += (dx / d) * 0.8
			rz += (dz / d) * 0.8
	var threat := Vec.hypot(rx, rz)

	var goal := _quest_goal() if do_quests else {}
	var gd0: float = Vec.hypot(goal.x - p.x, goal.z - p.z) if not goal.is_empty() else 0.0
	if not goal.is_empty() and gd0 > goal.r:
		var r: Array = _route(goal.x, goal.z)
		# no progress toward the goal for 1 s (pinned / jittering on a wall) → route only for 1.5 s
		if t - _prog.t >= 1.0:
			if _prog.d - gd0 < 1.0:
				_prog.until = t + 1.5
			_prog.t = t
			_prog.d = gd0
		var kk := 0.0 if t < _prog.until else (6.0 if threat > 0.35 else 1.5)
		return [r[0] * 3.0 + rx * kk, r[1] * 3.0 + rz * kk]

	# melee vs boss: close to sword reach, still dodging shots (kiting forever never lands a swing)
	if w.boss != null and w.hero.weapon == "holySword":
		var bi := w.boss_index()
		if bi >= 0:
			var bx := e.x[bi]
			var bz := e.z[bi]
			if Vec.hypot(bx - p.x, bz - p.z) > MELEE_REACH:
				var r: Array = _route(bx, bz)
				return [r[0] * 3.0 + rx * 2.0, r[1] * 3.0 + rz * 2.0]

	# dungeon: once this zone's budget is spent and the area is quiet, walk on toward the boss room
	if dungeon and w.boss == null and w.grid.has_boss_spawn:
		var near := 0
		for i in e.count:
			if Vec.hypot(e.x[i] - p.x, e.z[i] - p.z) < 10.0:
				near += 1
		var zb := w.zone_at(p.x, p.z)
		if not (zb < w.budget.size() and w.budget[zb] > 0) and near < 5:
			var r: Array = _route(w.grid.boss_spawn.x, w.grid.boss_spawn.y)
			return [r[0] * 3.0 + rx * 2.0, r[1] * 3.0 + rz * 2.0]

	# no quest: drift back toward the outer zone when nothing is chasing
	if not dungeon and do_quests and w.zone_at(p.x, p.z) > 0 and threat < 0.25 and w.boss == null:
		var r: Array = _route(w.grid.start.x, w.grid.start.y)
		return [r[0] * 2.0 + rx * 6.0, r[1] * 2.0 + rz * 6.0]

	# loot: gems + pickups nearby
	var gx := 0.0
	var gz := 0.0
	var gd := 1e9
	for g in w.gems:
		var d := Vec.hypot(g.x - p.x, g.z - p.z)
		if d < gd and d < 14.0:
			gd = d; gx = (g.x - p.x) / d; gz = (g.z - p.z) / d
	for it in w.pickups:
		var d := Vec.hypot(it.x - p.x, it.z - p.z) / 2.0
		if d < gd and d < 14.0:
			gd = d; gx = (it.x - p.x) / (d * 2.0); gz = (it.z - p.z) / (d * 2.0)
	var ang: float = _stuck.dir + t * 0.25
	var lk := 2.5 if threat < 0.15 else 0.6
	var x := rx * 6.0 + gx * lk + cos(ang) * 0.4
	var z := rz * 6.0 + gz * lk + sin(ang) * 0.4
	if Vec.hypot(p.x - _stuck.x, p.z - _stuck.z) < 0.02:
		_stuck.n += 1
		if _stuck.n > 15:
			_stuck.dir += 2.1
			_stuck.n = 0
	else:
		_stuck.n = 0
	_stuck.x = p.x
	_stuck.z = p.z
	if _stuck.n > 5:
		x = cos(_stuck.dir)
		z = sin(_stuck.dir)
	return [x, z]

## knight smashes when crowded or next to the boss, archer rolls when something is about to touch
func want_skill() -> bool:
	var p := w.player
	var e := w.enemies
	var near := 0
	var close := false
	for i in e.count:
		var d := Vec.hypot(e.x[i] - p.x, e.z[i] - p.z)
		if d < 5.0:
			near += 1
		if d < 2.2:
			close = true
	for s in w.hostile_shots:
		if Vec.hypot(s.x - p.x, s.z - p.z) < 2.0:
			close = true
	var bi := w.boss_index()
	var boss_near := bi >= 0 and Vec.hypot(e.x[bi] - p.x, e.z[bi] - p.z) < 4.5
	return near >= 5 or boss_near if w.hero.skill == "holyWrath" else close
