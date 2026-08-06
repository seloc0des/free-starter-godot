extends Node

# Quests — Lite autoload. Holds registered quests and their per-objective
# progress. Two objective types: COLLECT and KILL. Game code calls
# `QuestsLite.report_collect(item_id, n)` or `QuestsLite.report_kill(enemy_id, n)`
# to advance progress.
#
# Cut from Pro:
#   * 6 more objective types (USE, CURRENCY, TALK, REACH, FLAG, CUSTOM)
#   * Quest chains via prerequisite_quests
#   * Condition prerequisites (flags, min_level, biome lists)
#   * Optional + hidden objectives
#   * Rewards (ITEM, CURRENCY, FLAG, CUSTOM)
#   * Time limits + repeatable + auto-start / auto-complete / auto-grant
#   * Flag system (`set_flag`, `has_flag`)
#   * QuestGiver Node + QuestLogUI Control
#   * NPC integration (talk-based progression)
#   * Save-contract auto-join + shared Events bus

signal quest_registered(quest_id: String)
signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
# `current` + `required` (4 args) matches the Pro QuestManager signature so
# Lite→Pro upgrades don't have to rewrite listener bodies. Pre-existing
# 3-arg Lite consumers can still bind with `.unbind(1)`.
signal objective_progressed(quest_id: String, objective_id: String, current: int, required: int)
signal objective_completed(quest_id: String, objective_id: String)

enum State { AVAILABLE, ACTIVE, COMPLETE }

var _quests: Dictionary = {}  # id -> QuestLite
var _state: Dictionary = {}   # id -> State
var _progress: Dictionary = {}  # id -> Dictionary[objective_id -> int]


# ---- registration --------------------------------------------------------

func register(quest: QuestLite) -> void:
	if quest == null or String(quest.id) == "":
		return
	_quests[quest.id] = quest
	_state[quest.id] = State.AVAILABLE
	_progress[quest.id] = {}
	for o in quest.objectives:
		if o == null:
			continue
		_progress[quest.id][String(o.id)] = 0
	quest_registered.emit(quest.id)


func register_many(quests: Array) -> void:
	for q in quests:
		if q is QuestLite:
			register(q)


func is_registered(quest_id: String) -> bool:
	return _quests.has(quest_id)


func list_quests() -> Array:
	return _quests.values()


# ---- lifecycle -----------------------------------------------------------

func start_quest(quest_id: String) -> bool:
	if not _quests.has(quest_id):
		return false
	if int(_state.get(quest_id, State.AVAILABLE)) != State.AVAILABLE:
		return false
	_state[quest_id] = State.ACTIVE
	quest_started.emit(quest_id)
	return true


func is_active(quest_id: String) -> bool:
	return int(_state.get(quest_id, State.AVAILABLE)) == State.ACTIVE


func is_complete(quest_id: String) -> bool:
	return int(_state.get(quest_id, State.AVAILABLE)) == State.COMPLETE


# ---- progress reporting --------------------------------------------------

func report_collect(item_id: String, amount: int = 1) -> void:
	_report(QuestObjectiveLite.Type.COLLECT, item_id, amount)


func report_kill(enemy_id: String, amount: int = 1) -> void:
	_report(QuestObjectiveLite.Type.KILL, enemy_id, amount)


func _report(type: int, target_id: String, amount: int) -> void:
	if amount <= 0:
		return
	for quest_id in _quests.keys():
		if not is_active(String(quest_id)):
			continue
		var quest: QuestLite = _quests[quest_id]
		for o in quest.objectives:
			if o == null or int(o.type) != type:
				continue
			if String(o.target_id) != target_id:
				continue
			# Normalize key to String — register() initialises _progress with
			# String(o.id), so raw `o.id` (often StringName) was a silent miss.
			var key := String(o.id)
			var current := int(_progress[quest_id].get(key, 0))
			if current >= int(o.required):
				continue
			var new_val := min(int(o.required), current + amount)
			_progress[quest_id][key] = new_val
			objective_progressed.emit(String(quest_id), key, new_val, int(o.required))
			if new_val >= int(o.required):
				objective_completed.emit(String(quest_id), key)
		_check_completion(String(quest_id))


func _check_completion(quest_id: String) -> void:
	var quest: QuestLite = _quests[quest_id]
	for o in quest.objectives:
		if o == null:
			continue
		if int(_progress[quest_id].get(String(o.id), 0)) < int(o.required):
			return
	_state[quest_id] = State.COMPLETE
	quest_completed.emit(quest_id)


# ---- inspection ----------------------------------------------------------

func get_progress(quest_id: String, objective_id: String) -> int:
	if not _progress.has(quest_id):
		return 0
	return int(_progress[quest_id].get(objective_id, 0))


func get_state(quest_id: String) -> int:
	return int(_state.get(quest_id, State.AVAILABLE))
