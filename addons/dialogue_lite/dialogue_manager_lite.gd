extends Node

# Dialogue (Lite). Runs branching conversations authored as data. Write them in
# the Dialogue dock and let the Dialogue · Setup tab wire one to an NPC or to the
# scene loading, or register() them and start(id) from code. The drop-in
# DialogueBoxLite renders it either way.
#
# This is the **working core** of the selodev Dialogue addon, authoring dock and
# Setup tab included. What the paid Pro tier adds:
#
#   * Conditions / flags / variables
#   * Direct quest & inventory hooks
#   * Character portraits + expressions
#   * Typewriter / letter-by-letter text
#   * Save-aware conversation state
#   * Localization (CSV / translation keys)
#   * Conditions and actions in the authoring dock
#
# Lite fires a bare `event` string per node so you can wire outcomes yourself.

signal dialogue_started(id: String)
signal line_shown(speaker: String, text: String)
signal choices_shown(choices: PackedStringArray)
signal event_fired(event_id: String)
signal dialogue_finished(id: String)

var _registry: Dictionary = {}          # id -> DialogueLite
var _nodes: Dictionary = {}             # node id -> DialogueNodeLite (active dialogue)
var _active_id: String = ""
var _current: DialogueNodeLite = null


func register(dialogue: DialogueLite) -> void:
	if dialogue == null or String(dialogue.id) == "":
		return
	_registry[dialogue.id] = dialogue


func register_many(dialogues: Array) -> void:
	for d in dialogues:
		if d is DialogueLite:
			register(d)


func is_registered(id: String) -> bool:
	return _registry.has(id)


func list_dialogues() -> PackedStringArray:
	return PackedStringArray(_registry.keys())


func is_active() -> bool:
	return _active_id != ""


func current_node() -> DialogueNodeLite:
	return _current


# ---- lifecycle -----------------------------------------------------------

func start(id: String) -> bool:
	if not _registry.has(id):
		push_warning("[dialogue] unknown dialogue id: %s" % id)
		return false
	var dialogue: DialogueLite = _registry[id]
	_active_id = id
	_nodes = {}
	for n in dialogue.nodes:
		if n != null:
			_nodes[String(n.id)] = n
	dialogue_started.emit(id)
	_goto(String(dialogue.entry))
	return true


## Start a conversation straight from its .tres, registering it first, so one
## from any folder plays. This is what DialogueTriggerLite calls. A second touch
## mid-talk won't restart the one that's already running.
func start_dialogue(dialogue: Resource) -> bool:
	var d := dialogue as DialogueLite
	if d == null or String(d.id) == "":
		push_warning("[dialogue] start_dialogue needs a DialogueLite resource with an id.")
		return false
	if is_active():
		return false
	register(d)
	return start(d.id)


## Advance a plain (no-choice) node. No-op while choices are pending.
func advance() -> void:
	if _current == null:
		return
	if _current.choices.size() > 0:
		return
	_goto(String(_current.next))


## Pick a choice on the current node.
func choose(index: int) -> void:
	if _current == null or index < 0 or index >= _current.choices.size():
		return
	_goto(String(_current.choices[index].next))


func _goto(node_id: String) -> void:
	if node_id == "" or not _nodes.has(node_id):
		_finish()
		return
	_current = _nodes[node_id]
	if String(_current.event) != "":
		event_fired.emit(String(_current.event))
	line_shown.emit(String(_current.speaker), String(_current.text))
	if _current.choices.size() > 0:
		var texts: PackedStringArray = PackedStringArray()
		for c in _current.choices:
			texts.append(String(c.text))
		choices_shown.emit(texts)


func _finish() -> void:
	var id := _active_id
	_active_id = ""
	_current = null
	_nodes = {}
	dialogue_finished.emit(id)
