class_name Vfx
extends Node3D
## projectiles, gems, coins, swords, sparks, bolts, beams, frost, vortices, boss shots / zones,
## one-shot rings, quest props, pickups, arrow rain. Colours: the style's FxSkin.

const FROST := preload("res://scripts/game/weapons/frost_ring.gd")
const DUST_PER_POINT := 10
const SEGS := 700
const SPARKS := 300
const BALL_HEIGHT := 5.0

var shake_req := 0.0
var fx_skin: FxSkin
var arrows: MultiMeshInstance3D
var coins: MultiMeshInstance3D
var swords: MultiMeshInstance3D
var sword_glow: MultiMeshInstance3D
var beams: MultiMeshInstance3D
var vortex_rings: MultiMeshInstance3D
var vortex_core: MultiMeshInstance3D
var rain_mesh: MultiMeshInstance3D
var balls: MultiMeshInstance3D
var waves: MultiMeshInstance3D
var warns: MultiMeshInstance3D
var meteors: MultiMeshInstance3D
var gems: MultiMeshInstance3D
var bolts: MultiMeshInstance3D
var ice_dust: MultiMeshInstance3D
var boss_shots: MultiMeshInstance3D
var zones: MultiMeshInstance3D
var zone_fill: MultiMeshInstance3D
var spark_mesh: MultiMeshInstance3D
var pickup_mesh := {}
var frost_aura: MeshInstance3D
var aura: MeshInstance3D
# quest props
var rune_fill: MeshInstance3D
var hold_fill: MeshInstance3D
var landing: MeshInstance3D
var landing_edge: MeshInstance3D
var ball: MeshInstance3D
var crystal: MeshInstance3D
var crystal_mat: StandardMaterial3D

var _segs: Array = []  # [a: Vector3, b: Vector3, life, beam]
var _rain: Array = []  # [x, z, t, fall]
var _sparks: Array = []  # [pos: Vector3, vel: Vector3, life]
var _fx: Array = []  # {mesh, t, life, kind, r}
var _slash_mesh: ArrayMesh
var _ring_mesh: ArrayMesh

