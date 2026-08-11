extends CanvasLayer

# RPG HUD: gold on the left, quest line in the middle, Attack + Save/Load on
# the right. Gold reads the wallet, Attack reads the stats component, and the
# quest totals are seeded so the first coin reads against the full count.

@onready var _status: Label = $Bar/Status
@onready var _gold: Label = $Bar/Gold
@onready var _attack: Label = $Bar/Attack

var _progress: Dictionary = {}


func _ready() -> void:
	$Bar/Save.focus_mode = Control.FOCUS_NONE
	$Bar/Load.focus_mode = Control.FOCUS_NONE
	$Bar/Save.pressed.connect(func() -> void: SaveLite.save())
	$Bar/Load.pressed.connect(func() -> void: SaveLite.load())

	_status.text = "Gear up for the road — gather the town's lost coins."
	_seed_totals()
	QuestsLite.quest_started.connect(func(_id: String) -> void: _seed_totals())
	QuestsLite.objective_progressed.connect(_on_progress)
	QuestsLite.quest_completed.connect(func(_id: String) -> void:
		_status.text = "Geared up! The road is yours — save your game.")

	var wallets := get_tree().get_nodes_in_group("wallet")
	if wallets.size() > 0:
		var w: WalletLite = wallets[0]
		_gold.text = "Gold: %d" % w.get_balance()
		w.balance_changed.connect(func(total: int) -> void: _gold.text = "Gold: %d" % total)

	for p in get_tree().get_nodes_in_group("player"):
		if p.has_node("Stats"):
			var s: StatsComponentLite = p.get_node("Stats")
			_attack.text = "Attack: %d" % int(s.get_stat("attack"))
			s.stat_changed.connect(func(id: String, v: float) -> void:
				if id == "attack": _attack.text = "Attack: %d" % int(v))
			break


func _seed_totals() -> void:
	for q in QuestsLite.list_quests():
		if QuestsLite.is_active(q.id):
			for obj in q.objectives:
				if not _progress.has(obj.id):
					_progress[obj.id] = [0, obj.required]


func _on_progress(_q: String, objective_id: String, current: int, required: int) -> void:
	_progress[objective_id] = [current, required]
	var done := 0
	var total := 0
	for v in _progress.values():
		done += int(v[0])
		total += int(v[1])
	_status.text = "Road readiness: %d / %d" % [done, total]
