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

	# same story as the entries below: "systems": "quests" instead of a list is a
	# hard cast error, and this runs before anything else has a chance to boot.
	var systems: Array = _sub_array(config, "systems", CONTENT_DIR + "game.json", -1)
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


# path is a parameter only so the self-test can point it at a scratch file.
func _register_quests(path := CONTENT_DIR + "quests.json") -> void:
	var quests: Array = _load_array(path)
	var seen: Array[String] = []
	for i in quests.size():
		# Hand-edited JSON is the normal case here, so one bad entry must not
		# take the rest of the file with it: skip it, say which one, keep going.
		if not (quests[i] is Dictionary):
			_bad_entry(path, i, quests[i])
			continue
		var qd: Dictionary = quests[i]
		var quest := QuestLite.new()
		quest.id = _str(qd, "id")
		if quest.id == "":
			push_error("[chassis] %s entry %d has no \"id\" — skipped" % [path, i])
			continue
		if seen.has(quest.id):
			push_error("[chassis] %s entry %d repeats id \"%s\" — skipped" % [path, i, quest.id])
			continue
		seen.append(quest.id)
		quest.title = _str(qd, "title")
		quest.description = _str(qd, "description")

		var built: Array[QuestObjectiveLite] = []
		var objs: Array = _sub_array(qd, "objectives", path, i)
		for j in objs.size():
			if not (objs[j] is Dictionary):
				_bad_entry(path, i, objs[j], "objectives[%d]" % j)
				continue
			var od: Dictionary = objs[j]
			var obj := QuestObjectiveLite.new()
			obj.id = _str(od, "id")
			obj.type = QuestObjectiveLite.Type.KILL if _str(od, "type", "collect") == "kill" else QuestObjectiveLite.Type.COLLECT
			obj.target_id = _str(od, "target")
			# 0 would be a quest that can never be handed in, so floor it at 1.
			obj.required = maxi(1, _int(od, "required", 1))
			built.append(obj)
		quest.objectives = built

		QuestsLite.register(quest)
		quest_ids.append(quest.id)
		# genres without dialogue (dungeon) start their quest straight from content
		if qd.get("autostart", false):
			QuestsLite.start_quest(quest.id)


func _register_dialogues(path := CONTENT_DIR + "dialogue.json") -> void:
	var dialogues: Array = _load_array(path)
	for i in dialogues.size():
		if not (dialogues[i] is Dictionary):
			_bad_entry(path, i, dialogues[i])
			continue
		var dd: Dictionary = dialogues[i]
		var dialogue := DialogueLite.new()
		dialogue.id = _str(dd, "id")
		if dialogue.id == "":
			push_error("[chassis] %s entry %d has no \"id\" — skipped" % [path, i])
			continue
		dialogue.title = _str(dd, "title")
		dialogue.entry = _str(dd, "entry")

		var built: Array[DialogueNodeLite] = []
		var nodes: Array = _sub_array(dd, "nodes", path, i)
		for j in nodes.size():
			if not (nodes[j] is Dictionary):
				_bad_entry(path, i, nodes[j], "nodes[%d]" % j)
				continue
			var nd: Dictionary = nodes[j]
			var node := DialogueNodeLite.new()
			node.id = _str(nd, "id")
			node.speaker = _str(nd, "speaker")
			node.text = _str(nd, "text")
			node.next = _str(nd, "next")
			node.event = _str(nd, "event")

			var choices: Array[DialogueChoiceLite] = []
			var raw_choices: Array = _sub_array(nd, "choices", path, i, "nodes[%d]" % j)
			for c in raw_choices:
				if not (c is Dictionary):
					_bad_entry(path, i, c, "nodes[%d].choices" % j)
					continue
				var cd: Dictionary = c
				var choice := DialogueChoiceLite.new()
				choice.text = _str(cd, "text")
				choice.next = _str(cd, "next")
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
#
# Everything below assumes the buyer typed the JSON by hand and got something
# wrong. A null field or a stray value used to be a hard runtime error, which in
# GDScript aborts the whole registration pass — the game then booted looking
# fine, just missing every quest after the typo. Say what broke, skip it, boot.

# index < 0 means the key sits at the top level of the file, not inside a list.
func _where(index: int, field := "") -> String:
	if index < 0:
		return "top level" if field == "" else field
	return "entry %d" % index if field == "" else "entry %d %s" % [index, field]


func _bad_entry(path: String, index: int, value: Variant, field := "") -> void:
	push_error("[chassis] %s %s is %s, expected an object { ... } — skipped"
		% [path, _where(index, field), type_string(typeof(value))])


func _sub_array(d: Dictionary, key: String, path: String, index: int, field := "") -> Array:
	var v: Variant = d.get(key, [])
	if v is Array:
		return v
	if v != null:
		push_error("[chassis] %s %s: \"%s\" is %s, expected a list [ ... ] — ignored"
			% [path, _where(index, field), key, type_string(typeof(v))])
	return []


# String(null) and int(null) are hard errors in GDScript, not coercions, so a
# "title": null in content JSON would kill the loop. These never throw.
func _str(d: Dictionary, key: String, def := "") -> String:
	var v: Variant = d.get(key, def)
	return def if v == null else String(v)


func _int(d: Dictionary, key: String, def: int) -> int:
	var v: Variant = d.get(key, def)
	if v is int or v is float:
		return int(v)
	if v is String and (v as String).is_valid_float():
		return int((v as String).to_float())
	return def


func _load_object(path: String) -> Dictionary:
	var parsed: Variant = _parse(path)
	if parsed is Dictionary:
		return parsed
	if parsed != null:
		push_error("[chassis] %s: expected an object { ... }, got %s"
			% [path, type_string(typeof(parsed))])
	return {}


func _load_array(path: String) -> Array:
	var parsed: Variant = _parse(path)
	if parsed is Array:
		return parsed
	if parsed != null:
		push_error("[chassis] %s: expected a list [ ... ], got %s"
			% [path, type_string(typeof(parsed))])
	return []


func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[chassis] missing content file: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[chassis] can't open content file: %s" % path)
		return null
	var txt := f.get_as_text()
	f.close()
	# JSON.new() rather than parse_string: parse_string's error names a Godot
	# C++ file, which tells a non-coder nothing. This names their file and line.
	var json := JSON.new()
	if json.parse(txt) != OK:
		push_error("[chassis] %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
