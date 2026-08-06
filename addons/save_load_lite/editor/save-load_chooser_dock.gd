@tool
extends Control

# The "chooser" panel: a non-coder picks WHAT they want persisted, picks WHERE it
# applies, and hits Apply — the panel drops a SaveableLite into their own scene.
# Nothing here is a one-way street: re-pick and Apply again (it updates in place,
# never duplicates), or tweak the dropped node in the Inspector. This is the pack's
# only dock — Lite has no authoring sidebar, so keep it self-contained.
#
# Lite is deliberately scoped: it only makes a node saveable. Menus, checkpoints,
# autosave, and save-on-quit are the no-code wiring that Save / Load (Pro) unlocks —
# we say so honestly rather than pretending Lite does it.

const SAVEABLE_SCRIPT := "res://addons/save_load_lite/saveable.gd"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Outcome { SAVE_NODE }
enum Scope { SELECTED_NODE, THIS_SCENE }

var _chosen: int = -1
var _buttons := {}
var _scope: OptionButton
var _status: Label


func _ready() -> void:
	name = "Save/Load · Setup"
	custom_minimum_size = Vector2(320, 420)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  Pick what your game saves"))
	var col := VBoxContainer.new()
	root.add_child(col)
	_add_choice(col, Outcome.SAVE_NODE, "Save this node's state")

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
	note.text = "It's your game — change it any time: re-pick and Apply, or tweak the Saveable node in the Inspector (edit which properties persist).\n\nSave / Load (Pro) unlocks no-code wiring: save menus, checkpoints (save on touch), autosave timers, and save-on-quit — plus multi-slot, encryption, and screenshots."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)


# ---- pick ----------------------------------------------------------------

func _on_pick(id: int) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_say("Picked %s. Choose where, then Apply." % _pretty(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == -1:
		_say("Pick what your game saves first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	match _chosen:
		Outcome.SAVE_NODE: _apply_save_node(root)


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
	if props.is_empty():
		_say("Made %s saveable, but it had no obvious properties to persist — add them in the Inspector (save_properties)." % target.name, WARN_COLOR)
	else:
		_say("Made %s saveable — persists %d propert%s. Tweak the list in the Inspector. Call SaveLite.save() to write, .load() to restore." % [target.name, props.size(), "y" if props.size() == 1 else "ies"], OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses a SaveableLite already on the target rather than duplicating.

func wire_saveable(root: Node, target: Node) -> Node:
	var sv := _find_saveable_on(target, root)
	if sv == null:
		sv = load(SAVEABLE_SCRIPT).new()
		target.add_child(sv)
		sv.owner = root
		sv.name = "SaveableLite"
		# only prefill on first drop — a re-Apply keeps whatever the buyer edited
		sv.set("save_properties", _storable_props(target))
	return sv


# ---- helpers -------------------------------------------------------------

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
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _pretty(id: int) -> String:
	match id:
		Outcome.SAVE_NODE: return "Save this node's state"
	return "?"


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
