class_name EnemyPool
extends RefCounted
## struct-of-arrays pool; kill = swap-remove (last enemy moves into slot i)

var capacity: int
var count := 0
var _next_uid := 1
var x := PackedFloat32Array()
var z := PackedFloat32Array()
var hp := PackedFloat32Array()
var type := PackedByteArray()
var uid := PackedInt32Array()
var hit_flash := PackedFloat32Array()
var dir_x := PackedFloat32Array()
var dir_z := PackedFloat32Array()
var slow := PackedFloat32Array()
var frozen := PackedFloat32Array()
var elite := PackedByteArray()
## zone the enemy spawned in (drives its xp)
var zone := PackedByteArray()

static var CC_IMMUNE: Array[bool] = []
static var SCRIPTED: Array[bool] = []
static var RADIUS: Array[float] = []

func _init(cap: int) -> void:
	capacity = cap
	for a in [x, z, hp, hit_flash, dir_x, dir_z, slow, frozen, type, uid, elite, zone]:
		a.resize(cap)
	if CC_IMMUNE.is_empty():
		for d in Data.ENEMIES:
			CC_IMMUNE.append(d.cc_immune)
			SCRIPTED.append(d.scripted)
			RADIUS.append(d.radius)

func spawn(t: int, sx: float, sz: float, shp: float, is_elite := false, spawn_zone := 0) -> int:
	if count >= capacity:
		return -1
	var i := count
	count += 1
	x[i] = sx; z[i] = sz; hp[i] = shp
	type[i] = t
	uid[i] = _next_uid
	_next_uid += 1
	hit_flash[i] = 0.0; dir_x[i] = 0.0; dir_z[i] = 1.0; slow[i] = 0.0; frozen[i] = 0.0
	elite[i] = 1 if is_elite else 0
	zone[i] = spawn_zone
	return i

## elites and cc-immune types shrug off crowd control that moves or roots them
func immovable(i: int) -> bool:
	return elite[i] == 1 or CC_IMMUNE[type[i]]

func radius(i: int) -> float:
	return RADIUS[type[i]] * (Data.ELITE.radius_mul if elite[i] == 1 else 1.0)

func kill(i: int) -> void:
	count -= 1
	var last := count
	if i == last:
		return
	x[i] = x[last]; z[i] = z[last]; hp[i] = hp[last]; type[i] = type[last]; uid[i] = uid[last]
	hit_flash[i] = hit_flash[last]; dir_x[i] = dir_x[last]; dir_z[i] = dir_z[last]
	slow[i] = slow[last]; frozen[i] = frozen[last]; elite[i] = elite[last]; zone[i] = zone[last]

func index_of_uid(u: int) -> int:
	for i in count:
		if uid[i] == u:
			return i
	return -1
