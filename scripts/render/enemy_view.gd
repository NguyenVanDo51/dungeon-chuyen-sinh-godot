class_name EnemyView
extends Node3D
## one MultiMesh per enemy type: a baked run-pose + per-instance bob/tilt, hit flash, elite / frozen tint

const SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool use_tex = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 emissive : source_color = vec4(0.0);
uniform float emissive_energy = 0.0;
varying float v_flash;
varying float v_tint;
void vertex() { v_flash = INSTANCE_CUSTOM.r; v_tint = INSTANCE_CUSTOM.g; }
void fragment() {
	vec3 c = (use_tex ? texture(albedo_tex, UV).rgb : COLOR.rgb) * tint.rgb;
	vec3 em = emissive.rgb * emissive_energy;
	// 2 = frozen cyan, 1 = elite gold glow
	if (v_tint > 1.5) { c = mix(c, vec3(0.55, 1.15, 1.35), 0.55); em += vec3(0.1, 0.25, 0.3); }
	else if (v_tint > 0.5) { em += vec3(0.32, 0.22, 0.0); }
	ALBEDO = c;
	ROUGHNESS = 0.8;
	EMISSION = em + vec3(2.2) * v_flash;
}
"""

## [type] -> {mi: MultiMeshInstance3D, scale}
var _views := {}

func build(host: Node) -> void:
	var shader := Shader.new()
	shader.code = SHADER
	var minion := Gfx.load_glb("characters/Skeleton_Minion.glb")
	var warrior := Gfx.load_glb("characters/Skeleton_Warrior.glb")
	var mtex := _first_texture(minion)
	var wtex := _first_texture(warrior)
	var mk := func(tex: Texture2D, tint: Color, em: Color, energy: float) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("albedo_tex", tex)
		m.set_shader_parameter("use_tex", tex != null)
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("emissive", em)
		m.set_shader_parameter("emissive_energy", energy)
		return m
	var cap: int = Data.BALANCE.max_enemies
	# goblin placeholder: minion tinted + glowing green; thief violet so it never reads as a gold elite
	_add(Data.T_SLIME, _slime_mesh(), mk.call(null, Color.WHITE, Color("#2a8f6a"), 0.35), 0.8, cap, host)
	_add(Data.T_SKELETON, bake_pose(host, minion, "Running_A", 0.25), mk.call(mtex, Color.WHITE, Color.BLACK, 0.0), 0.8, cap, host)
	_add(Data.T_GOBLIN, bake_pose(host, minion, "Running_B", 0.1), mk.call(mtex, Color("#a6ff8a"), Color("#2f9e3a"), 0.55), 0.66, cap, host)
	_add(Data.T_WARRIOR, bake_pose(host, warrior, "Running_A", 0.25), mk.call(wtex, Color.WHITE, Color("#3a4f9e"), 0.3), 0.95, cap, host)
	_add(Data.T_THIEF, bake_pose(host, minion, "Running_B", 0.1), mk.call(mtex, Color("#d9a6ff"), Color("#7a3cc8"), 0.6), 0.6, 8, host)

func _add(t: int, mesh: Mesh, mat: Material, s: float, cap: int, _host: Node) -> void:
	var mi := Gfx.multi(mesh, mat, cap, false, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	_views[t] = { mi = mi, scale = s, n = 0 }

static func _first_texture(scene: PackedScene) -> Texture2D:
	var root := scene.instantiate()
	var tex: Texture2D = null
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh.surface_get_material(0)
		if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture:
			tex = (m as BaseMaterial3D).albedo_texture
			break
	root.free()
	return tex

## one animation frame of a skinned GLB baked into a single static mesh (so hundreds can be instanced)
static func bake_pose(host: Node, scene: PackedScene, clip: String, t: float) -> ArrayMesh:
	var root: Node3D = scene.instantiate()
	root.visible = false
	host.add_child(root)
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	ap.play(clip)
	ap.seek(t, true)
	ap.advance(0)
	var skel: Skeleton3D = root.find_child("Skeleton3D", true, false)
	skel.force_update_all_bone_transforms()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_inv := root.global_transform.affine_inverse()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible:
			continue
		var mesh: Mesh = mi.bake_mesh_from_current_skeleton_pose() if mi.skin != null else mi.mesh
		var xf := root_inv * mi.global_transform
		for s in mesh.get_surface_count():
			st.append_from(mesh, s, xf)
	root.queue_free()
	st.generate_normals()
	return st.commit()

static func _slime_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var add := func(mesh: Mesh, xf: Transform3D, col: Color) -> void:
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			st.set_color(col)
			st.set_normal((xf.basis * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
	add.call(Gfx.sphere(0.55, 12, 18), Transform3D(Basis.from_scale(Vector3(1, 0.72, 1)), Vector3(0, 0.4, 0)), Color("#8ff0c8"))
	for x in [-0.17, 0.17]:
		add.call(Gfx.sphere(0.09, 6, 8), Transform3D(Basis(), Vector3(x, 0.5, 0.47)), Color("#1a1a2e"))
		add.call(Gfx.sphere(0.03, 4, 6), Transform3D(Basis(), Vector3(x + 0.03, 0.54, 0.55)), Color.WHITE)
		var brow := Basis(Vector3.BACK, -0.45 if x < 0 else 0.45)
		add.call(Gfx.box(0.2, 0.05, 0.05), Transform3D(brow, Vector3(x, 0.64, 0.46)), Color("#1a1a2e"))
	return st.commit()

func update(pool: EnemyPool, time: float) -> void:
	for t in _views:
		_views[t].n = 0
	for i in pool.count:
		var t := pool.type[i]
		if not _views.has(t):
			continue
		var v: Dictionary = _views[t]
		var k: int = v.n
		if k >= v.mi.multimesh.instance_count:
			continue
		v.n = k + 1
		var frozen := pool.frozen[i] > 0.0
		var big: float = Data.ELITE.scale if pool.elite[i] == 1 else 1.0
		var phase := time * 10.0 + (pool.uid[i] % 97)
		var s := 0.0 if frozen else sin(phase)
		var yaw := atan2(pool.dir_x[i], pool.dir_z[i])
		var sc: float = v.scale * big
		var basis: Basis
		var pos := Vector3(pool.x[i], 0, pool.z[i])
		if t == Data.T_SLIME:
			basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sc * (1 - 0.08 * s), sc * (1 + 0.16 * s), sc * (1 - 0.08 * s)))
		else:
			# YXZ euler (yaw then roll) like the TS view
			basis = Basis.from_euler(Vector3(0, yaw, s * 0.17), EULER_ORDER_YXZ) * Basis.from_scale(Vector3.ONE * sc)
			pos.y = absf(s) * 0.12
		var mm: MultiMesh = v.mi.multimesh
		mm.set_instance_transform(k, Transform3D(basis, pos))
		mm.set_instance_custom_data(k, Color(1.0 if pool.hit_flash[i] > 0.0 else 0.0, 2.0 if frozen else (1.0 if pool.elite[i] == 1 else 0.0), 0, 0))
	for t in _views:
		_views[t].mi.multimesh.visible_instance_count = _views[t].n
