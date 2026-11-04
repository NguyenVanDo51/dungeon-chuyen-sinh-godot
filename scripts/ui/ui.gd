class_name Ui
extends Control
## HUD, level-up cards, menu / pause / end screens, minimap, edge arrows, alerts, damage numbers

signal start_pressed
signal resume_pressed
signal restart_pressed
signal menu_pressed
signal card_picked(i: int)

const PINK := Color("#ff8fd8")
const CYAN := Color("#5ff3ff")
const GOLD := Color("#ffd36e")
const MINT := Color("#7dff9a")
const INK := Color("#0d1030")
const PANEL := Color("#151a46e6")
const INPUT_LOCK := 0.3

var hud: Control
var xp_fill: ColorRect
var lvl: Label
var timer: Label
var hp_fill: ColorRect
var slots_box: HBoxContainer
var skill_box: Panel
var skill_cd: ColorRect
var boss_box: VBoxContainer
var boss_name: Label
var boss_fill: ColorRect
var quest_box: PanelContainer
var quest_title: Label
var quest_detail: Label
var quest_fill: ColorRect
var minimap: Minimap
var boss_arrow: Control
var quest_arrow: Control
var alert: Label
var banner: VBoxContainer
var banner_name: Label
var flash: ColorRect
var dmg_layer: Control
var _dmg: Array = []  # {label, x, z, t, life}

var overlay: ColorRect
var menu_panel: PanelContainer
var pause_panel: PanelContainer
var end_panel: PanelContainer
var end_title: Label
var end_stats: Label
var end_build: HBoxContainer
var lu_panel: PanelContainer
var cards_box: HBoxContainer
var mode := "menu"
var _lu_shown_at := 0.0
var _lu_count := 0
var _slots_key := ""
var _alert_t := 0.0
var _banner_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 16
	theme = th
	_build_hud()
	dmg_layer = Control.new()
	dmg_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dmg_layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dmg_layer)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	flash.color = Color(1, 0.95, 0.8, 0)
	flash.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(flash)
	_build_overlays()
	show_menu()

# ---------- builders ----------

