class_name DungeonView
extends Node3D
## floor / walls / pillars / torches / runes / boss doors from the grid (port of render/dungeonView.ts)
## pieces + colours come from the map theme's ThemeSkin; rebuilt when the map changes

const MAX_TORCH_LIGHTS := 8

var _doors: Node3D

func clear() -> void:
	for c in get_children():
		c.queue_free()

func build(g: Grid, th: ThemeSkin, spots: Array) -> void:
	var C := Grid.CELL
	var door_set := {}
	for i in g.doors:
		door_set[i] = true
	var open := func(cx: int, cz: int) -> bool:
		return g.walkable(cx, cz) or (cx >= 0 and cz >= 0 and cx < g.w and cz < g.h and door_set.has(cz * g.w + cx))
	var placements := {}
	var put := func(piece: String, x: float, y: float, z: float, rot_y := 0.0, s := Vector3.ONE) -> void:
		if not placements.has(piece):
			placements[piece] = []
		placements[piece].append(Transform3D(Basis(Vector3.UP, rot_y) * Basis.from_scale(s), Vector3(x, y, z)))
	var rng := Rng.new(1234)
	var torches: Array[Vector3] = []
	var door_xf: Array[Transform3D] = []
	for cz in g.h:
		for cx in g.w:
			var c := Grid.cell_center(cx, cz)
			var kind := g.cell_at(cx, cz)
			var is_door := door_set.has(cz * g.w + cx)
			if kind != Grid.WALL or is_door:
				put.call(th.floor_piece, c.x, 0.0, c.y)
			if is_door:
				var pass_z: bool = (g.walkable(cx, cz - 1) and not door_set.has((cz - 1) * g.w + cx)) or (g.walkable(cx, cz + 1) and not door_set.has((cz + 1) * g.w + cx))
				door_xf.append(Transform3D(Basis(Vector3.UP, 0.0 if pass_z else PI / 2), Vector3(c.x, 0, c.y)))
				continue
			if kind == Grid.PILLAR:
				put.call(th.pillar_piece, c.x, 0.0, c.y, 0.0, th.pillar_scale)
				put.call(th.prop_a, c.x + 1.4, 0.0, c.y + 1.3, rng.next() * 6.0)
				put.call(th.prop_b, c.x - 1.1, 0.0, c.y - 1.0, rng.next() * 6.0, Vector3(0.8, 0.8, 0.8))
				continue
			if kind != Grid.WALL:
				continue
			# wall faces toward each open neighbour
			var W := th.wall_piece
			if open.call(cx, cz + 1): put.call(W, c.x, 0.0, (cz + 1) * C - 0.5, 0.0)
			if open.call(cx, cz - 1): put.call(W, c.x, 0.0, cz * C + 0.5, PI, Vector3(1, th.near_wall_scale, 1))
			if open.call(cx + 1, cz): put.call(W, (cx + 1) * C - 0.5, 0.0, c.y, PI / 2)
			if open.call(cx - 1, cz): put.call(W, cx * C + 0.5, 0.0, c.y, -PI / 2)
			# torches on back walls (floor in front at +z), spaced out
			if g.walkable(cx, cz + 1) and not open.call(cx, cz) and (cx + cz) % 5 == 0:
				torches.append(Vector3(c.x, 0, (cz + 1) * C + 0.7))
	for t in torches:
		put.call(th.torch_piece, t.x, 0.4, t.z)

	for piece in placements:
		if piece == "":
			continue
		var scene := load(piece) as PackedScene
		if scene == null:
			push_error("theme %s: piece not found %s" % [th.id, piece])
			continue
		var src := Gfx.first_mesh(scene)
		var list: Array = placements[piece]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src.mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i] * src.xform)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if piece == th.floor_piece else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)

	# torch glow: a few real lights + a bloom flame on every torch
	var flames := Gfx.multi(Gfx.sphere(0.22, 6, 8), Gfx.glow_mat(th.torch_flame, Gfx.GLOW.torch), torches.size())
	for i in torches.size():
		flames.multimesh.set_instance_transform(i, Transform3D(Basis(), torches[i] + Vector3(0, 1.25, 0)))
	flames.multimesh.visible_instance_count = -1
	add_child(flames)
	var step := maxi(1, torches.size() / MAX_TORCH_LIGHTS)
	var n := 0
	var i := 0
	while i < torches.size() and n < MAX_TORCH_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = th.torch_lights[n % th.torch_lights.size()]
		l.light_energy = th.torch_energy
		l.omni_range = 22.0
		l.omni_attenuation = 1.5
		l.position = torches[i] + Vector3(0, 2.2, 0)
		add_child(l)
		i += step
		n += 1

	# floor runes
	var rune_ring := Gfx.ring_mesh(2.6, 3.0, 48)
	var rune_inner := Gfx.ring_mesh(1.4, 1.55, 6)
	var k := 0
	for s in spots:
		if not s.get("rune", false):
			continue
		var c := Grid.cell_center(s.cx, s.cz)
		var mat := Gfx.glow_mat(th.rune_colors[k % th.rune_colors.size()], Gfx.GLOW.rune, Gfx.GLOW.rune_opacity)
		for mesh in [rune_ring, rune_inner]:
			var m := MeshInstance3D.new()
			m.mesh = mesh
			m.material_override = mat
			m.position = Vector3(c.x, 0.13, c.y)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(m)
		k += 1

	# sealed boss doors: stone barrier + glowing seal
	_doors = Node3D.new()
	add_child(_doors)
	if door_xf.size() > 0 and th.barrier_piece != "":
		var src := Gfx.first_mesh(load(th.barrier_piece))
		var seal_mesh := Gfx.box(4, 2.6, 0.12)
		var seal_mat := Gfx.glow_mat(th.rune_colors[th.rune_colors.size() - 1], Gfx.GLOW.rune, 0.35)
		for xf in door_xf:
			var b := MeshInstance3D.new()
			b.mesh = src.mesh
			b.transform = xf * src.xform
			_doors.add_child(b)
			var s := MeshInstance3D.new()
			s.mesh = seal_mesh
			s.material_override = seal_mat
			s.transform = xf.translated_local(Vector3(0, 1.3, 0))
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_doors.add_child(s)

func set_doors(open: bool) -> void:
	_doors.visible = not open
