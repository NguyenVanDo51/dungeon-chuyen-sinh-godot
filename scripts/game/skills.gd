class_name Skills
## active skills (port of game/skills/*); add one: a class here + an entry in Characters.SKILLS + create()

static func create(id: String) -> SkillRuntime:
	match id:
		"holyWrath": return HolyWrath.new()
		"roll": return Roll.new()
	push_error("unknown skill " + id)
	return SkillRuntime.new()

## knight: ground smash — damage + stun around, staggers the boss
class HolyWrath extends SkillRuntime:
	func radius(w: World) -> float:
		return Characters.HOLY_WRATH.radius * w.mods.area_mul

	func activate(w: World) -> bool:
		var H := Characters.HOLY_WRATH
		var p := w.player
		var e := w.enemies
		var r := radius(w)
		var dmg: float = H.damage * w.mods.damage_mul
		for i in range(e.count - 1, -1, -1):
			if Vec.hypot(e.x[i] - p.x, e.z[i] - p.z) > r + e.radius(i) or not Enemies.can_reach(w, p.x, p.z, i):
				continue
			if w.boss != null and w.boss.uid == e.uid[i]:
				w.boss.stagger = maxf(w.boss.stagger, H.stagger)
			# stun before damage: a kill swap-removes slot i
			Enemies.freeze(w, i, H.stun)
			Enemies.damage(w, i, dmg)
		return true

## archer: dash along facing (away from the nearest enemy when standing), brief i-frames
class Roll extends SkillRuntime:
	func activate(w: World) -> bool:
		var R := Characters.ROLL
		var p := w.player
		var e := w.enemies
		var dx := p.facing_x
		var dz := p.facing_z
		if not p.moving:
			var best := -1
			var best_d := INF
			for i in e.count:
				var d := Vec.hypot(e.x[i] - p.x, e.z[i] - p.z)
				if d < best_d:
					best_d = d
					best = i
			if best >= 0 and best_d > 1e-4:
				dx = (p.x - e.x[best]) / best_d
				dz = (p.z - e.z[best]) / best_d
		# sub-steps so the dash cannot tunnel through a wall
		var steps := int(ceil(R.distance / R.substep))
		var step: float = R.distance / steps
		for k in steps:
			Collision.resolve(w.grid, p.x + dx * step, p.z + dz * step, Data.BALANCE.player_radius)
			p.x = Collision.rx
			p.z = Collision.rz
		p.facing_x = dx
		p.facing_z = dz
		p.invuln = maxf(p.invuln, R.invuln)
		return true
