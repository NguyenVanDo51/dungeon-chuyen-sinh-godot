extends WeaponRuntime
## exploding ball at the nearest enemy; hidden: meteors keep falling on enemies

const BALL := { radius = 0.35, life = 2.0 }
const METEOR := { every = 1.5, delay = 0.6, radius = 3.0, damage = 60.0 }
var timer := 0.0
var meteor_timer := 0.0
func update(w: World, level: int, hidden: bool, dt: float) -> void:
	var L := Items.lv(id, level)
	var p := w.player
	if hidden:
		meteor_timer -= dt
		if meteor_timer <= 0.0:
			var t := Enemies.random_within(w, p.x, p.z, Data.RANGES.sky)
			if t >= 0:
				meteor_timer = METEOR.every * w.mods.cooldown_mul
				var m := Projectiles.make("meteor", w.enemies.x[t], w.enemies.z[t], 0.0, 0.0, METEOR.damage * w.mods.damage_mul, INF, 0.0, METEOR.delay)
				m.explode_radius = METEOR.radius * w.mods.area_mul
				m.delay = METEOR.delay
				w.projectiles.append(m)
				w.events.append({ t = "meteorWarn", x = m.x, z = m.z, radius = m.explode_radius, delay = m.delay })
	timer -= dt
	if timer > 0.0:
		return
	var t := Enemies.nearest_visible(w, p.x, p.z, Data.RANGES.fireball * w.mods.area_mul)
	if t < 0:
		return
	timer = L.cooldown * w.mods.cooldown_mul
	var base := atan2(w.enemies.z[t] - p.z, w.enemies.x[t] - p.x)
	var v: float = L.speed * w.mods.projectile_speed_mul
	var cnt := int(L.count)
	for k in cnt:
		var a := base + (k - (cnt - 1) / 2.0) * 0.25
		var b := Projectiles.make("fireball", p.x, p.z, cos(a) * v, sin(a) * v, L.damage * w.mods.damage_mul, 1.0, BALL.radius, BALL.life)
		b.explode_radius = L.area * w.mods.area_mul
		w.projectiles.append(b)
