class_name BossSkin
extends Resource
## look of one boss; id = Bosses.DEFS[*].id

@export var id := ""
@export_file("*.glb", "*.gltf") var model := ""
@export var scale := 2.4
@export var walk_clip := ""
@export var idle_clip := ""
@export var cast_clip := ""
@export var summon_clip := ""
@export var death_clip := ""
## emission glow, calm / enraged
@export var calm_color := Color("#6b3cff")
@export var angry_color := Color("#ff2b4d")
