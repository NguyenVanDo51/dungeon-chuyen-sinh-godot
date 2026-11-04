class_name ActorViews
## hero (player) + boss: animated glTF scenes driven by a HeroSkin / BossSkin

## normalise a model to `height` world units (0 = keep the file's scale)
static func fit_height(model: Node3D, height: float) -> void:
	if height <= 0.0:
		return
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible:
			continue
		# node transform relative to the model root (works before entering the tree)
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != model:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if box.size.y > 0.01:
		model.scale = Vector3.ONE * (height / box.size.y)

class PlayerView extends Node3D:
	var model: Node3D
	var ap: AnimationPlayer
	var skin: HeroSkin
	var _base := ""
	var _attack_t := 0.0

	func build(s: HeroSkin) -> void:
		skin = s
		model = (load(s.model) as PackedScene).instantiate()
		add_child(model)
		for n in s.hide_nodes:
			var o := model.find_child(n, true, false)
			if o:
				o.visible = false
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_add_xray(mi as MeshInstance3D)
		ActorViews.fit_height(model, s.height)
		ap = model.find_child("AnimationPlayer", true, false)
		Gfx.set_loop(ap, [s.idle_clip, s.run_clip], true)
		Gfx.set_loop(ap, [s.attack_clip], false)
		var halo := MeshInstance3D.new()
		halo.mesh = Gfx.disc_mesh(0.9, 32)
		halo.material_override = Gfx.glow_mat(s.halo_color, Gfx.GLOW.halo, Gfx.GLOW.halo_opacity)
		halo.position.y = 0.11
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(halo)
		_play(s.idle_clip, 0.0)

	## x-ray silhouette (built-in stencil preset): drawn only where a pillar / wall hides the hero
	func _add_xray(mi: MeshInstance3D) -> void:
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as BaseMaterial3D
			if base == null:
				continue
			var m := base.duplicate() as BaseMaterial3D
			m.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
			m.stencil_color = skin.xray_color
			mi.set_surface_override_material(s, m)

	func _play(n: String, blend: float) -> void:
		if _base == n or not ap.has_animation(n):
			return
		_base = n
		ap.play(n, blend)

	func play_attack() -> void:
		if not ap.has_animation(skin.attack_clip):
			return
		ap.play(skin.attack_clip, 0.05)
		_base = ""
		_attack_t = 0.35

	func update(p: World.Player, dt: float) -> void:
		position = Vector3(p.x, 0, p.z)
		var target := atan2(p.facing_x, p.facing_z)
		var diff := wrapf(target - model.rotation.y, -PI, PI)
		model.rotation.y += diff * minf(1.0, dt * 14.0)
		if _attack_t > 0.0:
			_attack_t -= dt
		if _attack_t <= 0.0:
			_play(skin.run_clip if p.moving else skin.idle_clip, 0.15)
		# blink only during the short post-hit grace; long invuln shows as an aura instead
		model.visible = p.invuln <= 0.0 or p.invuln > Data.BALANCE.invuln_seconds + 0.01 or int(floor(p.invuln * 20.0)) % 2 == 0
		ap.speed_scale = 1.0 if dt > 0.0 else 0.0

class BossView extends Node3D:
	var model: Node3D
	var ap: AnimationPlayer
	var skin: BossSkin
	var mats: Array[StandardMaterial3D] = []
	var _base := ""
	var _cast_t := 0.0
	var _last := Vector2.ZERO
	var _dead := false

	func build(s: BossSkin) -> void:
		skin = s
		visible = false
		model = (load(s.model) as PackedScene).instantiate()
		model.scale = Vector3.ONE * s.scale
		add_child(model)
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			for k in mi.mesh.get_surface_count():
				var src := mi.get_active_material(k) as StandardMaterial3D
				if src == null:
					continue
				var m := src.duplicate() as StandardMaterial3D
				m.emission_enabled = true
				m.emission = s.calm_color
				m.emission_energy_multiplier = 0.25
				mi.set_surface_override_material(k, m)
				mats.append(m)
		ap = model.find_child("AnimationPlayer", true, false)
		Gfx.set_loop(ap, [s.walk_clip, s.idle_clip], true)
		Gfx.set_loop(ap, [s.cast_clip, s.summon_clip, s.death_clip], false)

	func reset() -> void:
		visible = false
		_dead = false
		_cast_t = 0.0
		_base = ""

	func _play(n: String, blend: float) -> void:
		if ap.has_animation(n):
			ap.play(n, blend)

	func cast(kind: String) -> void:
		_play(skin.summon_clip if kind == "summon" or kind == "adds" else skin.cast_clip, 0.1)
		_base = ""
		_cast_t = 0.9

	func update(w: World, dt: float) -> void:
		if w.boss == null:
			# keep the corpse on screen for the death animation after the win
			if w.boss_defeated and visible and not _dead:
				_dead = true
				_play(skin.death_clip, 0.1)
			return
		var i := w.boss_index()
		if i < 0:
			return
		visible = true
		var x := w.enemies.x[i]
		var z := w.enemies.z[i]
		var moving := Vector2(x, z).distance_squared_to(_last) > 1e-5
		_last = Vector2(x, z)
		position = Vector3(x, 0, z)
		rotation.y = atan2(w.enemies.dir_x[i], w.enemies.dir_z[i])
		if _cast_t > 0.0:
			_cast_t -= dt
		elif dt > 0.0:
			var want := skin.walk_clip if moving else skin.idle_clip
			if want != _base:
				_base = want
				_play(want, 0.2)
		var flash := 0.45 if w.enemies.hit_flash[i] > 0.0 else (0.4 + 0.15 * sin(w.time * 12.0) if w.boss.enraged else 0.12)
		for m in mats:
			m.emission = skin.angry_color if w.boss.enraged else skin.calm_color
			m.emission_energy_multiplier = flash * 2.0
