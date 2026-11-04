class_name Build
extends RefCounted
## 6 slots shared by weapons + stats; weapon lv5 + its paired stat in a slot = hidden skill

const MAX_SLOTS := 6
const MAX_LEVEL := 5

## [{id, level}]
var slots: Array[Dictionary] = []
## weapon id -> true
var hidden := {}

func _init(start_weapon: String) -> void:
	slots.append({ id = start_weapon, level = 1 })

func level_of(id: String) -> int:
	for s in slots:
		if s.id == id:
			return s.level
	return 0

func has(id: String) -> bool:
	return level_of(id) > 0

## offer = {type: "new"|"upgrade"|"heal", id, to_level}
func offer_choices(locked: Dictionary, rng: Rng, pool: Array[String], n := 3) -> Array[Dictionary]:
	var candidates: Array = []
	for id in pool:
		if locked.has(id):
			continue
		var lv := level_of(id)
		if lv > 0:
			if lv < MAX_LEVEL:
				candidates.append({ type = "upgrade", id = id, to_level = lv + 1 })
		elif slots.size() < MAX_SLOTS:
			candidates.append({ type = "new", id = id })
	var heal: Array[Dictionary] = [{ type = "heal" }]
	if candidates.is_empty():
		return heal
	var picked: Array[Dictionary] = []
	var remaining := candidates.duplicate()
	while picked.size() < n and remaining.size() > 0:
		var weights := []
		for o in remaining:
			weights.append(Items.def(o.id).weight)
		var o = rng.pick_weighted(remaining, weights)
		if o == null:
			break
		picked.append(o)
		remaining.erase(o)
	return picked if picked.size() > 0 else heal

## returns newly unlocked hidden weapon ids
func apply_offer(offer: Dictionary) -> Array[String]:
	if offer.type == "new":
		slots.append({ id = offer.id, level = 1 })
	elif offer.type == "upgrade":
		for s in slots:
			if s.id == offer.id:
				s.level = offer.to_level
	var unlocked: Array[String] = []
	for s in slots:
		if not Items.is_weapon(s.id) or s.level < MAX_LEVEL or hidden.has(s.id):
			continue
		if has(Items.WEAPONS[s.id].paired):
			hidden[s.id] = true
			unlocked.append(s.id)
	return unlocked

static func pick_locked(rng: Rng, pool: Array[String]) -> Dictionary:
	var n := mini(pool.size(), 1 if rng.next() < 0.5 else 2)
	var out := {}
	while out.size() < n:
		out[pool[rng.rint(0, pool.size() - 1)]] = true
	return out

## modifiers from stat levels × hero base stats
func modifiers(K: Dictionary) -> Dictionary:
	return {
		damage_mul = K.damage_mul * (1.0 + 0.1 * level_of("might")),
		move_speed_mul = K.speed_mul * (1.0 + 0.08 * level_of("speed")),
		projectile_speed_mul = 1.0 + 0.08 * level_of("speed"),
		cooldown_mul = K.cooldown_mul * (1.0 - 0.08 * level_of("haste")),
		pickup_radius = Data.BALANCE.base_pickup_radius * K.pickup_radius_mul * (1.0 + 0.25 * level_of("magnet")),
		area_mul = 1.0 + 0.1 * level_of("area"),
		max_hp_bonus = 20.0 * level_of("vitality"),
		regen_per_sec = 0.4 * level_of("vitality"),
	}
