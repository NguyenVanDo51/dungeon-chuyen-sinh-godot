class_name World
extends RefCounted
## the whole simulation (port of game/world.ts); no Nodes. Renderer reads it + drains `events` each frame.
## opts: seed, map (Maps id), rules (Dungeons.*_rules), character (Characters def, post-upgrades), locked (Array of item ids)

class Player:
	var x: float
	var z: float
	var hp: float
	var max_hp: float
	var facing_x := 0.0
	var facing_z := 1.0
	var invuln := 0.0
	var moving := false

class Gem:
	var x: float
	var z: float
	var value: float
	var magnet := false

class Pickup:
	var kind: String
	var x: float
	var z: float
	var life: float
	var magnet := false

## soul tome black hole
class Vortex:
	var x: float
	var z: float
	var r: float
	var life: float
	var tick: float

const GEM_SPEED := 14.0
const COLLECT_DIST := 0.6
const MAX_SUBSTEP := 0.25

var map: Dictionary
var rules: Dictionary
var grid: Grid
## zone index per cell
var zones: PackedByteArray
## per zone: monster type indices (repeats = weights)
var zone_types: Array = []
## hero def as this run sees it (stats × permanent upgrades)
var hero: Dictionary
var boss_def: Dictionary
## what level-up cards can offer: own signature weapon + shared pool
var item_pool: Array[String]
var rng: Rng
## coin rolls only: keeps rng (and the sim) identical to a gold-less run
var gold_rng: Rng
var time := 0.0
var paused := false
## playing | levelUp | won | lost
var state := "playing"
var player := Player.new()
var build: Build
var level := 1
var xp := 0.0
var locked := {}
var mods: Dictionary
var pending_level_ups := 0
var current_offers: Array[Dictionary] = []
var events: Array[Dictionary] = []
var kills := 0
var spawn_enabled := true
var enemies := EnemyPool.new(Data.BALANCE.max_enemies)
var enemy_hash: SpatialHash
var flow := FlowField.new()
var _flow_cell := -1
var _spawn_acc := 0.0
## depth mode: enemies left to spawn per zone
var budget: Array[int] = []
## debug: keep at least this many enemies alive
var min_enemies := 0
## set by the renderer: real camera view test (weapons only target what the player sees)
var in_view: Callable
## set by the renderer: spawn only where the camera can't see
var spawn_visibility: Callable
var god := false
var gems: Array[Gem] = []
## gold coins on the floor (same pickup rules as gems)
var coins: Array[Gem] = []
## gold earned this run; banked when the run ends
var gold := 0.0
var pickups: Array[Pickup] = []
## seconds left on the invulnerability pickup (HUD / aura)
var invuln_buff := 0.0
var projectiles: Array = []
## weapon id -> WeaponRuntime
var weapons := {}
## uid of the enemy whose contact hurt the player this tick (-1 = none)
var last_hurt_by := -1
var hurt_this_tick := false
## seconds since the player last took damage (archer light feet)
var since_hurt := 0.0
var vortices: Array[Vortex] = []
## frost ice marks: [x, z, life_left]
var frost_trail: Array = []
var boss: Boss.State = null
var boss_warned := false
## enterRoom: seconds the player has stood in the boss room this visit
var boss_warn_t := 0.0
## dungeon: the time-limit warning was shown
var limit_warned := false
## boss-room doors; dungeon floors start open and seal when the boss wakes
var doors_open := false
var boss_defeated := false
var hostile_shots: Array = []
var hostile_zones: Array = []
## this run's 2 quest kinds, in schedule order
var quests: Array[String]
var quest_next := 0
var quest: Quests.State = null
var lure: Quests.Lure = null
var quest_log: Array[Dictionary] = []
var skill: SkillRuntime
var skill_def: Dictionary
## seconds until the active skill is ready
var skill_cd := 0.0
## full cooldown of the last cast (HUD ring)
var skill_cd_max := 1.0
var _boss_idx_cache := 0

