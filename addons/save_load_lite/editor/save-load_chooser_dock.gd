@tool
extends Control

# The "chooser" panel: a non-coder picks WHAT they want persisted, picks WHERE it
# applies, and hits Apply — the panel drops a SaveableLite into their own scene.
# Nothing here is a one-way street: re-pick and Apply again (it updates in place,
# never duplicates), or tweak the dropped node in the Inspector. This is the pack's
# only dock — Lite has no authoring sidebar, so keep it self-contained.
#
# Lite is deliberately scoped: it makes a node saveable and adds quick save and load
# keys (F5 / F9). A save menu with slots, checkpoints, autosave and save-on-quit are
# the no-code wiring Save / Load (Pro) unlocks, and we say so honestly.

const SAVEABLE_SCRIPT := "res://addons/save_load_lite/saveable.gd"
const SAVE_KEYS_SCRIPT := "res://addons/save_load_lite/save_keys_lite.gd"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Outcome { SAVE_NODE, QUICK_KEYS }
enum Scope { SELECTED_NODE, THIS_SCENE }

var _chosen: int = -1
var _buttons := {}
var _scope: OptionButton
var _load_on_start: CheckBox
var _status: Label


func _ready() -> void:
	name = "Save & Load · Setup"  # a "/" is illegal in a node name, so Godot showed "Save_Load"
	custom_minimum_size = Vector2(0, 420)
	# Taller than the dock, the tab scrolls. Nothing in it is wider than a default
	# dock at 100% or 125%, so it never has to scroll sideways.
	var page := ScrollContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.minimum_size_changed.connect(update_minimum_size)
	add_child(page)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	page.add_child(root)

	root.add_child(_h("1.  Pick what your game saves"))
	var col := VBoxContainer.new()
	root.add_child(col)
	_add_choice(col, Outcome.SAVE_NODE, "Save this node's state")
	_add_choice(col, Outcome.QUICK_KEYS, "Quick save and load keys (F5 / F9)")
	_load_on_start = CheckBox.new()
	_load_on_start.text = "Load the save when the scene starts"
	_load_on_start.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_load_on_start.tooltip_text = "The game picks up where the player last saved. Does nothing until there's a save."
	_load_on_start.visible = false  # only means something for the keys
	col.add_child(_load_on_start)

	root.add_child(_h("2.  Where should it apply?"))
	_scope = OptionButton.new()
	_scope.add_item("Selected node", Scope.SELECTED_NODE)
	_scope.add_item("This scene", Scope.THIS_SCENE)
	root.add_child(_scope)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Change it any time: re-pick and Apply, or tweak the nodes in the Inspector (which properties the Saveable keeps, which keys SaveKeys uses).\n\nSave / Load (Pro) adds a save menu with slots, checkpoints (save on touch), autosave timers, save-on-quit, multi-slot, encryption and screenshots, and the RPG packs (Inventory, Quests and the rest) save through it by themselves."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)


# As wide as what's in it and no wider. The old fixed width pushed a laptop's
# default dock (270 px) wider whenever this tab was open.
func _get_minimum_size() -> Vector2:
	if get_child_count() == 0 or not (get_child(0) is Control):
		return Vector2.ZERO
	return Vector2((get_child(0) as Control).get_combined_minimum_size().x, 0.0)


# ---- pick ----------------------------------------------------------------

