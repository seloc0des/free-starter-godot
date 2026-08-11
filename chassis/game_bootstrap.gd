extends Node
# Phase 0 chassis. Reads content/ and boots whatever systems a genre enables.
# Non-coders edit content/*.json — never this file. Everything downstream reads
# from `config` and the systems this wires up.
#
# The whole point: this is the "wire the packs together" step that normally needs
# a developer. Here it's declarative — swap a lite pack for its paid version and
# nothing here changes (they share the same event-bus seam).

const CONTENT_DIR := "res://content/"

var config: Dictionary = {}
var quest_ids: Array[String] = []

func _ready() -> void:
	config = _load_object(CONTENT_DIR + "game.json")
	if config.is_empty():
		push_warning("[chassis] no content/game.json — starter has nothing to boot")
		return

	var systems: Array = config.get("systems", [])
	if systems.has("quests"):
		_register_quests()
	if systems.has("dialogue"):
		_register_dialogues()

	# Relay gameplay events into the quest manager so content stays declarative.
	GameEvents.item_collected.connect(_on_item_collected)
	GameEvents.enemy_defeated.connect(_on_enemy_defeated)

	# Dialogue drives quests through a bare event string — the decoupled seam.
	if systems.has("dialogue"):
		DialoguesLite.event_fired.connect(_on_dialogue_event)

	print("[chassis] booted '%s' — systems=%s quests=%d"
		% [config.get("title", "?"), str(systems), quest_ids.size()])


func _register_quests() -> void:
	var quests: Array = _load_array(CONTENT_DIR + "quests.json")
	for entry in quests:
		var qd: Dictionary = entry
		var quest := QuestLite.new()
		quest.id = String(qd.get("id", ""))
		quest.title = String(qd.get("title", ""))
		quest.description = String(qd.get("description", ""))

		var built: Array[QuestObjectiveLite] = []
		var objs: Array = qd.get("objectives", [])
		for o in objs:
			var od: Dictionary = o
			var obj := QuestObjectiveLite.new()
			obj.id = String(od.get("id", ""))
			obj.type = QuestObjectiveLite.Type.KILL if String(od.get("type", "collect")) == "kill" else QuestObjectiveLite.Type.COLLECT
			obj.target_id = String(od.get("target", ""))
			obj.required = int(od.get("required", 1))
			built.append(obj)
		quest.objectives = built

		QuestsLite.register(quest)
		quest_ids.append(quest.id)
		# genres without dialogue (dungeon) start their quest straight from content
		if qd.get("autostart", false):
			QuestsLite.start_quest(quest.id)


func _register_dialogues() -> void:
	var dialogues: Array = _load_array(CONTENT_DIR + "dialogue.json")
	for entry in dialogues:
		var dd: Dictionary = entry
		var dialogue := DialogueLite.new()
		dialogue.id = String(dd.get("id", ""))
		dialogue.title = String(dd.get("title", ""))
		dialogue.entry = String(dd.get("entry", ""))

		var built: Array[DialogueNodeLite] = []
		var nodes: Array = dd.get("nodes", [])
		for n in nodes:
			var nd: Dictionary = n
			var node := DialogueNodeLite.new()
			node.id = String(nd.get("id", ""))
			node.speaker = String(nd.get("speaker", ""))
			node.text = String(nd.get("text", ""))
			node.next = String(nd.get("next", ""))
			node.event = String(nd.get("event", ""))

			var choices: Array[DialogueChoiceLite] = []
			for c in nd.get("choices", []):
				var cd: Dictionary = c
				var choice := DialogueChoiceLite.new()
				choice.text = String(cd.get("text", ""))
				choice.next = String(cd.get("next", ""))
				choices.append(choice)
			node.choices = choices
			built.append(node)
		dialogue.nodes = built
		DialoguesLite.register(dialogue)


func _on_dialogue_event(event_id: String) -> void:
	# Convention: "give_quest:<id>" starts a quest. Keeps dialogue decoupled from
	# the quest system — the chassis decides what an event means.
	if event_id.begins_with("give_quest:"):
		var quest_id := event_id.substr("give_quest:".length())
		QuestsLite.start_quest(quest_id)


func _on_item_collected(item_id: String, amount: int) -> void:
	QuestsLite.report_collect(item_id, amount)


func _on_enemy_defeated(enemy_id: String) -> void:
	QuestsLite.report_kill(enemy_id, 1)


# --- content helpers (JSON is the reskin/data convention non-coders edit) ---

func _load_object(path: String) -> Dictionary:
	var parsed: Variant = _parse(path)
	return parsed if parsed is Dictionary else {}


func _load_array(path: String) -> Array:
	var parsed: Variant = _parse(path)
	return parsed if parsed is Array else []


func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[chassis] missing content file: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	return JSON.parse_string(txt)
