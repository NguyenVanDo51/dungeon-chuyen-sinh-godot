class_name Sfx
extends Node
## sounds + music: reads world.events like Vfx; never touches World. Files per slot come from the style's SfxSkin

## slot -> gap = min seconds between plays (per-enemy events fire hundreds/tick), voices = max overlap
const SLOTS := {
	swing = { gap = 0.06, voices = 3 }, swing_holy = { gap = 0.06, voices = 3 }, bow = { gap = 0.05, voices = 3 },
	fire_cast = { gap = 0.1, voices = 2 }, explode = { gap = 0.07, voices = 4 }, meteor = { gap = 0.1, voices = 3 },
	meteor_warn = { gap = 0.15, voices = 2 }, nova = { gap = 0.12, voices = 3 }, thunder = { gap = 0.08, voices = 3 },
	thunder_big = { gap = 0.12, voices = 3 }, beam = { gap = 0.07, voices = 3 }, frost = { gap = 0.1, voices = 2 },
	shield = { gap = 0.1, voices = 2 }, shield_holy = { gap = 0.2, voices = 2 }, arrow_rain = { gap = 0.3, voices = 2 },
	holy_wrath = { gap = 0.3, voices = 1 }, roll = { gap = 0.15, voices = 1 },
	hit = { gap = 0.045, voices = 4 }, kill = { gap = 0.05, voices = 4 }, elite_kill = { gap = 0.1, voices = 2 },
	hurt = { gap = 0.2, voices = 1 }, pickup = { gap = 0.1, voices = 2 }, gold = { gap = 0.07, voices = 3 },
	level_up = { gap = 0.3, voices = 1 }, hidden_unlock = { gap = 0.5, voices = 1 },
	boss_roar = { gap = 1.0, voices = 1 }, enrage = { gap = 1.0, voices = 1 }, boss_bell = { gap = 1.0, voices = 2 },
	boss_cast = { gap = 0.3, voices = 2 }, doors = { gap = 0.3, voices = 1 },
	quest_appear = { gap = 0.3, voices = 1 }, quest_start = { gap = 0.3, voices = 1 }, quest_ok = { gap = 0.3, voices = 1 },
	quest_fail = { gap = 0.3, voices = 1 }, bounce_land = { gap = 0.1, voices = 2 },
	win = { gap = 1.0, voices = 1 }, lose = { gap = 1.0, voices = 1 }, heartbeat = { gap = 0.3, voices = 1 },
	footstep = { gap = 0.12, voices = 2 },
	ui_click = { gap = 0.04, voices = 2 }, ui_back = { gap = 0.04, voices = 2 }, ui_card = { gap = 0.04, voices = 2 },
	ui_buy = { gap = 0.04, voices = 2 }, ui_error = { gap = 0.1, voices = 1 },
}
const EXPLODE_SLOT := { meteor = "meteor", nova = "nova" }
const FADE := 1.2
const STEP_EVERY := 0.33

static var main: Sfx
var skin: SfxSkin
var _players := {}
var _last := {}
var _music: Array[AudioStreamPlayer] = []
var _tracks := {}
var _track := ""
var _cur := 0
var _step_t := 0.0
var _beat_t := 0.0
## debug counters (flag sfx_stats)
var played := {}
var throttled := 0

func _exit_tree() -> void:
	if main == self:
		main = null

static func ui(slot: String) -> void:
	if main:
		main.play(slot)

func build(s: SfxSkin) -> void:
	main = self
	skin = s
	_buses()
	for slot in SLOTS:
		var files := _files(s.folder.path_join(slot), ["ogg", "wav"])
		if files.is_empty():
			continue
		var r := AudioStreamRandomizer.new()
		r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS if files.size() > 2 else AudioStreamRandomizer.PLAYBACK_RANDOM
		r.random_pitch = 1.0 + s.pitch_jitter
		r.random_volume_offset_db = 1.5
		for f in files:
			r.add_stream(-1, load(f))
		var p := AudioStreamPlayer.new()
		p.stream = r
		p.bus = "SFX"
		p.max_polyphony = SLOTS[slot].voices
		p.volume_db = s.gain_db.get(slot, 0.0)
		add_child(p)
		_players[slot] = p
	for f in _files(s.music_folder, ["ogg", "mp3", "wav"]):
		var st: AudioStream = load(f)
		if st is AudioStreamOggVorbis or st is AudioStreamMP3:
			st.loop = true
		elif st is AudioStreamWAV:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_end = int(st.get_length() * st.mix_rate)
		_tracks[f.get_file().get_basename()] = st
	for k in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)

