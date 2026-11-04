extends WeaponRuntime
## swords orbiting the player; hidden: twice the swords, every 3 s they dash into enemies and return

const HIT_RADIUS := 0.6
const DASH := { every = 3.0, speed = 20.0, max_time = 0.6 }

var angle := 0.0
var dash_timer: float = DASH.every
## per enemy uid: clock of the last hit (cooldown is per enemy for the whole weapon)
var last_hit := {}
var clock := 0.0

func _hit_around(w: World, x: float, z: float, damage: float, hit_cd: float) -> void:
	var e := w.enemies
	for i in range(e.count - 1, -1, -1):
		# a sword clipping into a wall must not cut the far side: the player needs a clear line to the target
		if Vec.hypot(e.x[i] - x, e.z[i] - z) > HIT_RADIUS + e.radius(i) or not Enemies.can_reach(w, w.player.x, w.player.z, i):
			continue
		var u := e.uid[i]
		if clock - last_hit.get(u, -INF) < hit_cd:
			continue
		last_hit[u] = clock
		Enemies.damage(w, i, damage)

func update(w: World, level: int, hidden: bool, dt: float) -> void:
	clock += dt
	var L := Items.lv(id, level)
	var n := int(L.count) * (2 if hidden else 1)
	while visuals.size() < n:
		visuals.append({ x = w.player.x, z = w.player.z, angle = 0.0, dashing = false, mode = "orbit", tx = 0.0, tz = 0.0, t = 0.0 })
	visuals.resize(n)
	angle += L.speed * w.mods.projectile_speed_mul * dt
	var damage: float = L.damage * w.mods.damage_mul
	var hit_cd: float = L.cooldown

	if hidden:
		dash_timer -= dt
		if dash_timer <= 0.0:
			dash_timer = DASH.every * w.mods.cooldown_mul
			var cand := Enemies.visible_within(w, w.player.x, w.player.z, Data.RANGES.flyingSwordsDash * w.mods.area_mul)
			var taken := {}
			for s in visuals:
				# each sword takes the nearest enemy to itself, preferring one no other sword took
				var best := -1
				var best_d := INF
				var best_free := false
				for i in cand:
					var free := not taken.has(i)
					var d := Vec.hypot(w.enemies.x[i] - s.x, w.enemies.z[i] - s.z)
					if (free and not best_free) or (free == best_free and d < best_d):
						best = i
						best_d = d
						best_free = free
				if best < 0:
					break
				taken[best] = true
				s.mode = "dash"; s.tx = w.enemies.x[best]; s.tz = w.enemies.z[best]; s.t = 0.0

	var p := w.player
	for k in visuals.size():
		var s: Dictionary = visuals[k]
		var a := angle + (TAU * k) / n
		var orbit: float = L.area * w.mods.area_mul
		var ox := p.x + cos(a) * orbit
		var oz := p.z + sin(a) * orbit
		if s.mode == "orbit":
			s.x = ox; s.z = oz; s.angle = a + PI / 2.0
		else:
			var tx: float = s.tx if s.mode == "dash" else ox
			var tz: float = s.tz if s.mode == "dash" else oz
			var dx: float = tx - s.x
			var dz: float = tz - s.z
			var d := Vec.hypot(dx, dz)
			var step: float = DASH.speed * w.mods.projectile_speed_mul * dt
			s.t += dt
			if d <= step:
				s.x = tx; s.z = tz
			else:
				s.x += (dx / d) * step; s.z += (dz / d) * step; s.angle = atan2(dz, dx)
			if s.mode == "dash" and (d <= step or s.t > DASH.max_time):
				s.mode = "return"
			elif s.mode == "return" and d <= step:
				s.mode = "orbit"
		s.dashing = s.mode != "orbit"
		_hit_around(w, s.x, s.z, damage, hit_cd)

	if last_hit.size() > 2000:
		for u in last_hit.keys():
			if clock - last_hit[u] > 2.0:
				last_hit.erase(u)
