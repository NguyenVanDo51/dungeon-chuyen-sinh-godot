class_name SpatialHash
extends RefCounted
## fixed bucket grid over the map; linked lists in packed arrays (no per-frame allocation)

var cell: float
var bw: int
var bh: int
var heads: PackedInt32Array
var nxt: PackedInt32Array

func _init(cell_size: float, world_w: float, world_h: float, capacity: int) -> void:
	cell = cell_size
	bw = int(ceil(world_w / cell)) + 1
	bh = int(ceil(world_h / cell)) + 1
	heads.resize(bw * bh)
	nxt.resize(capacity)
	heads.fill(-1)

func clear() -> void:
	heads.fill(-1)

func _bucket(x: float, z: float) -> int:
	var ix := clampi(int(floor(x / cell)), 0, bw - 1)
	var iz := clampi(int(floor(z / cell)), 0, bh - 1)
	return iz * bw + ix

func insert(id: int, x: float, z: float) -> void:
	var b := _bucket(x, z)
	nxt[id] = heads[b]
	heads[b] = id

## fills out from index 0, returns count
func query(x: float, z: float, r: float, out: PackedInt32Array) -> int:
	var n := 0
	var x0 := clampi(int(floor((x - r) / cell)), 0, bw - 1)
	var x1 := clampi(int(floor((x + r) / cell)), 0, bw - 1)
	var z0 := clampi(int(floor((z - r) / cell)), 0, bh - 1)
	var z1 := clampi(int(floor((z + r) / cell)), 0, bh - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var id := heads[iz * bw + ix]
			while id >= 0:
				if n >= out.size():
					out.resize(out.size() * 2)
				out[n] = id
				n += 1
				id = nxt[id]
	return n
