class_name Items
## weapons + stats (port of src/data/items.ts); runtime per weapon: scripts/game/weapons/*

## order = TS ALL_ITEMS (feeds the level-up rng)
const WEAPON_IDS: Array[String] = ["holySword", "elvenBow", "flyingSwords", "fireball", "thunderSeal", "frostRing", "holyShield", "soulTome"]
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
		id = "holySword", name = "Thánh Kiếm", icon = "🗡️",
		description = "Chém vòng cung 120° phía trước.",
		hidden_name = "Kiếm Khí", hidden_description = "Mỗi nhát chém bắn sóng kiếm xuyên quái.",
		paired = "might", weight = 1.0,
		levels = _lerp_levels({ damage = [15, 35], cooldown = [0.9, 0.55], count = 1, area = [2.8, 3.8], pierce = 0, speed = 0 }),
	},
	elvenBow = {
		id = "elvenBow", name = "Cung Tinh Linh", icon = "🏹",
		description = "Bắn tên vào mục tiêu; lên cấp bắn nhiều mũi xoè vòng cung.",
		hidden_name = "Mưa Tên", hidden_description = "Định kỳ trút mưa tên xuống chỗ quái đông nhất.",
		paired = "speed", weight = 1.0,
		levels = _lerp_levels({ damage = [17, 32], cooldown = [0.65, 0.5], count = [1, 5], area = 0, pierce = [1, 3], speed = 18 }, ["count", "pierce"]),
	},
	flyingSwords = {
		id = "flyingSwords", name = "Phi Kiếm", icon = "⚔️",
		description = "Kiếm bay vòng quanh người.",
		hidden_name = "Kiếm Trận", hidden_description = "Gấp đôi số kiếm, định kỳ phóng ra đâm quái.",
		paired = "speed", weight = 0.8,
		levels = _lerp_levels({ damage = [6, 14], cooldown = 0.5, count = [2, 4], area = 2.4, pierce = 0, speed = 3 }, ["count"]),
	},
	fireball = {
		id = "fireball", name = "Cầu Lửa", icon = "🔥",
		description = "Ném cầu lửa nổ vùng vào quái gần nhất.",
		hidden_name = "Mưa Thiên Thạch", hidden_description = "Thiên thạch liên tục rơi xuống quái.",
		paired = "haste", weight = 0.9,
		levels = _lerp_levels({ damage = [20, 45], cooldown = [2.0, 1.2], count = [1, 2], area = [1.5, 2.5], pierce = 0, speed = 12 }, ["count"]),
	},
	thunderSeal = {
		id = "thunderSeal", name = "Lôi Ấn", icon = "🌩️",
		description = "Sét nhảy liên tiếp giữa các quái.",
		hidden_name = "Lôi Thần Giáng", hidden_description = "Sét đánh xuống khắp màn hình.",
		paired = "might", weight = 0.9,
		levels = _lerp_levels({ damage = [10, 24], cooldown = [1.4, 0.8], count = [3, 6], area = 5, pierce = 0, speed = 0 }, ["count"]),
	},
	frostRing = {
		id = "frostRing", name = "Vòng Băng", icon = "❄️",
		description = "Vùng lạnh quanh người, làm chậm và gây sát thương.",
		hidden_name = "Vệt Băng", hidden_description = "Chạy để lại vệt băng, quái giẫm lên bị đóng băng.",
		paired = "area", weight = 0.8,
		levels = _lerp_levels({ damage = [4, 10], cooldown = 0.5, count = 1, area = [2.5, 4], pierce = 0, speed = 0 }),
	},
	holyShield = {
		id = "holyShield", name = "Khiên Thánh", icon = "🛡️",
		description = "Phản sát thương và đẩy quái lùi lại.",
		hidden_name = "Thánh Vực", hidden_description = "Mỗi lần bị đánh phát ra sóng thánh.",
		paired = "vitality", weight = 0.8,
		levels = _lerp_levels({ damage = [8, 20], cooldown = [3, 1.8], count = 1, area = [2.5, 3.5], pierce = 0, speed = 3 }),
	},
	soulTome = {
		id = "soulTome", name = "Ma Thư Hút Hồn", icon = "📖",
		description = "Tia hút hồn quái để hồi máu.",
		hidden_name = "Hố Đen", hidden_description = "Hút cả quái lẫn kinh nghiệm vào giữa.",
		paired = "magnet", weight = 0.7,
		levels = _lerp_levels({ damage = [8, 20], cooldown = [1.0, 0.6], count = [1, 3], area = 8, pierce = 0, speed = 0 }, ["count"]),
	},
}

const STATS := {
	might = { id = "might", name = "Sức mạnh", icon = "💪", description = "+10% sát thương mỗi cấp.", weight = 1.0 },
	speed = { id = "speed", name = "Tốc độ", icon = "👟", description = "+8% tốc chạy & tốc đạn mỗi cấp.", weight = 1.0 },
	haste = { id = "haste", name = "Hồi chiêu", icon = "⏳", description = "−8% thời gian hồi mỗi cấp.", weight = 0.8 },
	magnet = { id = "magnet", name = "Phạm vi nhặt", icon = "🧲", description = "+25% bán kính hút kinh nghiệm mỗi cấp.", weight = 0.7 },
	area = { id = "area", name = "Phạm vi", icon = "🌀", description = "+10% kích thước vùng ảnh hưởng mỗi cấp.", weight = 0.8 },
	vitality = { id = "vitality", name = "Máu", icon = "❤️", description = "+20 máu tối đa và hồi máu chậm mỗi cấp.", weight = 0.8 },
}

static func all_items() -> Array[String]:
	var out: Array[String] = WEAPON_IDS.duplicate()
	out.append_array(STAT_IDS)
	return out

static func is_weapon(id: String) -> bool:
	return WEAPONS.has(id)

static func def(id: String) -> Dictionary:
	return WEAPONS[id] if WEAPONS.has(id) else STATS[id]

static func lv(id: String, level: int) -> Dictionary:
	return WEAPONS[id].levels[level - 1]