func _init(opts: Dictionary = {}) -> void:
	var seed_value: int = opts.get("seed", 1)
	map = Maps.DEFS[opts.get("map", Dungeons.SURVIVAL_MAP)]
	rules = opts.get("rules", Dungeons.survival_rules())
	grid = Grid.parse(Maps.ascii(map.id))
	boss_def = Bosses.DEFS[map.boss]
	if map.has("depth"):
		for b in map.depth.budget:
			budget.append(b)
	# dungeon: the way to the boss is open (doors count as floor for zones and flow)
	if rules.boss == "enterRoom":
		grid.set_doors(true)
		doors_open = true
	for pool in map.zone_types:
		var ids: Array[int] = []
		for id in pool:
			ids.append(Monsters.idx(id))
		zone_types.append(ids)
	zones = Zones.compute(grid, zone_types.size())
	enemy_hash = SpatialHash.new(2.0, grid.w * Grid.CELL, grid.h * Grid.CELL, enemies.capacity)
	rng = Rng.new(seed_value)
	gold_rng = Rng.new(seed_value ^ 0x5bd1e995)
	hero = opts.get("character", Characters.DEFS[Characters.DEFAULT])
	skill_def = Characters.SKILLS[hero.skill]
	var shared := Characters.shared_items()
	item_pool = [hero.weapon]
	item_pool.append_array(shared)
	player.x = grid.start.x
	player.z = grid.start.y
	player.hp = hero.hp
	player.max_hp = hero.hp
	build = Build.new(hero.weapon)
	skill = Skills.create(hero.skill)
	var lo: Array = opts.get("locked", [])
	if lo.is_empty():
		locked = Build.pick_locked(rng, shared)
	else:
		for id in lo:
			locked[id] = true
	quests = Quests.pick_kinds(rng, map.quests)
	mods = compute_mods()
	sync_weapons()
	refresh_flow_field()

# ---------- queries ----------

## weapons target only what is on screen; headless runs use the VIEW box around the player
func on_screen(x: float, z: float) -> bool:
	if in_view.is_valid():
		return in_view.call(x, z)
	var dx := x - player.x
	var dz := z - player.z
	return absf(dx) <= Data.VIEW.side and dz >= -Data.VIEW.up and dz <= Data.VIEW.down

func zone_at(x: float, z: float) -> int:
	var cx := int(floor(x / Grid.CELL))
	var cz := int(floor(z / Grid.CELL))
	if cx < 0 or cz < 0 or cx >= grid.w or cz >= grid.h:
		return 0
	return zones[cz * grid.w + cx]

func last_zone() -> int:
	return zone_types.size() - 1

## hp / contact-damage / elite-chance multipliers for a zone: survival scales with time, a dungeon with depth
func scale_at(zone: int) -> Dictionary:
	var dif: float = rules.difficulty
	if rules.spawn != "depth" or not map.has("depth"):
		return { hp = Monsters.hp_scale(time) * dif, dmg = Monsters.dmg_scale(time) * dif, elite = Monsters.elite_chance(time) }
	var d: Dictionary = map.depth
	var z := mini(zone, d.hp.size() - 1)
	return { hp = d.hp[z] * dif, dmg = d.dmg[z] * dif, elite = d.elite[z] }

## seconds until the boss fight starts at the latest (survival 8:00, dungeon the pull)
func boss_time() -> float:
	return rules.boss_at

## cached: the boss rarely moves in the pool, so the last index is usually still right
func boss_index() -> int:
	if boss == null:
		return -1
	if _boss_idx_cache < enemies.count and enemies.uid[_boss_idx_cache] == boss.uid:
		return _boss_idx_cache
	_boss_idx_cache = enemies.index_of_uid(boss.uid)
	return _boss_idx_cache

func refresh_flow_field() -> void:
	var cx := int(floor(player.x / Grid.CELL))
	var cz := int(floor(player.z / Grid.CELL))
	var key := cz * grid.w + cx
	if key == _flow_cell:
		return
	_flow_cell = key
	flow.compute(grid, cx, cz)

# ---------- build ----------

func compute_mods() -> Dictionary:
	var m := build.modifiers(hero)
	# grow current hp by exactly the max-hp gain so a new Máu level feels like an instant heal
	var max_hp: float = hero.hp + m.max_hp_bonus
	if max_hp > player.max_hp and player.max_hp < 1e8:
		player.hp += max_hp - player.max_hp
		player.max_hp = max_hp
	return m

func base_max_hp() -> float:
	return hero.hp + mods.max_hp_bonus

func sync_weapons() -> void:
	for s in build.slots:
		if Items.is_weapon(s.id) and not weapons.has(s.id):
			weapons[s.id] = Weapons.create(s.id)

## debug: preset items/levels (may exceed slot cap); still runs the normal hidden-skill check
func debug_give(items: Dictionary) -> void:
	for id in items:
		var found := false
		for s in build.slots:
			if s.id == id:
				s.level = items[id]
				found = true
		if not found:
			build.slots.append({ id = id, level = items[id] })
	build.apply_offer({ type = "heal" })
	mods = compute_mods()
	sync_weapons()