static func _style(bg: Color, border: Color, radius := 14, bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12; s.content_margin_right = 12; s.content_margin_top = 8; s.content_margin_bottom = 8
	return s

func _label(text: String, size := 16, color := Color.WHITE, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(l)
	return l

func _bar(parent: Control, bg: Color, fg: Color, h: float) -> ColorRect:
	var back := ColorRect.new()
	back.color = bg
	back.custom_minimum_size.y = h
	back.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.color = fg
	fill.mouse_filter = MOUSE_FILTER_IGNORE
	fill.set_anchors_preset(PRESET_LEFT_WIDE)
	fill.anchor_right = 0.0
	back.add_child(fill)
	return fill

## anchor point (ax, ay) in 0..1 of the parent, then a rect offset from it
static func _at(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax; c.anchor_right = ax; c.anchor_top = ay; c.anchor_bottom = ay
	c.offset_left = x; c.offset_top = y; c.offset_right = x + w; c.offset_bottom = y + h

func _set_fill(fill: ColorRect, k: float) -> void:
	fill.anchor_right = clampf(k, 0.0, 1.0)
	fill.offset_right = 0

func _button(text: String, alt: bool, cb: Callable, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	var col := PINK if alt else CYAN
	b.add_theme_stylebox_override("normal", _style(col, col.lightened(0.2), 12, 0))
	b.add_theme_stylebox_override("hover", _style(col.lightened(0.15), Color.WHITE, 12, 2))
	b.add_theme_stylebox_override("pressed", _style(col.darkened(0.1), Color.WHITE, 12, 2))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color.WHITE, 12, 2))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, INK)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	hud.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(hud)
	var xb := VBoxContainer.new()
	xb.anchor_right = 1.0
	xb.offset_bottom = 12
	xb.mouse_filter = MOUSE_FILTER_IGNORE
	hud.add_child(xb)
	xp_fill = _bar(xb, Color("#1c2250"), PINK, 12)
	lvl = _label("Lv 1", 22, GOLD, hud)
	_at(lvl, 1, 0, -110, 16, 92, 30)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer = _label("00:00", 30, Color.WHITE, hud)
	_at(timer, 0.5, 0, -80, 14, 160, 36)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.add_theme_color_override("font_shadow_color", Color(CYAN, 0.6))
	# boss bar
	boss_box = VBoxContainer.new()
	_at(boss_box, 0.5, 0, -280, 54, 560, 40)
	boss_box.mouse_filter = MOUSE_FILTER_IGNORE
	hud.add_child(boss_box)
	boss_name = _label("LICH", 16, Color("#d9c8ff"), boss_box)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_fill = _bar(boss_box, Color("#1a0f30"), Color("#b04cff"), 14)
	# quest box
	quest_box = PanelContainer.new()
	quest_box.add_theme_stylebox_override("panel", _style(Color("#0b0e2acc"), Color(CYAN, 0.4), 10, 1))
	_at(quest_box, 1, 0, -284, 60, 270, 0)
	quest_box.custom_minimum_size = Vector2(270, 0)
	quest_box.mouse_filter = MOUSE_FILTER_IGNORE
	hud.add_child(quest_box)
	var qv := VBoxContainer.new()
	qv.mouse_filter = MOUSE_FILTER_IGNORE
	quest_box.add_child(qv)
	quest_title = _label("", 15, CYAN, qv)
	quest_detail = _label("", 13, Color(1, 1, 1, 0.9), qv)
	quest_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_detail.custom_minimum_size.x = 246
	quest_fill = _bar(qv, Color("#1a1f4a"), CYAN, 6)
	# bottom bar: hp + skill + slots
	var bottom := VBoxContainer.new()
	_at(bottom, 0.5, 1, -300, -120, 600, 104)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 14)
	bottom.mouse_filter = MOUSE_FILTER_IGNORE
	hud.add_child(bottom)
	var hp_wrap := CenterContainer.new()
	hp_wrap.mouse_filter = MOUSE_FILTER_IGNORE
	bottom.add_child(hp_wrap)
	var hp_back := ColorRect.new()
	hp_back.color = Color("#2a0f2a")
	hp_back.custom_minimum_size = Vector2(280, 12)
	hp_back.mouse_filter = MOUSE_FILTER_IGNORE
	hp_wrap.add_child(hp_back)
	hp_fill = ColorRect.new()
	hp_fill.color = Color("#ff5aa0")
	hp_fill.set_anchors_preset(PRESET_LEFT_WIDE)
	hp_fill.mouse_filter = MOUSE_FILTER_IGNORE
	hp_back.add_child(hp_fill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	skill_box = Panel.new()
	skill_box.custom_minimum_size = Vector2(64, 64)
	skill_box.add_theme_stylebox_override("panel", _style(Color("#1c2250cc"), Color(MINT, 0.6), 14, 2))
	skill_box.clip_contents = true
	skill_box.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(skill_box)
	var sic := _label(Data.SKILL.icon, 26, Color.WHITE, skill_box)
	_at(sic, 0, 0, 0, 4, 64, 36)
	sic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kbd := _label("Space", 10, Color(1, 1, 1, 0.8), skill_box)
	_at(kbd, 0, 0, 0, 46, 64, 14)
	kbd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_cd = ColorRect.new()
	skill_cd.color = Color(0.05, 0.06, 0.19, 0.7)
	skill_cd.anchor_right = 1.0
	skill_cd.anchor_bottom = 1.0
	skill_cd.mouse_filter = MOUSE_FILTER_IGNORE
	skill_box.add_child(skill_cd)
	slots_box = HBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 8)
	slots_box.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(slots_box)
	minimap = Minimap.new()
	minimap.anchor_left = 1; minimap.anchor_right = 1; minimap.anchor_top = 1; minimap.anchor_bottom = 1
	hud.add_child(minimap)
	boss_arrow = _edge_arrow("☠", Color("#6b3cff"))
	quest_arrow = _edge_arrow("★", Color("#1b6f8a"))
	alert = _label("", 38, Color("#ffd0e0"), hud)
	_at(alert, 0.5, 0, -500, 180, 1000, 60)
	alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert.add_theme_color_override("font_shadow_color", Color("#ff4d6d"))
	alert.modulate.a = 0
	banner = VBoxContainer.new()
	_at(banner, 0.5, 0, -400, 240, 800, 120)
	banner.pivot_offset = Vector2(400, 60)
	banner.mouse_filter = MOUSE_FILTER_IGNORE
	banner.modulate.a = 0
	hud.add_child(banner)
	var ba := _label("⚡ KỸ NĂNG ẨN ⚡", 22, GOLD, banner)
	ba.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_name = _label("", 60, Color.WHITE, banner)
	banner_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_name.add_theme_color_override("font_shadow_color", GOLD)

