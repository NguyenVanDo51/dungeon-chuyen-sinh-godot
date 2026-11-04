class_name Data
## core tuning (port of src/data/{balance,pickups,quests,gold}.ts + core/xp.ts)
## content lives next door: Items, Characters, Monsters, Bosses, Maps, Dungeons; looks: content/styles/*

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

## base targeting range per weapon (× area); sky = meteor / storm / arrow rain / black hole
const RANGES := { elvenBow = 16.0, fireball = 11.0, thunderSeal = 8.0, soulTome = 7.0, flyingSwordsDash = 9.0, sky = 16.0 }

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
const QUESTS := {
	window = 40.0, trigger_radius = 3.0, max_walk = 20, reward_levels = 5.0,
	bounce = { count = 5, warn = 1.5, radius = 1.6, roam = 6.0, min_hop = 2.5, max_miss = 2 },
	hold = { need = 20.0, radius = 3.0, drain = 0.5, timeout = 40.0 },
	crystal = { seconds = 30.0, hp = 400.0, aggro = 10.0, radius = 0.8, chip = 2.0, elite_chip = 3.0 },
	thief = { seconds = 20.0, head_start = 8.0 },
}

# ---------- gold (every amount × rules.gold_mul) ----------
const GOLD := {
	drop_chance = 0.01,
	## coin value by the zone the enemy spawned in
	zone_value = [1.0, 2.0, 3.0],
	elite = 10.0, quest = 30.0, boss = 100.0,
	## coins on the floor; past it new value folds into the nearest coin
	max_coins = 200,
}

# ---------- xp ----------
## past lv 10 the curve bends up so the 6×5 build completes late in the run
static func xp_to_next(level: int) -> float:
	return 5.0 + 3.0 * (level - 1) + 1.5 * pow(maxf(0.0, level - 10), 2)