func _on_pick(id: int) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	# the keys always go on the scene root, so "where" doesn't apply to them
	_load_on_start.visible = id == Outcome.QUICK_KEYS
	_scope.disabled = id == Outcome.QUICK_KEYS
	if id == Outcome.QUICK_KEYS:
		_say("Picked %s. Press Apply to add them to this scene." % _pretty(id), OK_COLOR)
	else:
		_say("Picked %s. Choose where, then Apply." % _pretty(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == -1:
		_say("Pick what your game saves first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	match _chosen:
		Outcome.SAVE_NODE: _apply_save_node(root)
		Outcome.QUICK_KEYS: _apply_quick_keys(root)


func _apply_save_node(root: Node) -> void:
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var target := _scope_target(root)
	if target == null:
		_say("Select the node you want to save first (or pick 'This scene').", WARN_COLOR)
		return
	var sv := wire_saveable(root, target)
	var props: PackedStringArray = sv.get("save_properties")
	_select(sv)
	_say(save_node_status(root, target, props), WARN_COLOR if props.is_empty() else OK_COLOR)


func _apply_quick_keys(root: Node) -> void:
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var added := find_keys(root) == null
	var keys := wire_keys(root, _load_on_start.button_pressed)
	_select(keys)
	_say(keys_status(root, keys, added), OK_COLOR if has_saveable(root) else WARN_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses a SaveableLite already on the target rather than duplicating.

func wire_saveable(root: Node, target: Node) -> Node:
	var sv := _find_saveable_on(target, root)
	if sv == null:
		sv = _inert(load(SAVEABLE_SCRIPT))
		target.add_child(sv, true)
		sv.owner = root
		sv.name = "SaveableLite"
		# only prefill on first drop — a re-Apply keeps whatever the buyer edited
		sv.set("save_properties", _storable_props(target))
	return sv


# One SaveKeys per scene, on the root. A second Apply updates that one and keeps any
# keys the buyer picked in the Inspector.
func wire_keys(root: Node, load_on_start: bool) -> Node:
	var keys := find_keys(root)
	if keys == null:
		keys = _inert(load(SAVE_KEYS_SCRIPT))
		root.add_child(keys, true)
		keys.owner = root
		keys.name = "SaveKeys"
	keys.set("load_on_start", load_on_start)
	return keys


# The scene's SaveKeys. `owned_only` skips one inside an instanced sub-scene: it still
# works at runtime, but an edit made here wouldn't be saved with this scene.
func find_keys(root: Node, owned_only := true) -> Node:
	for n in root.find_children("*", "", true, false):
		if _is_cls(n, "SaveKeysLite") and (not owned_only or n.owner == root):
			return n
	return null


func has_saveable(root: Node) -> bool:
	for n in root.find_children("*", "", true, false):
		if _is_cls(n, "SaveableLite"):
			return true
	return false


func save_node_status(root: Node, target: Node, props: PackedStringArray) -> String:
	var msg := ""
	if props.is_empty():
		msg = "Made %s saveable, but it had no obvious properties to persist. Add them in the Inspector (save_properties)." % target.name
	else:
		msg = "Made %s saveable. Persists %d propert%s. Tweak the list in the Inspector." % [target.name, props.size(), "y" if props.size() == 1 else "ies"]
	var keys := find_keys(root, false)
	if keys == null:
		msg += " Add \"Quick save and load keys\" so the player can save (F5) and load (F9)."
	else:
		msg += " %s saves it and %s loads it." % [_key_label(keys, "save_key"), _key_label(keys, "load_key")]
	return msg


func keys_status(root: Node, keys: Node, added: bool) -> String:
	var msg := "%s quick save: %s saves, %s loads." % ["Added" if added else "Updated", _key_label(keys, "save_key"), _key_label(keys, "load_key")]
	if keys.get("load_on_start"):
		msg += " It loads the save when the scene starts."
	if not has_saveable(root):
		msg += " Nothing in this scene is saveable yet: select a node and use \"Save this node's state\"."
	return msg


# ---- helpers -------------------------------------------------------------

# A runtime script's .new() is a live instance, so its game code would run in the
# editor until the scene is reopened. Attach the script to a plain native node instead:
# that's the inert placeholder a hand-added node gets.
func _inert(script: Script) -> Node:
	var n: Node = ClassDB.instantiate(script.get_instance_base_type())
	n.set_script(script)
	return n


# What "Selected node" / "This scene" resolves to. Selected returns the first
# selected node (or null if nothing's selected); scene returns the root.
func _scope_target(root: Node) -> Node:
	if _scope.get_selected_id() == Scope.THIS_SCENE:
		return root
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.size() > 0 and sel[0] is Node:
		return sel[0]
	return null


# Reuse a SaveableLite already parented on THIS target, scoped to what root owns —
# a node inside an instanced sub-scene (owner != root) is skipped, since editing it
# wouldn't serialize into the buyer's scene (it'd silently no-op). Two different
# targets each get their own Saveable.
func _find_saveable_on(target: Node, root: Node) -> Node:
	for c in target.get_children():
		if _is_cls(c, "SaveableLite") and (c == root or c.owner == root):
			return c
	return null


# Pre-fill save_properties from the node's storable exports — mirrors the Pro
# dock's _on_add_saveable so a non-coder gets a working save target in one click.
# Node/embedded-resource exports don't survive the JSON round-trip, so skip them.
func _storable_props(target: Node) -> PackedStringArray:
	var props := PackedStringArray()
	# where it is: the one thing nearly every game wants back on load
	if target is Node2D or target is Node3D:
		props.append("position")
	for p in target.get_property_list():
		var usage: int = p["usage"]
		if not ((usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (usage & PROPERTY_USAGE_STORAGE) and (usage & PROPERTY_USAGE_EDITOR)):
			continue
		var v: Variant = target.get(str(p["name"]))
		if v is Object and not (v is Resource and str(v.resource_path) != ""):
			continue
		props.append(str(p["name"]))
	return props


func _is_cls(node: Node, cls: String) -> bool:
	if node.is_class(cls):
		return true  # native class
	var scr := node.get_script()
	return scr != null and scr.get_global_name() == cls  # class_name script


func _select(n: Node) -> void:
	# Apply adds nodes without the undo manager, so the editor never flags the scene
	# and Play would run the saved file without them. Flag it by hand.
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _pretty(id: int) -> String:
	match id:
		Outcome.SAVE_NODE: return "Save this node's state"
		Outcome.QUICK_KEYS: return "Quick save and load keys (F5 / F9)"
	return "?"


# "F5", or whatever key the buyer picked on that SaveKeys in the Inspector
func _key_label(keys: Node, prop: String) -> String:
	var code: Variant = keys.get(prop)
	if code == null:
		return "?"
	return OS.get_keycode_string(code)


func _add_choice(parent: Node, id: int, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.pressed.connect(_on_pick.bind(id))
	parent.add_child(b)
	_buttons[id] = b


func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


func _btn(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _say(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text
