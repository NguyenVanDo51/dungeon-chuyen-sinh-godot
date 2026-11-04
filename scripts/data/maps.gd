class_name Maps
## levels (port of src/data/map.ts). Layout = content/maps/<id>.txt, everything else here.
## txt: '#' wall '.' floor 'o' pillar 'S' start 'D' door 'B' boss spawn 'b' boss room; 1 char = 1 cell (Grid.CELL units)
## zone_types: monster ids per zone (repeats = weights); zones = bands of walking distance from S
## spots: room-centre cells; rune = glowing floor ring, quest = a quest can appear here (order feeds the rng)
## depth (dungeon floors): per-zone enemy budget, spawns/s while the player stands there, hp/dmg/elite multipliers

const DUNGEON_DEPTH := { budget = [180, 260, 320], rate = [1.2, 2.4, 3.4], hp = [1.2, 3.0, 5.5], dmg = [1.0, 1.5, 1.8], elite = [0.0, 0.008, 0.016] }
const DUNGEON_ZONES := [["slime", "slime", "slime", "skeleton"], ["skeleton", "goblin"], ["goblin", "warrior"]]

const DEFS := {
	m1 = {
		id = "m1", name = "Hầm cũ", theme = "crypt", boss = "lich",
		zone_types = [["slime", "skeleton", "goblin"]], zone_xp_mul = [1.0],
		quests = [],
		spots = [
			{ cx = 7, cz = 6, rune = true }, { cx = 32, cz = 6, rune = true }, { cx = 20, cz = 15, rune = true },
			{ cx = 7, cz = 24, rune = true }, { cx = 32, cz = 24, rune = true },
		],
	},
	m2 = {
		id = "m2", name = "Hầm Mộ", theme = "crypt", boss = "lich",
		# the outer zone is mostly slimes so the first minute is survivable
		zone_types = [["slime", "slime", "slime", "slime", "skeleton"], ["skeleton", "goblin"], ["goblin", "warrior"]],
		zone_xp_mul = [1.0, 1.3, 1.7],
		quests = ["bounce", "hold", "crystal", "thief"],
		# no rune in the start room: it sat right under the player's halo
		spots = [
			{ cx = 7, cz = 6, quest = true },
			{ cx = 24, cz = 6, quest = true, rune = true }, { cx = 40, cz = 6, quest = true, rune = true },
			{ cx = 7, cz = 19, quest = true, rune = true }, { cx = 40, cz = 19, quest = true, rune = true },
			{ cx = 7, cz = 32, quest = true, rune = true }, { cx = 24, cz = 32, quest = true, rune = true }, { cx = 40, cz = 32, quest = true, rune = true },
			{ cx = 24, cz = 19, rune = true },
		],
		# where the boss fight drops the player
		arena_entry = Vector2i(18, 23),
	},
	d1 = {
		id = "d1", name = "Hầm Mộ — Tầng 1", theme = "crypt", boss = "lich",
		zone_types = DUNGEON_ZONES, zone_xp_mul = [1.0, 1.3, 1.7],
		quests = ["bounce", "hold", "crystal", "thief"],
		spots = [
			{ cx = 7, cz = 6, quest = true }, { cx = 26, cz = 6, quest = true, rune = true }, { cx = 45, cz = 6, quest = true, rune = true },
			{ cx = 44, cz = 18, quest = true }, { cx = 25, cz = 19, quest = true, rune = true }, { cx = 7, cz = 19, quest = true, rune = true },
			{ cx = 9, cz = 30, quest = true },
		],
		arena_entry = Vector2i(31, 29),
		depth = DUNGEON_DEPTH,
	},
	d2 = {
		id = "d2", name = "Hầm Mộ — Tầng 2", theme = "crypt", boss = "lich",
		zone_types = DUNGEON_ZONES, zone_xp_mul = [1.0, 1.3, 1.7],
		quests = ["bounce", "hold", "crystal", "thief"],
		spots = [
			{ cx = 8, cz = 30, quest = true }, { cx = 9, cz = 13, quest = true, rune = true }, { cx = 29, cz = 11, quest = true, rune = true },
			{ cx = 29, cz = 3, quest = true }, { cx = 28, cz = 30, quest = true, rune = true }, { cx = 49, cz = 13, quest = true, rune = true },
		],
		arena_entry = Vector2i(49, 27),
		depth = DUNGEON_DEPTH,
	},
}

static func ascii(id: String) -> String:
	var path := "res://content/maps/%s.txt" % id
	var s := FileAccess.get_file_as_string(path)
	if s.is_empty():
		push_error("map file missing: " + path)
	return s
