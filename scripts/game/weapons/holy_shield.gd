extends WeaponRuntime
## pulse that damages + knocks back; reflects contact damage; hidden: a holy wave on every hit taken

const REFLECT := 0.9
const HOLY := { radius = 6.0, damage = 40.0, push = 4.0, invuln = 0.5, cooldown = 0.8 }

var timer := 0.0
var holy_cd := 0.0

static func _pulse(w: World, radius: float, damage: float, push: float) -> void:
	var e := w.enemies
	var p := w.player
	for i in range(e.count - 1, -1, -1):
		if Vec.hypot(e.x[i] - p.x, e.z[i] - p.z) > radius + e.radius(i) or not Enemies.can_reach(w, p.x, p.z, i):
			continue
		Enemies.knockback(w, i, p.x, p.z, push)
		Enemies.damage(w, i, damage)

func update(w: World, level: int, hidden: bool, dt: float) -> void:
	var L := Items.lv(id, level)
	var p := w.player
	var m := w.mods
	holy_cd -= dt
	if w.hurt_this_tick:
		var i := w.enemies.index_of_uid(w.last_hurt_by) if w.last_hurt_by >= 0 else -1
		if i >= 0:
			Enemies.damage(w, i, L.damage * REFLECT * m.damage_mul)
		if hidden and holy_cd <= 0.0:
			holy_cd = HOLY.cooldown
			var r: float = HOLY.radius * m.area_mul
			_pulse(w, r, HOLY.damage * m.damage_mul, HOLY.push)
			p.invuln += HOLY.invuln
			w.events.append({ t = "shieldPulse", x = p.x, z = p.z, radius = r, holy = true })
	timer -= dt
	if timer > 0.0:
		return
	timer = L.cooldown * m.cooldown_mul
	var r: float = L.area * m.area_mul
	_pulse(w, r, L.damage * m.damage_mul, L.speed)
	w.events.append({ t = "shieldPulse", x = p.x, z = p.z, radius = r, holy = false })
