extends Node
## game shell: scene, camera, input, run lifecycle; World does the rules, views draw it
## debug args (after `--`): seed=123 god boss enemies=300 give=fireball:5,haste:1 quest=bounce
##   bot (autoplay) autostart shots=DIR shot_at=5,30 quit_at=60 fps

const CAM_DIST := 30.0
const CAM_PITCH := deg_to_rad(55.0)
const SLOWMO := { seconds = 0.5, scale = 0.3 }

var world: World
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var dungeon: DungeonView
var enemy_view: EnemyView
var player_view: ActorViews.PlayerView
var boss_view: ActorViews.BossView
var vfx: Vfx
var ui: Ui
var focus := Vector3.ZERO
var shake := 0.0
var started := false
var slowmo := 0.0
var unlock_queue: Array[String] = []
var skill_pressed := false
var end_shown := false
var flags := {}
var bot: Bot
var _shot_at: Array[float] = []
var _fps := { frames = 0, acc = 0.0, worst = 0.0, report = 0.0 }

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		flags[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if flags.has("shot_at"):
		for s in flags.shot_at.split(","):
			_shot_at.append(float(s))
	_build_scene()
	ui = Ui.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	ui.start_pressed.connect(begin_run)
	ui.restart_pressed.connect(begin_run)
	ui.resume_pressed.connect(_resume)
	ui.menu_pressed.connect(_to_menu)
	ui.card_picked.connect(_on_card)
	world = _new_world()
	_follow(0.0, true)
	if flags.has("autostart") or flags.has("bot"):
		begin_run()
	if flags.has("keytest"):
		_key_test()

func _build_scene() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Gfx.BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3a4290")
	env.ambient_light_energy = 0.18
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Gfx.BG
	env.fog_density = 1.0
	env.fog_depth_begin = CAM_DIST + 8.0
	env.fog_depth_end = CAM_DIST + 45.0
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#c9d4ff")
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	dungeon = DungeonView.new()
	add_child(dungeon)
	var g := Grid.parse(Data.MAP_ASCII)
	dungeon.build(g)
	dungeon.set_doors(false)
	enemy_view = EnemyView.new()
	add_child(enemy_view)
	enemy_view.build(self)
	player_view = ActorViews.PlayerView.new()
	add_child(player_view)
	player_view.build()
	boss_view = ActorViews.BossView.new()
	add_child(boss_view)
	boss_view.build()
	vfx = Vfx.new()
	add_child(vfx)
	vfx.build()

func _new_world() -> World:
	var s := int(flags.get("seed", str(randi())))
	var w := World.new(s)
	w.spawn_visibility = _spawn_visible
	w.in_view = _in_frame
	if flags.has("enemies"):
		w.min_enemies = int(flags.enemies)
	if flags.has("god"):
		w.god = true
	if flags.has("give"):
		var items := {}
		for kv in flags.give.split(","):
			var p := (kv as String).split(":")
			items[p[0]] = int(p[1]) if p.size() > 1 else 1
		w.debug_give(items)
	if flags.has("hp"):
		w.player.hp = float(flags.hp)
	if flags.has("boss"):
		w.time = Data.BOSS_AT - 2.0
	if flags.has("quest"):
		Quests.start(w, flags.quest)
	return w

## reject spawn points inside the (slightly enlarged) view so enemies never pop in on screen
func _ndc(x: float, y: float, z: float) -> Vector3:
	var p := Vector3(x, y, z)
	if cam.is_position_behind(p):
		return Vector3(9, 9, 9)
	var s := cam.unproject_position(p)
	var vp := get_viewport().get_visible_rect().size
	return Vector3(s.x / vp.x * 2.0 - 1.0, 1.0 - s.y / vp.y * 2.0, 0)

func _spawn_visible(x: float, z: float) -> bool:
	var n := _ndc(x, 1.0, z)
	return absf(n.x) < 1.15 and absf(n.y) < 1.15

## weapons: strictly inside the frame
func _in_frame(x: float, z: float) -> bool:
	var n := _ndc(x, 0.5, z)
	return absf(n.x) <= 1.0 and absf(n.y) <= 1.0

func begin_run() -> void:
	world = _new_world()
	bot = Bot.new(world, true) if flags.has("bot") else null
	unlock_queue.clear()
	slowmo = 0.0
	end_shown = false
	vfx.reset()
	boss_view.reset()
	started = true
	ui.show_game()
	_follow(0.0, true)

func _resume() -> void:
	world.paused = false
	ui.hide_all()

func _to_menu() -> void:
	started = false
	world.paused = true
	ui.show_menu()

func _toggle_pause() -> void:
	if not started or world.state == "won" or world.state == "lost":
		return
	if ui.mode == "pause":
		_resume()
	else:
		world.paused = true
		ui.show_pause()

func _on_card(i: int) -> void:
	if world.paused:
		return
	world.choose_offer(i)
	if world.state == "levelUp":
		ui.show_level_up(world)
	else:
		ui.hide_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and started and ui.mode in ["none", "levelUp"] and not flags.has("bot") and not flags.has("shots"):
		world.paused = true
		ui.show_pause()

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: Key = e.physical_keycode
	if k == KEY_ESCAPE:
		_toggle_pause()
	elif k == KEY_SPACE and started and ui.mode == "none" and world.state == "playing":
		skill_pressed = true
	elif k in [KEY_ENTER, KEY_KP_ENTER] and ui.mode in ["menu", "end"]:
		begin_run()
	elif k in [KEY_1, KEY_2, KEY_3, KEY_KP_1, KEY_KP_2, KEY_KP_3]:
		ui.pick_card(({ KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_KP_1: 0, KEY_KP_2: 1, KEY_KP_3: 2 } as Dictionary)[k])

func _read_move() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	return v

func _process(delta: float) -> void:
	var dt := minf(delta, Data.BALANCE.dt_max)
	_measure(delta)
	if started:
		var playable := not world.paused and world.state == "playing"
		var scaled := dt * SLOWMO.scale if slowmo > 0.0 else dt
		# slow-mo only burns while the world actually runs
		if playable:
			slowmo = maxf(0.0, slowmo - dt)
		var mv := _read_move()
		var sk := skill_pressed
		skill_pressed = false
		if bot and playable:
			mv = bot.input(world.time)
			sk = bot.want_skill()
		world.tick(scaled, mv, sk)
		if bot and world.state == "levelUp" and not world.paused:
			world.choose_offer(bot.pick(world.current_offers))
	_handle_events()
	if started and ui.mode == "none" and not unlock_queue.is_empty() and world.state == "playing" and not world.paused:
		var id: String = unlock_queue.pop_front()
		ui.play_unlock(id)
		vfx.unlock_burst(world.player.x, world.player.z)
		slowmo = SLOWMO.seconds
	if started and world.state == "levelUp" and ui.mode == "none" and not bot:
		ui.show_level_up(world)
	if started and (world.state == "won" or world.state == "lost") and not end_shown:
		end_shown = true
		ui.show_end(world)
		if flags.has("bot"):
			print("RUN END: %s at %s lv%d kills%d" % [world.state, Ui.fmt_time(world.time), world.level, world.kills])
	var frozen := world.paused or world.state != "playing"
	var vdt := 0.0 if frozen else (dt * SLOWMO.scale if slowmo > 0.0 else dt)
	player_view.update(world.player, vdt)
	enemy_view.update(world.enemies, world.time)
	boss_view.update(world, vdt if vdt > 0.0 else (dt if world.boss_defeated else 0.0))
	vfx.update(world, vdt, world.time)
	shake = minf(1.2, shake + vfx.shake_req)
	vfx.shake_req = 0.0
	if started:
		ui.update_hud(world, cam, dt)
	_follow(dt)
	_screenshots()

func _handle_events() -> void:
	for ev in world.events:
		match ev.t:
			"slash": player_view.play_attack()
			"questAppear": ui.play_alert("★ Nhiệm vụ: %s!" % Data.QUEST_NAMES[ev.kind])
			"questEnd": ui.play_alert(("✔ %s — hoàn thành! +XP" if ev.success else "✘ %s — thất bại") % Data.QUEST_NAMES[ev.kind])
			"pickup": ui.add_text(world.player.x, world.player.z, Data.PICKUP_NAMES[ev.kind])
			"hit": ui.add_damage(ev.x, ev.z, ev.amount)
			"hiddenUnlocked": unlock_queue.append(ev.id)
			"bossWarn": ui.play_alert("⚠ Boss thức tỉnh!")
			"bossArena":
				ui.play_alert("☠ Bị kéo vào phòng boss!")
				_follow(0.0, true)
				shake += 0.6
			"enrage":
				ui.play_alert("LICH CUỒNG NỘ!")
				shake += 0.8
			"bossCast": boss_view.cast(ev.kind)
		vfx.on_event(ev)
	world.events.clear()

func _follow(dt: float, snap := false) -> void:
	var k := 1.0 if snap else 1.0 - exp(-8.0 * dt)
	focus.x += (world.player.x - focus.x) * k
	focus.z += (world.player.z - focus.z) * k
	var jx := (randf() - 0.5) * shake
	var jz := (randf() - 0.5) * shake
	shake = maxf(0.0, shake - dt * 3.0)
	cam.position = Vector3(focus.x + jx, sin(CAM_PITCH) * CAM_DIST, focus.z + cos(CAM_PITCH) * CAM_DIST + jz)
	cam.look_at(Vector3(focus.x + jx, 0, focus.z + jz))
	sun.position = Vector3(focus.x - 12, 30, focus.z + 10)
	sun.look_at(Vector3(focus.x, 0, focus.z))

func _measure(delta: float) -> void:
	if not flags.has("fps"):
		return
	_fps.frames += 1
	_fps.acc += delta
	_fps.worst = maxf(_fps.worst, delta)
	_fps.report += delta
	if _fps.report >= 5.0:
		var vp := get_viewport().get_visible_rect().size
		print("FPS avg %.1f worst %.1f | enemies %d | t=%s | draw calls %d | %dx%d" % [_fps.frames / _fps.acc, 1.0 / _fps.worst, world.enemies.count, Ui.fmt_time(world.time),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), get_window().size.x, get_window().size.y])
		_fps = { frames = 0, acc = 0.0, worst = 0.0, report = 0.0 }

