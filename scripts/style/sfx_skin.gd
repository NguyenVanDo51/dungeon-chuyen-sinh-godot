class_name SfxSkin
extends Resource
## sounds: <folder>/<slot>/*.ogg|wav = variations (random pick + pitch jitter) -> swap a sound = replace files in its folder
## music: <music_folder>/<menu|combat|boss>.ogg|mp3|wav (looped); missing file = silence. Slot list: Sfx.SLOTS

@export_dir var folder := "res://assets/sfx/default"
@export_dir var music_folder := "res://assets/music/default"
## per-slot volume offset (dB); missing = 0
@export var gain_db: Dictionary[String, float] = {}
@export var music_db := -12.0
@export_range(0.0, 0.3) var pitch_jitter := 0.07
