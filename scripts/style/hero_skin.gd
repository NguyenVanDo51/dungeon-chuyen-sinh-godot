class_name HeroSkin
extends Resource
## look of one hero; id = Characters.DEFS[*].model

@export var id := ""
@export_file("*.glb", "*.gltf") var model := ""
@export var idle_clip := "Idle"
@export var run_clip := "Running_A"
## played on each slash / shot
@export var attack_clip := ""
## mesh nodes to hide (spare weapons baked into the model)
@export var hide_nodes: PackedStringArray = []
## world height in units (0 = keep the file's scale); player radius = 0.5
@export var height := 0.0
## silhouette drawn where walls / pillars hide the hero
@export var xray_color := Color(1.0, 0.56, 0.85, 0.45)
@export var halo_color := Color("#ff8fd8")
