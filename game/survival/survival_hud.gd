extends CanvasLayer

# Survival HUD: the camp checklist line plus Save/Load. Totals are seeded from
# the active quest so the first gather reads against the full count.

@onready var _status: Label = $Bar/Status
@onready var _foraging: Label = $Bar/Foraging

var _progress: Dictionary = {}


func _ready() -> void:
	$Bar/Save.focus_mode = Control.FOCUS_NONE
	$Bar/Load.focus_mode = Control.FOCUS_NONE
	$Bar/Save.pressed.connect(func() -> void: SaveLite.save())
	$Bar/Load.pressed.connect(func() -> void: SaveLite.load())

	_status.text = "Make camp. Gather what the forest offers."
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_node("Stats"):
			var s: StatsComponentLite = p.get_node("Stats")
			_foraging.text = "Foraging: %d" % int(s.get_stat("foraging"))
			s.stat_changed.connect(func(id: String, v: float) -> void:
				if id == "foraging": _foraging.text = "Foraging: %d" % int(v))
			break
	_seed_totals()
	QuestsLite.quest_started.connect(func(_id: String) -> void: _seed_totals())
	QuestsLite.objective_progressed.connect(_on_progress)
	QuestsLite.quest_completed.connect(func(_id: String) -> void:
		_status.text = "Camp is made. Save your evening.")


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
	_status.text = "Camp supplies: %d / %d" % [done, total]
