class_name Gfx
## glow materials, procedural meshes, GLB helpers; UI palette (3D colours come from the style)

const BG := Color("#0d1030")
const PINK := Color("#ff8fd8")
const CYAN := Color("#5ff3ff")
const GOLD := Color("#ffd36e")
const MINT := Color("#7dff9a")

## glow strengths (values >1 push a material over the bloom threshold); lowered after "chói mắt"
const GLOW := {
	torch = 5.0, rune = 1.1, rune_opacity = 0.45, halo = 1.0, halo_opacity = 0.22, gem = 0.95,
	arrow = 1.6, fireball = 1.9, sword_wave = 1.7, sword_glow = 1.2, sword_glow_opacity = 0.4, meteor_warn = 1.3, meteor = 2.2, spark = 1.5,
	slash = 1.6, explode = 1.8, unlock = 1.6, bolt = 1.3, frost = 0.9, frost_aura_opacity = 0.05,
	ice_shard = 1.1, shield = 1.4, beam = 1.6, vortex = 1.4, boss_shot = 1.8, zone = 1.3,
}

static func glow_mat(c: Color, k: float, opacity := 1.0, no_depth_test := false, double_sided := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r * k, c.g * k, c.b * k, opacity)
	if opacity < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if no_depth_test:
		m.no_depth_test = true
		m.render_priority = 10
	return m

## flat ring on the XZ plane; angle θ from +X toward -Z (= three RingGeometry.rotateX(-π/2))
static func ring_mesh(inner: float, outer: float, segs: int, theta0 := 0.0, theta_len := TAU) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segs:
		var a0 := theta0 + theta_len * i / segs
		var a1 := theta0 + theta_len * (i + 1) / segs
		var p0i := Vector3(cos(a0) * inner, 0, -sin(a0) * inner)
		var p0o := Vector3(cos(a0) * outer, 0, -sin(a0) * outer)
		var p1i := Vector3(cos(a1) * inner, 0, -sin(a1) * inner)
		var p1o := Vector3(cos(a1) * outer, 0, -sin(a1) * outer)
		st.add_vertex(p0i); st.add_vertex(p1o); st.add_vertex(p0o)
		st.add_vertex(p0i); st.add_vertex(p1i); st.add_vertex(p1o)
	return st.commit()

static func disc_mesh(r: float, segs := 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a1) * r, 0, -sin(a1) * r))
		st.add_vertex(Vector3(cos(a0) * r, 0, -sin(a0) * r))
	return st.commit()

static func sphere(r: float, rings := 8, segs := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.rings = rings
	s.radial_segments = segs
	return s

static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func octahedron(r: float) -> ArrayMesh:
	var v := [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		st.set_normal((c - a).cross(b - a).normalized())
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	return st.commit()

## dynamic MultiMesh of `cap` instances (visible_instance_count drives how many draw)
static func multi(mesh: Mesh, mat: Material, cap: int, colors := false, custom := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# instances move anywhere: never cull by the (stale) aabb
	mi.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	return mi

## first MeshInstance3D of a static GLB with its node transform relative to the scene root
static func first_mesh(scene: PackedScene) -> Dictionary:
	var root := scene.instantiate()
	var found: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var xf := Transform3D.IDENTITY
	var n: Node = found
	while n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var out := { mesh = found.mesh, xform = xf }
	root.free()
	return out

static func load_glb(path: String) -> PackedScene:
	return load("res://assets/" + path)

## Animation resource by name from a GLB scene's AnimationPlayer, set to loop
static func set_loop(ap: AnimationPlayer, names: Array, loop: bool) -> void:
	for n in names:
		var a := ap.get_animation(n)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
