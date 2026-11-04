class_name HeroPreview
extends SubViewportContainer
## the chosen hero turning slowly on a pedestal, in its own little 3D world (menu + character screen)
## built once (all heroes); Screens moves it between panels instead of rebuilding (each hero is a glTF instance)

const HEIGHT := 2.0
const SPIN := 0.6

var _vp: SubViewport
var _style: Style
var _views := {}
var _shown: ActorViews.PlayerView

func _init(style: Style, px := Vector2(340, 380)) -> void:
	_style = style
	stretch = true
	custom_minimum_size = px
	mouse_filter = MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8a90d8")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-35, 30, 0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ff8fd8")
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(-20, 200, 0)
	_vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.transform = Transform3D(Basis(), Vector3(0, 1.7, 5.6)).looking_at(Vector3(0, 0.95, 0))
	_vp.add_child(cam)
	# every hero up front: a hero built on the spot shows its rest pose for a few frames
	for c in Characters.IDS:
		_build(Characters.DEFS[c].model)

func _build(model: String) -> void:
	if _views.has(model):
		return
	var hv := ActorViews.PlayerView.new()
	_vp.add_child(hv)
	hv.build(_style.hero(model))
	ActorViews.fit_height(hv.model, HEIGHT)
	hv.visible = false
	_views[model] = hv

## model = Characters.DEFS[*].model
func show_hero(model: String) -> void:
	_build(model)
	_shown = _views[model]
	for m in _views:
		_views[m].visible = _views[m] == _shown

## off = the viewport stops rendering (mid-run it would cost frames for nothing)
func set_active(on: bool) -> void:
	visible = on
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)

func _process(dt: float) -> void:
	if _shown:
		_shown.model.rotation.y += SPIN * dt
