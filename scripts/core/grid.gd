class_name Grid
extends RefCounted
## '#' wall, '.' floor, 'o' pillar, 'S' start, 'D' door, 'B' boss spawn, 'b' boss room

const CELL := 4.0
const FLOOR := 0
const WALL := 1
const PILLAR := 2

var w: int
var h: int
var cells: PackedByteArray
var start: Vector2
var doors: PackedInt32Array
var has_boss_spawn := false
var boss_spawn: Vector2
var boss_room: PackedByteArray

static func cell_center(cx: int, cz: int) -> Vector2:
	return Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)

static func parse(ascii: String) -> Grid:
	var g := Grid.new()
	var rows: Array[String] = []
	for r in ascii.split("\n"):
		if r.length() > 0:
			rows.append(r)
	g.h = rows.size()
	g.w = 0
	for r in rows:
		g.w = maxi(g.w, r.length())
	g.cells = PackedByteArray()
	g.cells.resize(g.w * g.h)
	g.cells.fill(WALL)
	g.boss_room = PackedByteArray()
	g.boss_room.resize(g.w * g.h)
	g.start = cell_center(1, 1)
	for cz in g.h:
		var row := rows[cz]
		for cx in row.length():
			var ch := row[cx]
			var i := cz * g.w + cx
			if ch == "." or ch == "S" or ch == "B" or ch == "b":
				g.cells[i] = FLOOR
			if ch == "B" or ch == "b":
				g.boss_room[i] = 1
			if ch == "B":
				g.has_boss_spawn = true
				g.boss_spawn = cell_center(cx, cz)
			elif ch == "o":
				g.cells[i] = PILLAR
			elif ch == "D":
				g.doors.append(i)
			if ch == "S":
				g.start = cell_center(cx, cz)
	return g

func set_doors(open: bool) -> void:
	for i in doors:
		cells[i] = FLOOR if open else WALL

func in_boss_room(x: float, z: float) -> bool:
	var cx := int(floor(x / CELL))
	var cz := int(floor(z / CELL))
	if cx < 0 or cz < 0 or cx >= w or cz >= h:
		return false
	return boss_room[cz * w + cx] == 1

func cell_at(cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= w or cz >= h:
		return WALL
	return cells[cz * w + cx]

func walkable(cx: int, cz: int) -> bool:
	if cx < 0 or cz < 0 or cx >= w or cz >= h:
		return false
	return cells[cz * w + cx] == FLOOR

func walkable_at(x: float, z: float) -> bool:
	return walkable(int(floor(x / CELL)), int(floor(z / CELL)))

## samples the segment every 0.5 units; walls and pillars block sight
func line_of_sight(x0: float, z0: float, x1: float, z1: float) -> bool:
	var d := sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0))
	var steps := int(ceil(d / 0.5))
	for i in range(1, steps):
		var t := float(i) / steps
		if not walkable(int(floor((x0 + (x1 - x0) * t) / CELL)), int(floor((z0 + (z1 - z0) * t) / CELL))):
			return false
	return true
