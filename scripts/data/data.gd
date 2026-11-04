class_name Data
## all game data (port of src/data/*); survival-only subset: 1 hero, 4 weapons

const BALANCE := {
	run_seconds = 480,
	player_speed = 6.0, player_radius = 0.5, invuln_seconds = 0.7,
	base_pickup_radius = 2.0,
	heal_amount = 30.0,
	max_enemies = 400,
	max_gems = 500,
	spawn_min = 18.0, spawn_max = 26.0,
	dt_max = 1.0 / 30.0,
}

## headless stand-in for "on screen" (world units around the player; up = away from the camera)
const VIEW := { side = 19.0, up = 15.0, down = 9.0 }

const RANGES := { fireball = 11.0, thunderSeal = 8.0, sky = 16.0 }

# ---------- items ----------
const WEAPON_IDS: Array[String] = ["holySword", "fireball", "thunderSeal", "frostRing"]
const STAT_IDS: Array[String] = ["might", "speed", "haste", "magnet", "area", "vitality"]

## linear lv1→lv5; [a, b] ranges, plain numbers constant; round = integer keys
static func _lerp_levels(spec: Dictionary, round_keys: Array = []) -> Array:
	var out := []
	for i in 5:
		var lv := {}
		for k in spec:
			var r = spec[k]
			var v: float = r if typeof(r) != TYPE_ARRAY else r[0] + (r[1] - r[0]) * i / 4.0
			lv[k] = float(roundi(v)) if k in round_keys else roundf(v * 100.0) / 100.0
		out.append(lv)
	return out

static var WEAPONS := {
	holySword = {
		kind = "weapon", id = "holySword", name = "Thánh Kiếm", icon = "🗡️",
		description = "Chém vòng cung 120° phía trước.",
		hidden_name = "Kiếm Khí", hidden_description = "Mỗi nhát chém bắn sóng kiếm xuyên quái.",
		paired = "might", weight = 1.0,
		levels = _lerp_levels({ damage = [15, 35], cooldown = [0.9, 0.55], count = 1, area = [2.8, 3.8], pierce = 0, speed = 0 }),
	},
	fireball = {
		kind = "weapon", id = "fireball", name = "Cầu Lửa", icon = "🔥",
		description = "Ném cầu lửa nổ vùng vào quái gần nhất.",
		hidden_name = "Mưa Thiên Thạch", hidden_description = "Thiên thạch liên tục rơi xuống quái.",
		paired = "haste", weight = 0.9,
		levels = _lerp_levels({ damage = [20, 45], cooldown = [2.0, 1.2], count = [1, 2], area = [1.5, 2.5], pierce = 0, speed = 12 }, ["count"]),
	},
	thunderSeal = {
		kind = "weapon", id = "thunderSeal", name = "Lôi Ấn", icon = "🌩️",
		description = "Sét nhảy liên tiếp giữa các quái.",
		hidden_name = "Lôi Thần Giáng", hidden_description = "Sét đánh xuống khắp màn hình.",
		paired = "might", weight = 0.9,
		levels = _lerp_levels({ damage = [10, 24], cooldown = [1.4, 0.8], count = [3, 6], area = 5, pierce = 0, speed = 0 }, ["count"]),
	},
	frostRing = {
		kind = "weapon", id = "frostRing", name = "Vòng Băng", icon = "❄️",
		description = "Vùng lạnh quanh người, làm chậm và gây sát thương.",
		hidden_name = "Vệt Băng", hidden_description = "Chạy để lại vệt băng, quái giẫm lên bị đóng băng.",
		paired = "area", weight = 0.8,
		levels = _lerp_levels({ damage = [4, 10], cooldown = 0.5, count = 1, area = [2.5, 4], pierce = 0, speed = 0 }),
	},
}

const STATS := {
	might = { kind = "stat", id = "might", name = "Sức mạnh", icon = "💪", description = "+10% sát thương mỗi cấp.", weight = 1.0 },
	speed = { kind = "stat", id = "speed", name = "Tốc độ", icon = "👟", description = "+8% tốc chạy & tốc đạn mỗi cấp.", weight = 1.0 },
	haste = { kind = "stat", id = "haste", name = "Hồi chiêu", icon = "⏳", description = "−8% thời gian hồi mỗi cấp.", weight = 0.8 },
	magnet = { kind = "stat", id = "magnet", name = "Phạm vi nhặt", icon = "🧲", description = "+25% bán kính hút kinh nghiệm mỗi cấp.", weight = 0.7 },
	area = { kind = "stat", id = "area", name = "Phạm vi", icon = "🌀", description = "+10% kích thước vùng ảnh hưởng mỗi cấp.", weight = 0.8 },
	vitality = { kind = "stat", id = "vitality", name = "Máu", icon = "❤️", description = "+20 máu tối đa và hồi máu chậm mỗi cấp.", weight = 0.8 },
}

