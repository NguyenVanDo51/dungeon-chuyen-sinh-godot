class_name ActorViews
## knight (player) + Lich (boss): animated GLB scenes

class PlayerView extends Node3D:
	## spare weapons baked into the KayKit model
	const HIDE := ["2H_Sword", "1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Spike_Shield"]
	var model: Node3D
	var ap: AnimationPlayer
	var _base := ""
	var _attack_t := 0.0

	func build() -> void:
		model = Gfx.load_glb("characters/Knight.glb").instantiate()
		add_child(model)
		for n in HIDE:
			var o := model.find_child(n, true, false)
			if o:
				o.visible = false
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_add_xray(mi as MeshInstance3D)
		ap = model.find_child("AnimationPlayer", true, false)
		Gfx.set_loop(ap, ["Idle", "Running_A"], true)
		Gfx.set_loop(ap, ["1H_Melee_Attack_Slice_Horizontal"], false)
		var halo := MeshInstance3D.new()
		halo.mesh = Gfx.disc_mesh(0.9, 32)
		halo.material_override = Gfx.glow_mat(Gfx.PINK, Gfx.GLOW.halo, Gfx.GLOW.halo_opacity)
		halo.position.y = 0.11
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(halo)
		_play("Idle", 0.0)

	## x-ray silhouette (built-in stencil preset): drawn only where a pillar / wall hides the knight
	func _add_xray(mi: MeshInstance3D) -> void:
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as BaseMaterial3D
			if base == null:
				continue
			var m := base.duplicate() as BaseMaterial3D
			m.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
			m.stencil_color = Color(1.0, 0.56, 0.85, 0.45)
			mi.set_surface_override_material(s, m)

	func _play(n: String, blend: float) -> void:
		if _base == n:
			return
		_base = n
		ap.play(n, blend)

	func play_attack() -> void:
		ap.play("1H_Melee_Attack_Slice_Horizontal", 0.05)
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
			_play("Running_A" if p.moving else "Idle", 0.15)
		# blink only during the short post-hit grace; long invuln shows as an aura instead
		model.visible = p.invuln <= 0.0 or p.invuln > Data.BALANCE.invuln_seconds + 0.01 or int(floor(p.invuln * 20.0)) % 2 == 0
		ap.speed_scale = 1.0 if dt > 0.0 else 0.0

class BossView extends Node3D:
	const SCALE := 2.4
	const CALM := Color("#6b3cff")
	const ANGRY := Color("#ff2b4d")
	var model: Node3D
	var ap: AnimationPlayer
	var mats: Array[StandardMaterial3D] = []
	var _base := ""
	var _cast_t := 0.0
	var _last := Vector2.ZERO
	var _dead := false

	func build() -> void:
		visible = false
		model = Gfx.load_glb("characters/Skeleton_Mage.glb").instantiate()
		model.scale = Vector3.ONE * SCALE
		add_child(model)
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			for s in mi.mesh.get_surface_count():
				var m := (mi.get_active_material(s) as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.emission_enabled = true
				m.emission = CALM
				m.emission_energy_multiplier = 0.25
				mi.set_surface_override_material(s, m)
				mats.append(m)
		ap = model.find_child("AnimationPlayer", true, false)
		Gfx.set_loop(ap, ["Walking_A", "Idle_Combat"], true)
		Gfx.set_loop(ap, ["Spellcast_Shoot", "Spellcast_Summon", "Death_A"], false)

	func reset() -> void:
		visible = false
		_dead = false
		_cast_t = 0.0
		_base = ""

	func cast(kind: String) -> void:
		ap.play("Spellcast_Summon" if kind == "summon" or kind == "adds" else "Spellcast_Shoot", 0.1)
		_base = ""
		_cast_t = 0.9

	func update(w: World, dt: float) -> void:
		if w.boss == null:
			# keep the corpse on screen for the death animation after the win
			if w.boss_defeated and visible and not _dead:
				_dead = true
				ap.play("Death_A", 0.1)
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
			var want := "Walking_A" if moving else "Idle_Combat"
			if want != _base:
				_base = want
				ap.play(want, 0.2)
		var flash := 0.45 if w.enemies.hit_flash[i] > 0.0 else (0.4 + 0.15 * sin(w.time * 12.0) if w.boss.enraged else 0.12)
		for m in mats:
			m.emission = ANGRY if w.boss.enraged else CALM
			m.emission_energy_multiplier = flash * 2.0
