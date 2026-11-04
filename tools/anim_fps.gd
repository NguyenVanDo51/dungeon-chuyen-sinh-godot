extends SceneTree
## prints baked frames + resulting animation fps per enemy type: -s tools/anim_fps.gd -- style=quaternius
func _init() -> void:
	await process_frame
	var host := Node.new()
	get_root().add_child(host)
	var t0 := Time.get_ticks_msec()
	var ev := EnemyView.new()
	host.add_child(ev)
	var st := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("style="):
			st = a.substr(6)
	ev.build(host, Style.load_active(st))
	print("bake ms ", Time.get_ticks_msec() - t0)
	for t in ev._views:
		var v: Dictionary = ev._views[t]
		print("%s frames %d anim fps %.1f" % [Monsters.IDS[t], v.frames.size(), v.frames.size() * v.rate / v.len if v.animated else 0.0])
	quit()