func choose_offer(index: int) -> void:
	if paused or state != "levelUp" or index >= current_offers.size():
		return
	var offer := current_offers[index]
	if offer.type == "heal":
		player.hp = minf(player.max_hp, player.hp + Data.BALANCE.heal_amount)
	for id in build.apply_offer(offer):
		events.append({ t = "hiddenUnlocked", id = id })
	mods = compute_mods()
	sync_weapons()
	pending_level_ups -= 1
	_open_level_up_if_pending()

func _open_level_up_if_pending() -> void:
	if pending_level_ups > 0:
		state = "levelUp"
		current_offers = build.offer_choices(locked, rng, item_pool)
		events.append({ t = "levelUp" })
	else:
		state = "playing"
		current_offers = []

func add_xp(amount: float) -> void:
	xp += amount
	while xp >= Data.xp_to_next(level):
		xp -= Data.xp_to_next(level)
		level += 1
		pending_level_ups += 1

# ---------- events from systems ----------

func heal(amount: float) -> void:
	if player.hp <= 0.0:
		return
	player.hp = minf(player.max_hp, player.hp + amount)

func weapon_hits(weapon: String, hits: int) -> void:
	Characters.on_weapon_hits(self, weapon, hits)

func add_gold(amount: float) -> void:
	var a: float = amount * rules.gold_mul
	gold += a
	events.append({ t = "gold", amount = a })

func _drop_coin(x: float, z: float, elite: bool, zone: int) -> void:
	var G := Data.GOLD
	if not elite and gold_rng.next() >= G.drop_chance:
		return
	var zv: Array = G.zone_value
	var value: float = (G.elite if elite else (zv[zone] if zone < zv.size() else zv[0])) * rules.gold_mul
	if coins.size() < G.max_coins:
		var c := Gem.new()
		c.x = x; c.z = z; c.value = value
		coins.append(c)
		return
	_nearest(coins, x, z).value += value

static func _nearest(list: Array[Gem], x: float, z: float) -> Gem:
	var best: Gem = list[0]
	var best_d := INF
	for g in list:
		var d := (g.x - x) * (g.x - x) + (g.z - z) * (g.z - z)
		if d < best_d:
			best_d = d
			best = g
	return best

func on_enemy_killed(x: float, z: float, t: int, elite: bool, zone: int) -> void:
	# boss fight: adds and summons are pressure only, no loot to snowball on
	if boss != null:
		return
	_drop_pickup(x, z, elite)
	_drop_coin(x, z, elite, zone)
	var zx: Array = map.zone_xp_mul
	var value: float = Monsters.DEFS[t].xp * (Monsters.ELITE.xp_mul if elite else 1.0) * (zx[zone] if zone < zx.size() else 1.0)
	# past the cap, fold xp into the nearest gem so huge waves don't flood the floor
	if gems.size() < Data.BALANCE.max_gems:
		var g := Gem.new()
		g.x = x; g.z = z; g.value = value
		gems.append(g)
		return
	_nearest(gems, x, z).value += value

func on_boss_killed() -> void:
	boss_defeated = true
	boss = null
	hostile_shots.clear()
	hostile_zones.clear()
	add_gold(Data.GOLD.boss)
	state = "won"
	events.append({ t = "win" })

## boss time: everything outside vanishes (gems stay); pull = a dungeon player dragged in when time ran out
func enter_arena(pull := false) -> void:
	# a quest still open when the boss wakes counts as failed
	if quest != null:
		Quests.end(self, false)
	enemies.count = 0
	hostile_shots.clear()
	hostile_zones.clear()
	spawn_enabled = false
	if rules.boss == "enterRoom":
		# the player walked in: seal the doors behind them instead of teleporting
		grid.set_doors(false)
		doors_open = false
		# the boss appears beside a player who walked in: same grace as the survival arena drop
		player.invuln = maxf(player.invuln, 1.0)
		events.append({ t = "doors", open = false })
		_flow_cell = -1
		refresh_flow_field()
		events.append({ t = "bossArena", pull = pull })
		return
	var at: Vector2
	if map.has("arena_entry"):
		at = Grid.cell_center(map.arena_entry.x, map.arena_entry.y)
	else:
		var s := grid.boss_spawn if grid.has_boss_spawn else grid.start
		at = Vector2(s.x, s.y + 5.0 * Grid.CELL)
	player.x = at.x
	player.z = at.y
	player.invuln = maxf(player.invuln, 1.0)
	_flow_cell = -1
	refresh_flow_field()
	events.append({ t = "bossArena", pull = false })

