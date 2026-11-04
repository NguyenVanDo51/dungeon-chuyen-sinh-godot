extends SceneTree
## headless balance sim: godot --headless -s sim/sim.gd -- seeds=20 quests=skip|do|both skill=1 verbose=1 only=3,5

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("seeds", "10"))
	var modes: Array[bool] = [false, true]
	if args.get("quests", "both") == "skip": modes = [false]
	elif args.get("quests", "both") == "do": modes = [true]
	var only: Array[int] = []
	if args.has("only"):
		for s in args.only.split(","):
			only.append(int(s))
	var skill := args.has("skill")
	var verbose := args.has("verbose")
	var t0 := Time.get_ticks_msec()
	for s in [1, 2]:
		print(_run(s, true, false, false).line)
	for do_q in modes:
		var wins := 0
		var reached := 0
		var qdone := 0
		var lv_boss := 0
		var runs := 0
		for k in n:
			if only.size() > 0 and not only.has(k + 1):
				continue
			var r := _run(k + 1, false, do_q, skill)
			runs += 1
			if verbose:
				print(r.line)
			wins += 1 if r.won else 0
			reached += 1 if r.boss_at >= 0.0 else 0
			lv_boss += r.boss_level
			qdone += r.quests
		print("knight %s quests: win %d/%d, boss reached %d/%d, level at boss avg %.1f, quests done avg %.2f" % [
			"DO" if do_q else "SKIP", wins, runs, reached, runs, float(lv_boss) / maxi(1, reached), float(qdone) / maxi(1, runs)])
	print("wall time %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()

func _run(seed_value: int, idle: bool, do_q: bool, skill: bool) -> Dictionary:
	var w := World.new(seed_value)
	var bot := Bot.new(w, do_q)
	var dt := 1.0 / 30.0
	var boss_at := -1.0
	var boss_level := 0
	var lv_at: Array[int] = []
	var casts := {}
	while w.state == "playing" or w.state == "levelUp":
		if w.state == "levelUp":
			w.choose_offer(bot.pick(w.current_offers))
			continue
		var mv := Vector2.ZERO if idle else bot.input(w.time)
		w.tick(dt, mv, skill and bot.want_skill())
		if boss_at < 0.0 and w.boss != null:
			boss_at = w.time
			boss_level = w.level
		if w.time >= (lv_at.size() + 1) * 60.0 and lv_at.size() < 8:
			lv_at.append(w.level)
		for ev in w.events:
			if ev.t == "bossCast":
				casts[ev.kind] = casts.get(ev.kind, 0) + 1
		w.events.clear()
		if w.time > 900.0:
			break
	var qs := []
	var done := 0
	for q in w.quest_log:
		qs.append(q.kind + ("✔" if q.success else "✘"))
		done += 1 if q.success else 0
	var slots := []
	for s in w.build.slots:
		slots.append("%s%d" % [s.id, s.level])
	var bi := w.boss_index()
	var boss_info := "no boss" if boss_at < 0.0 else "boss %ds%s casts%s" % [w.time - boss_at, (" hp%d" % w.enemies.hp[bi]) if bi >= 0 else "", str(casts)]
	var line := "  knight %s %s s%d: %s %.2fm lv%d kills%d %s quests%s lvByMin%s slots%s locked%s" % [
		"do" if do_q else "skip", "idle" if idle else "kite", seed_value, w.state, w.time / 60.0, w.level, w.kills, boss_info, str(qs), str(lv_at), str(slots), str(w.locked.keys())]
	return { won = w.state == "won", boss_at = boss_at, boss_level = boss_level, quests = done, line = line }
