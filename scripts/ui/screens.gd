class_name Screens
extends Control
## menu (start screen with the chosen hero), character select, shop, dungeon floors, pause, end
## the hero is chosen once on its own screen and kept (Meta.selected); every run starts with it

signal start(c: String, run: Dictionary)
## an owned hero was picked on the character screen (main saves it)
signal select(c: String)
signal restart
signal next_floor
signal floors
signal resume
signal menu
signal buy(c: String)
signal upgrade(id: String)

const PINK := Ui.PINK
const CYAN := Ui.CYAN
const GOLD := Ui.GOLD
const MINT := Ui.MINT
const DIM := Color(1, 1, 1, 0.75)
const INK := Ui.INK

## loading | menu | floors | chars | shop | pause | end | none
var mode := "loading"
var meta: Meta
## the hero every run starts with (= meta.selected, always owned)
var chosen: String = Characters.DEFAULT
## the hero shown on the character screen (may be a locked one being looked at)
var browsing: String = Characters.DEFAULT
var tab := "upgrades"
## set by main before the first screen; null = no 3D preview
var style: Style
var preview: HeroPreview
var dungeon_id := "crypt"
var _end_enter := "menu"
var _overlay: ColorRect
var _box: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.color = Color("#070920b8")
	add_child(_overlay)
	_overlay.visible = false

## 1.0 → "1", 1.85 → "1.85" (like the TS copy)
static func num(x: float) -> String:
	return str(int(x)) if x == floorf(x) else str(x)

func coin(n: float) -> String:
	return "🪙 %d" % floori(n)

## fresh panel for a screen; the old one is dropped (screens are cheap to rebuild), the 3D preview is kept
func _open(m: String) -> VBoxContainer:
	if preview:
		if preview.get_parent():
			preview.get_parent().remove_child(preview)
		preview.set_active(false)
	for c in _overlay.get_children():
		c.queue_free()
	_box = Ui._panel(_overlay)
	mode = m
	_overlay.visible = true
	return _box

func hide_all() -> void:
	mode = "none"
	_overlay.visible = false
	if preview:
		preview.set_active(false)

## left column of the menu / character screen: the hero turning + its name
func _hero_column(parent: Node, id: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)
	if style and not preview:
		preview = HeroPreview.new(style)
	if preview:
		col.add_child(preview)
		preview.show_hero(Characters.DEFS[id].model)
		preview.set_active(true)
	var c: Dictionary = Characters.DEFS[id]
	_center(Ui._label("%s %s" % [c.icon, c.name], 26, Color.WHITE, col))
	_center(Ui._label(c.role, 15, CYAN, col))
	return col

func _row(parent: Node) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	parent.add_child(hb)
	return hb

func _center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _wrap(text: String, size: int, col: Color, parent: Node, width := 0.0) -> Label:
	var l := Ui._label(text, size, col, parent)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width if width > 0.0 else (420.0 if mode == "chars" else 300.0)
	return l

## clickable card; on = highlighted border, locked = dimmed
func _card(parent: Node, on: bool, locked: bool, cb: Callable, width := 320.0) -> VBoxContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	var border := GOLD if on else Color(CYAN, 0.35)
	var st := Ui._style(Color("#1b2160") if not locked else Color("#141838"), border, 16, 3 if on else 2)
	st.content_margin_left = 16; st.content_margin_right = 16; st.content_margin_top = 12; st.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = MOUSE_FILTER_STOP
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			cb.call())
	if locked:
		p.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v

# ---------- main menu ----------

