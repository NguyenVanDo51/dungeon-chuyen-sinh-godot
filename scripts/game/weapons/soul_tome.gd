extends WeaponRuntime
## beam that drains the nearest enemy and heals; hidden: black holes pull enemies + xp together

const HOLE := { every = 6.0, life = 2.5, radius = 5.0, pull = 6.0, tick = 0.5, damage = 10.0 }

var timer := 0.0
var hole_timer := 0.0

static func _update_vortices(w: World, dt: float) -> void:
	var e := w.enemies
	for k in range(w.vortices.size() - 1, -1, -1):
		var v := w.vortices[k]
		v.life -= dt
		v.tick -= dt
		var do_damage := v.tick <= 0.0
		if do_damage:
			v.tick = HOLE.tick
		for i in range(e.count - 1, -1, -1):
			if Vec.hypot(e.x[i] - v.x, e.z[i] - v.z) > v.r + e.radius(i) or not Enemies.can_reach(w, v.x, v.z, i):
				continue
			Enemies.pull_toward(w, i, v.x, v.z, HOLE.pull, dt)
			if do_damage:
				Enemies.damage(w, i, HOLE.damage * w.mods.damage_mul)
		for g in w.gems:
			var dx := v.x - g.x
			var dz := v.z - g.z
			var d := Vec.hypot(dx, dz)
			if d > v.r or d < 0.05:
				continue
			var step := minf(d, HOLE.pull * dt)
			g.x += (dx / d) * step
			g.z += (dz / d) * step
		if v.life <= 0.0:
			w.vortices[k] = w.vortices[w.vortices.size() - 1]
			w.vortices.pop_back()

func update(w: World, level: int, hidden: bool, dt: float) -> void:
	var L := Items.lv(id, level)
	var p := w.player
	var e := w.enemies
	if hidden:
		hole_timer -= dt
		if hole_timer <= 0.0:
			var t := Enemies.nearest_visible(w, p.x, p.z, Data.RANGES.sky)
			if t >= 0:
				hole_timer = HOLE.every * w.mods.cooldown_mul
				var v := World.Vortex.new()
				v.x = e.x[t]; v.z = e.z[t]; v.r = HOLE.radius * w.mods.area_mul; v.life = HOLE.life; v.tick = 0.0
				w.vortices.append(v)
	_update_vortices(w, dt)
	timer -= dt
	if timer > 0.0:
		return
	var t := Enemies.nearest_visible(w, p.x, p.z, Data.RANGES.soulTome * w.mods.area_mul)
	if t < 0:
		return
	timer = L.cooldown * w.mods.cooldown_mul
	w.events.append({ t = "beam", x0 = p.x, z0 = p.z, x1 = e.x[t], z1 = e.z[t] })
	Enemies.damage(w, t, L.damage * w.mods.damage_mul)
	w.heal(L.count)
