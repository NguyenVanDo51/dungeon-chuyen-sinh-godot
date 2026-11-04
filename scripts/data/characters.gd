class_name Characters
## heroes, skills, passives (port of src/data/{characters,skills}.ts + game/passives.ts, skills/*)
## add a hero: one entry here + a hero skin in each style (content/styles/*.tres, key = model)

const DEFS := {
	knight = {
		id = "knight", name = "Thạch Kiên", role = "Kiếm sĩ", icon = "🗡️", model = "knight", price = 0,
		description = "Tay ngắn. Máu trâu, giáp dày, sát thương thấp.",
		hp = 130.0, damage_reduction = 0.2, damage_mul = 0.85, speed_mul = 1.0, pickup_radius_mul = 1.0, cooldown_mul = 1.0,
		weapon = "holySword", skill = "holyWrath",
		passive = "swordLeech", passive_text = "Hút Máu: mỗi nhát Thánh Kiếm trúng quái hồi chút máu.",
	},
	archer = {
		id = "archer", name = "Lam Vũ", role = "Cung thủ", icon = "🏹", model = "archer", price = 0,
		description = "Tay dài. Máu mỏng, không giáp, sát thương to.",
		hp = 85.0, damage_reduction = 0.0, damage_mul = 1.3, speed_mul = 1.0, pickup_radius_mul = 1.0, cooldown_mul = 1.0,
		weapon = "elvenBow", skill = "roll",
		passive = "lightFeet", passive_text = "Chân Nhẹ: 2 giây không trúng đòn thì chạy nhanh hơn 20%.",
	},
}
const IDS: Array[String] = ["knight", "archer"]
const DEFAULT := "knight"

## trigger auto = World fires it when the runtime's should_trigger says so
const SKILLS := {
	holyWrath = { id = "holyWrath", name = "Thánh Nộ", icon = "✴️", description = "Đập đất: gây sát thương, làm choáng quái quanh người và làm boss khựng lại.", cooldown = 12.0, trigger = "manual" },
	roll = { id = "roll", name = "Lăn Né", icon = "💨", description = "Lướt nhanh một đoạn, bất tử trong chốc lát.", cooldown = 6.0, trigger = "manual" },
}
## stagger: the cc-immune boss loses this many seconds of walking and casting
const HOLY_WRATH := { radius = 5.0, damage = 30.0, stun = 1.5, stagger = 1.5 }
const ROLL := { distance = 6.0, invuln = 0.4, substep = 0.4 }

## knight: heal per enemy hit by the holy sword, capped per swing/wave
const LEECH := { per_hit = 0.4, max_per_swing = 3.0 }
## archer: run faster after `delay` s without taking a hit
const LIGHT_FEET := { delay = 2.0, bonus = 0.2 }

## class-bound weapons: never in the shared pool, never locked
static func signature_weapons() -> Array[String]:
	var out: Array[String] = []
	for c in IDS:
		out.append(DEFS[c].weapon)
	return out

static func shared_items() -> Array[String]:
	var sig := signature_weapons()
	var out: Array[String] = []
	for id in Items.all_items():
		if not id in sig:
			out.append(id)
	return out

# ---------- passives ----------

static func on_weapon_hits(w: World, weapon: String, hits: int) -> void:
	if w.hero.passive == "swordLeech":
		if weapon != "holySword" or hits <= 0:
			return
		w.heal(minf(LEECH.max_per_swing, LEECH.per_hit * hits))

static func move_speed_mul(w: World) -> float:
	if w.hero.passive == "lightFeet":
		return 1.0 + LIGHT_FEET.bonus if w.since_hurt >= LIGHT_FEET.delay else 1.0
	return 1.0
