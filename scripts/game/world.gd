class_name World
extends RefCounted
## the whole simulation; no Nodes. Renderer reads it + drains `events` each frame.

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

const GEM_SPEED := 14.0
const COLLECT_DIST := 0.6
const MAX_SUBSTEP := 0.25

var grid: Grid
## zone index per cell
var zones: PackedByteArray
var item_pool: Array[String]
var rng: Rng
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
## debug: keep at least this many enemies alive
var min_enemies := 0
## set by the renderer: real camera view test (weapons only target what the player sees)
var in_view: Callable
## set by the renderer: spawn only where the camera can't see
var spawn_visibility: Callable
var god := false
var gems: Array[Gem] = []
var pickups: Array[Pickup] = []
## seconds left on the invulnerability pickup (HUD / aura)
var invuln_buff := 0.0
var projectiles: Array = []
## weapon id -> Weapons.Runtime
var weapons := {}
var last_hurt_by := -1
var hurt_this_tick := false
var since_hurt := 0.0
## Vector3(x, z, life_left)
var frost_trail: Array[Vector3] = []
var boss: Boss.State = null
var boss_warned := false
var boss_defeated := false
var hostile_shots: Array = []
var hostile_zones: Array = []
var quests: Array[String]
var quest_next := 0
var quest: Quests.State = null
var lure: Quests.Lure = null
var quest_log: Array[Dictionary] = []
var skill_cd := 0.0
var skill_cd_max := 1.0
var _boss_idx_cache := 0

func _init(seed_value: int, locked_override: Array = []) -> void:
	grid = Grid.parse(Data.MAP_ASCII)
	zones = Zones.compute(grid, Data.ZONE_TYPES.size())
	enemy_hash = SpatialHash.new(2.0, grid.w * Grid.CELL, grid.h * Grid.CELL, enemies.capacity)
	rng = Rng.new(seed_value)
	var shared := Data.shared_items()
	item_pool = [Data.KNIGHT.weapon]
	item_pool.append_array(shared)
	player.x = grid.start.x
	player.z = grid.start.y
	player.hp = Data.KNIGHT.hp
	player.max_hp = Data.KNIGHT.hp
	build = Build.new(Data.KNIGHT.weapon)
	if locked_override.is_empty():
		locked = Build.pick_locked(rng, shared)
	else:
		for id in locked_override:
			locked[id] = true
	quests = Quests.pick_kinds(rng)
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

## hp / contact-damage / elite-chance multipliers (survival: by time)
func scale_at(_zone: int) -> Dictionary:
	return { hp = Data.hp_scale(time), dmg = Data.dmg_scale(time), elite = Data.elite_chance(time) }

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
	var m := build.modifiers()
	# grow current hp by exactly the max-hp gain so a new Máu level feels like an instant heal
	var max_hp: float = Data.KNIGHT.hp + m.max_hp_bonus
	if max_hp > player.max_hp:
		player.hp += max_hp - player.max_hp
		player.max_hp = max_hp
	return m

func sync_weapons() -> void:
	for s in build.slots:
		if Data.is_weapon(s.id) and not weapons.has(s.id):
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

## knight passive: heal per enemy hit by the holy sword, capped per swing
func weapon_hits(weapon: String, hits: int) -> void:
	if weapon != "holySword" or hits <= 0:
		return
	heal(minf(Data.LEECH.max_per_swing, Data.LEECH.per_hit * hits))

func on_enemy_killed(x: float, z: float, t: int, elite: bool, zone: int) -> void:
	# boss fight: adds and summons are pressure only, no loot to snowball on
	if boss != null:
		return
	_drop_pickup(x, z, elite)
	var value: float = Data.ENEMIES[t].xp * (Data.ELITE.xp_mul if elite else 1.0) * Data.ZONE_XP_MUL[mini(zone, 2)]
	# past the cap, fold xp into the nearest gem so huge waves don't flood the floor
	if gems.size() < Data.BALANCE.max_gems:
		var g := Gem.new()
		g.x = x; g.z = z; g.value = value
		gems.append(g)
		return
	var best: Gem = gems[0]
	var best_d := INF
	for g in gems:
		var d := (g.x - x) * (g.x - x) + (g.z - z) * (g.z - z)
		if d < best_d:
			best_d = d
			best = g
	best.value += value

func on_boss_killed() -> void:
	boss_defeated = true
	boss = null
	hostile_shots.clear()
	hostile_zones.clear()
	state = "won"
	events.append({ t = "win" })

## boss time: everything outside vanishes (gems stay), the player lands in the sealed boss room
func enter_arena() -> void:
	if quest != null:
		Quests.end(self, false)
	enemies.count = 0
	hostile_shots.clear()
	hostile_zones.clear()
	spawn_enabled = false
	var at := Grid.cell_center(Data.ARENA_ENTRY.x, Data.ARENA_ENTRY.y)
	player.x = at.x
	player.z = at.y
	player.invuln = maxf(player.invuln, 1.0)
	_flow_cell = -1
	refresh_flow_field()
	events.append({ t = "bossArena" })

# ---------- tick ----------

