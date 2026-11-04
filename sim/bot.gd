class_name Bot
extends RefCounted
## port of scripts/sim/balance.sim.ts kite bot (also drives the in-game autoplay)

const MELEE_REACH := 2.5

var w: World
var do_quests: bool
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
	if Data.is_weapon(o.id):
		var has := w.build.has(Data.WEAPONS[o.id].paired)
		return (5.0 if o.type == "upgrade" else 3.0) + (2.0 if has else 0.0)
	var pairs := 0
	for id in Data.WEAPONS:
		if Data.WEAPONS[id].paired == o.id and w.build.has(id):
			pairs += 1
	return (4.0 if o.type == "new" else 1.5) + pairs * 2.0

func _route(gx: float, gz: float) -> Vector2:
	var p := w.player
	var cx := int(floor(gx / Grid.CELL))
	var cz := int(floor(gz / Grid.CELL))
	var k := cz * w.grid.w + cx
	if k != _route_key or _route_ff == null:
		_route_key = k
		_route_ff = FlowField.make(w.grid, cx, cz)
	var out := _route_ff.direction(w.grid, p.x, p.z)
	if out == Vector2.ZERO and w.grid.line_of_sight(p.x, p.z, gx, gz):
		var d := maxf(1e-6, Vector2(gx - p.x, gz - p.z).length())
		out = Vector2((gx - p.x) / d, (gz - p.z) / d)
	return out

## {x, z, r} or {} = no goal
func _quest_goal() -> Dictionary:
	var q := w.quest
	if q == null:
		return {}
	if q.phase == "waiting":
		return { x = q.x, z = q.z, r = 0.5 }
	match q.kind:
		"bounce": return { x = q.data.target.x, z = q.data.target.y, r = 1.2 }
		"hold": return { x = q.x, z = q.z, r = 2.4 }
		"crystal": return { x = q.x, z = q.z, r = 3.0 }
		"thief":
			var i := w.enemies.index_of_uid(q.data.uid)
			return { x = w.enemies.x[i], z = w.enemies.z[i], r = 0.0 } if i >= 0 else {}
	return {}

func input(t: float) -> Vector2:
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
		var d := sqrt(dx * dx + dz * dz)
		if d < zn.r + 1.5 and d > 1e-4:
			rx += (dx / d) * 0.8
			rz += (dz / d) * 0.8
	var threat := Vector2(rx, rz).length()

	var goal := _quest_goal() if do_quests else {}
	var gd0: float = Vector2(goal.x - p.x, goal.z - p.z).length() if not goal.is_empty() else 0.0
	if not goal.is_empty() and gd0 > goal.r:
		var r := _route(goal.x, goal.z)
		# no progress toward the goal for 1 s (pinned / jittering on a wall) → route only for 1.5 s
		if t - _prog.t >= 1.0:
			if _prog.d - gd0 < 1.0:
				_prog.until = t + 1.5
			_prog.t = t
			_prog.d = gd0
		var kk := 0.0 if t < _prog.until else (6.0 if threat > 0.35 else 1.5)
		return Vector2(r.x * 3.0 + rx * kk, r.y * 3.0 + rz * kk)

	# melee vs boss: close to sword reach, still dodging shots
	if w.boss != null:
		var bi := w.boss_index()
		if bi >= 0:
			var bx := e.x[bi]
			var bz := e.z[bi]
			if Vector2(bx - p.x, bz - p.z).length() > MELEE_REACH:
				var r := _route(bx, bz)
				return Vector2(r.x * 3.0 + rx * 2.0, r.y * 3.0 + rz * 2.0)

	# no quest: drift back toward the outer zone when nothing is chasing
	if do_quests and w.zone_at(p.x, p.z) > 0 and threat < 0.25 and w.boss == null:
		var r := _route(w.grid.start.x, w.grid.start.y)
		return Vector2(r.x * 2.0 + rx * 6.0, r.y * 2.0 + rz * 6.0)

	# loot: gems + pickups nearby
	var gx := 0.0
	var gz := 0.0
	var gd := 1e9
	for g in w.gems:
		var d := Vector2(g.x - p.x, g.z - p.z).length()
		if d < gd and d < 14.0:
			gd = d; gx = (g.x - p.x) / d; gz = (g.z - p.z) / d
	for it in w.pickups:
		var d := Vector2(it.x - p.x, it.z - p.z).length() / 2.0
		if d < gd and d < 14.0:
			gd = d; gx = (it.x - p.x) / (d * 2.0); gz = (it.z - p.z) / (d * 2.0)
	var ang: float = _stuck.dir + t * 0.25
	var lk := 2.5 if threat < 0.15 else 0.6
	var x := rx * 6.0 + gx * lk + cos(ang) * 0.4
	var z := rz * 6.0 + gz * lk + sin(ang) * 0.4
	if Vector2(p.x - _stuck.x, p.z - _stuck.z).length() < 0.02:
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
	return Vector2(x, z)

## SIM_SKILL: knight smashes when crowded
func want_skill() -> bool:
	var p := w.player
	var near := 0
	for i in w.enemies.count:
		if Vector2(w.enemies.x[i] - p.x, w.enemies.z[i] - p.z).length() < 5.0:
			near += 1
	return near >= 5
