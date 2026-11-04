class_name Dungeons
## dungeons + per-mode rules (port of src/data/{dungeons,modes}.ts)
## one dungeon = floors (map ids) sharing a theme; deeper floors are harder and pay more

const DEFS := {
	crypt = {
		id = "crypt", name = "Hầm Mộ", theme = "crypt", floors = ["d1", "d2"],
		## per floor: × enemy hp / damage
		difficulty = [1.0, 1.2],
		## per floor: × boss hp / damage (split: melee pays for tougher corridors far more than ranged)
		boss_difficulty = [1.85, 1.9],
		gold_mul = [1.0, 1.5],
		## per floor: seconds before the player is pulled into the boss room
		time_limit = [390.0, 390.0],
	},
}
const SURVIVAL_MAP := "m2"
const SURVIVAL_BOSS_AT := 480.0

## rules: spawn time|depth · boss atTime|enterRoom (boss_at = time / pull limit) · quests atTime|atZone (quest_at = times / zones)
static func survival_rules() -> Dictionary:
	return {
		spawn = "time", boss = "atTime", boss_at = SURVIVAL_BOSS_AT,
		quests = "atTime", quest_at = [90.0, 240.0],
		difficulty = 1.0, boss_difficulty = 1.0, gold_mul = 1.0, dungeon = {},
	}

## floor is 0-based
static func floor_rules(id: String, f: int) -> Dictionary:
	var d: Dictionary = DEFS[id]
	return {
		spawn = "depth", boss = "enterRoom", boss_at = d.time_limit[f] if f < d.time_limit.size() else SURVIVAL_BOSS_AT,
		quests = "atZone", quest_at = [1, 2],
		difficulty = d.difficulty[f] if f < d.difficulty.size() else 1.0,
		boss_difficulty = d.boss_difficulty[f] if f < d.boss_difficulty.size() else 1.0,
		gold_mul = d.gold_mul[f] if f < d.gold_mul.size() else 1.0,
		dungeon = { id = id, floor = f },
	}

static func floor_map(id: String, f: int) -> String:
	return DEFS[id].floors[f]
