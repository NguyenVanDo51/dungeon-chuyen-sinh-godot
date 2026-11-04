class_name Style
extends Resource
## one complete look of the game: swap every hero / monster / boss / dungeon / effect by editing or adding a .tres.
## active: project setting game/style (or `-- style=name` → res://content/styles/<name>.tres)

@export var name := ""
@export var heroes: Array[HeroSkin] = []
@export var monsters: Array[MonsterSkin] = []
@export var bosses: Array[BossSkin] = []
@export var themes: Array[ThemeSkin] = []
@export var fx: FxSkin

const DEFAULT := "res://content/styles/kaykit.tres"

static func load_active(override := "") -> Style:
	var path: String = ProjectSettings.get_setting("game/style", DEFAULT)
	if override != "":
		path = override if override.begins_with("res://") else "res://content/styles/%s.tres" % override
	var s := load(path) as Style
	if s == null:
		push_error("style not found: " + path)
		s = load(DEFAULT)
	return s

func hero(id: String) -> HeroSkin:
	for h in heroes:
		if h.id == id:
			return h
	push_error("style %s: no hero skin '%s'" % [name, id])
	return heroes[0]

## null = not drawn
func monster(id: String) -> MonsterSkin:
	for m in monsters:
		if m.id == id:
			return m
	return null

func boss(id: String) -> BossSkin:
	for b in bosses:
		if b.id == id:
			return b
	push_error("style %s: no boss skin '%s'" % [name, id])
	return bosses[0]

func theme(id: String) -> ThemeSkin:
	for t in themes:
		if t.id == id:
			return t
	return themes[0]
