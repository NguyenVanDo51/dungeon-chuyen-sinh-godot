class_name Monsters
## enemy types: logic stats only (port of src/data/enemies.ts); looks = monster skins in content/styles/*
## add a monster: one entry here + a skin per style; maps reference it by id. Order = pool type index.

const DEFS := [
	{ id = "slime", hp = 8.0, speed = 2.2, damage = 4.0, radius = 0.45, xp = 1.0, role = "", cc_immune = false, scripted = false },
	{ id = "skeleton", hp = 18.0, speed = 2.6, damage = 7.0, radius = 0.5, xp = 2.0, role = "", cc_immune = false, scripted = false },
	{ id = "goblin", hp = 10.0, speed = 4.5, damage = 6.0, radius = 0.45, xp = 2.0, role = "", cc_immune = false, scripted = false },
	{ id = "warrior", hp = 40.0, speed = 2.0, damage = 14.0, radius = 0.55, xp = 4.0, role = "", cc_immune = false, scripted = false },
	# boss body: its death wins the run
	{ id = "lich", hp = 9000.0, speed = 1.8, damage = 20.0, radius = 1.3, xp = 0.0, role = "boss", cc_immune = true, scripted = true },
	# quest target: runs away, drops nothing
	{ id = "thief", hp = 150.0, speed = 5.0, damage = 0.0, radius = 0.5, xp = 0.0, role = "quest", cc_immune = true, scripted = true },
]

static var IDS: Array[String] = _ids()
static var THIEF: int = idx("thief")

static func _ids() -> Array[String]:
	var out: Array[String] = []
	for d in DEFS:
		out.append(d.id)
	return out

static func idx(id: String) -> int:
	for i in DEFS.size():
		if DEFS[i].id == id:
			return i
	push_error("unknown monster " + id)
	return 0

const ELITE := { hp_mul = 5.0, damage_mul = 1.5, xp_mul = 10.0, scale = 1.6, radius_mul = 1.5 }
const ELITE_MAX_ALIVE := 2
const ELITE_FROM := 120.0

## survival: 0 before 2:00, ramps to 2% by 8:00
static func elite_chance(t: float) -> float:
	return 0.0 if t < ELITE_FROM else minf(0.02, 0.004 + (0.016 * t) / 480.0)

## quadratic tail keeps late game pressing on a finished build
static func hp_scale(t: float) -> float:
	return 1.0 + t / 100.0 + pow(t / 200.0, 2)

static func dmg_scale(t: float) -> float:
	return 1.0 + t / 240.0

## survival spawns / s. EARLY adds a boost that fades out by `fade` s, so the opening is busy and the late game is unchanged
const EARLY := { boost = 1.5, fade = 180.0, alive_from = 14.0, alive_to = 30.0, alive_until = 90.0 }

static func spawn_rate(t: float) -> float:
	return 1.0 + 0.04 * t + EARLY.boost * maxf(0.0, 1.0 - t / EARLY.fade)

## survival: enemies kept alive at least (topped up off-screen); ramps alive_from → alive_to, then off
static func min_alive(t: float) -> int:
	if t >= EARLY.alive_until:
		return 0
	return roundi(lerpf(EARLY.alive_from, EARLY.alive_to, t / EARLY.alive_until))