func _edge_arrow(icon: String, col: Color) -> Control:
	var a := Control.new()
	a.mouse_filter = MOUSE_FILTER_IGNORE
	hud.add_child(a)
	var tip := Polygon2D.new()
	tip.polygon = PackedVector2Array([Vector2(10, -8), Vector2(24, 0), Vector2(10, 8)])
	tip.color = PINK
	a.add_child(tip)
	var disc := Panel.new()
	disc.position = Vector2(-14, -14)
	disc.size = Vector2(28, 28)
	disc.add_theme_stylebox_override("panel", _style(Color(col, 0.85), Color(col.lightened(0.4), 0.8), 14, 1))
	disc.mouse_filter = MOUSE_FILTER_IGNORE
	disc.pivot_offset = Vector2(14, 14)
	a.add_child(disc)
	var l := _label(icon, 16, Color.WHITE, disc)
	l.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	a.visible = false
	return a

func _panel(parent: Control) -> VBoxContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	c.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(c)
	var p := PanelContainer.new()
	var s := _style(PANEL, Color(CYAN, 0.4), 22, 2)
	s.content_margin_left = 34; s.content_margin_right = 34; s.content_margin_top = 28; s.content_margin_bottom = 28
	s.shadow_color = Color(CYAN, 0.2)
	s.shadow_size = 30
	p.add_theme_stylebox_override("panel", s)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v

func _title(text: String, size: int, parent: Node) -> Label:
	var t := _label(text, size, PINK, parent)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_shadow_color", Color(PINK, 0.4))
	t.add_theme_constant_override("shadow_outline_size", 12)
	return t

func _build_overlays() -> void:
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.color = Color("#070920b8")
	add_child(overlay)
	# menu
	var mv := _panel(overlay)
	menu_panel = mv.get_parent()
	_title("Dungeon Chuyển Sinh", 56, mv)
	var sub := _label("Sinh tồn 8 phút · hạ Lich để thắng", 17, Color(1, 1, 1, 0.85), mv)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color(CYAN, 0.08), CYAN, 14, 2))
	mv.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	var K := Data.KNIGHT
	_label("%s %s · %s" % [K.icon, K.name, K.role], 26, Color.WHITE, cv)
	_label(K.description, 14, Color(1, 1, 1, 0.9), cv)
	_label("%d máu · giảm %d%% sát thương nhận · sát thương ×%.2f" % [K.hp, K.damage_reduction * 100, K.damage_mul], 14, Color(1, 1, 1, 0.8), cv)
	_label("Vũ khí: %s %s" % [Data.WEAPONS.holySword.icon, Data.WEAPONS.holySword.name], 14, GOLD, cv)
	_label(K.passive_text, 14, MINT, cv)
	_label("Kỹ năng %s %s (Space): %s" % [Data.SKILL.icon, Data.SKILL.name, Data.SKILL.description], 14, CYAN, cv)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_child(hb)
	_button("Bắt đầu (Enter)", false, func() -> void: start_pressed.emit(), hb)
	var keys := _label("W A S D: di chuyển   ·   vũ khí tự bắn   ·   Space: kỹ năng   ·   1 2 3: chọn thẻ   ·   Esc: tạm dừng", 14, Color(1, 1, 1, 0.75), mv)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# pause
	var pv := _panel(overlay)
	pause_panel = pv.get_parent()
	_title("Tạm dừng", 44, pv)
	var pb := HBoxContainer.new()
	pb.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(pb)
	_button("Tiếp tục (Esc)", false, func() -> void: resume_pressed.emit(), pb)
	_button("Chơi lại", true, func() -> void: restart_pressed.emit(), pb)
	_button("Về menu", true, func() -> void: menu_pressed.emit(), pb)
	# end
	var ev := _panel(overlay)
	end_panel = ev.get_parent()
	end_title = _title("", 52, ev)
	end_stats = _label("", 20, CYAN, ev)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_build = HBoxContainer.new()
	end_build.alignment = BoxContainer.ALIGNMENT_CENTER
	end_build.add_theme_constant_override("separation", 8)
	ev.add_child(end_build)
	var eb := HBoxContainer.new()
	eb.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_child(eb)
	_button("Chơi lại (Enter)", false, func() -> void: restart_pressed.emit(), eb)
	_button("Về menu", true, func() -> void: menu_pressed.emit(), eb)
	# level-up
	var lv := _panel(overlay)
	lu_panel = lv.get_parent()
	var head := _label("LÊN CẤP!", 34, GOLD, lv)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 16)
	cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_child(cards_box)

