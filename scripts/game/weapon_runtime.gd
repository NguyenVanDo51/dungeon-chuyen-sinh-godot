class_name WeaponRuntime
extends RefCounted
## base for weapon logic; one file per weapon in scripts/game/weapons/, registered in Weapons.SCRIPTS

var id: String
## render-facing state for weapons that own persistent objects (flying swords): [{x, z, angle, dashing}]
var visuals: Array = []

func update(_w: World, _level: int, _hidden: bool, _dt: float) -> void:
	pass