# ---------- tick ----------

## input: move (mx, mz), any length; skill_key = key went down this tick
func tick(dt: float, mx: float, mz: float, skill_key: bool) -> void:
	if paused or state != "playing":
		return
	time += dt
	hurt_this_tick = false
	last_hurt_by = -1
	since_hurt += dt
	_move_player(mx, mz, Data.BALANCE.player_speed * mods.move_speed_mul * Characters.move_speed_mul(self), dt)
	if player.invuln > 0.0:
		player.invuln = maxf(0.0, player.invuln - dt)
	if invuln_buff > 0.0:
		invuln_buff = maxf(0.0, invuln_buff - dt)
	_update_skill(dt, skill_key)
	if mods.regen_per_sec > 0.0:
		heal(mods.regen_per_sec * dt)
	_spawn_enemies(dt)
	Boss.update(self, dt)
	Quests.update(self, dt)
	Enemies.update(self, dt)
	Boss.update_hostile(self, dt)
	for s in build.slots:
		if Items.is_weapon(s.id):
			weapons[s.id].update(self, s.level, build.hidden.has(s.id), dt)
	Projectiles.update(self, dt)
	# no pickups after the winning blow: the end screen must show the level the player chose
	if state != "won":
		_pull_list(gems, dt, true)
		_pull_list(coins, dt, false)
		_update_pickups(dt)
	if god:
		player.hp = maxf(player.hp, 1.0)
	# death wins ties: dying on the same tick the boss falls is still a loss
	if player.hp <= 0.0:
		player.hp = 0.0
		state = "lost"
		var kept: Array[Dictionary] = []
		kept.assign(events.filter(func(e: Dictionary) -> bool: return e.t != "win"))
		events = kept
		events.append({ t = "lose" })
		return
	if state == "won":
		return
	if pending_level_ups > 0:
		_open_level_up_if_pending()

func _move_player(mx: float, mz: float, speed: float, dt: float) -> void:
	var p := player
	var l := Vec.hypot(mx, mz)
	p.moving = l > 0.0
	if not p.moving:
		return
	var nx := mx / l
	var nz := mz / l
	p.facing_x = nx
	p.facing_z = nz
	var dist := speed * dt
	# sub-steps keep each move shorter than the player radius so walls cannot be tunnelled
	var steps := maxi(1, int(ceil(dist / MAX_SUBSTEP)))
	var step := dist / steps
	for i in steps:
		Collision.resolve(grid, p.x + nx * step, p.z + nz * step, Data.BALANCE.player_radius)
		p.x = Collision.rx
		p.z = Collision.rz

func skill_radius() -> float:
	return skill.radius(self)

func _update_skill(dt: float, want_key: bool) -> void:
	skill_cd = maxf(0.0, skill_cd - dt)
	skill.update(self, dt)
	var want := want_key if skill_def.trigger == "manual" else skill.should_trigger(self)
	if not want or skill_cd > 0.0:
		return
	var x := player.x
	var z := player.z
	if not skill.activate(self):
		return
	skill_cd = skill_def.cooldown * mods.cooldown_mul
	skill_cd_max = skill_cd
	events.append({ t = "skill", id = skill_def.id, x = x, z = z, r = skill.radius(self) })

func _spawn_enemies(dt: float) -> void:
	if not spawn_enabled:
		return
	var depth: Dictionary = map.depth if rules.spawn == "depth" and map.has("depth") else {}
	var pz := zone_at(player.x, player.z)
	if depth.is_empty():
		_spawn_acc += Monsters.spawn_rate(time) * dt
	else:
		_spawn_acc += (depth.rate[pz] if pz < depth.rate.size() else 0.0) * dt
	var deficit := min_enemies - enemies.count
	var n := int(floor(_spawn_acc)) + maxi(0, deficit)
	_spawn_acc -= floor(_spawn_acc)
	if n <= 0:
		return
	var elites := 0
	for i in enemies.count:
		elites += enemies.elite[i]
	while n > 0 and enemies.count < enemies.capacity:
		n -= 1
		if not _pick_spawn_point():
			continue
		var px := _spawn_x
		var pz2 := _spawn_z
		# the spawn point's zone decides the type: chasers keep theirs when the player crosses zones
		var zone := zone_at(px, pz2)
		# depth: nothing comes from deeper than the player, the boss room, or a spent zone
		if not depth.is_empty():
			if zone > pz or grid.in_boss_room(px, pz2) or not (zone < budget.size() and budget[zone] > 0):
				continue
			budget[zone] -= 1
		var s := scale_at(zone)
		var pool: Array = zone_types[zone] if zone < zone_types.size() else zone_types[0]
		var t: int = pool[rng.rint(0, pool.size() - 1)]
		var elite: bool = elites < Monsters.ELITE_MAX_ALIVE and rng.next() < s.elite
		if elite:
			elites += 1
		enemies.spawn(t, px, pz2, Monsters.DEFS[t].hp * s.hp * (Monsters.ELITE.hp_mul if elite else 1.0), elite, zone)