# ---------- screens ----------

func _show_only(p: Control) -> void:
	overlay.visible = p != null
	for x in [menu_panel, pause_panel, end_panel, lu_panel]:
		x.get_parent().visible = x == p

func show_menu() -> void:
	mode = "menu"
	hud.visible = false
	_show_only(menu_panel)

func show_pause() -> void:
	mode = "pause"
	_show_only(pause_panel)

func hide_all() -> void:
	mode = "none"
	_show_only(null)

func show_game() -> void:
	hide_all()
	hud.visible = true
	_slots_key = ""
	for d in _dmg:
		d.label.visible = false

func show_end(w: World) -> void:
	mode = "end"
	hud.visible = false
	var won := w.state == "won"
	end_title.text = "Chiến thắng!" if won else "Thất bại"
	end_title.add_theme_color_override("font_color", PINK if won else Color("#ff6b8a"))
	var qd := 0
	for q in w.quest_log:
		qd += 1 if q.success else 0
	end_stats.text = "%s thời gian   ·   cấp %d   ·   %d quái hạ   ·   %d kỹ năng ẩn   ·   %d/%d nhiệm vụ" % [fmt_time(w.time), w.level, w.kills, w.build.hidden.size(), qd, w.quests.size()]
	_fill_slots(end_build, w.build)
	_show_only(end_panel)

func show_level_up(w: World) -> void:
	mode = "levelUp"
	for c in cards_box.get_children():
		c.queue_free()
	_lu_count = w.current_offers.size()
	for i in _lu_count:
		cards_box.add_child(_card(w.current_offers[i], w, i))
	_lu_shown_at = Time.get_ticks_msec() / 1000.0
	_show_only(lu_panel)

func pick_card(i: int) -> void:
	if mode != "levelUp" or i >= _lu_count or Time.get_ticks_msec() / 1000.0 - _lu_shown_at < INPUT_LOCK:
		return
	card_picked.emit(i)