func build(f: FxSkin) -> void:
	fx_skin = f
	arrows = _m(Gfx.box(1.1, 0.12, 0.12), Gfx.glow_mat(f.arrow, Gfx.GLOW.arrow), 400)
	balls = _m(Gfx.sphere(0.38, 8, 12), Gfx.glow_mat(f.fireball, Gfx.GLOW.fireball), 100)
	waves = _m(Gfx.ring_mesh(0.9, 1.35, 24, -PI * 0.4, PI * 0.8), Gfx.glow_mat(f.primary, Gfx.GLOW.sword_wave, 0.8), 60)
	var warn_ring := Gfx.ring_mesh(0.85, 1.0, 40)
	warns = _m(warn_ring, Gfx.glow_mat(f.danger, Gfx.GLOW.meteor_warn, 0.85), 40)
	var ico := SphereMesh.new()
	ico.radius = 0.8; ico.height = 1.6; ico.rings = 3; ico.radial_segments = 5
	meteors = _m(ico, Gfx.glow_mat(f.meteor, Gfx.GLOW.meteor), 40)
	gems = _m(Gfx.sphere(0.2, 8, 12), Gfx.glow_mat(f.xp_gem, Gfx.GLOW.gem), 500)
	# standing disc so the spin reads as a coin
	var coin := CylinderMesh.new()
	coin.top_radius = 0.24; coin.bottom_radius = 0.24; coin.height = 0.06; coin.radial_segments = 18
	coins = _m(coin, Gfx.glow_mat(f.gold, Gfx.GLOW.gem), 200)
	var blade: Mesh = Gfx.box(1.1, 0.05, 0.16)
	var blade_xf := Transform3D.IDENTITY
	var blade_mat: Material = Gfx.glow_mat(f.secondary, 1.0)
	if f.sword_model != "" and load(f.sword_model) is PackedScene:
		var src := Gfx.first_mesh(load(f.sword_model))
		blade = src.mesh
		# the prop stands along +Y: lay it along +X like the orbit tangent
		blade_xf = Transform3D(Basis(Vector3.BACK, -PI / 2).scaled(Vector3.ONE * 1.1), Vector3.ZERO) * src.xform
		blade_mat = null
	swords = _m(blade, blade_mat, 16)
	swords.set_meta("xf", blade_xf)
	sword_glow = _m(Gfx.box(1.6, 0.06, 0.3), Gfx.glow_mat(f.secondary, Gfx.GLOW.sword_glow, Gfx.GLOW.sword_glow_opacity), 16)
	bolts = _m(Gfx.box(1, 0.09, 0.09), Gfx.glow_mat(f.secondary, Gfx.GLOW.bolt), SEGS)
	beams = _m(Gfx.box(1, 0.14, 0.14), Gfx.glow_mat(f.soul, Gfx.GLOW.beam, 0.85), 40)
	vortex_rings = _m(Gfx.ring_mesh(0.75, 1.0, 40, 0.0, PI * 1.5), Gfx.glow_mat(f.soul, Gfx.GLOW.vortex, 0.8), 16)
	vortex_core = _m(Gfx.disc_mesh(1.0, 32), Gfx.glow_mat(Color("#070414"), 1.0, 0.7), 8)
	rain_mesh = _m(Gfx.box(0.08, 1.0, 0.08), Gfx.glow_mat(f.arrow, Gfx.GLOW.arrow), 160)
	ice_dust = _m(Gfx.octahedron(0.1), Gfx.glow_mat(f.frost, Gfx.GLOW.ice_shard), 120 * DUST_PER_POINT)
	boss_shots = _m(Gfx.sphere(0.4, 6, 10), Gfx.glow_mat(f.soul, Gfx.GLOW.boss_shot), 400)
	zones = _m(warn_ring, Gfx.glow_mat(f.boss_zone, Gfx.GLOW.zone, 0.85), 40)
	zone_fill = _m(Gfx.disc_mesh(1.0, 40), Gfx.glow_mat(f.boss_zone, 0.6, 0.18), 40)
	spark_mesh = _m(Gfx.sphere(0.08, 3, 4), Gfx.glow_mat(f.primary, Gfx.GLOW.spark), SPARKS)
	var pmesh := { heal = Gfx.octahedron(0.38), magnet = _torus(0.3, 0.11), freeze = Gfx.sphere(0.36, 3, 5), invuln = Gfx.box(0.45, 0.45, 0.45) }
	var pcol := { heal = f.pickup_heal, magnet = f.pickup_magnet, freeze = f.pickup_freeze, invuln = f.pickup_invuln }
	for k in pmesh:
		pickup_mesh[k] = _m(pmesh[k], Gfx.glow_mat(pcol[k], 1.3), Data.PICKUPS.max)
	# flat, very transparent disc (playtest: gradient/rim looked off)
	frost_aura = _one(Gfx.disc_mesh(1.0, 64), Gfx.glow_mat(f.frost, Gfx.GLOW.frost, Gfx.GLOW.frost_aura_opacity))
	aura = _one(Gfx.ring_mesh(1.15, 1.25, 64), Gfx.glow_mat(f.gold, 1.1, 0.55, true))
	# quest spots sit on the floor runes: fill only, always visible over the crowd
	rune_fill = _one(Gfx.disc_mesh(1.0), Gfx.glow_mat(f.secondary, 0.8, 0.12, true))
	hold_fill = _one(Gfx.disc_mesh(1.0), Gfx.glow_mat(f.gold, 0.9, 0.22, true))
	landing = _one(Gfx.disc_mesh(1.0), Gfx.glow_mat(f.primary, 1.0, 0.25, true))
	landing_edge = _one(Gfx.ring_mesh(0.92, 1.0, 64), Gfx.glow_mat(f.primary, 1.2, 0.8, true))
	ball = _one(Gfx.sphere(0.55, 14, 20), Gfx.glow_mat(f.primary, 1.3))
	crystal_mat = Gfx.glow_mat(f.secondary, 1.2)
	crystal = _one(Gfx.octahedron(1.1), crystal_mat)
	_slash_mesh = Gfx.ring_mesh(0.35, 1.0, 32, -PI / 3, TAU / 3)
	_ring_mesh = Gfx.ring_mesh(0.8, 1.0, 48)

func _m(mesh: Mesh, mat: Variant, cap: int) -> MultiMeshInstance3D:
	var mi := Gfx.multi(mesh, mat, cap)
	add_child(mi)
	return mi

