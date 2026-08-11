@tool
extends Control

# The "chooser" panel: a non-coder picks what shop piece they want, picks WHERE
# it goes, and hits Apply — it's dropped into their own scene, baked in, and still
# editable. Nothing here is one-way: re-pick and Apply again (it updates in place,
# never duplicates), or tune the node in the Inspector.
#
# This is Lite: outcomes only DROP the component on your node. No drop-in ShopUI,
# no open-on-interact trigger — those live in Vendor (Pro). We say so honestly in
# the note instead of hiding it.

const VENDOR_SCRIPT := "res://addons/vendor_lite/vendor_lite.gd"
const WALLET_SCRIPT := "res://addons/vendor_lite/wallet_lite.gd"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Outcome { SHOP, WALLET, SHOP_AND_WALLET }
enum Scope { SELECTED, SCENE_ROOT }

var _chosen: int = -1
var _buttons := {}
var _scope: OptionButton
var _balance: SpinBox
var _status: Label


func _ready() -> void:
	name = "Vendor · Setup"
	custom_minimum_size = Vector2(320, 420)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  What do you want to add?"))
	var picks := [
		[Outcome.SHOP, "A shop / vendor"],
		[Outcome.WALLET, "Give the player a wallet"],
		[Outcome.SHOP_AND_WALLET, "Shop + wallet (working pair)"],
	]
	for p in picks:
		var b := Button.new()
		b.text = p[1]
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(p[0]))
		root.add_child(b)
		_buttons[p[0]] = b

	root.add_child(_h("2.  Where should it go?"))
	_scope = OptionButton.new()
	_scope.add_item("On the selected node", Scope.SELECTED)
	_scope.add_item("On the scene root", Scope.SCENE_ROOT)
	root.add_child(_scope)

	# starting balance only matters for the wallet outcomes; it's a real @export
	var bal_row := HBoxContainer.new()
	root.add_child(bal_row)
	bal_row.add_child(_h("Starting balance"))
	_balance = SpinBox.new()
	_balance.min_value = 0
	_balance.max_value = 1000000
	_balance.step = 1
	_balance.value = 100
	bal_row.add_child(_balance)

	root.add_child(_btn("Apply", _on_apply, true))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Re-pick and Apply any time (it updates in place), or tweak the node's stock, prices and wallet path in the Inspector. Pro unlocks no-code wiring: a drop-in ShopUI, open-on-interact, multi-currency and buyback."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)


# ---- pick ----------------------------------------------------------------

func _on_pick(id: int) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_say("Picked %s. Choose where, then Apply." % _label(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == -1:
		_say("Pick what to add first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var target := _target(root)
	if target == null:
		_say("Select the node you want this on first.", WARN_COLOR)
		return

	match _chosen:
		Outcome.SHOP:
			_select(wire_shop(root, target))
			_say("Added a VendorLite. Fill its Stock in the Inspector (item / price / stock), then point its Wallet Path at a WalletLite.", OK_COLOR)
		Outcome.WALLET:
			_select(wire_wallet(root, target, int(_balance.value)))
			_say("Added a WalletLite (starts at %d). Rename the currency in the Inspector if you like." % int(_balance.value), OK_COLOR)
		Outcome.SHOP_AND_WALLET:
			var vendor := wire_shop_and_wallet(root, target, int(_balance.value))
			_select(vendor)
			_say("Added a VendorLite + WalletLite (wired together, %d to start). Fill the Stock in the Inspector. It's a working shop." % int(_balance.value), OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Each is re-entrant: it reuses the existing node rather than duplicating.

func wire_shop(root: Node, target: Node) -> Node:
	return _ensure(target, root, "VendorLite", VENDOR_SCRIPT)


func wire_wallet(root: Node, target: Node, starting: int) -> Node:
	var w := _ensure(target, root, "WalletLite", WALLET_SCRIPT)
	w.set("starting_balance", starting)
	return w


# Same-scene convenience: drop both and point the vendor's own wallet_path at the
# wallet sibling. This is a component pointing at its own currency source in the
# same scene — not cross-system UI/trigger wiring (that's Pro).
func wire_shop_and_wallet(root: Node, target: Node, starting: int) -> Node:
	var wallet := wire_wallet(root, target, starting)
	var vendor := _ensure(target, root, "VendorLite", VENDOR_SCRIPT)
	vendor.set("wallet_path", vendor.get_path_to(wallet))
	return vendor


# ---- helpers -------------------------------------------------------------

func _ensure(parent: Node, root: Node, cls: String, script_path: String) -> Node:
	var found := _find(parent, root, cls)
	if found != null:
		return found  # re-entrant: reuse the existing one, never duplicate
	var n: Node = load(script_path).new()
	parent.add_child(n)
	n.owner = root
	n.name = cls
	return n


# Re-entrancy search, scoped to nodes THIS scene owns and to the target subtree.
# A component inside an instanced child scene (owner != root) is skipped — updating
# it wouldn't serialize into the buyer's scene, so we'd silently no-op. Same trap
# the save dock's CanvasLayer search hit.
func _find(parent: Node, root: Node, cls: String) -> Node:
	return _find_owned(parent, root, cls)


func _find_owned(node: Node, root: Node, cls: String) -> Node:
	if (node == root or node.owner == root) and _is_cls(node, cls):
		return node
	for c in node.get_children():
		var f := _find_owned(c, root, cls)
		if f != null:
			return f
	return null


func _is_cls(node: Node, cls: String) -> bool:
	if node.is_class(cls):
		return true  # native class
	var scr := node.get_script()
	return scr != null and scr.get_global_name() == cls  # class_name script


# The node we drop onto: the selection when scope is SELECTED, else the scene root.
func _target(root: Node) -> Node:
	if _scope.get_selected_id() == Scope.SCENE_ROOT:
		return root
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.size() > 0 and sel[0] is Node:
		return sel[0]
	return null


func _select(n: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _label(id: int) -> String:
	match id:
		Outcome.SHOP: return "a shop / vendor"
		Outcome.WALLET: return "a wallet"
		Outcome.SHOP_AND_WALLET: return "a shop + wallet"
	return "?"


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
