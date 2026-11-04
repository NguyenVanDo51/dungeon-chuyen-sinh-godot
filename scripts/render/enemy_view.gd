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

## baked poses per second of on-screen animation (8 frames/loop looked choppy: ~10-14 fps)
const ANIM_FPS := 30.0

## [type] -> {frames: Array[MultiMeshInstance3D], n: Array[int], scale, rate, len, animated}
var _views := {}

## one view per Monsters type that the style has a skin for (no skin = not drawn)
func build(host: Node, style: Style) -> void:
	var shader := Shader.new()
	shader.code = SHADER
	var cap: int = Data.BALANCE.max_enemies
	for t in Monsters.DEFS.size():
		var sk := style.monster(Monsters.DEFS[t].id)
		if sk == null:
			continue
		var c := sk.max_instances if sk.max_instances > 0 else cap
		if sk.kind == "slime":
			_add(t, [_slime_mesh()], _mat(shader, null, sk), sk.scale, 1.0, 1.0, c)
			continue
		var scene := load(sk.model) as PackedScene
		if scene == null:
			push_error("monster %s: model not found %s" % [sk.id, sk.model])
			continue
		_add_anim(host, t, scene, sk.clip, _mat(shader, _first_texture(scene), sk), sk.scale, sk.height, sk.anim_rate, c)

static func _mat(shader: Shader, tex: Texture2D, sk: MonsterSkin) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("use_tex", tex != null)
	m.set_shader_parameter("tint", sk.tint)
	m.set_shader_parameter("emissive", sk.emissive)
	m.set_shader_parameter("emissive_energy", sk.emissive_energy)
	return m

## height > 0 = normalise the baked pose to that world height, else fixed scale
func _add_anim(host: Node, t: int, scene: PackedScene, clip: String, mat: Material, scale: float, height: float, rate: float, cap: int) -> void:
	var probe := scene.instantiate()
	var player := probe.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var anim: Animation = player.get_animation(clip) if player and player.has_animation(clip) else null
	probe.free()
	if anim == null:
		push_error("monster %s: clip '%s' not found" % [Monsters.DEFS[t].id, clip])
		return
	var n := clampi(ceili(ANIM_FPS * anim.length / rate), 8, 48)
	var baked := bake_frames(host, scene, clip, n)
	var meshes: Array = baked.meshes
	var s := scale
	if height > 0.0:
		s = height / maxf(0.01, (meshes[0] as Mesh).get_aabb().size.y)
	_add(t, meshes, mat, s, rate, baked.length, cap)

func _add(t: int, meshes: Array, mat: Material, s: float, rate: float, clip_len: float, cap: int) -> void:
	var frames: Array[MultiMeshInstance3D] = []
	var counts: Array[int] = []
	for m in meshes:
		var mi := Gfx.multi(m, mat, cap, false, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		frames.append(mi)
		counts.append(0)
	_views[t] = { frames = frames, n = counts, scale = s, rate = rate, len = clip_len, animated = meshes.size() > 1 }

## FRAMES evenly spaced poses of a looping clip
static func bake_frames(host: Node, scene: PackedScene, clip: String, n: int) -> Dictionary:
	var root: Node3D = scene.instantiate()
	root.visible = false
	host.add_child(root)
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var length := ap.get_animation(clip).length
	var out := []
	for k in n:
		out.append(_bake_at(root, ap, clip, length * k / n))
	root.queue_free()
	return { meshes = out, length = length }

static func _bake_at(root: Node3D, ap: AnimationPlayer, clip: String, t: float) -> ArrayMesh:
	ap.play(clip)
	ap.seek(t, true)
	ap.advance(0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_inv := root.global_transform.affine_inverse()
	for nd in root.find_children("*", "MeshInstance3D", true, false):
		var mi := nd as MeshInstance3D
		if not mi.visible:
			continue
		if mi.skin == null:
			for s in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, s, root_inv * mi.global_transform)
			continue
		var skel := mi.get_node(mi.skeleton) as Skeleton3D
		var tmp := _skin_cpu(mi.mesh, mi.skin, skel)
		for s in tmp.get_surface_count():
			st.append_from(tmp, s, root_inv * skel.global_transform)
	st.generate_normals()
	return st.commit()

## CPU linear-blend skinning of the skeleton's current pose (no renderer needed); result in skeleton space
static func _skin_cpu(mesh: Mesh, skin: Skin, skel: Skeleton3D) -> ArrayMesh:
	var mats: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		mats.append(skel.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := weights.size() / maxi(1, verts.size())
		var nv := PackedVector3Array()
		nv.resize(verts.size())
		for i in verts.size():
			var v := verts[i]
			var acc := Vector3.ZERO
			var wsum := 0.0
			for k in per:
				var w := weights[i * per + k]
				if w <= 0.0:
					continue
				acc += (mats[int(bones[i * per + k])] * v) * w
				wsum += w
			nv[i] = acc / wsum if wsum > 0.0 else v
		var na := []
		na.resize(Mesh.ARRAY_MAX)
		na[Mesh.ARRAY_VERTEX] = nv
		na[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
		na[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
		if arr[Mesh.ARRAY_COLOR] != null:
			na[Mesh.ARRAY_COLOR] = arr[Mesh.ARRAY_COLOR]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
	return out

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
		_views[t].n.fill(0)
	for i in pool.count:
		var t := pool.type[i]
		if not _views.has(t):
			continue
		var v: Dictionary = _views[t]
		var frozen := pool.frozen[i] > 0.0
		var big: float = Monsters.ELITE.scale if pool.elite[i] == 1 else 1.0
		var sc: float = v.scale * big
		var yaw := atan2(pool.dir_x[i], pool.dir_z[i])
		var pos := Vector3(pool.x[i], 0, pool.z[i])
		var basis: Basis
		var f := 0
		if v.animated:
			# each enemy runs its own loop offset; frozen = held pose
			var ph: float = (pool.uid[i] % 97) * 0.173 + (0.0 if frozen else time * v.rate / v.len)
			var nf: int = v.frames.size()
			f = int(floor(ph * nf)) % nf
			basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * sc)
		else:
			var s := 0.0 if frozen else sin(time * 10.0 + (pool.uid[i] % 97))
			basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sc * (1 - 0.08 * s), sc * (1 + 0.16 * s), sc * (1 - 0.08 * s)))
		var mi: MultiMeshInstance3D = v.frames[f]
		var k: int = v.n[f]
		if k >= mi.multimesh.instance_count:
			continue
		v.n[f] = k + 1
		mi.multimesh.set_instance_transform(k, Transform3D(basis, pos))
		mi.multimesh.set_instance_custom_data(k, Color(1.0 if pool.hit_flash[i] > 0.0 else 0.0, 2.0 if frozen else (1.0 if pool.elite[i] == 1 else 0.0), 0, 0))
	for t in _views:
		var v: Dictionary = _views[t]
		for f in v.frames.size():
			v.frames[f].multimesh.visible_instance_count = v.n[f]