func show_menu() -> void:
	_fix_chosen()
	var v := _open("menu")
	Ui._title("Dungeon Chuyển Sinh", 56, v)
	var hb := _row(v)
	hb.add_theme_constant_override("separation", 40)
	_hero_column(hb, chosen)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size.x = 280
	col.add_theme_constant_override("separation", 12)
	hb.add_child(col)
	_center(Ui._label(coin(meta.gold) + " vàng", 18, GOLD, col))
	Ui._button("Sinh tồn (Enter)", false, play_survival, col)
	Ui._button("Dungeon", false, show_floors, col)
	Ui._button("Nhân vật (C)", true, show_chars, col)
	Ui._button("Cửa hàng", true, show_shop, col)
	_center(_wrap("Sống sót 8 phút trong dungeon dị giới. Làm nhiệm vụ để lên cấp nhanh, build đúng đồ để mở kỹ năng ẩn.", 13, DIM, col, 280))

func play_survival() -> void:
	_fix_chosen()
	start.emit(chosen, { kind = "survival" })

## a hero no longer owned (or a broken save) falls back to the first owned one
func _fix_chosen() -> void:
	if not chosen in meta.owned:
		chosen = meta.owned[0] if meta.owned.size() > 0 else Characters.DEFAULT

# ---------- character select ----------

## chars screen: stacked in `parent` (a column); shop: side by side
func _char_cards(parent: Node, on_pick: Callable) -> void:
	var row: Node = parent if mode == "chars" else _row(parent)
	for k in Characters.IDS.size():
		var id: String = Characters.IDS[k]
		var c: Dictionary = Characters.DEFS[id]
		var owned := id in meta.owned
		var v := _card(row, mode == "chars" and id == browsing, not owned, on_pick.bind(id), 460.0 if mode == "chars" else 320.0)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.mouse_filter = MOUSE_FILTER_IGNORE
		v.add_child(head)
		Ui._label("%s  %d. %s · %s" % [c.icon, k + 1, c.name, c.role], 20, Color.WHITE, head)
		if mode == "chars" and id == chosen:
			var tag := Ui._label("ĐANG DÙNG", 11, INK, head)
			tag.add_theme_stylebox_override("normal", Ui._style(MINT, Color(0, 0, 0, 0), 8, 0))
			tag.size_flags_vertical = SIZE_SHRINK_CENTER
		_wrap(c.description, 13, Color(1, 1, 1, 0.9), v)
		_wrap("❤ %d máu · 🛡 %d%% giáp · ⚔ ×%s" % [c.hp, roundi(c.damage_reduction * 100), num(c.damage_mul)], 13, DIM, v)
		_wrap("Vũ khí riêng: %s %s" % [Items.WEAPONS[c.weapon].icon, Items.WEAPONS[c.weapon].name], 13, GOLD, v)
		_wrap("Nội tại: " + c.passive_text, 13, MINT, v)
		var sk: Dictionary = Characters.SKILLS[c.skill]
		_wrap("Kỹ năng (Space): %s %s — %s" % [sk.icon, sk.name, sk.description], 13, CYAN, v)
		if not owned:
			var hb := HBoxContainer.new()
			v.add_child(hb)
			Ui._label("🔒 " + coin(c.price), 14, GOLD, hb)
			var b := Ui._button("Mua", false, buy.emit.bind(id), hb)
			b.disabled = meta.gold < c.price

## its own screen, reached from the menu; picking an owned hero keeps it for every later run
func show_chars() -> void:
	_fix_chosen()
	if mode != "chars":
		browsing = chosen
	var v := _open("chars")
	Ui._title("Chọn nhân vật", 44, v)
	var hb := _row(v)
	hb.add_theme_constant_override("separation", 28)
	_hero_column(hb, browsing)
	var cards := VBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 10)
	hb.add_child(cards)
	_char_cards(cards, pick)
	_center(_wrap("Chọn một lần là xong: mọi ván sau (Sinh tồn lẫn Dungeon) đều dùng nhân vật này.   " + coin(meta.gold), 13, DIM, v, 680))
	_center_btn(v, "Xong (Enter / Esc)", show_menu)

## owned: becomes the hero of every run (saved) · locked: only looked at (its card has the buy button)
func pick(c: String) -> void:
	browsing = c
	if c in meta.owned and c != chosen:
		chosen = c
		select.emit(c)
	if mode == "chars":
		show_chars()

