@tool
extends Control

# The "chooser" panel: pick what you want equipment-wise, pick WHERE it goes, hit
# Apply — it drops the EquipmentLite component into your own scene, owned by the
# scene root so it bakes into your .tscn and stays editable. Re-pick and Apply
# again (it reuses the node, never duplicates). The sibling "Equippables — Lite"
# tab is where you author the item resources.
#
# Lite tier: the one outcome is "add the component." The Pro outcomes (paper-doll
# UI, stat-modifier layouts, one-click wiring) are shown as an honest note, not a
# nag — Lite bakes in the component; Pro adds the no-code wiring on top.

const COMPONENT_SCRIPT := "res://addons/equipment_lite/equipment_lite.gd"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Scope { SELECTED, SCENE_ROOT }

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _status: Label


func _ready() -> void:
	name = "Equipment · Setup"
	custom_minimum_size = Vector2(320, 380)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  What do you want to add?"))
	# Lite has one bake-in outcome; keep the toggle-group shape so Pro slots in later.
	var b := Button.new()
	b.text = "Equipment slots on a node"
	b.toggle_mode = true
	b.pressed.connect(_on_pick.bind("component"))
	root.add_child(b)
	_buttons["component"] = b

	root.add_child(_h("2.  Where should it go?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene's root", Scope.SCENE_ROOT)
	root.add_child(_scope)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("Author items…", _on_author))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Re-pick and Apply any time (it updates in place, never duplicates), or tweak the component in the Inspector. Author the equippable items on the \"Equippables (Lite)\" tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	root.add_child(HSeparator.new())
	var pro := Label.new()
	pro.text = "🔒 Pro unlocks no-code wiring: a paper-doll UI, drag-drop slots, stat-modifier layouts, and one-click bind. No scripting."
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.modulate = Color(0.85, 0.8, 0.55)
	root.add_child(pro)


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_say("Choose where, then Apply.", OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick what to add first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var target: Node = root
	if _scope.get_selected_id() == Scope.SELECTED:
		var sel: Node = _selected_node()
		if sel != null:
			target = sel
	var comp: Node = wire_component(root, target)
	_select(comp)
	if target == root:
		_say("Equipment on the scene root. It bakes into your .tscn. Tweak it in the Inspector, or re-pick here.", OK_COLOR)
	else:
		_say("Equipment on %s. It bakes into your .tscn. Tweak it in the Inspector, or re-pick here." % target.name, OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses the component already parented to `target` rather than
# adding a second one. `root` is the scene root every spawned node is owned by,
# so everything serializes into the buyer's .tscn.

func wire_component(root: Node, target: Node) -> Node:
	return _ensure(target, root, "EquipmentLite", COMPONENT_SCRIPT)


# ---- author hand-off -----------------------------------------------------

func _on_author() -> void:
	# Nudge toward the sibling authoring tab — that's where item resources live.
	_say("Author equippable items on the \"Equippables (Lite)\" tab (this dock's neighbor).", OK_COLOR)


# ---- helpers -------------------------------------------------------------

# Re-entrant add: if `target` already owns an EquipmentLite of its own, reuse it.
func _ensure(target: Node, root: Node, cls: String, script_path: String) -> Node:
	var found := _find(target, root, cls)
	if found != null:
		return found  # re-entrant: reuse, never duplicate
	var n: Node = load(script_path).new()
	target.add_child(n)
	n.owner = root  # owned by the scene root so it serializes into the .tscn
	n.name = cls
	return n


# Search scoped to nodes THIS scene owns. A component inside an instanced child
# scene (owner != root) is skipped — updating it wouldn't serialize into the
# buyer's scene, so we'd silently no-op. Same trap the save dock's CanvasLayer
# search had.
func _find(start: Node, root: Node, cls: String) -> Node:
	if (start == root or start.owner == root) and _is_cls(start, cls):
		return start
	for c in start.get_children():
		var f := _find(c, root, cls)
		if f != null:
			return f
	return null


func _is_cls(node: Node, cls: String) -> bool:
	if node.is_class(cls):
		return true  # native class
	var scr := node.get_script()
	return scr != null and scr.get_global_name() == cls  # class_name script


func _selected_node() -> Node:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		return null
	return sel[0]


func _select(n: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _pretty(id: String) -> String:
	return id.replace("_", " ").capitalize()


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
