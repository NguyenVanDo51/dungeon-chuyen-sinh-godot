extends WeaponRuntime
## 120° arc in front (auto-aims at the nearest enemy); hidden: piercing sword waves

const HALF_ARC := PI / 3.0
const WAVE := { speed = 14.0, life = 1.2, radius = 1.2 }
var timer := 0.0
func update(w: World, level: int, hidden: bool, dt: float) -> void:
	timer -= dt
	if timer > 0.0:
		return
	var L := Items.lv(id, level)
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
		var d := Vec.hypot(dx, dz)
		if d > 1e-4:
			fx = dx / d
			fz = dz / d
	var damage: float = L.damage * w.mods.damage_mul
	var hits := 0
	for i in range(e.count - 1, -1, -1):
		var dx := e.x[i] - p.x
		var dz := e.z[i] - p.z
		var d := Vec.hypot(dx, dz)
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