# ---------- shop ----------

func show_shop() -> void:
	var v := _open("shop")
	Ui._title("Cửa hàng", 44, v)
	_center(Ui._label(coin(meta.gold) + " vàng", 18, GOLD, v))
	var tabs := _row(v)
	Ui._button("Nhân vật", tab != "chars", _set_tab.bind("chars"), tabs)
	Ui._button("Nâng cấp", tab != "upgrades", _set_tab.bind("upgrades"), tabs)
	if tab == "chars":
		_char_cards(v, func(_c: String) -> void: pass)
	else:
		for id in Meta.UPGRADE_IDS:
			var u: Dictionary = Meta.UPGRADES[id]
			var l: int = meta.upgrades[id]
			var mx := l >= Meta.UPGRADE_MAX
			var price := 0 if mx else Meta.upgrade_price(id, l)
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 12)
			v.add_child(hb)
			Ui._label(u.icon, 24, Color.WHITE, hb).custom_minimum_size.x = 36
			var nm := VBoxContainer.new()
			nm.custom_minimum_size.x = 220
			hb.add_child(nm)
			Ui._label(u.name, 17, Color.WHITE, nm)
			Ui._label(u.per + " mỗi cấp", 12, DIM, nm)
			var dots := HBoxContainer.new()
			dots.alignment = BoxContainer.ALIGNMENT_CENTER
			dots.custom_minimum_size.x = 110
			hb.add_child(dots)
			for k in Meta.UPGRADE_MAX:
				var d := ColorRect.new()
				d.custom_minimum_size = Vector2(12, 12)
				d.color = GOLD if k < l else Color(1, 1, 1, 0.15)
				d.size_flags_vertical = SIZE_SHRINK_CENTER
				dots.add_child(d)
			var b := Ui._button("Tối đa" if mx else coin(price), false, upgrade.emit.bind(id), hb)
			b.custom_minimum_size.x = 110
			b.disabled = mx or meta.gold < price
		_center(Ui._label("Nâng cấp áp dụng cho mọi chế độ, từ ván sau.", 13, DIM, v))
	_center_btn(v, "Quay lại (Esc)", show_menu)

func _set_tab(t: String) -> void:
	tab = t
	show_shop()

func _center_btn(v: Node, text: String, cb: Callable) -> void:
	Ui._button(text, true, cb, _row(v))

# ---------- dungeon floors ----------

func show_floors() -> void:
	var d: Dictionary = Dungeons.DEFS[dungeon_id]
	var v := _open("floors")
	Ui._title(d.name, 44, v)
	_center(_wrap("Càng vào sâu quái càng mạnh. Cuối tầng là phòng boss: bước vào là cửa khoá. Mỗi tầng chơi lại từ cấp 1. Bấm một tầng để vào ngay với %s." % Characters.DEFS[chosen].name, 15, Color(1, 1, 1, 0.85), v, 680))
	var row := _row(v)
	for k in d.floors.size():
		var open := meta.floor_open(dungeon_id, k)
		var cleared: bool = k < meta.floors_cleared[dungeon_id]
		var c := _card(row, false, not open, _pick_floor.bind(k), 260)
		Ui._label("Tầng %d%s" % [k + 1, " ✔" if cleared else ""], 22, Color.WHITE, c)
		Ui._label(Maps.DEFS[d.floors[k]].name, 13, DIM, c)
		Ui._label("Quái ×%s · boss ×%s · vàng ×%s" % [num(d.difficulty[k]), num(d.boss_difficulty[k]), num(d.gold_mul[k])], 13, GOLD, c)
		if not open:
			Ui._label("🔒 Hạ boss tầng %d để mở" % k, 13, PINK, c)
	_center_btn(v, "Quay lại (Esc)", show_menu)

