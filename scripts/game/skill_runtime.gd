class_name SkillRuntime
extends RefCounted
## base for active skills; activate false = nothing happened, cooldown not spent

func activate(_w: World) -> bool:
	return false

func update(_w: World, _dt: float) -> void:
	pass

## trigger "auto" skills only
func should_trigger(_w: World) -> bool:
	return false

## area for the skill VFX (0 = none)
func radius(_w: World) -> float:
	return 0.0