func _one(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

static func _torus(r: float, tube: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - tube
	t.outer_radius = r + tube
	t.rings = 20
	t.ring_segments = 8
	return t

func reset() -> void:
	_segs.clear()
	_rain.clear()
	_sparks.clear()
	for fx in _fx:
		fx.t = fx.life
		fx.mesh.visible = false

func _spawn_fx(kind: String, color: Color, k: float, life: float) -> Dictionary:
	var fx: Dictionary = {}
	for f in _fx:
		if f.t >= f.life and f.kind == kind:
			fx = f
			break
	if fx.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = _slash_mesh if kind == "slash" else _ring_mesh
		mi.material_override = Gfx.glow_mat(color, k, 0.99)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		fx = { mesh = mi, t = 0.0, life = life, kind = kind, r = 1.0 }
		_fx.append(fx)
	var mat: StandardMaterial3D = fx.mesh.material_override
	mat.albedo_color = Color(color.r * k, color.g * k, color.b * k, 1.0)
	fx.t = 0.0
	fx.life = life
	fx.mesh.visible = true
	return fx

func _add_seg(a: Vector3, b: Vector3, life: float, beam := false) -> void:
	if _segs.size() < SEGS:
		_segs.append([a, b, life, beam])

func _jagged(a: Vector2, b: Vector2, y: float) -> void:
	var n := 4
	var p := a
	for k in range(1, n + 1):
		var t := float(k) / n
		var j := Vector2(randf() - 0.5, randf() - 0.5) * 0.9 if k < n else Vector2.ZERO
		var q := a + (b - a) * t + j
		_add_seg(Vector3(p.x, y, p.y), Vector3(q.x, y, q.y), 0.15)
		p = q

func unlock_burst(x: float, z: float) -> void:
	for k in 3:
		var fx := _spawn_fx("unlock", fx_skin.gold, Gfx.GLOW.unlock - k * 0.3, 0.6 + k * 0.2)
		fx.r = 5.0 + k * 2.5
		fx.mesh.position = Vector3(x, 0.3, z)
	shake_req += 0.5

func on_event(ev: Dictionary) -> void:
	match ev.t:
		"slash":
			var fx := _spawn_fx("slash", fx_skin.gold if ev.hidden else fx_skin.primary, Gfx.GLOW.slash, 0.18)
			fx.r = ev.radius
			fx.mesh.position = Vector3(ev.x, 0.9, ev.z)
			fx.mesh.rotation = Vector3(0, atan2(ev.dir_x, ev.dir_z) - PI / 2, 0)
		"explode":
			var col := fx_skin.meteor if ev.kind == "meteor" else (fx_skin.boss_zone if ev.kind == "nova" else fx_skin.fire_burst)
			var fx := _spawn_fx("explode", col, Gfx.GLOW.explode, 0.35)
			fx.r = ev.radius
			fx.mesh.position = Vector3(ev.x, 0.2, ev.z)
			if ev.kind == "meteor":
				shake_req += 0.35
		"bolt":
			var p: PackedVector2Array = ev.points
			if ev.big:
				var x := p[0].x
				var z := p[0].y
				var mid := Vector3(x + (randf() - 0.5) * 0.6, 3.5, z)
				_add_seg(Vector3(x, 7, z), mid, 0.14)
				_add_seg(mid, Vector3(x, 0.2, z), 0.14)
			else:
				for k in p.size() - 1:
					_jagged(p[k], p[k + 1], 1.0)
		"beam":
			_add_seg(Vector3(ev.x0, 1.1, ev.z0), Vector3(ev.x1, 0.9, ev.z1), 0.12, true)
		"shieldPulse":
			var fx := _spawn_fx("explode", fx_skin.gold, Gfx.GLOW.shield * (1.4 if ev.holy else 1.0), 0.45 if ev.holy else 0.3)
			fx.r = ev.radius
			fx.mesh.position = Vector3(ev.x, 0.4, ev.z)
		"arrowRain":
			for a in ev.arrows:
				if _rain.size() < 160:
					_rain.append([a.x, a.y, ev.fall - a.z, ev.fall])
		"skill":
			if ev.id == "roll":
				# dust puff where the roll started
				for k in 8:
					if _sparks.size() >= SPARKS:
						break
					var a := randf() * TAU
					_sparks.append([Vector3(ev.x, 0.2, ev.z), Vector3(cos(a) * 2.5, 1.0 + randf(), sin(a) * 2.5), 0.35])
			else:
				var fx := _spawn_fx("explode", fx_skin.gold, Gfx.GLOW.shield, 0.4)
				fx.r = ev.r if ev.r > 0.0 else 5.0
				fx.mesh.position = Vector3(ev.x, 0.2, ev.z)
				shake_req += 0.3
		"kill":
			for k in 6:
				if _sparks.size() >= SPARKS:
					break
				var a := randf() * TAU
				_sparks.append([Vector3(ev.x, 0.6, ev.z), Vector3(cos(a) * 4.0, 3.0 + randf() * 3.0, sin(a) * 4.0), 0.45])

func _xf(pos: Vector3, yaw := 0.0, s := 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)

func update(w: World, dt: float, time: float) -> void:
	# projectiles
	var na := 0
	var nb := 0
	var nw := 0
	var nwarn := 0
	for p in w.projectiles:
		var yaw := -atan2(p.vz, p.vx)
		if p.kind == "arrow" and na < 400:
			arrows.multimesh.set_instance_transform(na, _xf(Vector3(p.x, 0.9, p.z), yaw))
			na += 1
		elif p.kind == "fireball" and nb < 100:
			balls.multimesh.set_instance_transform(nb, _xf(Vector3(p.x, 0.9, p.z), 0.0, 1.0 + 0.15 * sin(time * 30.0)))
			nb += 1
		elif p.kind == "swordWave" and nw < 60:
			waves.multimesh.set_instance_transform(nw, _xf(Vector3(p.x, 0.7, p.z), yaw, 1.6))
			nw += 1
		elif p.kind == "meteor" and nwarn < 40:
			var k := 1.0 - maxf(0.0, p.delay) / 0.6
			warns.multimesh.set_instance_transform(nwarn, _xf(Vector3(p.x, 0.14, p.z), 0.0, p.explode_radius))
			meteors.multimesh.set_instance_transform(nwarn, _xf(Vector3(p.x, 0.5 + (1.0 - k) * 14.0, p.z)))
			nwarn += 1
	arrows.multimesh.visible_instance_count = na
	balls.multimesh.visible_instance_count = nb
	waves.multimesh.visible_instance_count = nw
	warns.multimesh.visible_instance_count = nwarn
	meteors.multimesh.visible_instance_count = nwarn

	var ng := 0
	for g in w.gems:
		if ng >= 500:
			break
		gems.multimesh.set_instance_transform(ng, _xf(Vector3(g.x, 0.45 + 0.1 * sin(time * 4.0 + g.z), g.z), time * 3.0 + g.x, minf(2.2, 0.9 + g.value * 0.08)))
		ng += 1
	gems.multimesh.visible_instance_count = ng
	var nc := 0
	for c in w.coins:
		if nc >= 200:
			break
		coins.multimesh.set_instance_transform(nc, Transform3D(Basis(Vector3.UP, time * 4.0 + c.x) * Basis(Vector3.RIGHT, PI / 2), Vector3(c.x, 0.5 + 0.08 * sin(time * 4.0 + c.z), c.z)))
		nc += 1
	coins.multimesh.visible_instance_count = nc

	# orbiting swords
	var ns := 0
	var bxf: Transform3D = swords.get_meta("xf")
	if w.weapons.has("flyingSwords"):
		for sw in w.weapons.flyingSwords.visuals:
			var xf := Transform3D(Basis(Vector3.UP, -sw.angle), Vector3(sw.x, 1.0, sw.z))
			swords.multimesh.set_instance_transform(ns, xf * bxf)
			sword_glow.multimesh.set_instance_transform(ns, xf)
			ns += 1
	swords.multimesh.visible_instance_count = ns
	sword_glow.multimesh.visible_instance_count = ns

	# arrow rain: falling streaks, landing when the damage does
	var nr := 0
	for k in range(_rain.size() - 1, -1, -1):
		var r: Array = _rain[k]
		r[2] += dt
		if r[2] > r[3]:
			_rain[k] = _rain[_rain.size() - 1]
			_rain.pop_back()
			continue
		if r[2] < 0.0:
			continue
		rain_mesh.multimesh.set_instance_transform(nr, Transform3D(Basis(), Vector3(r[0], 8.0 * (1.0 - r[2] / r[3]) + 0.5, r[1])))
		nr += 1
	rain_mesh.multimesh.visible_instance_count = nr

	# soul tome black holes
	var nvr := 0
	var nvc := 0
	for v in w.vortices:
		for k in 2:
			if nvr < 16:
				vortex_rings.multimesh.set_instance_transform(nvr, _xf(Vector3(v.x, 0.16 + k * 0.03, v.z), (-1.0 if k else 1.0) * time * 5.0 + k, v.r * (0.6 if k else 1.0)))
				nvr += 1
		if nvc < 8:
			vortex_core.multimesh.set_instance_transform(nvc, _xf(Vector3(v.x, 0.12, v.z), 0.0, v.r * 0.45))
			nvc += 1
	vortex_rings.multimesh.visible_instance_count = nvr
	vortex_core.multimesh.visible_instance_count = nvc

	# sparks
	for k in range(_sparks.size() - 1, -1, -1):
		var s: Array = _sparks[k]
		s[2] -= dt
		s[1].y -= 18.0 * dt
		s[0] += s[1] * dt
		s[0].y = maxf(0.05, s[0].y)
		if s[2] <= 0.0:
			_sparks[k] = _sparks[_sparks.size() - 1]
			_sparks.pop_back()
	for k in _sparks.size():
		spark_mesh.multimesh.set_instance_transform(k, _xf(_sparks[k][0], 0.0, maxf(0.2, _sparks[k][2] * 2.2)))
	spark_mesh.multimesh.visible_instance_count = _sparks.size()

	# lightning + soul beam segments: unit box along +X stretched between the two points
	var nbolt := 0
	var nbeam := 0
	for k in range(_segs.size() - 1, -1, -1):
		var s: Array = _segs[k]
		s[2] -= dt
		if s[2] <= 0.0:
			_segs[k] = _segs[_segs.size() - 1]
			_segs.pop_back()
			continue
		var d: Vector3 = s[1] - s[0]
		var l := d.length()
		if l < 1e-4:
			continue
		var x := d / l
		var up := Vector3.UP if absf(x.y) < 0.99 else Vector3.FORWARD
		var zz := x.cross(up).normalized()
		var yy := zz.cross(x)
		var sxf := Transform3D(Basis(x * l, yy, zz), (s[0] + s[1]) / 2.0)
		if s[3]:
			if nbeam < 40:
				beams.multimesh.set_instance_transform(nbeam, sxf)
				nbeam += 1
		else:
			bolts.multimesh.set_instance_transform(nbolt, sxf)
			nbolt += 1
	bolts.multimesh.visible_instance_count = nbolt
	beams.multimesh.visible_instance_count = nbeam

	# frost aura follows the player
	var fr := w.build.level_of("frostRing")
	frost_aura.visible = fr > 0
	if fr > 0:
		frost_aura.position = Vector3(w.player.x, 0.12, w.player.z)
		frost_aura.scale = Vector3.ONE * Items.lv("frostRing", fr).area * w.mods.area_mul

	# Vệt Băng: twinkling frost dust over each trail point (stable pseudo-random layout per point)
	var nd := 0
	var tr: float = FROST.TRAIL.radius * w.mods.area_mul
	for tm in w.frost_trail:
		var t := Vector3(tm[0], tm[1], tm[2])
		var kk: float = minf(1.0, t.z / FROST.TRAIL.life)
		var sd := t.x * 7.1 + t.y * 3.3
		for s in DUST_PER_POINT:
			if nd >= 120 * DUST_PER_POINT:
				break
			var h1 := fmod(absf(sin(sd * 12.9898 + s * 78.233)) * 43758.5453, 1.0)
			var h2 := fmod(absf(sin(sd * 39.346 + s * 11.135)) * 24634.6345, 1.0)
			var a := h1 * TAU
			var r := sqrt(h2) * tr
			var tw := 0.55 + 0.45 * sin(time * 7.0 + s * 1.9 + t.x)
			ice_dust.multimesh.set_instance_transform(nd, _xf(Vector3(t.x + cos(a) * r, 0.15 + h2 * 0.35 + (1.0 - kk) * 0.5, t.y + sin(a) * r), time * 2.0 + s, (0.6 + h1 * 0.8) * tw * (0.35 + 0.65 * kk)))
			nd += 1
	ice_dust.multimesh.visible_instance_count = nd

	# boss attacks
	var nsh := 0
	for s in w.hostile_shots:
		if nsh >= 400:
			break
		boss_shots.multimesh.set_instance_transform(nsh, _xf(Vector3(s.x, 1.0, s.z), 0.0, s.r / 0.4))
		nsh += 1
	boss_shots.multimesh.visible_instance_count = nsh
	var nz := 0
	for zn in w.hostile_zones:
		if nz >= 40:
			break
		var k := clampf(zn.delay / 1.2, 0.0, 1.0)
		zones.multimesh.set_instance_transform(nz, _xf(Vector3(zn.x, 0.15, zn.z), 0.0, zn.r * (0.35 + 0.65 * k)))
		zone_fill.multimesh.set_instance_transform(nz, _xf(Vector3(zn.x, 0.12, zn.z), 0.0, zn.r))
		nz += 1
	zones.multimesh.visible_instance_count = nz
	zone_fill.multimesh.visible_instance_count = nz

	# one-shots
	for fx in _fx:
		if fx.t >= fx.life:
			fx.mesh.visible = false
			continue
		fx.t += dt
		var k := minf(1.0, fx.t / fx.life)
		var mat: StandardMaterial3D = fx.mesh.material_override
		mat.albedo_color.a = 1.0 - k
		var s: float = fx.r * (0.85 + 0.15 * k) if fx.kind == "slash" else fx.r * (0.3 + 0.7 * k)
		fx.mesh.scale = Vector3.ONE * s

	_update_quest(w, time)
	aura.visible = w.invuln_buff > 0.0
	if aura.visible:
		aura.position = Vector3(w.player.x, 0.16, w.player.z)
		aura.scale = Vector3.ONE * (1.0 + 0.06 * sin(time * 8.0))
	var counts := { heal = 0, magnet = 0, freeze = 0, invuln = 0 }
	for p in w.pickups:
		var mm: MultiMesh = pickup_mesh[p.kind].multimesh
		var k: int = counts[p.kind]
		counts[p.kind] = k + 1
		# blink in the last 4 s before it vanishes
		var hide := p.life < 4.0 and int(floor(p.life * 6.0)) % 2 == 0
		mm.set_instance_transform(k, Transform3D(Basis.from_euler(Vector3(0.4, time * 2.0, 0)).scaled(Vector3.ONE * (0.0001 if hide else 1.0)), Vector3(p.x, 0.6 + 0.15 * sin(time * 3.0 + p.x), p.z)))
	for k in pickup_mesh:
		pickup_mesh[k].multimesh.visible_instance_count = counts[k]

func _place(m: MeshInstance3D, x: float, z: float, r: float, y: float) -> void:
	m.visible = true
	m.position = Vector3(x, y, z)
	m.scale = Vector3.ONE * r

func _update_quest(w: World, time: float) -> void:
	for o in [rune_fill, hold_fill, landing, landing_edge, ball, crystal]:
		o.visible = false
	var q := w.quest
	if q == null:
		return
	var pulse := 0.85 + 0.15 * sin(time * 5.0)
	(rune_fill.material_override as StandardMaterial3D).albedo_color.a = 0.1 + 0.14 * pulse if q.phase == "waiting" else 0.1
	if q.phase == "waiting":
		_place(rune_fill, q.x, q.z, Data.QUESTS.trigger_radius, 0.13)
		return
	var d := q.data
	match q.kind:
		"hold":
			_place(rune_fill, q.x, q.z, Data.QUESTS.hold.radius, 0.13)
			_place(hold_fill, q.x, q.z, maxf(0.01, Data.QUESTS.hold.radius * (d.progress / Data.QUESTS.hold.need)), 0.15)
		"bounce":
			var u: float = 1.0 - maxf(0.0, d.land) / Data.QUESTS.bounce.warn
			var r: float = Data.QUESTS.bounce.radius + Data.BALANCE.player_radius
			_place(landing, d.target.x, d.target.z, r, 0.14)
			(landing.material_override as StandardMaterial3D).albedo_color.a = 0.12 + 0.3 * u
			_place(landing_edge, d.target.x, d.target.z, r, 0.15)
			ball.visible = true
			var f: Dictionary = d.from
			var t: Dictionary = d.target
			ball.position = Vector3(f.x + (t.x - f.x) * u, 0.55 + 4.0 * BALL_HEIGHT * u * (1.0 - u), f.z + (t.z - f.z) * u)
		"crystal":
			crystal.visible = true
			# floats above the swarm so it stays readable when enemies pile on it
			crystal.position = Vector3(q.x, 2.6 + 0.15 * sin(time * 2.0), q.z)
			crystal.rotation.y = time * 1.2
			var hp := maxf(0.0, d.hp / Data.QUESTS.crystal.hp)
			var c := (fx_skin.secondary * 1.2).lerp(fx_skin.danger * 1.2, 1.0 - hp)
			crystal_mat.albedo_color = Color(c.r, c.g, c.b, 1.0)
