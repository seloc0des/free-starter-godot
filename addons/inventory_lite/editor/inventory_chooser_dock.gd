@tool
extends Control

# The "chooser" panel: a non-coder picks what kind of inventory they want, picks
# WHERE it goes, and hits Apply — it drops an InventoryLite onto their own node.
# Nothing is a one-way street: re-pick and Apply again (it updates in place, never
# duplicates), or tweak the node in the Inspector. The sibling "Items — Lite" tab
# is the item authoring dock (the .tres your inventory holds).
#
# Lite scope: this only adds the InventoryLite component (baked in, re-editable).
# Anything that would auto-wire it — world pickups, chests that open on interact,
# a drop-in inventory UI — is the Pro tier. We say so honestly, we don't nag.

const INVENTORY_SCRIPT := "res://addons/inventory_lite/inventory_lite.gd"
const UPGRADE_URL := "https://selodev.itch.io/godot-inventory-system"

# Outcomes are all "add InventoryLite" — they differ only by a sensible starting
# capacity so a non-coder isn't guessing a number. Everything stays editable.
const OUTCOMES := {
	"player": {"label": "Player inventory", "capacity": 24},
	"container": {"label": "A container / chest", "capacity": 16},
	"small": {"label": "A small pouch", "capacity": 6},
}
const OUTCOME_IDS := ["player", "container", "small"]

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Scope { SELECTED, THIS_SCENE }

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _status: Label


func _ready() -> void:
	name = "Inventory · Setup"
	custom_minimum_size = Vector2(320, 420)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  What do you want?"))
	for id in OUTCOME_IDS:
		var b := Button.new()
		b.text = OUTCOMES[id]["label"]
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		root.add_child(b)
		_buttons[id] = b

	root.add_child(_h("2.  Where should it go?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene (its root)", Scope.THIS_SCENE)
	root.add_child(_scope)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Change it any time: re-pick and Apply, or tweak capacity in the Inspector. Author the items it holds in the Items (Lite) tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	# Honest funnel, not a nag: name the wiring Lite can't do rather than hide it.
	var up := Label.new()
	up.text = "🔒 Pro unlocks no-code wiring: world pickups, chests that open on interact, and a drop-in inventory UI bound for you."
	up.modulate = Color(0.85, 0.8, 0.55)
	up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(up)
	root.add_child(_btn("Upgrade to Pro →", func(): OS.shell_open(UPGRADE_URL)))


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_say("Picked %s. Choose where, then Apply." % OUTCOMES[id]["label"], OK_COLOR)


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
		# Only trust a selection that actually belongs to this scene, else fall
		# back to the root — never bake onto a node that won't serialize.
		if sel.size() > 0 and (sel[0] == root or sel[0].owner == root):
			target = sel[0]
	var inv := wire_inventory(root, target, _chosen)
	_select(inv)
	_say("%s → added InventoryLite (capacity %d) on '%s'. Tweak it in the Inspector, or re-pick here." % [OUTCOMES[_chosen]["label"], int(inv.get("capacity")), target.name], OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: updates the existing InventoryLite under `target` rather than
# duplicating. `root` is the scene root every spawned node must be owned by so
# it bakes into the buyer's .tscn.

func wire_inventory(root: Node, target: Node, outcome: String) -> Node:
	var inv := _ensure(root, target, "InventoryLite", INVENTORY_SCRIPT)
	inv.set("capacity", int(OUTCOMES[outcome]["capacity"]))
	return inv


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
# dock's CanvasLayer search and the visuals _find had.)
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
