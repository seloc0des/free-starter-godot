extends CanvasLayer

# Dungeon HUD: hearts on the left, the quest line in the middle, Save/Load on
# the right. Hearts read the player's HealthLite; the quest line listens to the
# lite quest bus. No wiring needed in the scene beyond node paths.

const HEART_FULL := preload("res://game/art/ui_heart_full.png")
const HEART_HALF := preload("res://game/art/ui_heart_half.png")
const HEART_EMPTY := preload("res://game/art/ui_heart_empty.png")
const HEART_COUNT := 5

@onready var _status: Label = $Bar/Status
@onready var _hearts: HBoxContainer = $Bar/Hearts
@onready var _attack: Label = $Bar/Attack

var _player_health: HealthLite = null


func _ready() -> void:
	$Bar/Save.focus_mode = Control.FOCUS_NONE
	$Bar/Load.focus_mode = Control.FOCUS_NONE
	$Bar/Save.pressed.connect(func() -> void: SaveLite.save())
	$Bar/Load.pressed.connect(func() -> void: SaveLite.load())

	for i in HEART_COUNT:
		var h := TextureRect.new()
		h.texture = HEART_FULL
		h.stretch_mode = TextureRect.STRETCH_KEEP
		_hearts.add_child(h)

	_status.text = "Clear the crypt — attack with Space."
	_seed_totals()
	QuestsLite.quest_started.connect(func(_id: String) -> void: _seed_totals())
	QuestsLite.objective_progressed.connect(_on_progress)
	QuestsLite.quest_completed.connect(func(_id: String) -> void:
		_status.text = "The crypt is clear! Nice — save your run.")

	# player spawns in the same scene, so it exists by the time we're ready
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0].has_node("Stats"):
		var s: StatsComponentLite = players[0].get_node("Stats")
		_attack.text = "Attack: %d" % int(s.get_stat("attack"))
		s.stat_changed.connect(func(id: String, v: float) -> void:
			if id == "attack": _attack.text = "Attack: %d" % int(v))
	if players.size() > 0 and players[0].has_node("Health"):
		_player_health = players[0].get_node("Health") as HealthLite
		_player_health.damaged.connect(func(_a: float, _s: Node) -> void: _refresh())
		_player_health.healed.connect(func(_a: float) -> void: _refresh())
		_player_health.died.connect(_refresh)
		_refresh()


var _progress: Dictionary = {}


func _seed_totals() -> void:
	# know the full body count up front so the first kill reads "1 / 5", not "1 / 3"
	for q in QuestsLite.list_quests():
		if QuestsLite.is_active(q.id):
			for obj in q.objectives:
				if not _progress.has(obj.id):
					_progress[obj.id] = [0, obj.required]


func _on_progress(_q: String, objective_id: String, current: int, required: int) -> void:
	# two kill objectives, one line: show the combined body count
	_progress[objective_id] = [current, required]
	var done := 0
	var total := 0
	for v in _progress.values():
		done += int(v[0])
		total += int(v[1])
	_status.text = "Monsters slain: %d / %d" % [done, total]


func _refresh() -> void:
	if _player_health == null:
		return
	var per_heart: float = _player_health.max_health / float(HEART_COUNT)
	for i in HEART_COUNT:
		var h := _hearts.get_child(i) as TextureRect
		var filled: float = _player_health.current - float(i) * per_heart
		if filled >= per_heart * 0.99:
			h.texture = HEART_FULL
		elif filled >= per_heart * 0.5:
			h.texture = HEART_HALF
		else:
			h.texture = HEART_EMPTY
