class_name Bosses
## boss fights (port of src/data/bosses.ts); body = a Monsters entry, look = boss skin in content/styles/*

const DEFS := {
	lich = {
		id = "lich", enemy = "lich", name = "Lich", hp = 9000.0,
		warn_seconds = 3.0, keep_distance = 4.0, enrage_after = 120.0,
		enrage = { cd_mul = 0.5, speed_mul = 1.5, count_mul = 1.5, damage_mul = 1.5 },
		minion = "skeleton",
		attacks = [
			{ kind = "volley", first = 2.0, every = 4.0, count = 12, speed = 7.0, damage = 12.0, radius = 0.4, life = 6.0 },
			{ kind = "summon", first = 6.0, every = 10.0, n = 6, ring = 2.5 },
			{ kind = "nova", first = 4.0, every = 6.0, n = 3, delay = 1.2, radius = 2.5, damage = 25.0, spread = 2.0 },
			# normal enemies of the deepest zone, anywhere the player can reach but not close
			{ kind = "adds", first = 5.0, every = 7.0, n = 4, min_dist = 10.0 },
			# rotating stream; rate = shots/s per arm, turn = rad/s
			{ kind = "spiral", first = 9.0, every = 13.0, duration = 2.4, rate = 12.0, arms = 2, turn = 2.4, speed = 6.0, damage = 10.0, radius = 0.35, life = 6.0 },
			# ring of warning zones around the player; enrage count_mul not applied (zones would overlap)
			{ kind = "cage", first = 12.0, every = 15.0, n = 8, ring = 4.2, radius = 1.4, delay = 1.6, damage = 28.0 },
		],
	},
}
