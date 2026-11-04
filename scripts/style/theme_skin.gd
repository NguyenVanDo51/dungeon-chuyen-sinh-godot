class_name ThemeSkin
extends Resource
## dungeon look for maps with this theme (Maps.DEFS[*].theme): tile pieces, light, fog, palette

@export var id := "crypt"
@export_file("*.glb", "*.gltf") var floor_piece := ""
@export_file("*.glb", "*.gltf") var wall_piece := ""
@export_file("*.glb", "*.gltf") var pillar_piece := ""
@export_file("*.glb", "*.gltf") var torch_piece := ""
## boss-room door while sealed
@export_file("*.glb", "*.gltf") var barrier_piece := ""
## clutter next to each pillar (empty = none)
@export_file("*.glb", "*.gltf") var prop_a := ""
@export_file("*.glb", "*.gltf") var prop_b := ""
@export var pillar_scale := Vector3(1.8, 1.0, 1.8)
## walls on the camera side are shortened so they never hide the player
@export var near_wall_scale := 0.3
@export var background := Color("#0d1030")
@export var ambient := Color("#3a4290")
@export var ambient_energy := 0.18
@export var sun_color := Color("#c9d4ff")
@export var sun_energy := 0.45
## fog distances past the camera distance
@export var fog_near := 8.0
@export var fog_far := 45.0
@export var torch_flame := Color("#ff8fd8")
## real torch lights alternate these
@export var torch_lights: PackedColorArray = [Color("#ff8fd8"), Color("#5ff3ff")]
@export var torch_energy := 4.0
## floor rune rings alternate these
@export var rune_colors: PackedColorArray = [Color("#ff8fd8"), Color("#5ff3ff")]
