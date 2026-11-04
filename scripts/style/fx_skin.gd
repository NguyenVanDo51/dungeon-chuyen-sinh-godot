class_name FxSkin
extends Resource
## effect palette + prop models; Gfx.GLOW sets how hard each one blooms

@export var primary := Color("#ff8fd8")
@export var secondary := Color("#5ff3ff")
@export var gold := Color("#ffd36e")
@export var xp_gem := Color("#7dff9a")
@export var fireball := Color("#ff9a5c")
@export var fire_burst := Color("#ff7a6b")
@export var meteor := Color("#ffb36b")
@export var danger := Color("#ff4d6d")
@export var boss_zone := Color("#ff4d8d")
@export var frost := Color("#9ff6ff")
@export var soul := Color("#b08cff")
@export var arrow := Color("#5ff3ff")
@export var pickup_heal := Color("#ff6b9a")
@export var pickup_magnet := Color("#ffd36e")
@export var pickup_freeze := Color("#9ff6ff")
@export var pickup_invuln := Color("#fff2b0")
## flying swords mesh (empty = a glowing blade)
@export_file("*.glb", "*.gltf") var sword_model := ""
