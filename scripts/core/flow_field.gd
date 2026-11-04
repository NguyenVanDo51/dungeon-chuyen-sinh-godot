class_name FlowField
extends RefCounted
## BFS walking distance (cells) to a target cell; -1 = unreachable

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var dist: PackedInt32Array
var _queue: PackedInt32Array

## diagonal step only when both orthogonal neighbours are open (no corner cutting)
static func can_step(g: Grid, cx: int, cz: int, dx: int, dz: int) -> bool:
	if not g.walkable(cx + dx, cz + dz):
		return false
	if dx != 0 and dz != 0:
		return g.walkable(cx + dx, cz) and g.walkable(cx, cz + dz)
	return true

func compute(g: Grid, tcx: int, tcz: int) -> void:
	var n := g.w * g.h
	if dist.size() != n:
		dist.resize(n)
		_queue.resize(n)
	dist.fill(-1)
	if not g.walkable(tcx, tcz):
		return
	var head := 0
	var tail := 0
	var t := tcz * g.w + tcx
	dist[t] = 0
	_queue[tail] = t
	tail += 1
	while head < tail:
		var i := _queue[head]
		head += 1
		var cx := i % g.w
		var cz := i / g.w
		var d := dist[i] + 1
		for dv in DIRS:
			if not can_step(g, cx, cz, dv.x, dv.y):
				continue
			var j := (cz + dv.y) * g.w + cx + dv.x
			if dist[j] != -1:
				continue
			dist[j] = d
			_queue[tail] = j
			tail += 1

static func make(g: Grid, tcx: int, tcz: int) -> FlowField:
	var f := FlowField.new()
	f.compute(g, tcx, tcz)
	return f

## unit step toward the target in ox / oz (0, 0 = at target / unreachable)
static var ox := 0.0
static var oz := 0.0

func direction(g: Grid, x: float, z: float) -> void:
	ox = 0.0
	oz = 0.0
	var cx := int(floor(x / Grid.CELL))
	var cz := int(floor(z / Grid.CELL))
	if cx < 0 or cz < 0 or cx >= g.w or cz >= g.h:
		return
	var here := dist[cz * g.w + cx]
	if here <= 0:
		return
	var best := here
	var bx := 0
	var bz := 0
	for dv in DIRS:
		if not can_step(g, cx, cz, dv.x, dv.y):
			continue
		var d := dist[(cz + dv.y) * g.w + cx + dv.x]
		if d >= 0 and d < best:
			best = d
			bx = dv.x
			bz = dv.y
	var l := Vec.hypot(bx, bz)
	if l > 0.0:
		ox = bx / l
		oz = bz / l