func _pick_floor(f: int) -> void:
	_fix_chosen()
	if meta.floor_open(dungeon_id, f):
		start.emit(chosen, { kind = "dungeon", floor = f })

# ---------- pause / end ----------

func show_pause() -> void:
	var v := _open("pause")
	Ui._title("Tạm dừng", 44, v)
	var hb := _row(v)
	Ui._button("Tiếp tục (Esc)", false, func() -> void: resume.emit(), hb)
	Ui._button("Chơi lại", true, func() -> void: restart.emit(), hb)
	Ui._button("Về menu", true, func() -> void: menu.emit(), hb)

## end-screen buttons; the first one is the Enter action
static func end_actions(won: bool, d: Dictionary, last: bool) -> Array:
	var m := { a = "menu", label = "Về menu" }
	if d.is_empty():
		return [{ a = "restart", label = "Chơi lại (Enter)" }, m]
	if not won:
		return [{ a = "restart", label = "Chơi lại tầng (Enter)" }, { a = "floors", label = "Chọn tầng" }, m]
	if last:
		return [{ a = "floors", label = "Hoàn thành dungeon! (Enter)" }, m]
	return [{ a = "next", label = "Xuống tầng %d (Enter)" % (d.floor + 2) }, m]

func show_end(w: World, actions: Array) -> void:
	var won := w.state == "won"
	var v := _open("end")
	var t := Ui._title("Chiến thắng!" if won else "Thất bại", 52, v)
	t.add_theme_color_override("font_color", PINK if won else Color("#ff6b8a"))
	var qd := 0
	for q in w.quest_log:
		qd += 1 if q.success else 0
	var stats := _row(v)
	stats.add_theme_constant_override("separation", 26)
	var cells := [[Ui.fmt_time(w.time), "thời gian"], [str(w.level), "cấp"], [str(w.kills), "quái hạ"], [str(w.build.hidden.size()), "kỹ năng ẩn"], ["%d/%d" % [qd, w.quests.size()], "nhiệm vụ"]]
	for c in cells:
		var col := VBoxContainer.new()
		stats.add_child(col)
		_center(Ui._label(c[0], 26, CYAN, col))
		_center(Ui._label(c[1], 12, DIM, col))
	var gcol := VBoxContainer.new()
	stats.add_child(gcol)
	_center(Ui._label("+%d" % roundi(w.gold), 26, GOLD, gcol))
	_center(Ui._label("vàng · tổng " + coin(meta.gold), 12, DIM, gcol))
	var build := HBoxContainer.new()
	build.alignment = BoxContainer.ALIGNMENT_CENTER
	build.add_theme_constant_override("separation", 8)
	v.add_child(build)
	Ui._fill_slots(build, w.build)
	var hb := _row(v)
	for k in actions.size():
		var a: String = actions[k].a
		Ui._button(actions[k].label, k > 0, _act.bind(a), hb)
	_end_enter = actions[0].a if actions.size() > 0 else "menu"

func _act(a: String) -> void:
	match a:
		"restart": restart.emit()
		"next": next_floor.emit()
		"floors": floors.emit()
		"menu": menu.emit()

## after a purchase: redraw whatever is open
func refresh() -> void:
	match mode:
		"chars": show_chars()
		"shop": show_shop()
		"menu": show_menu()

## keyboard on overlays; true = handled
func handle_key(k: Key) -> bool:
	if mode == "chars" and k >= KEY_1 and k <= KEY_9:
		var i := k - KEY_1
		if i < Characters.IDS.size():
			pick(Characters.IDS[i])
		return true
	if mode == "menu" and k == KEY_C:
		show_chars()
		return true
	if k == KEY_ESCAPE:
		if mode == "shop" or mode == "floors" or mode == "chars":
			show_menu()
			return true
		return false
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		match mode:
			"menu": play_survival()
			"chars": show_menu()
			"end": _act(_end_enter)
			_: return false
		return true
	return false
