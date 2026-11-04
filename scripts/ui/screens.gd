class_name Screens
extends Control
## menu, character select, shop, dungeon floors, pause, end (port of ui/screens.ts + menus.ts)

signal start(c: String, run: Dictionary)
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

## loading | menu | floors | start | shop | pause | end | none
var mode := "loading"
var meta: Meta
var chosen: String = Characters.DEFAULT
## what the character select will start: {kind = "survival"} | {kind = "dungeon", floor}
var pending := { kind = "survival" }
var tab := "upgrades"
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

## fresh panel for a screen; the old one is dropped (screens are cheap to rebuild)
func _open(m: String) -> VBoxContainer:
	for c in _overlay.get_children():
		c.queue_free()
	_box = Ui._panel(_overlay)
	mode = m
	_overlay.visible = true
	return _box

func hide_all() -> void:
	mode = "none"
	_overlay.visible = false

func _row(parent: Node) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	parent.add_child(hb)
	return hb

func _center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _wrap(text: String, size: int, col: Color, parent: Node, width := 300.0) -> Label:
	var l := Ui._label(text, size, col, parent)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
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
	var v := _open("menu")
	Ui._title("Dungeon Chuyển Sinh", 56, v)
	_center(Ui._label(coin(meta.gold) + " vàng", 18, GOLD, v))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	v.add_child(col)
	Ui._button("Sinh tồn (Enter)", false, func() -> void: show_start({ kind = "survival" }), col)
	Ui._button("Dungeon", false, show_floors, col)
	Ui._button("Cửa hàng", true, show_shop, col)

# ---------- character select ----------

func _char_cards(parent: Node, on_pick: Callable) -> void:
	var row := _row(parent)
	for k in Characters.IDS.size():
		var id: String = Characters.IDS[k]
		var c: Dictionary = Characters.DEFS[id]
		var owned := id in meta.owned
		var v := _card(row, mode == "start" and id == chosen, not owned, on_pick.bind(id))
		Ui._label(c.icon, 34, Color.WHITE, v)
		Ui._label("%d. %s · %s" % [k + 1, c.name, c.role], 20, Color.WHITE, v)
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

func show_start(run: Dictionary = {}) -> void:
	if not run.is_empty():
		pending = run
	if not chosen in meta.owned:
		chosen = meta.owned[0] if meta.owned.size() > 0 else Characters.DEFAULT
	var v := _open("start")
	Ui._title("Chọn nhân vật", 44, v)
	var d: Dictionary = Dungeons.DEFS[dungeon_id]
	var sub: String = "%s — Tầng %d. Đi sâu để gặp boss; đứng yên thì quái cạn dần." % [d.name, pending.floor + 1] if pending.kind == "dungeon" \
		else "Sống sót 8 phút trong dungeon dị giới. Làm nhiệm vụ để lên cấp nhanh, build đúng đồ để mở kỹ năng ẩn."
	_center(_wrap(sub + "   " + coin(meta.gold), 15, Color(1, 1, 1, 0.85), v, 680))
	_char_cards(v, pick)
	var hb := _row(v)
	var b := Ui._button("Bắt đầu (Enter)", false, try_start, hb)
	b.disabled = not chosen in meta.owned
	Ui._button("Quay lại (Esc)", true, back, hb)
	_center(Ui._label("W A S D: di chuyển  ·  vũ khí tự bắn  ·  Space: kỹ năng  ·  1 2 3: chọn thẻ  ·  Esc: tạm dừng", 13, DIM, v))

func pick(c: String) -> void:
	chosen = c
	if mode == "start":
		show_start()

func try_start() -> void:
	if not chosen in meta.owned:
		return
	if pending.kind == "dungeon" and not meta.floor_open(dungeon_id, pending.floor):
		return
	start.emit(chosen, pending)

func back() -> void:
	if pending.kind == "dungeon":
		show_floors()
	else:
		show_menu()

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
	_center(_wrap("Càng vào sâu quái càng mạnh. Cuối tầng là phòng boss: bước vào là cửa khoá. Mỗi tầng chơi lại từ cấp 1.", 15, Color(1, 1, 1, 0.85), v, 680))
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
	if meta.floor_open(dungeon_id, f):
		show_start({ kind = "dungeon", floor = f })

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
		"start": show_start()
		"shop": show_shop()
		"menu": show_menu()

## keyboard on overlays; true = handled
func handle_key(k: Key) -> bool:
	if mode == "start" and k >= KEY_1 and k <= KEY_9:
		var i := k - KEY_1
		if i < Characters.IDS.size():
			pick(Characters.IDS[i])
		return true
	if k == KEY_ESCAPE:
		if mode == "start":
			back()
			return true
		if mode == "shop" or mode == "floors":
			show_menu()
			return true
		return false
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		match mode:
			"menu": show_start({ kind = "survival" })
			"start": try_start()
			"end": _act(_end_enter)
			_: return false
		return true
	return false
