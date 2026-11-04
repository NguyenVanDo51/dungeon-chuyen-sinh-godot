extends SceneTree
func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		extra = " mesh surfaces=%d skin=%s aabb=%s" % [mi.mesh.get_surface_count(), str(mi.skin != null), str(mi.mesh.get_aabb())]
	if n is Node3D and depth < 3:
		extra += " xf=" + str((n as Node3D).transform.origin) + " s=" + str((n as Node3D).scale)
	print("  ".repeat(depth), n.name, " <", n.get_class(), ">", extra)
	for c in n.get_children():
		_dump(c, depth + 1)
func _init() -> void:
	for f in ["characters/Skeleton_Minion.glb", "characters/Knight.glb", "dungeon/wall.glb", "dungeon/floor_tile_large.glb", "dungeon/torch_lit.glb"]:
		var s: PackedScene = load("res://assets/" + f)
		var n := s.instantiate()
		print("== ", f)
		_dump(n, 0)
		var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			print("  anims: ", ap.get_animation_list())
	print("has bake: ", MeshInstance3D.new().has_method("bake_mesh_from_current_skeleton_pose"))
	quit()