var _lu_shot := false

func _screenshots() -> void:
	# shot_mode=levelUp|end: one capture the first time that screen opens
	if flags.has("shot_mode"):
		if flags.has("shots") and ui.mode == flags.shot_mode and not _lu_shot:
			_lu_shot = true
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png("%s/shot_%s.png" % [flags.shots, flags.shot_mode])
			print("SHOT ", flags.shot_mode)
			get_tree().quit()
		return
	if flags.has("keytest"):
		return
	if not flags.has("shots"):
		if flags.has("quit_at") and world.time >= float(flags.quit_at):
			get_tree().quit()
		return
	if _shot_at.size() > 0 and world.time >= _shot_at[0]:
		var t: float = _shot_at.pop_front()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/shot_%04d.png" % [flags.shots, int(t)]
		img.save_png(path)
		print("SHOT ", path)
	if (flags.has("quit_at") and world.time >= float(flags.quit_at)) or (_shot_at.is_empty() and not flags.has("quit_at")):
		await RenderingServer.frame_post_draw
		get_tree().quit()

# ---------- keytest: real key events through the input path ----------

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _tap(k: Key) -> void:
	_key(k, true)
	await get_tree().process_frame
	_key(k, false)
	await get_tree().process_frame

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _check(name: String, ok: bool) -> void:
	printerr("KEYTEST %s %s" % ["PASS" if ok else "FAIL", name])

