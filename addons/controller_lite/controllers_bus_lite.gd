extends Node

# ControllersLite global bus: THE player reference, interactions, and
# reason-counted movement locks (dialogue + cutscene can overlap safely).

signal player_registered(body: Node)
# Emitted by Interactor rather than from here, so the compiler can't see a use
# and warns. Silenced so a buyer's debugger stays clean on first run.
@warning_ignore("unused_signal")
signal interacted(interactable: Node, by: Node)
signal movement_locked_changed(locked: bool)

var player: Node = null

var _lock_reasons: Dictionary = {}

const DIALOGUE_MANAGERS := ["/root/DialoguesLite", "/root/DialogueManager"]


## The pack's own movement actions, and what they are bound to out of the box.
##
## These used to default to ui_left, ui_right, ui_up and ui_down. Those work,
## but no settings menu will ever let a player rebind them: a rebinding UI has
## to keep ui_* off limits or one stray keypress in the rebind screen leaves the
## player unable to navigate the menu they are standing in. Naming them here
## fixes both halves at once. Same names as the Pro pack, so upgrading changes
## nothing.
const DEFAULT_ACTIONS := {
	&"move_left": {"keys": [KEY_A, KEY_LEFT], "axis": [JOY_AXIS_LEFT_X, -1.0]},
	&"move_right": {"keys": [KEY_D, KEY_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	&"move_up": {"keys": [KEY_W, KEY_UP], "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	&"move_down": {"keys": [KEY_S, KEY_DOWN], "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	# Interaction had the same problem and for the same reason. Enter and the A
	# button are what ui_accept already answered to, so the two most common ways
	# a player interacts still work.
	&"interact": {"keys": [KEY_E, KEY_ENTER], "axis": [], "pad": [JOY_BUTTON_A]},
}


func _ready() -> void:
	ensure_actions()


## Register anything missing, and never touch anything already there.
static func ensure_actions() -> void:
	for name in DEFAULT_ACTIONS:
		if InputMap.has_action(name):
			continue
		InputMap.add_action(name, 0.5)
		for ev in events_for(name):
			InputMap.action_add_event(name, ev)


static func events_for(action: StringName) -> Array:
	var spec: Dictionary = DEFAULT_ACTIONS.get(action, {})
	var out: Array = []
	# device -1 is every device. A new event takes the running engine's own keyboard id
	# (0 on 4.5, 16 on 4.7) and an action only matches presses from that id, so an
	# action saved by one version went dead in the other. The Input Map editor saves -1.
	for code in spec.get("keys", []):
		var k := InputEventKey.new()
		k.physical_keycode = code
		k.device = -1
		out.append(k)
	var axis: Array = spec.get("axis", [])
	if axis.size() == 2:
		var m := InputEventJoypadMotion.new()
		m.axis = axis[0]
		m.axis_value = axis[1]
		m.device = -1
		out.append(m)
	for button in spec.get("pad", []):
		var b := InputEventJoypadButton.new()
		b.button_index = button
		b.device = -1
		out.append(b)
	return out


## The first key bound to an action, as text ("E"), for prompts. Reads the
## project's binding when there is one, else the default above. "" for none.
static func key_label(action: StringName) -> String:
	var events: Array = InputMap.action_get_events(action) if InputMap.has_action(action) else events_for(action)
	for ev in events:
		var k := ev as InputEventKey
		if k == null:
			continue
		if k.physical_keycode != KEY_NONE:
			return OS.get_keycode_string(k.physical_keycode)
		if k.keycode != KEY_NONE:
			return OS.get_keycode_string(k.keycode)
	return ""


func register_player(body: Node) -> void:
	player = body
	player_registered.emit(body)


## True while a Dialogue (Lite or Pro) conversation is on screen. Looked up by
## name each time, so neither pack is needed; both managers answer is_active().
func in_dialogue() -> bool:
	for path in DIALOGUE_MANAGERS:
		var m := get_node_or_null(NodePath(path))
		if m != null and m.has_method("is_active") and bool(m.call("is_active")):
			return true
	return false


func lock_movement(reason: StringName = &"default") -> void:
	var was := is_locked()
	_lock_reasons[reason] = true
	if not was:
		movement_locked_changed.emit(true)


func unlock_movement(reason: StringName = &"default") -> void:
	if not _lock_reasons.erase(reason):
		return
	if _lock_reasons.is_empty():
		movement_locked_changed.emit(false)


func is_locked() -> bool:
	return not _lock_reasons.is_empty()
