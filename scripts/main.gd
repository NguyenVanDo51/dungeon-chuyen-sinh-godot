extends Node
## game shell: scene, camera, input, meta + run lifecycle; World does the rules, views draw it (style = the look)
## debug args (after `--`): seed=123 god boss enemies=300 give=fireball:5,haste:1 hidden=all quest=bounce lock=a,b
##   char=archer mode=dungeon floor=2 style=quaternius fresh (ignore the save) unlock (all floors / chars)
##   bot (autoplay) autostart shots=DIR shot_at=5,30 quit_at=60 fps mute (M in game) sfx_stats

const CAM_DIST := 30.0
const CAM_PITCH := deg_to_rad(55.0)
const SLOWMO := { seconds = 0.5, scale = 0.3 }
## frozen frames on heavy hits (logic just skips ticks; sim never sees it)
const HITSTOP := { elite = 0.05, wrath = 0.07, enrage = 0.12, cooldown = 0.3 }
## seconds the death / victory moment plays before the end screen
const END_DELAY := { won = 2.2, lost = 1.4 }

var world: World
var style: Style
var meta: Meta
## what the next World plays: map id + rules
var run := { map = Dungeons.SURVIVAL_MAP, rules = Dungeons.survival_rules() }
var character: String = Characters.DEFAULT
var _banked := false
var _map_built := ""
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var dungeon: DungeonView
var enemy_view: EnemyView
var player_view: ActorViews.PlayerView
var hero_views := {}
var boss_view: ActorViews.BossView
var vfx: Vfx
var sfx: Sfx
var hitstop := 0.0
var _hitstop_ready := 0.0
var _end_t := 0.0
var ui: Ui
var screens: Screens
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
	style = Style.load_active(flags.get("style", ""))
	meta = Meta.fresh() if flags.has("fresh") else Meta.load_from()
	if flags.has("unlock"):
		for c in Characters.IDS:
			if not c in meta.owned:
				meta.owned.append(c)
		for d in Dungeons.DEFS:
			meta.floors_cleared[d] = Dungeons.DEFS[d].floors.size()
	character = meta.selected
	if flags.has("char") and flags.char in meta.owned:
		character = flags.char
	if flags.get("mode", "") == "dungeon":
		_set_run({ kind = "dungeon", floor = int(flags.get("floor", "1")) - 1 })
	_build_scene()
	ui = Ui.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	ui.card_picked.connect(_on_card)
	screens = Screens.new()
	screens.meta = meta
	screens.style = style
	screens.chosen = character
	layer.add_child(screens)
	screens.start.connect(_on_start)
	screens.select.connect(_on_select)
	screens.restart.connect(_on_restart)
	screens.next_floor.connect(_on_next)
	screens.floors.connect(_leave_run.bind("floors"))
	screens.resume.connect(_resume)
	screens.menu.connect(_leave_run.bind("menu"))
	screens.buy.connect(_on_buy)
	screens.upgrade.connect(_on_upgrade)
	world = _new_world()
	_sync_map()
	_follow(0.0, true)
	screens.show_menu()
	match flags.get("screen", ""):
		"shop": screens.show_shop()
		"floors": screens.show_floors()
		"chars": screens.show_chars()
	if flags.has("autostart") or flags.has("bot"):
		begin_run()
	if flags.has("keytest"):
		_key_test()

func _on_restart() -> void:
	_bank()
	begin_run()

## picked once on the character screen, kept for every later run
func _on_select(c: String) -> void:
	if not c in meta.owned:
		return
	character = c
	meta.selected = c
	_save_meta()

func _on_buy(c: String) -> void:
	var ok := meta.buy(c)
	sfx.play("ui_buy" if ok else "ui_error")
	if ok:
		_save_meta()

func _on_upgrade(id: String) -> void:
	var ok := meta.upgrade(id)
	sfx.play("ui_buy" if ok else "ui_error")
	if ok:
		_save_meta()

func _save_meta() -> void:
	if not flags.has("fresh"):
		meta.save()
	screens.refresh()

## kind survival | dungeon (floor 0-based)
func _set_run(p: Dictionary) -> void:
	if p.kind == "survival":
		run = { map = Dungeons.SURVIVAL_MAP, rules = Dungeons.survival_rules() }
	else:
		run = { map = Dungeons.floor_map("crypt", p.floor), rules = Dungeons.floor_rules("crypt", p.floor) }

func _on_start(c: String, p: Dictionary) -> void:
	if not c in meta.owned:
		return
	character = c
	_set_run(p)
	begin_run()

func _on_next() -> void:
	var d: Dictionary = run.rules.dungeon
	if d.is_empty() or d.floor + 1 >= Dungeons.DEFS[d.id].floors.size() or not meta.floor_open(d.id, d.floor + 1):
		return
	_bank()
	_set_run({ kind = "dungeon", floor = d.floor + 1 })
	begin_run()