var _spawn_x := 0.0
var _spawn_z := 0.0

## true = found, point in _spawn_x / _spawn_z
func _pick_spawn_point() -> bool:
	var B := Data.BALANCE
	for attempt in 30:
		var a := rng.next() * TAU
		var d: float = B.spawn_min + rng.next() * (B.spawn_max - B.spawn_min)
		var x := player.x + cos(a) * d
		var z := player.z + sin(a) * d
		var cx := int(floor(x / Grid.CELL))
		var cz := int(floor(z / Grid.CELL))
		if not grid.walkable(cx, cz):
			continue
		if flow.dist[cz * grid.w + cx] < 0:
			continue
		if spawn_visibility.is_valid() and spawn_visibility.call(x, z):
			continue
		_spawn_x = x
		_spawn_z = z
		return true
	return false

## gems (xp) and coins (gold): magnet inside pickup radius, collect on touch
func _pull_list(list: Array[Gem], dt: float, is_xp: bool) -> void:
	var p := player
	var r: float = mods.pickup_radius
	for k in range(list.size() - 1, -1, -1):
		var g := list[k]
		var dx := p.x - g.x
		var dz := p.z - g.z
		var d := Vec.hypot(dx, dz)
		if d <= r:
			g.magnet = true
		if g.magnet and d > COLLECT_DIST:
			var step := minf(d, GEM_SPEED * dt)
			g.x += (dx / d) * step
			g.z += (dz / d) * step
		if Vec.hypot(p.x - g.x, p.z - g.z) <= COLLECT_DIST:
			if is_xp:
				add_xp(g.value)
			else:
				gold += g.value
				events.append({ t = "gold", amount = g.value })
			list[k] = list[list.size() - 1]
			list.pop_back()

func _drop_pickup(x: float, z: float, elite: bool) -> void:
	var P := Data.PICKUPS
	if not elite and (pickups.size() >= P.max or rng.next() >= P.drop_chance):
		return
	# elites always drop: at the cap the oldest pickup makes room
	if pickups.size() >= P.max:
		var old := 0
		for k in range(1, pickups.size()):
			if pickups[k].life < pickups[old].life:
				old = k
		pickups.remove_at(old)
	var it := Pickup.new()
	it.kind = rng.pick_weighted(Data.PICKUP_KINDS, P.weights)
	it.x = x; it.z = z; it.life = P.life
	pickups.append(it)

func _apply_pickup(kind: String) -> void:
	var p := player
	var P := Data.PICKUPS
	match kind:
		"heal":
			heal(Data.BALANCE.heal_amount)
		"invuln":
			p.invuln = maxf(p.invuln, P.invuln_seconds)
			invuln_buff = P.invuln_seconds
		"magnet":
			for list in [gems, coins]:
				for g in list:
					if Vec.hypot(g.x - p.x, g.z - p.z) <= P.magnet_radius:
						g.magnet = true
		"freeze":
			for i in enemies.count:
				if Vec.hypot(enemies.x[i] - p.x, enemies.z[i] - p.z) <= P.freeze_radius:
					Enemies.freeze(self, i, P.freeze_seconds, true)
	events.append({ t = "pickup", kind = kind })

func _update_pickups(dt: float) -> void:
	var p := player
	var r: float = mods.pickup_radius
	for k in range(pickups.size() - 1, -1, -1):
		var it := pickups[k]
		it.life -= dt
		var dx := p.x - it.x
		var dz := p.z - it.z
		var d := Vec.hypot(dx, dz)
		if d <= r:
			it.magnet = true
		if it.magnet and d > COLLECT_DIST:
			var s := minf(d, GEM_SPEED * dt)
			it.x += (dx / d) * s
			it.z += (dz / d) * s
		var got := Vec.hypot(p.x - it.x, p.z - it.z) <= COLLECT_DIST
		if got or it.life <= 0.0:
			pickups[k] = pickups[pickups.size() - 1]
			pickups.pop_back()
		if got:
			_apply_pickup(it.kind)