func _card(o: Dictionary, w: World, idx: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(230, 250)
	var is_stat: bool = o.type != "heal" and not Data.is_weapon(o.id)
	var border := GOLD if is_stat else CYAN
	var st := _style(Color("#1b2160"), Color(border, 0.35), 18, 2)
	st.content_margin_left = 16; st.content_margin_right = 16; st.content_margin_top = 14
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = MOUSE_FILTER_STOP
	p.mouse_entered.connect(func() -> void: st.border_color = border)
	p.mouse_exited.connect(func() -> void: st.border_color = Color(border, 0.35))
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pick_card(idx))
	var v := VBoxContainer.new()
	v.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_child(v)
	var add_wrap := func(text: String, size: int, col: Color) -> void:
		var l := _label(text, size, col, v)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 198
	_label("%d" % (idx + 1), 12, Color(1, 1, 1, 0.6), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if o.type == "heal":
		_label("💖", 40, Color.WHITE, v)
		_label("Hồi máu", 22, Color.WHITE, v)
		add_wrap.call("Hồi %d máu." % Data.BALANCE.heal_amount, 14, Color(1, 1, 1, 0.9))
		return p
	var def := Data.item_def(o.id)
	_label(def.icon, 40, Color.WHITE, v)
	_label(def.name, 22, Color.WHITE, v)
	var badge := _label("MỚI" if o.type == "new" else "Cấp %d → %d" % [o.to_level - 1, o.to_level], 12, INK, v)
	badge.add_theme_stylebox_override("normal", _style(MINT if o.type == "new" else CYAN, Color(0, 0, 0, 0), 8, 0))
	badge.size_flags_horizontal = SIZE_SHRINK_BEGIN
	add_wrap.call(def.description, 14, Color(1, 1, 1, 0.9))
	if Data.is_weapon(o.id):
		add_wrap.call("Cần: %s" % Data.STATS[def.paired].name, 13, GOLD)
		if o.type == "upgrade" and o.to_level == Build.MAX_LEVEL and w.build.has(def.paired):
			add_wrap.call("⚡ Mở kỹ năng ẩn: %s" % def.hidden_name, 13, Color.WHITE)
	else:
		var powers := []
		var awakens := []
		for id in Data.WEAPONS:
			var wd: Dictionary = Data.WEAPONS[id]
			if wd.paired == o.id:
				powers.append(wd.name)
				if w.build.level_of(id) == Build.MAX_LEVEL and not w.build.hidden.has(id):
					awakens.append(wd.hidden_name)
		if powers.size() > 0:
			add_wrap.call("Kích hoạt kỹ năng ẩn cho: %s" % ", ".join(powers), 13, GOLD)
		if o.type == "new" and awakens.size() > 0:
			add_wrap.call("⚡ Mở ngay: %s" % ", ".join(awakens), 13, Color.WHITE)
	return p

func _slot(s: Variant, b: Build) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(64, 64)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	if s == null:
		p.add_theme_stylebox_override("panel", _style(Color("#1c225066"), Color(1, 1, 1, 0.13), 14, 2))
		return p
	var weapon := Data.is_weapon(s.id)
	var awake: bool = weapon and b.hidden.has(s.id)
	var col := CYAN if weapon else GOLD
	var st := _style(Color("#1c2250cc"), GOLD if awake else Color(col, 0.35), 14, 2)
	if awake:
		st.shadow_color = Color(GOLD, 0.6)
		st.shadow_size = 10
	p.add_theme_stylebox_override("panel", st)
	var def := Data.item_def(s.id)
	var ic := _label(def.icon, 24, Color.WHITE, p)
	ic.set_anchors_preset(PRESET_CENTER_TOP)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.position = Vector2(-32, 4)
	ic.size = Vector2(64, 30)
	var nm := _label(def.name, 10, Color(1, 1, 1, 0.85), p)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(-8, 34)
	nm.size = Vector2(80, 14)
	nm.clip_text = true
	for k in 5:
		var d := ColorRect.new()
		d.size = Vector2(6, 6)
		d.position = Vector2(14 + k * 8, 52)
		d.color = col if k < s.level else Color(1, 1, 1, 0.13)
		d.mouse_filter = MOUSE_FILTER_IGNORE
		p.add_child(d)
	if awake:
		var star := _label("★", 18, GOLD, p)
		star.position = Vector2(50, -12)
	return p

func _fill_slots(box: HBoxContainer, b: Build) -> void:
	for c in box.get_children():
		c.queue_free()
	for i in Build.MAX_SLOTS:
		box.add_child(_slot(b.slots[i] if i < b.slots.size() else null, b))

# ---------- per frame ----------

static func fmt_time(t: float) -> String:
	var s := int(floor(t))
	return "%02d:%02d" % [s / 60, s % 60]

func play_alert(text: String) -> void:
	alert.text = text
	_alert_t = 2.4

func play_unlock(id: String) -> void:
	banner_name.text = Data.WEAPONS[id].hidden_name
	_banner_t = 2.4
	flash.color.a = 0.35

func update_hud(w: World, cam: Camera3D, dt: float) -> void:
	_set_fill(xp_fill, w.xp / Data.xp_to_next(w.level))
	lvl.text = "Lv %d" % w.level
	timer.text = fmt_time(w.time)
	_set_fill(hp_fill, w.player.hp / w.player.max_hp)
	hp_fill.anchor_right = clampf(w.player.hp / w.player.max_hp, 0.0, 1.0)
	var bi := w.boss_index()
	boss_box.visible = bi >= 0
	if bi >= 0:
		_set_fill(boss_fill, w.enemies.hp[bi] / Data.LICH.hp)
		boss_name.text = "LICH" + ("   CUỒNG NỘ!" if w.boss.enraged and int(w.time * 4) % 2 == 0 else ("   " if w.boss.enraged else ""))
	var k := w.skill_cd / w.skill_cd_max
	skill_cd.anchor_top = 1.0 - k
	skill_cd.offset_top = 0
	var q := w.quest
	quest_box.visible = q != null
	if q != null:
		var st := _quest_status(q)
		quest_title.text = "★ " + Data.QUEST_NAMES[q.kind]
		quest_detail.text = st[0]
		_set_fill(quest_fill, st[1])
	var hidden_n := w.build.hidden.size()
	var key := ""
	for s in w.build.slots:
		key += "%s%d," % [s.id, s.level]
	key += str(hidden_n)
	if key != _slots_key:
		_slots_key = key
		_fill_slots(slots_box, w.build)
	minimap.tick(w, dt)
	# off-screen boss / quest → arrow on the screen edge
	_point_arrow(boss_arrow, cam, Vector3(w.enemies.x[bi], 1.5, w.enemies.z[bi]) if bi >= 0 else Vector3.INF)
	var qt := Vector3.INF
	if q != null:
		var t := Quests.arrow_target(w, q)
		qt = Vector3(t.x, 1, t.y)
	_point_arrow(quest_arrow, cam, qt)
	if _alert_t > 0.0:
		_alert_t -= dt
		alert.modulate.a = clampf(minf(_alert_t / 0.4, (2.4 - _alert_t) / 0.2), 0.0, 1.0)
	if _banner_t > 0.0:
		_banner_t -= dt
		banner.modulate.a = clampf(minf(_banner_t / 0.5, (2.4 - _banner_t) / 0.2), 0.0, 1.0)
		banner.scale = Vector2.ONE * (1.0 + 0.08 * maxf(0.0, _banner_t - 2.1) / 0.3)
	flash.color.a = maxf(0.0, flash.color.a - dt * 0.7)
	_update_dmg(cam, dt)

func _quest_status(q: Quests.State) -> Array:
	var left := func(s: float) -> String: return "còn %ds" % maxi(0, ceili(s))
	var Q := Data.QUESTS
	if q.phase == "waiting":
		return ["Chạy tới vòng rune ★ · " + left.call(Q.window - q.t), 1.0 - q.t / Q.window]
	var d := q.data
	match q.kind:
		"bounce":
			return ["Đứng vào chỗ bóng rơi · %d/%d · trượt %d/%d" % [d.progress + d.misses, Q.bounce.count, d.misses, Q.bounce.max_miss], float(d.progress + d.misses) / Q.bounce.count]
		"hold":
			return ["Đứng trong vòng · %d/%ds" % [floori(d.progress), Q.hold.need], d.progress / Q.hold.need]
		"crystal":
			return ["Tinh thể %d%% · %s" % [maxi(0, roundi(d.hp / Q.crystal.hp * 100.0)), left.call(Q.crystal.seconds - q.t)], maxf(0.0, d.hp / Q.crystal.hp)]
		"thief":
			return ["Hạ kẻ trộm trước khi nó trốn · " + left.call(Q.thief.seconds - q.t), 1.0 - q.t / Q.thief.seconds]
	return ["", 0.0]

func _point_arrow(a: Control, cam: Camera3D, at: Vector3) -> void:
	if at == Vector3.INF or cam.is_position_behind(at):
		a.visible = false
		return
	var vp := get_viewport_rect().size
	var p := cam.unproject_position(at)
	var m := 40.0
	if p.x >= m and p.x <= vp.x - m and p.y >= m and p.y <= vp.y - m:
		a.visible = false
		return
	var c := vp / 2.0
	var d := p - c
	var s := minf((c.x - m) / maxf(absf(d.x), 1e-4), (c.y - m) / maxf(absf(d.y), 1e-4))
	a.visible = true
	a.position = c + d * s
	a.rotation = d.angle()
	a.get_child(1).rotation = -d.angle()

# ---------- damage numbers ----------

func add_damage(x: float, z: float, amount: float) -> void:
	_spawn_dmg(x, z, str(roundi(amount)), amount >= 40.0)

func add_text(x: float, z: float, text: String) -> void:
	_spawn_dmg(x, z, text, true)

func _spawn_dmg(x: float, z: float, text: String, big: bool) -> void:
	var d: Dictionary = {}
	for e in _dmg:
		if e.t >= e.life:
			d = e
			break
	if d.is_empty():
		if _dmg.size() >= 80:
			return
		var l := _label("", 15, Color.WHITE, dmg_layer)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color("#1a1040"))
		d = { label = l, x = 0.0, z = 0.0, t = 0.0, life = 0.7, ox = 0.0 }
		_dmg.append(d)
	d.label.text = text
	d.label.add_theme_font_size_override("font_size", 22 if big else 15)
	d.label.add_theme_color_override("font_color", GOLD if big else Color.WHITE)
	d.x = x; d.z = z; d.t = 0.0; d.ox = randf_range(-12.0, 12.0)
	d.label.visible = true

func _update_dmg(cam: Camera3D, dt: float) -> void:
	for d in _dmg:
		if d.t >= d.life:
			d.label.visible = false
			continue
		d.t += dt
		var p := cam.unproject_position(Vector3(d.x, 1.6, d.z))
		var k: float = d.t / d.life
		d.label.position = p + Vector2(d.ox - 10.0, -30.0 * k - 10.0)
		d.label.modulate.a = 1.0 - k * k
