class_name Collision
## circle vs blocked grid cells; result in rx / rz (float64: Vector2 would round to float32)

static var rx := 0.0
static var rz := 0.0

static func resolve(g: Grid, x: float, z: float, r: float) -> void:
	var px := x
	var pz := z
	var C := Grid.CELL
	# two passes settle corners where two blocked cells push in different directions
	for _pass in 2:
		var ccx := int(floor(px / C))
		var ccz := int(floor(pz / C))
		var span := int(ceil(r / C))
		for cz in range(ccz - span, ccz + span + 1):
			for cx in range(ccx - span, ccx + span + 1):
				if g.walkable(cx, cz):
					continue
				var min_x := cx * C
				var max_x := min_x + C
				var min_z := cz * C
				var max_z := min_z + C
				var nx := clampf(px, min_x, max_x)
				var nz := clampf(pz, min_z, max_z)
				var dx := px - nx
				var dz := pz - nz
				var d2 := dx * dx + dz * dz
				if d2 >= r * r:
					continue
				if d2 > 1e-12:
					var d := sqrt(d2)
					px = nx + (dx / d) * r
					pz = nz + (dz / d) * r
				else:
					# centre inside the block: push out along the shallowest axis
					var left := px - min_x
					var right := max_x - px
					var top := pz - min_z
					var bottom := max_z - pz
					var m := minf(minf(left, right), minf(top, bottom))
					if m == left: px = min_x - r
					elif m == right: px = max_x + r
					elif m == top: pz = min_z - r
					else: pz = max_z + r
	rx = px
	rz = pz
