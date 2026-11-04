class_name MonsterSkin
extends Resource
## look of one enemy type; id = Monsters.DEFS[*].id. Animated models are baked to a flipbook at load.

@export var id := ""
## model = glTF + looping clip; slime = procedural blob (no file)
@export_enum("model", "slime") var kind := "model"
@export_file("*.glb", "*.gltf") var model := ""
@export var clip := ""
## world height of the baked pose (0 = use `scale`)
@export var height := 1.0
@export var scale := 1.0
## clip playback speed
@export var anim_rate := 1.0
## multiplies the texture colour
@export var tint := Color.WHITE
@export var emissive := Color.BLACK
@export var emissive_energy := 0.0
## instances drawn per frame (0 = enemy pool size)
@export var max_instances := 0