static func is_weapon(id: String) -> bool:
	return WEAPONS.has(id)

static func item_def(id: String) -> Dictionary:
	return WEAPONS[id] if WEAPONS.has(id) else STATS[id]

# ---------- character ----------
const KNIGHT := {
	id = "knight", name = "Thạch Kiên", role = "Kiếm sĩ", icon = "🗡️",
	description = "Tay ngắn. Máu trâu, giáp dày, sát thương thấp.",
	hp = 130.0, damage_reduction = 0.2, damage_mul = 0.85, speed_mul = 1.0, pickup_radius_mul = 1.0, cooldown_mul = 1.0,
	weapon = "holySword",
	passive_text = "Hút Máu: mỗi nhát Thánh Kiếm trúng quái hồi chút máu.",
}
## knight: heal per enemy hit by the holy sword, capped per swing/wave
const LEECH := { per_hit = 0.4, max_per_swing = 3.0 }

const SKILL := { id = "holyWrath", name = "Thánh Nộ", icon = "✴️", description = "Đập đất: gây sát thương, làm choáng quái quanh người và làm boss khựng lại.", cooldown = 12.0 }
## stagger: the cc-immune boss loses this many seconds of walking and casting
const HOLY_WRATH := { radius = 5.0, damage = 30.0, stun = 1.5, stagger = 1.5 }

## level-up pool order = TS ALL_ITEMS order minus the dropped weapons (rng picks stay comparable)
static func shared_items() -> Array[String]:
	var out: Array[String] = []
	for id in WEAPON_IDS:
		if id != KNIGHT.weapon:
			out.append(id)
	out.append_array(STAT_IDS)
	return out

# ---------- enemies ----------
const ENEMY_TYPES: Array[String] = ["slime", "skeleton", "goblin", "warrior", "lich", "thief"]
const T_SLIME := 0
const T_SKELETON := 1
const T_GOBLIN := 2
const T_WARRIOR := 3
const T_LICH := 4
const T_THIEF := 5

const ENEMIES := [
	{ id = "slime", hp = 8.0, speed = 2.2, damage = 4.0, radius = 0.45, xp = 1.0, role = "", cc_immune = false, scripted = false },
	{ id = "skeleton", hp = 18.0, speed = 2.6, damage = 7.0, radius = 0.5, xp = 2.0, role = "", cc_immune = false, scripted = false },
	{ id = "goblin", hp = 10.0, speed = 4.5, damage = 6.0, radius = 0.45, xp = 2.0, role = "", cc_immune = false, scripted = false },
	{ id = "warrior", hp = 40.0, speed = 2.0, damage = 14.0, radius = 0.55, xp = 4.0, role = "", cc_immune = false, scripted = false },
	{ id = "lich", hp = 9000.0, speed = 1.8, damage = 20.0, radius = 1.3, xp = 0.0, role = "boss", cc_immune = true, scripted = true },
	# quest target: runs away, drops nothing
	{ id = "thief", hp = 150.0, speed = 5.0, damage = 0.0, radius = 0.5, xp = 0.0, role = "quest", cc_immune = true, scripted = true },
]

const ELITE := { hp_mul = 5.0, damage_mul = 1.5, xp_mul = 10.0, scale = 1.6, radius_mul = 1.5 }
const ELITE_MAX_ALIVE := 2
const ELITE_FROM := 120.0

## 0 before 2:00, ramps to 2% by 8:00
static func elite_chance(t: float) -> float:
	return 0.0 if t < ELITE_FROM else minf(0.02, 0.004 + (0.016 * t) / 480.0)

## quadratic tail keeps late game pressing on a finished build
static func hp_scale(t: float) -> float:
	return 1.0 + t / 100.0 + pow(t / 200.0, 2)

static func dmg_scale(t: float) -> float:
	return 1.0 + t / 240.0

static func spawn_rate(t: float) -> float:
	return 1.0 + 0.04 * t

