extends WeaponRuntime
## lightning chains between enemies; hidden: storm strikes all over the screen

const STORM := { strikes = 10, damage_mul = 1.5 }
var timer := 0.0
func update(w: World, level: int, hidden: bool, dt: float) -> void:
	timer -= dt
	if timer > 0.0:
		return
	var L := Items.lv(id, level)
	var e := w.enemies
	var p := w.player
	var first := Enemies.nearest_visible(w, p.x, p.z, Data.RANGES.thunderSeal * w.mods.area_mul)
	if first < 0:
		return
	timer = L.cooldown * w.mods.cooldown_mul
	var damage: float = L.damage * w.mods.damage_mul
	var chain: Array[int] = [first]
	var in_chain := { first: true }
	var points := PackedVector2Array([Vector2(p.x, p.z), Vector2(e.x[first], e.z[first])])
	var area2: float = L.area * L.area
	while chain.size() < int(L.count):
		var from := chain[chain.size() - 1]
		var best := -1
		var best_d := area2
		for i in e.count:
			if in_chain.has(i):
				continue
			var d := pow(e.x[i] - e.x[from], 2) + pow(e.z[i] - e.z[from], 2)
			if d <= best_d and Enemies.can_reach(w, e.x[from], e.z[from], i):
				best_d = d
				best = i
		if best < 0:
			break
		chain.append(best)
		in_chain[best] = true
		points.append(Vector2(e.x[best], e.z[best]))
	w.events.append({ t = "bolt", points = points, big = false })
	var storm: Array[int] = []
	if hidden:
		var pool: Array[int] = []
		for i in e.count:
			if not in_chain.has(i) and Vec.hypot(e.x[i] - p.x, e.z[i] - p.z) <= Data.RANGES.sky and w.on_screen(e.x[i], e.z[i]):
				pool.append(i)
		while storm.size() < STORM.strikes and pool.size() > 0:
			var k := w.rng.rint(0, pool.size() - 1)
			storm.append(pool[k])
			pool[k] = pool[pool.size() - 1]
			pool.pop_back()
		for i in storm:
			w.events.append({ t = "bolt", points = PackedVector2Array([Vector2(e.x[i], e.z[i]), Vector2(e.x[i], e.z[i])]), big = true })
	# kills swap-remove: hitting in descending index order keeps every pending index valid
	var hits: Array = []
	for i in chain:
		hits.append([i, damage])
	for i in storm:
		hits.append([i, damage * STORM.damage_mul])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for h in hits:
		Enemies.damage(w, h[0], h[1])