## Master limiter keeps 300-enemy pileups from clipping
static func _buses() -> void:
	if AudioServer.get_bus_index("SFX") >= 0:
		return
	for b in ["SFX", "Music"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, b)
		AudioServer.set_bus_send(i, "Master")
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, lim)

## res-path listing that also works in exports (imported files are remapped)
static func _files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in ResourceLoader.list_directory(dir):
		if f.get_extension().to_lower() in exts:
			out.append(dir.path_join(f))
	out.sort()
	return out

static func set_muted(m: bool) -> void:
	AudioServer.set_bus_mute(0, m)

func play(slot: String) -> void:
	var p: AudioStreamPlayer = _players.get(slot)
	if p == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(slot, -99.0) < SLOTS[slot].gap:
		throttled += 1
		return
	_last[slot] = now
	played[slot] = played.get(slot, 0) + 1
	p.play()

func on_event(ev: Dictionary) -> void:
	match ev.t:
		"slash": play("swing_holy" if ev.hidden else "swing")
		"shot": play("bow")
		"cast": play("fire_cast")
		"explode": play(EXPLODE_SLOT.get(ev.kind, "explode"))
		"meteorWarn": play("meteor_warn")
		"bolt": play("thunder_big" if ev.big else "thunder")
		"beam": play("beam")
		"frostPulse": play("frost")
		"shieldPulse": play("shield_holy" if ev.holy else "shield")
		"arrowRain": play("arrow_rain")
		"skill": play("roll" if ev.id == "roll" else "holy_wrath")
		"hit": play("hit")
		"kill": play("elite_kill" if ev.get("elite", false) else "kill")
		"playerHurt": play("hurt")
		"pickup": play("pickup")
		"gold": play("gold")
		"levelUp": play("level_up")
		"bossSpawn": play("boss_roar")
		"bossWarn": play("boss_bell")
		"bossArena": play("boss_bell")
		"doors":
			if not ev.open:
				play("doors")
		"enrage": play("enrage")
		"bossCast": play("boss_cast")
		"questAppear": play("quest_appear")
		"questStart": play("quest_start")
		"questEnd": play("quest_ok" if ev.success else "quest_fail")
		"bounceLand": play("bounce_land")
		"win": play("win")
		"lose": play("lose")

## track: menu / combat / boss / "" (silence); w null = not in a run
func update(w: World, track: String, dt: float) -> void:
	_set_track(track)
	var target := skin.music_db if _track != "" else -80.0
	for k in 2:
		var m := _music[k]
		var want := target if k == _cur else -80.0
		m.volume_db = move_toward(m.volume_db, want, dt * 70.0 / FADE)
		if m.playing and k != _cur and m.volume_db <= -79.0:
			m.stop()
	if w == null or w.state != "playing" or w.paused:
		return
	var p := w.player
	if p.moving:
		_step_t -= dt
		if _step_t <= 0.0:
			_step_t = STEP_EVERY
			play("footstep")
	var frac := p.hp / p.max_hp
	if frac < 0.3 and p.hp > 0.0:
		_beat_t -= dt
		if _beat_t <= 0.0:
			_beat_t = lerpf(0.55, 0.95, frac / 0.3)
			play("heartbeat")

func _set_track(t: String) -> void:
	if t == _track:
		return
	_track = t
	_cur = 1 - _cur
	var m := _music[_cur]
	if not _tracks.has(t):
		m.stop()
		return
	m.stream = _tracks[t]
	m.volume_db = -40.0
	m.play()