# ---------- boss ----------
const LICH := {
	name = "Lich", hp = 9000.0, enemy = T_LICH,
	warn_seconds = 3.0, keep_distance = 4.0, enrage_after = 120.0,
	enrage = { cd_mul = 0.5, speed_mul = 1.5, count_mul = 1.5, damage_mul = 1.5 },
	minion = T_SKELETON,
	attacks = [
		{ kind = "volley", first = 2.0, every = 4.0, count = 12, speed = 7.0, damage = 12.0, radius = 0.4, life = 6.0 },
		{ kind = "summon", first = 6.0, every = 10.0, n = 6, ring = 2.5 },
		{ kind = "nova", first = 4.0, every = 6.0, n = 3, delay = 1.2, radius = 2.5, damage = 25.0, spread = 2.0 },
		{ kind = "adds", first = 5.0, every = 7.0, n = 4, min_dist = 10.0 },
		{ kind = "spiral", first = 9.0, every = 13.0, duration = 2.4, rate = 12.0, arms = 2, turn = 2.4, speed = 6.0, damage = 10.0, radius = 0.35, life = 6.0 },
		{ kind = "cage", first = 12.0, every = 15.0, n = 8, ring = 4.2, radius = 1.4, delay = 1.6, damage = 28.0 },
	],
}
const BOSS_AT := 480.0

# ---------- pickups ----------
const PICKUP_KINDS: Array[String] = ["heal", "magnet", "freeze", "invuln"]
const PICKUPS := {
	drop_chance = 0.005, life = 20.0, max = 6,
	weights = [0.35, 0.3, 0.2, 0.15],
	magnet_radius = 40.0, invuln_seconds = 5.0, freeze_radius = 12.0, freeze_seconds = 4.0,
}
const PICKUP_NAMES := { heal = "Hồi máu", magnet = "Nam châm", freeze = "Băng giá", invuln = "Bất tử" }

# ---------- quests ----------
const QUEST_KINDS: Array[String] = ["bounce", "hold", "crystal", "thief"]
const QUEST_NAMES := { bounce = "Bóng nảy", hold = "Giữ vòng rune", crystal = "Bảo vệ tinh thể", thief = "Săn kẻ trộm" }
const QUEST_AT: Array[float] = [90.0, 240.0]
const QUESTS := {
	window = 40.0, trigger_radius = 3.0, max_walk = 20, reward_levels = 5.0,
	bounce = { count = 5, warn = 1.5, radius = 1.6, roam = 6.0, min_hop = 2.5, max_miss = 2 },
	hold = { need = 20.0, radius = 3.0, drain = 0.5, timeout = 40.0 },
	crystal = { seconds = 30.0, hp = 400.0, aggro = 10.0, radius = 0.8, chip = 2.0, elite_chip = 3.0 },
	thief = { seconds = 20.0, head_start = 8.0 },
}

# ---------- map (M2 "Hầm Mộ", the survival map) ----------
const MAP_ASCII := """################################################
################################################
##...........#####............#####...........##
##...........#####............#####...........##
##..o........#####...o........#####..o........##
##.....S......................................##
##............................................##
##............................................##
##........o..#####.........o..#####........o..##
##...........#####............#####...........##
######...##############..##############...######
######...##############..##############...######
######...##############DD##############...######
######...########..............########...######
######...########..............########...######
##...........####..............####...........##
##...........####...o......o...####...........##
##..o........####..............####..o........##
##..............D......B.......D..............##
##..............D..............D..............##
##...........####..............####...........##
##...........####...o......o...####...........##
##........o..####..............####........o..##
##...........####..............####...........##
######...########..............########...######
######...##############DD##############...######
######...##############..##############...######
######...##############..##############...######
##...........#####............#####...........##
##...........#####............#####...........##
##..o........#####.........o..#####..o........##
##............................................##
##............................................##
##............................................##
##........o..#####...o........#####........o..##
##...........#####............#####...........##
################################################
################################################"""

## repeats = weights: the outer zone is mostly slimes so the first minute is survivable
const ZONE_TYPES := [[T_SLIME, T_SLIME, T_SLIME, T_SLIME, T_SKELETON], [T_SKELETON, T_GOBLIN], [T_GOBLIN, T_WARRIOR]]
const ZONE_XP_MUL: Array[float] = [1.0, 1.3, 1.7]
## room centres: rune = glowing floor ring, quest = quest can appear here (order feeds the rng)
const SPOTS := [
	{ cx = 7, cz = 6, quest = true, rune = false },
	{ cx = 24, cz = 6, quest = true, rune = true }, { cx = 40, cz = 6, quest = true, rune = true },
	{ cx = 7, cz = 19, quest = true, rune = true }, { cx = 40, cz = 19, quest = true, rune = true },
	{ cx = 7, cz = 32, quest = true, rune = true }, { cx = 24, cz = 32, quest = true, rune = true }, { cx = 40, cz = 32, quest = true, rune = true },
	{ cx = 24, cz = 19, quest = false, rune = true },
]
const ARENA_ENTRY := Vector2i(18, 23)

# ---------- xp ----------
## past lv 10 the curve bends up so the 6×5 build completes late in the run
static func xp_to_next(level: int) -> float:
	return 5.0 + 3.0 * (level - 1) + 1.5 * pow(maxf(0.0, level - 10), 2)