## every exit from a run goes through here; a run's gold counts once
func _bank() -> void:
	if _banked or world == null:
		return
	_banked = true
	meta.bank(world.gold)
	_save_meta()

## to = menu | floors
func _leave_run(to: String) -> void:
	_bank()
	started = false
	world.paused = true
	ui.hide_all()
	ui.show_hud(false)
	if to == "floors":
		screens.show_floors()
	else:
		screens.show_menu()

func _build_scene() -> void:
	var t0 := Time.get_ticks_msec()
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	dungeon = DungeonView.new()
	add_child(dungeon)
	enemy_view = EnemyView.new()
	add_child(enemy_view)
	enemy_view.build(self, style)
	for c in Characters.IDS:
		var m: String = Characters.DEFS[c].model
		if hero_views.has(m):
			continue
		var hv := ActorViews.PlayerView.new()
		add_child(hv)
		hv.build(style.hero(m))
		hv.visible = false
		hero_views[m] = hv
	boss_view = ActorViews.BossView.new()
	add_child(boss_view)
	boss_view.build(style.boss(Bosses.DEFS.keys()[0]))
	vfx = Vfx.new()
	add_child(vfx)
	vfx.build(style.fx)
	sfx = Sfx.new()
	add_child(sfx)
	sfx.build(style.sfx if style.sfx else SfxSkin.new())
	Sfx.set_muted(flags.has("mute"))
	print("scene built in %d ms" % (Time.get_ticks_msec() - t0))

## level mesh, light and fog follow the World's map theme; doors follow its grid
func _sync_map() -> void:
	var th := style.theme(world.map.theme)
	if world.map.id != _map_built:
		_map_built = world.map.id
		dungeon.clear()
		dungeon.build(world.grid, th, world.map.spots)
		env.background_color = th.background
		env.fog_light_color = th.background
		env.ambient_light_color = th.ambient
		env.ambient_light_energy = th.ambient_energy
		env.fog_depth_begin = CAM_DIST + th.fog_near
		env.fog_depth_end = CAM_DIST + th.fog_far
		sun.light_color = th.sun_color
		sun.light_energy = th.sun_energy
	dungeon.set_doors(world.doors_open)
	player_view = hero_views[world.hero.model]
	for m in hero_views:
		hero_views[m].visible = hero_views[m] == player_view

func _new_world() -> World:
	var s := int(flags.get("seed", str(randi())))
	var lock: Array = flags.lock.split(",") if flags.has("lock") else []
	var w := World.new({ seed = s, map = run.map, rules = run.rules, locked = lock, character = meta.apply_upgrades(Characters.DEFS[character]) })
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
	if flags.get("hidden", "") == "all":
		var all := {}
		for id in Items.all_items():
			all[id] = 5 if Items.is_weapon(id) else 1
		w.debug_give(all)
	if flags.has("hp"):
		w.player.hp = float(flags.hp)
	if flags.has("boss"):
		w.time = w.boss_time() - 2.0
	if flags.has("quest"):
		Quests.start(w, flags.quest)
	if flags.has("showcase"):
		_setup_showcase(w)
	return w

## showcase: one row per enemy type running in place in front of the knight (art review)
var _show := []

func _setup_showcase(w: World) -> void:
	w.spawn_enabled = false
	w.god = true
	_show.clear()
	var types: Array[int] = []
	for t in Monsters.DEFS.size():
		if Monsters.DEFS[t].role == "":
			types.append(t)
	for r in types.size():
		for c in 3:
			var x := w.player.x - 6.0 + c * 3.0 + (1.5 if r % 2 else 0.0)
			var z := w.player.z - 13.0 + r * 3.4
			var i := w.enemies.spawn(types[r], x, z, 1e9, c == 2)
			_show.append([w.enemies.uid[i], x, z])

func _hold_showcase() -> void:
	var e := world.enemies
	for s in _show:
		var i := e.index_of_uid(s[0])
		if i >= 0:
			e.x[i] = s[1]; e.z[i] = s[2]; e.dir_x[i] = 0.0; e.dir_z[i] = 1.0; e.hp[i] = 1e9; e.hit_flash[i] = 0.0

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

## fresh World with the current upgrades (bought between runs)
func begin_run() -> void:
	world = _new_world()
	_banked = false
	bot = Bot.new(world, true) if flags.has("bot") else null
	if bot:
		bot.dungeon = run.rules.spawn == "depth"
	_sync_map()
	unlock_queue.clear()
	slowmo = 0.0
	end_shown = false
	_end_t = 0.0
	hitstop = 0.0
	vfx.reset()
	boss_view.reset()
	started = true
	screens.hide_all()
	ui.hide_all()
	ui.show_hud(true)
	_follow(0.0, true)

