@tool
extends Control

# The "chooser" panel: a non-coder picks what crafting they want for THEIR game,
# picks WHERE it goes, and hits Apply — the panel drops a CraftingLite component
# into their own scene. Nothing here is a one-way street: re-pick and Apply again
# (it updates in place, never duplicates), or tweak the dropped node in the
# Inspector. The sibling "Recipes — Lite" tab authors the recipes it crafts.
#
# Lite tier: outcomes only ADD THE COMPONENT (baked-in, re-editable). The Pro
# unlocks the no-code wiring (browser UI + open-on-interact trigger) — we show an
# honest one-line note where Pro would auto-wire, never a nag.

const CRAFTING_SCRIPT := "res://addons/crafting_lite/crafting_lite.gd"
const UPGRADE_URL := "https://selodev.itch.io/godot-crafting-system"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Scope { SELECTED, THIS_SCENE }

# Each outcome bakes in the same CraftingLite node — the difference is intent, so
# the buyer lands on the right mental model (a station vs. the player). The Pro
# note tells the truth about what Lite doesn't auto-wire for that outcome.
const OUTCOMES := {
	"bench": {
		"label": "A crafting bench",
		"pro": "Pro unlocks no-code wiring: a browser UI + open-on-interact trigger on the bench.",
	},
	"anywhere": {
		"label": "Player crafts anywhere",
		"pro": "Pro unlocks no-code wiring: a craft menu the player opens from a button.",
	},
}

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _pro_note: Label
var _status: Label


func _ready() -> void:
	name = "Crafting · Setup"
	custom_minimum_size = Vector2(320, 380)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  What crafting do you want?"))
	for id in OUTCOMES.keys():
		var b := Button.new()
		b.text = OUTCOMES[id]["label"]
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		root.add_child(b)
		_buttons[id] = b

	root.add_child(_h("2.  Where should it go?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene's root", Scope.THIS_SCENE)
	root.add_child(_scope)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("Author recipes…", _on_author))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	# Honest funnel: the Pro-only wiring for the picked outcome. Lite adds the
	# component; you bind the inventory + call craft() yourself (or upgrade).
	_pro_note = Label.new()
	_pro_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pro_note.modulate = Color(0.85, 0.8, 0.55)
	root.add_child(_pro_note)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Change it any time: re-pick and Apply, or tweak the node in the Inspector. Author the recipes it crafts in the Recipes (Lite) tab, then bind an inventory via its Inventory Path."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_pro_note.text = "🔒 " + OUTCOMES[id]["pro"]
	_say("Picked \"%s\". Choose where, then Apply." % OUTCOMES[id]["label"], OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick what you want first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var target: Node = root
	if _scope.get_selected_id() == Scope.SELECTED:
		var sel := EditorInterface.get_selection().get_selected_nodes()
		if sel.is_empty():
			_say("Select a node in the scene first (or pick \"This scene's root\").", WARN_COLOR)
			return
		target = sel[0]
	var comp := wire_crafting(root, target)
	_select(comp)
	_say("Added crafting to \"%s\". Set its Inventory Path + author recipes; re-pick any time." % target.name, OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses an existing CraftingLite under the target rather than
# duplicating. The node is owned by the SCENE ROOT so it bakes into the .tscn.

func wire_crafting(root: Node, target: Node) -> Node:
	return _ensure(root, target, "CraftingLite", CRAFTING_SCRIPT)


# ---- author hand-off -----------------------------------------------------

func _on_author() -> void:
	# The Recipes — Lite tab is the sibling; nudge them there for recipe CRUD.
	_say("Open the \"Recipes (Lite)\" tab to author the recipes this crafts.", OK_COLOR)


# ---- helpers -------------------------------------------------------------

func _ensure(root: Node, target: Node, cls: String, script_path: String) -> Node:
	var found := _find(target, root, cls)
	if found != null:
		return found  # re-entrant: reuse the existing one, never duplicate
	var n: Node = load(script_path).new()
	n.name = cls
	target.add_child(n)
	n.owner = root
	return n


# Re-entrancy search, scoped to nodes THIS scene owns. A component inside an
# instanced child scene (owner != root) is skipped — updating it wouldn't
# serialize into the buyer's scene, so we'd silently no-op. (Same trap the save
# dock's CanvasLayer search had.)
func _find(node: Node, root: Node, cls: String) -> Node:
	if (node == root or node.owner == root) and _is_cls(node, cls):
		return node
	for c in node.get_children():
		var f := _find(c, root, cls)
		if f != null:
			return f
	return null


func _is_cls(node: Node, cls: String) -> bool:
	if node.is_class(cls):
		return true  # native class
	var scr := node.get_script()
	return scr != null and scr.get_global_name() == cls  # class_name script


func _select(n: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


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