## input: Vector2(x, z) move; skill = key went down this tick
func tick(dt: float, move: Vector2, skill: bool) -> void:
	if paused or state != "playing":
		return
	time += dt
	hurt_this_tick = false
	last_hurt_by = -1
	since_hurt += dt
	_move_player(move, Data.BALANCE.player_speed * mods.move_speed_mul, dt)
	if player.invuln > 0.0:
		player.invuln = maxf(0.0, player.invuln - dt)
	if invuln_buff > 0.0:
		invuln_buff = maxf(0.0, invuln_buff - dt)
	_update_skill(dt, skill)
	if mods.regen_per_sec > 0.0:
		heal(mods.regen_per_sec * dt)
	_spawn_enemies(dt)
	Boss.update(self, dt)
	Quests.update(self, dt)
	Enemies.update(self, dt)
	Boss.update_hostile(self, dt)
	for s in build.slots:
		if Data.is_weapon(s.id):
			weapons[s.id].update(self, s.level, build.hidden.has(s.id), dt)
	Projectiles.update(self, dt)
	# no pickups after the winning blow: the end screen must show the level the player chose
	if state != "won":
		_update_gems(dt)
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

func _move_player(move: Vector2, speed: float, dt: float) -> void:
	var p := player
	var l := move.length()
	p.moving = l > 0.0
	if not p.moving:
		return
	var nx := move.x / l
	var nz := move.y / l
	p.facing_x = nx
	p.facing_z = nz
	var dist := speed * dt
	# sub-steps keep each move shorter than the player radius so walls cannot be tunnelled
	var steps := maxi(1, int(ceil(dist / MAX_SUBSTEP)))
	var step := dist / steps
	for i in steps:
		var r := Collision.resolve(grid, p.x + nx * step, p.z + nz * step, Data.BALANCE.player_radius)
		p.x = r.x
		p.z = r.y

func skill_radius() -> float:
	return Data.HOLY_WRATH.radius * mods.area_mul

func _update_skill(dt: float, want: bool) -> void:
	skill_cd = maxf(0.0, skill_cd - dt)
	if not want or skill_cd > 0.0:
		return
	var p := player
	var e := enemies
	var r := skill_radius()
	var dmg: float = Data.HOLY_WRATH.damage * mods.damage_mul
	for i in range(e.count - 1, -1, -1):
		if Vector2(e.x[i] - p.x, e.z[i] - p.z).length() > r + e.radius(i) or not Enemies.can_reach(self, p.x, p.z, i):
			continue
		if boss != null and boss.uid == e.uid[i]:
			boss.stagger = maxf(boss.stagger, Data.HOLY_WRATH.stagger)
		# stun before damage: a kill swap-removes slot i
		Enemies.freeze(self, i, Data.HOLY_WRATH.stun)
		Enemies.damage(self, i, dmg)
	skill_cd = Data.SKILL.cooldown * mods.cooldown_mul
	skill_cd_max = skill_cd
	events.append({ t = "skill", x = p.x, z = p.z, r = r })

func _spawn_enemies(dt: float) -> void:
	if not spawn_enabled:
		return
	_spawn_acc += Data.spawn_rate(time) * dt
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
		var pt = _pick_spawn_point()
		if pt == null:
			continue
		# the spawn point's zone decides the type: chasers keep theirs when the player crosses zones
		var zone := zone_at(pt.x, pt.y)
		var s := scale_at(zone)
		var pool: Array = Data.ZONE_TYPES[zone]
		var t: int = pool[rng.rint(0, pool.size() - 1)]
		var elite: bool = elites < Data.ELITE_MAX_ALIVE and rng.next() < s.elite
		if elite:
			elites += 1
		enemies.spawn(t, pt.x, pt.y, Data.ENEMIES[t].hp * s.hp * (Data.ELITE.hp_mul if elite else 1.0), elite, zone)

func _pick_spawn_point() -> Variant:
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
		return Vector2(x, z)
	return null

func _update_gems(dt: float) -> void:
	var p := player
	var r: float = mods.pickup_radius
	for k in range(gems.size() - 1, -1, -1):
		var g := gems[k]
		var dx := p.x - g.x
		var dz := p.z - g.z
		var d := sqrt(dx * dx + dz * dz)
		if d <= r:
			g.magnet = true
		if g.magnet and d > COLLECT_DIST:
			var step := minf(d, GEM_SPEED * dt)
			g.x += (dx / d) * step
			g.z += (dz / d) * step
		if Vector2(p.x - g.x, p.z - g.z).length() <= COLLECT_DIST:
			add_xp(g.value)
			gems[k] = gems[gems.size() - 1]
			gems.pop_back()

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
			for g in gems:
				if Vector2(g.x - p.x, g.z - p.z).length() <= P.magnet_radius:
					g.magnet = true
		"freeze":
			for i in enemies.count:
				if Vector2(enemies.x[i] - p.x, enemies.z[i] - p.z).length() <= P.freeze_radius:
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
		var d := sqrt(dx * dx + dz * dz)
		if d <= r:
			it.magnet = true
		if it.magnet and d > COLLECT_DIST:
			var s := minf(d, GEM_SPEED * dt)
			it.x += (dx / d) * s
			it.z += (dz / d) * s
		var got := Vector2(p.x - it.x, p.z - it.z).length() <= COLLECT_DIST
		if got or it.life <= 0.0:
			pickups[k] = pickups[pickups.size() - 1]
			pickups.pop_back()
		if got:
			_apply_pickup(it.kind)