func _shot(n: String) -> void:
	if flags.has("shots"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/shot_%s.png" % [flags.shots, n])

func _key_test() -> void:
	await _wait(1.0)
	_check("menu shown", ui.mode == "menu")
	await _tap(KEY_ENTER)
	_check("Enter starts run", started and ui.mode == "none")
	var z0 := world.player.z
	_key(KEY_W, true)
	await _wait(1.0)
	_key(KEY_W, false)
	_check("W moves up (dz=%.2f)" % (world.player.z - z0), world.player.z < z0 - 2.0)
	var x0 := world.player.x
	_key(KEY_D, true)
	await _wait(0.6)
	_key(KEY_D, false)
	_check("D moves right (dx=%.2f)" % (world.player.x - x0), world.player.x > x0 + 1.0)
	await _tap(KEY_SPACE)
	await _wait(0.1)
	_check("Space casts skill (cd=%.1f)" % world.skill_cd, world.skill_cd > 0.0)
	await _tap(KEY_ESCAPE)
	_check("Esc pauses", ui.mode == "pause" and world.paused)
	await _shot("pause")
	var t0 := world.time
	await _wait(0.5)
	_check("paused clock frozen", world.time == t0)
	await _tap(KEY_SPACE)
	_check("Space in pause does nothing", ui.mode == "pause")
	await _tap(KEY_ESCAPE)
	_check("Esc resumes", ui.mode == "none" and not world.paused)
	# level-up: force the 5th Thánh Kiếm level so the hidden-skill moment fires (give=holySword:4,might:1)
	world.add_xp(Data.xp_to_next(world.level))
	await _wait(0.1)
	_check("level-up opens cards", ui.mode == "levelUp")
	world.current_offers = [{ type = "upgrade", id = "holySword", to_level = 5 }]
	ui.show_level_up(world)
	await _wait(0.5)
	await _tap(KEY_1)
	_check("key 1 picks card", world.state == "playing" and world.build.level_of("holySword") == 5)
	await _wait(0.4)
	_check("hidden skill unlocked", world.build.hidden.has("holySword"))
	await _shot("unlock")
	await _wait(1.0)
	await _shot("kiemkhi")
	get_tree().quit()