func _resume() -> void:
	world.paused = false
	screens.hide_all()

func _toggle_pause() -> void:
	if not started or world.state == "won" or world.state == "lost":
		return
	if screens.mode == "pause":
		_resume()
	elif screens.mode == "none":
		world.paused = true
		screens.show_pause()

func _on_card(i: int) -> void:
	if world.paused:
		return
	world.choose_offer(i)
	sfx.play("ui_card")
	if world.state == "levelUp":
		ui.show_level_up(world)
	else:
		ui.hide_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and started and screens.mode == "none" and world.state in ["playing", "levelUp"] and not flags.has("bot") and not flags.has("shots"):
		world.paused = true
		screens.show_pause()

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: Key = e.physical_keycode
	if screens.mode != "none" and screens.mode != "pause" and screens.handle_key(k):
		sfx.play("ui_back" if k == KEY_ESCAPE else "ui_click")
		return
	if k == KEY_M:
		Sfx.set_muted(not AudioServer.is_bus_mute(0))
	elif k == KEY_ESCAPE:
		sfx.play("ui_back")
		_toggle_pause()
	elif k == KEY_SPACE and started and screens.mode == "none" and ui.mode == "none" and world.state == "playing":
		skill_pressed = true
	elif screens.mode == "none" and k in [KEY_1, KEY_2, KEY_3, KEY_KP_1, KEY_KP_2, KEY_KP_3]:
		ui.pick_card(({ KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_KP_1: 0, KEY_KP_2: 1, KEY_KP_3: 2 } as Dictionary)[k])

func _read_move() -> Array:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	return [v.x, v.y]

func _process(delta: float) -> void:
	var dt := minf(delta, Data.BALANCE.dt_max)
	_measure(delta)
	var stopped := hitstop > 0.0
	hitstop = maxf(0.0, hitstop - delta)
	if started and not stopped:
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
		world.tick(scaled, mv[0], mv[1], sk)
		if flags.has("showcase"):
			_hold_showcase()
			world.player.x = world.grid.start.x
			world.player.z = world.grid.start.y
		if bot and world.state == "levelUp" and not world.paused:
			world.choose_offer(bot.pick(world.current_offers))
	_handle_events()
	if started and screens.mode == "none" and ui.mode == "none" and not unlock_queue.is_empty() and world.state == "playing" and not world.paused:
		var id: String = unlock_queue.pop_front()
		ui.play_unlock(id)
		sfx.play("hidden_unlock")
		vfx.unlock_burst(world.player.x, world.player.z)
		slowmo = SLOWMO.seconds
	# started: an abandoned run left in levelUp must not pop its cards over the menu
	if started and world.state == "levelUp" and ui.mode == "none" and screens.mode == "none" and not bot:
		ui.show_level_up(world)
	if started and (world.state == "won" or world.state == "lost") and not end_shown:
		_end_t += delta
		if _end_t < END_DELAY[world.state]:
			_finish_frame(dt, stopped)
			return
		end_shown = true
		ui.hide_all()
		ui.show_hud(false)
		_bank()
		var d: Dictionary = world.rules.dungeon
		var won := world.state == "won"
		if not d.is_empty() and won:
			meta.clear_floor(d.id, d.floor)
			_save_meta()
		var last: bool = not d.is_empty() and d.floor == Dungeons.DEFS[d.id].floors.size() - 1
		screens.show_end(world, Screens.end_actions(won, d, last))
		if flags.has("bot"):
			print("RUN END: %s at %s lv%d kills%d" % [world.state, Ui.fmt_time(world.time), world.level, world.kills])
		if flags.has("sfx_stats"):
			print("SFX played %s throttled %d music %s" % [sfx.played, sfx.throttled, sfx.track_log])
	_finish_frame(dt, stopped)

func _finish_frame(dt: float, stopped: bool) -> void:
	var frozen := world.paused or world.state != "playing" or stopped
	var vdt := 0.0 if frozen else (dt * SLOWMO.scale if slowmo > 0.0 else dt)
	player_view.update(world.player, vdt)
	enemy_view.update(world.enemies, world.time)
	boss_view.update(world, vdt if vdt > 0.0 else (dt if world.boss_defeated else 0.0))
	vfx.update(world, vdt, world.time)
	shake = minf(1.2, shake + vfx.shake_req)
	vfx.shake_req = 0.0
	if started and ui.hud.visible:
		ui.update_hud(world, cam, dt)
	_follow(dt)
	sfx.update(world if started else null, _music_track(), dt)
	_screenshots()

func _music_track() -> String:
	if not started:
		return "menu"
	if world.state != "playing" and world.state != "levelUp":
		return ""
	return "boss" if world.boss != null else "combat"

