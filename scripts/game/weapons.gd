class_name Weapons
## weapon registry (port of game/weapons/index.ts); add a weapon: Items entry + a file here + one line below

const SCRIPTS := {
	holySword = preload("res://scripts/game/weapons/holy_sword.gd"),
	elvenBow = preload("res://scripts/game/weapons/elven_bow.gd"),
	flyingSwords = preload("res://scripts/game/weapons/flying_swords.gd"),
	fireball = preload("res://scripts/game/weapons/fireball.gd"),
	thunderSeal = preload("res://scripts/game/weapons/thunder_seal.gd"),
	frostRing = preload("res://scripts/game/weapons/frost_ring.gd"),
	holyShield = preload("res://scripts/game/weapons/holy_shield.gd"),
	soulTome = preload("res://scripts/game/weapons/soul_tome.gd"),
}

static func create(id: String) -> WeaponRuntime:
	if not SCRIPTS.has(id):
		push_error("unknown weapon " + id)
		return WeaponRuntime.new()
	var r: WeaponRuntime = SCRIPTS[id].new()
	r.id = id
	return r
