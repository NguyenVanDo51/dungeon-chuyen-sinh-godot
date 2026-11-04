extends SceneTree
## headless balance sim (port of scripts/sim/balance.sim.ts)
## godot --headless -s sim/sim.gd -- seeds=20 char=knight|archer quests=skip|do skill=1 mode=dungeon floor=1|2 diff=1.3 boss_diff=1.5 verbose=1 only=3,5

var args := {}

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("seeds", "20"))
	var chars: Array[String] = Characters.IDS.duplicate()
	if args.has("char"):
		chars = [args.char]
	var modes: Array[bool] = [false, true]
	if args.get("quests", "") == "skip": modes = [false]
	elif args.get("quests", "") == "do": modes = [true]
	var only: Array[int] = []
	if args.has("only"):
		for s in args.only.split(","):
			only.append(int(s))
	var t0 := Time.get_ticks_msec()
	for c in chars:
		for s in [1, 2, 3]:
			print(_run(s, true, c, false).line)
	for c in chars:
		for do_q in modes:
			var rs: Array[Dictionary] = []
			for k in n:
				if only.size() > 0 and not only.has(k + 1):
					continue
				var r := _run(k + 1, false, c, do_q)
				rs.append(r)
				if args.has("verbose"):
					print(r.line)
			var tag := "%s %s" % [c, "DO" if do_q else "SKIP"]
			var cnt := func(key: String) -> int: return rs.filter(func(r: Dictionary) -> bool: return r[key]).size()
			var avg := func(xs: Array, key: String) -> float:
				var t := 0.0
				for r in xs: t += r[key]
				return t / maxi(1, xs.size())
			var reached := rs.filter(func(r: Dictionary) -> bool: return r.reached)
			print("%s quests: win %d/%d, boss reached %d/%d, level at boss avg %.1f, quests done avg %.2f" % [tag, cnt.call("won"), rs.size(), reached.size(), rs.size(), avg.call(reached, "boss_level"), avg.call(rs, "quests")])
			if args.get("mode", "") == "dungeon":
				print("%s floor %s: boss at avg %ds" % [tag, args.get("floor", "1"), avg.call(reached, "boss_at")])
			print("%s gold: avg %d, left on floor avg %d" % [tag, avg.call(rs, "gold"), avg.call(rs, "floor_gold")])
	print("wall time %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()

func _run(seed_value: int, idle: bool, c: String, do_q: bool) -> Dictionary:
	var dungeon: bool = args.get("mode", "") == "dungeon"
	var f := maxi(0, int(args.get("floor", "1")) - 1)
	var rules := Dungeons.floor_rules("crypt", f) if dungeon else Dungeons.survival_rules()
	if args.has("diff"): rules.difficulty = float(args.diff)
	if args.has("boss_diff"): rules.boss_difficulty = float(args.boss_diff)
	var map_id: String = Dungeons.floor_map("crypt", f) if dungeon else args.get("map", Dungeons.SURVIVAL_MAP)
	var w := World.new({ seed = seed_value, map = map_id, rules = rules, character = Characters.DEFS[c] })
	var bot := Bot.new(w, do_q)
	bot.dungeon = dungeon
	var skill := args.has("skill")
	var dt := 1.0 / 30.0
	var boss_at := -1.0
	var boss_level := 0
	var lv_at: Array[int] = []
	while w.state == "playing" or w.state == "levelUp":
		if w.state == "levelUp":
			w.choose_offer(bot.pick(w.current_offers))
			continue
		var mv: Array = [0.0, 0.0] if idle else bot.input(w.time)
		w.tick(dt, mv[0], mv[1], skill and not idle and bot.want_skill())
		if boss_at < 0.0 and w.boss != null:
			boss_at = w.time
			boss_level = w.level
		if w.time >= (lv_at.size() + 1) * 60.0 and lv_at.size() < 8:
			lv_at.append(w.level)
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
	var boss_info := "no boss" if boss_at < 0.0 else "boss %ds%s" % [roundi(w.time - boss_at), (" hp%d" % roundi(w.enemies.hp[bi])) if bi >= 0 else ""]
	var budget_left := " budget%s z%d" % [str(w.budget), w.zone_at(w.player.x, w.player.z)] if dungeon else ""
	var floor_gold := 0.0
	for cn in w.coins:
		floor_gold += cn.value
	var line := "  %s %s %s s%d: %s %.2fm lv%d kills%d %s quests%s lvByMin%s slots%s%s gold%d" % [
		c, "do" if do_q else "skip", "idle" if idle else "kite", seed_value, w.state, w.time / 60.0, w.level, w.kills, boss_info, str(qs), str(lv_at), str(slots), budget_left, roundi(w.gold)]
	return { won = w.state == "won", reached = boss_at >= 0.0, boss_at = boss_at, boss_level = boss_level, quests = done, gold = w.gold, floor_gold = floor_gold, line = line }