func _handle_events() -> void:
	for ev in world.events:
		match ev.t:
			"slash", "shot": player_view.play_attack()
			"questAppear": ui.play_alert("★ Nhiệm vụ: %s!" % Data.QUEST_NAMES[ev.kind])
			"questEnd": ui.play_alert(("✔ %s — hoàn thành! +XP" if ev.success else "✘ %s — thất bại") % Data.QUEST_NAMES[ev.kind], "good" if ev.success else "bad")
			"pickup": ui.add_text(world.player.x, world.player.z, Data.PICKUP_NAMES[ev.kind])
			"hit": ui.add_damage(ev.x, ev.z, ev.amount)
			"hiddenUnlocked": unlock_queue.append(ev.id)
			"bossWarn":
				var room: bool = world.rules.boss == "enterRoom"
				ui.play_alert("⚠ Hết giờ! Sắp bị kéo vào phòng boss" if ev.pull else ("⚠ Phòng boss! Ở lại để đánh thức boss" if room else "⚠ Boss thức tỉnh!"), "boss")
			"bossArena":
				ui.play_alert("☠ Cửa đã khoá!" if world.rules.boss == "enterRoom" and not ev.pull else "☠ Bị kéo vào phòng boss!", "boss")
				_follow(0.0, true)
				shake += 0.6
			"doors": dungeon.set_doors(ev.open)
			"enrage":
				ui.play_alert("%s CUỒNG NỘ!" % String(world.boss_def.name).to_upper(), "bad")
				shake += 0.8
				_freeze(HITSTOP.enrage)
			"bossCast": boss_view.cast(ev.kind)
			"kill":
				if ev.elite:
					_freeze(HITSTOP.elite)
					shake += 0.25
			"skill":
				if ev.id != "roll":
					_freeze(HITSTOP.wrath)
			"bossSpawn": shake += 0.5
			"playerHurt": ui.hurt_flash()
			"win":
				shake += 1.0
				ui.win_flash()
		vfx.on_event(ev)
		sfx.on_event(ev)
	world.events.clear()

## cooldown: an elite wave must not stutter frame after frame
func _freeze(s: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _hitstop_ready:
		return
	hitstop = maxf(hitstop, s)
	_hitstop_ready = now + s + HITSTOP.cooldown

func _follow(dt: float, snap := false) -> void:
	var k := 1.0 if snap else 1.0 - exp(-8.0 * dt)
	focus.x += (world.player.x - focus.x) * k
	focus.z += (world.player.z - focus.z) * k
	var jx := (randf() - 0.5) * shake
	var jz := (randf() - 0.5) * shake
	shake = maxf(0.0, shake - dt * 3.0)
	var dist := float(flags.get("cam", str(CAM_DIST)))
	var fz := focus.z - (7.0 if flags.has("showcase") else 0.0)
	var pitch := deg_to_rad(float(flags.get("pitch", "55")))
	cam.position = Vector3(focus.x + jx, sin(pitch) * dist, fz + cos(pitch) * dist + jz)
	cam.look_at(Vector3(focus.x + jx, 0, fz + jz))
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
		if flags.has("shots") and (ui.mode == flags.shot_mode or screens.mode == flags.shot_mode) and not _lu_shot:
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
			if flags.has("sfx_stats"):
				print("SFX played %s throttled %d music %s" % [sfx.played, sfx.throttled, sfx.track_log])
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
	_check("menu shown", screens.mode == "menu")
	await _shot("menu")
	await _tap(KEY_C)
	_check("C opens character select", screens.mode == "chars")
	await _tap(KEY_2)
	_check("key 2 picks the archer and keeps it", screens.chosen == "archer" and meta.selected == "archer" and meta.to_dict().selected == "archer")
	await _wait(1.2)
	await _shot("select")
	await _tap(KEY_ESCAPE)
	_check("Esc back to menu", screens.mode == "menu")
	await _tap(KEY_ENTER)
	_check("Enter on menu starts at once with the kept hero", started and screens.mode == "none" and world.hero.id == "archer")
	await _tap(KEY_ESCAPE)
	screens.menu.emit()
	await _tap(KEY_C)
	await _tap(KEY_1)
	await _tap(KEY_ENTER)
	_check("Enter on chars closes it", screens.mode == "menu" and meta.selected == "knight")
	await _tap(KEY_ENTER)
	_check("next run uses the knight without asking", started and screens.mode == "none" and world.hero.id == "knight")
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
	_check("Esc pauses", screens.mode == "pause" and world.paused)
	await _shot("pause")
	var t0 := world.time
	await _wait(0.5)
	_check("paused clock frozen", world.time == t0)
	await _tap(KEY_SPACE)
	_check("Space in pause does nothing", screens.mode == "pause")
	await _tap(KEY_ESCAPE)
	_check("Esc resumes", screens.mode == "none" and not world.paused)
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
