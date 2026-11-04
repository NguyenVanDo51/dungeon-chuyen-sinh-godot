class_name Zones
## n bands by walking distance from start (0 = nearest); boss-room / unreachable cells join the deepest band

static func compute(g: Grid, n: int) -> PackedByteArray:
	var zones := PackedByteArray()
	zones.resize(g.w * g.h)
	if n <= 1:
		return zones
	var s := Vector2i(int(floor(g.start.x / Grid.CELL)), int(floor(g.start.y / Grid.CELL)))
	var dist := FlowField.make(g, s.x, s.y).dist
	var reach: Array[int] = []
	for i in dist.size():
		if dist[i] >= 0 and g.boss_room[i] == 0:
			reach.append(dist[i])
	reach.sort()
	var cut: Array[int] = []
	for k in n - 1:
		cut.append(reach[int(floor(float(reach.size() * (k + 1)) / n))])
	for i in zones.size():
		var d := dist[i]
		if d < 0 or g.boss_room[i] == 1:
			zones[i] = n - 1
			continue
		var z := 0
		while z < cut.size() and d >= cut[z]:
			z += 1
		zones[i] = z
	return zones
