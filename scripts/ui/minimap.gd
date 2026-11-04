class_name Minimap
extends Control
## corner map: rooms, the sealed boss room (☠ + countdown), player, elites, thief, quest ★, boss

const WIDTH := 230.0
const REFRESH := 1.0 / 12.0

var _w: World
var _cell := 4.0
var _acc := 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

func tick(w: World, dt: float) -> void:
	if _w != w:
		_w = w
		_cell = WIDTH / w.grid.w
		custom_minimum_size = Vector2(WIDTH, WIDTH * w.grid.h / w.grid.w) + Vector2(12, 12)
		size = custom_minimum_size
		offset_left = -size.x - 14; offset_top = -size.y - 14; offset_right = -14; offset_bottom = -14
		queue_redraw()
	_acc += dt
	if _acc >= REFRESH:
		_acc = 0.0
		queue_redraw()

func _p(x: float, z: float) -> Vector2:
	return Vector2(6, 6) + Vector2(x, z) / Grid.CELL * _cell

func _draw() -> void:
	if _w == null:
		return
	draw_style_box(Ui._style(Color("#0b0e2acc"), Color("#5ff3ff55"), 12, 1), Rect2(Vector2.ZERO, size))
	var g := _w.grid
	for cz in g.h:
		for cx in g.w:
			var k := g.cells[cz * g.w + cx]
			var col: Color
			if k == Grid.FLOOR: col = Color("#5560b8")
			elif k == Grid.PILLAR: col = Color("#262b66")
			else: continue
			draw_rect(Rect2(Vector2(6, 6) + Vector2(cx, cz) * _cell, Vector2(_cell + 0.5, _cell + 0.5)), col)
	for i in g.doors:
		if g.cells[i] != Grid.FLOOR:
			draw_rect(Rect2(Vector2(6, 6) + Vector2(i % g.w, i / g.w) * _cell, Vector2(_cell, _cell)), Color("#5ff3ff"))
	var font := get_theme_default_font()
	for p in _w.pickups:
		draw_circle(_p(p.x, p.z), 0.4 * _cell, Color.WHITE)
	var e := _w.enemies
	for i in e.count:
		if e.elite[i] == 1:
			draw_circle(_p(e.x[i], e.z[i]), 0.6 * _cell, Color("#ffd36e"))
		elif e.type[i] == Data.T_THIEF:
			draw_circle(_p(e.x[i], e.z[i]), 0.7 * _cell, Color("#d9a6ff"))
	if _w.quest:
		var q := _w.quest
		var c := Color("#5ff3ff", 0.6 + 0.4 * sin(_w.time * 6.0))
		draw_string(font, _p(q.x, q.z) + Vector2(-6, 6), "★", HORIZONTAL_ALIGNMENT_CENTER, -1, int(_cell * 3), c)
	var bi := _w.boss_index()
	var pulse := 0.9 + 0.25 * sin(_w.time * 6.0)
	if bi >= 0:
		var bp := _p(e.x[bi], e.z[bi])
		draw_circle(bp, 1.1 * pulse * _cell + 1.5, Color.WHITE)
		draw_circle(bp, 1.1 * pulse * _cell, Color("#ff2b4d") if _w.boss.enraged else Color("#b08cff"))
	elif not _w.boss_defeated and g.has_boss_spawn:
		# boss not out yet: mark its room, label with the time left
		var sp := _p(g.boss_spawn.x, g.boss_spawn.y)
		draw_string(font, sp + Vector2(-8, 5), "☠", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_cell * 3), Color.WHITE)
		var left := ceili(maxf(0.0, Data.BOSS_AT - _w.time))
		draw_string(font, sp + Vector2(-12, _cell * 3.2), "%d:%02d" % [left / 60, left % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, int(_cell * 1.7), Color("#d9c8ff"))
	var pp := _p(_w.player.x, _w.player.z)
	draw_circle(pp, 0.8 * _cell + 1.5, Color.WHITE)
	draw_circle(pp, 0.8 * _cell, Color("#ff8fd8"))
