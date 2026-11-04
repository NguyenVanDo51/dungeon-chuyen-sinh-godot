class_name Meta
extends RefCounted
## everything kept between runs (port of core/meta.ts, store.ts, data/upgrades.ts); saved as JSON in user://

const SAVE_PATH := "user://meta.json"
const VERSION := 1

## step = effect per level (see apply_upgrades); level L+1 costs base × 1.6^L. Sim: ~300 gold/run → full set ≈ 40 runs
const UPGRADES := {
	hp = { id = "hp", name = "Máu", icon = "❤️", per = "+5% máu", step = 0.05, base = 120.0 },
	armor = { id = "armor", name = "Giáp", icon = "🛡️", per = "+2% giảm sát thương", step = 0.02, base = 160.0 },
	damage = { id = "damage", name = "Sát thương", icon = "⚔️", per = "+4% sát thương", step = 0.04, base = 160.0 },
	speed = { id = "speed", name = "Tốc chạy", icon = "👟", per = "+3% tốc chạy", step = 0.03, base = 120.0 },
	pickup = { id = "pickup", name = "Tầm nhặt", icon = "🧲", per = "+8% tầm nhặt", step = 0.08, base = 80.0 },
	cooldown = { id = "cooldown", name = "Hồi chiêu", icon = "⏳", per = "−3% hồi chiêu", step = 0.03, base = 160.0 },
}
const UPGRADE_IDS: Array[String] = ["hp", "armor", "damage", "speed", "pickup", "cooldown"]
const UPGRADE_MAX := 5
const PRICE_GROWTH := 1.6

var gold := 0
var owned: Array[String] = []
## the hero every run starts with; picked once on the character screen (always one of `owned`)
var selected: String = Characters.DEFAULT
## upgrade id -> level
var upgrades := {}
## dungeon id -> floors beaten
var floors_cleared := {}

static func upgrade_price(id: String, level: int) -> int:
	return roundi(UPGRADES[id].base * pow(PRICE_GROWTH, level))

static func fresh() -> Meta:
	var m := Meta.new()
	for c in Characters.IDS:
		if Characters.DEFS[c].price == 0:
			m.owned.append(c)
	m.selected = Characters.DEFAULT if Characters.DEFAULT in m.owned else (m.owned[0] if m.owned.size() > 0 else Characters.DEFAULT)
	for id in UPGRADE_IDS:
		m.upgrades[id] = 0
	for id in Dungeons.DEFS:
		m.floors_cleared[id] = 0
	return m

static func _level(v: Variant, mx: int) -> int:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 0
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return 0
	return clampi(floori(f), 0, mx)

## any parsed JSON → a valid Meta; never fails
static func migrate(raw: Variant) -> Meta:
	var m := fresh()
	if typeof(raw) != TYPE_DICTIONARY or raw.get("version") != float(VERSION) and raw.get("version") != VERSION:
		return m
	var g = raw.get("gold")
	if (typeof(g) == TYPE_FLOAT or typeof(g) == TYPE_INT) and is_finite(float(g)) and float(g) > 0.0:
		m.gold = floori(float(g))
	var ow = raw.get("owned")
	if typeof(ow) == TYPE_ARRAY:
		for c in ow:
			if typeof(c) == TYPE_STRING and c in Characters.IDS and not c in m.owned:
				m.owned.append(c)
	# older saves have no `selected`: keep the default
	var sel = raw.get("selected")
	if typeof(sel) == TYPE_STRING and sel in m.owned:
		m.selected = sel
	var up = raw.get("upgrades")
	if typeof(up) == TYPE_DICTIONARY:
		for id in UPGRADE_IDS:
			m.upgrades[id] = _level(up.get(id), UPGRADE_MAX)
	var fc = raw.get("floorsCleared")
	if typeof(fc) == TYPE_DICTIONARY:
		for id in Dungeons.DEFS:
			m.floors_cleared[id] = _level(fc.get(id), 1 << 30)
	return m

func to_dict() -> Dictionary:
	return { version = VERSION, gold = gold, owned = owned, selected = selected, upgrades = upgrades, floorsCleared = floors_cleared }

## blocked storage / broken JSON fall back to a fresh meta
static func load_from(path := SAVE_PATH) -> Meta:
	if not FileAccess.file_exists(path):
		return fresh()
	return migrate(JSON.parse_string(FileAccess.get_file_as_string(path)))

func save(path := SAVE_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict()))

func buy(c: String) -> bool:
	var price: int = Characters.DEFS[c].price
	if c in owned or gold < price:
		return false
	gold -= price
	owned.append(c)
	return true

func upgrade(id: String) -> bool:
	var l: int = upgrades[id]
	if l >= UPGRADE_MAX or gold < upgrade_price(id, l):
		return false
	gold -= upgrade_price(id, l)
	upgrades[id] = l + 1
	return true

func bank(amount: float) -> void:
	if is_finite(amount):
		gold += maxi(0, roundi(amount))

## floor is 0-based; floors_cleared counts floors beaten
func clear_floor(d: String, f: int) -> void:
	floors_cleared[d] = maxi(floors_cleared[d], f + 1)

func floor_open(d: String, f: int) -> bool:
	return f <= floors_cleared[d]

## the character as a run sees it: base stats × permanent upgrades
func apply_upgrades(def: Dictionary) -> Dictionary:
	var u := upgrades
	var U := UPGRADES
	var out := def.duplicate()
	out.hp = float(roundi(def.hp * (1.0 + U.hp.step * u.hp)))
	out.damage_reduction = def.damage_reduction + U.armor.step * u.armor
	out.damage_mul = def.damage_mul * (1.0 + U.damage.step * u.damage)
	out.speed_mul = def.speed_mul * (1.0 + U.speed.step * u.speed)
	out.pickup_radius_mul = def.pickup_radius_mul * (1.0 + U.pickup.step * u.pickup)
	out.cooldown_mul = def.cooldown_mul * (1.0 - U.cooldown.step * u.cooldown)
	return out
