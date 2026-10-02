@tool
extends Control

# The "chooser" panel: a non-coder picks what shop piece they want, picks WHERE
# it goes, and hits Apply — it's dropped into their own scene, baked in, and still
# editable. Nothing here is one-way: re-pick and Apply again (it updates in place,
# never duplicates), or tune the node in the Inspector.
#
# A shop comes with a plain ShopPanel that opens when the player walks into the
# shop's area, and links to the player's wallet and bag on Play. Pro's shop is the
# styled one (icons, tabs, buyback, several currencies). The note says so.

const VENDOR_SCRIPT := "res://addons/vendor_lite/vendor_lite.gd"
const WALLET_SCRIPT := "res://addons/vendor_lite/wallet_lite.gd"
const PANEL_SCRIPT := "res://addons/vendor_lite/shop_panel_lite.gd"
const SHOP_AREA := "ShopArea"
const ITEM_DIR := "res://items"  # the buyer's own items
# The demo's items, offered after yours as examples. The build nests the demo
# under the addon's name, so the zip path comes first.
const DEMO_ITEM_DIRS := [
	"res://demo/vendor_lite/items",
	"res://demo/items",  # repo layout
]
# New items use Inventory's item script when it's there, so bags and shops share them.
const ITEM_SCRIPTS := [
	"res://addons/inventory/resources/item_resource.gd",
	"res://addons/inventory_lite/item_resource.gd",
	"res://addons/vendor_lite/item_resource.gd",
]
const NEW_ROW_PRICE := 10

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)
const NO_PLAYER := "Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."

enum Outcome { SHOP, WALLET, SHOP_AND_WALLET }
enum Scope { SELECTED, SCENE_ROOT }

var _chosen: int = -1
var _buttons := {}
var _scope: OptionButton
var _balance: SpinBox
var _status: Label
var _shop: Node  # the VendorLite whose stock the rows show
var _stock_label: Label
var _stock_box: VBoxContainer
var _add_row_btn: Button
var _new_item_btn: Button
var _choices: Array = []  # [{item, label}] behind every row's item picker
var _item_dir := ITEM_DIR  # where the rows look for your items (the verify points it at user://)


func _ready() -> void:
	name = "Vendor · Setup"
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

	# the walk-up shop only opens for the "player" group, and nothing else sets it
	# on a row of its own, so on a narrow dock it wraps its label instead of widening the tab
	var mk := _btn("Make the selected node the player", _on_make_player)
	mk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mk.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	root.add_child(mk)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	# what the selected shop sells, one row per item: no dictionaries to type
	root.add_child(HSeparator.new())
	root.add_child(_h("3.  What does the shop sell?"))
	_stock_label = Label.new()
	_stock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_stock_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_stock_box = VBoxContainer.new()
	_stock_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stock_box)
	var srow := HBoxContainer.new()
	root.add_child(srow)
	_add_row_btn = _btn("Add row", _on_add_row, true)
	srow.add_child(_add_row_btn)
	_new_item_btn = _btn("New item", _on_new_item)
	srow.add_child(_new_item_btn)
	if Engine.is_editor_hint():
		EditorInterface.get_selection().selection_changed.connect(_reload_stock)
	visibility_changed.connect(_reload_stock)
	_reload_stock()

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Re-pick and Apply any time (it updates in place), or tweak the shop's stock and prices here or in the Inspector. Pro adds a styled shop with icons and Buy/Sell tabs, buyback, several currencies, restock timers and timed offers."
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
			var shop := wire_shop(root, target)
			_select(shop)
			var note := _no_player_note(root) + _player_gaps(root, true)
			_say("Added a shop to \"%s\": a VendorLite and %s. On Play it takes payment from the player's wallet and puts what they buy in the player's bag. Fill in what it sells under 3 below.%s" % [target.name, _panel_words(shop), note], WARN_COLOR if note != "" else OK_COLOR)
			_reload_stock()
		Outcome.WALLET:
			var wallet := wire_wallet(root, target, int(_balance.value))
			var tagged := tag_player(root, target)
			_select(wallet)
			var who := " and marked \"%s\" as the player. Shops take payment from it on Play" % target.name if tagged \
				else ". It's on the scene root, so nothing was marked as the player: put it on your player node to do that"
			_say("Added a WalletLite (starts at %d)%s. Rename the currency in the Inspector if you like." % [int(_balance.value), who], OK_COLOR if tagged else WARN_COLOR)
		Outcome.SHOP_AND_WALLET:
			var vendor := wire_shop_and_wallet(root, target, int(_balance.value))
			_select(vendor)
			var note := _no_player_note(root) + _player_gaps(root, false)
			_say("Added a VendorLite + WalletLite on \"%s\" (wired together, %d to start) and %s. The shop takes payment from that wallet, not the player's, and puts what they buy in the player's bag. Fill in what it sells under 3 below.%s" % [target.name, int(_balance.value), _panel_words(vendor), note], WARN_COLOR if note != "" else OK_COLOR)
			_reload_stock()


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Each is re-entrant: it reuses the existing node rather than duplicating.

func wire_shop(root: Node, target: Node) -> Node:
	var vendor := _ensure(target, root, "VendorLite", VENDOR_SCRIPT)
	wire_panel(root, vendor)
	return vendor


# The walk-up window: one ShopPanel per shop on the scene's UI layer, found again
# by the shop it shows. It opens when the player walks into the shop's area.
func wire_panel(root: Node, vendor: Node) -> Node:
	var host := vendor.get_parent()
	var area := _touch_area(root, host)
	var panel := _find_panel(root, root, vendor)
	if panel == null:
		var layer := _ui_layer(root)
		panel = _inert(load(PANEL_SCRIPT))
		# the first keeps the plain name, more get their shopkeeper's in front
		panel.name = "ShopPanel" if layer.get_node_or_null(^"ShopPanel") == null else "%sShopPanel" % host.name
		panel.set("visible", false)  # before it enters, so it never tries to open empty
		layer.add_child(panel, true)
		panel.owner = root
	panel.set("visible", false)  # starts hidden, walking in opens it
	panel.set("vendor_path", panel.get_path_to(vendor))
	panel.set("area_path", panel.get_path_to(area))
	_place_panel(panel as Control)
	return panel


func wire_wallet(root: Node, target: Node, starting: int) -> Node:
	var w := _ensure(target, root, "WalletLite", WALLET_SCRIPT)
	w.set("starting_balance", starting)
	return w


# The player's wallet: tag its node so touch triggers and zones from other packs
# find the player. Not a level's root though, that's not the player.
func tag_player(root: Node, target: Node) -> bool:
	if target == root and not (target is CollisionObject2D or target is CollisionObject3D):
		return false
	target.add_to_group("player", true)  # persistent, so it saves with the scene
	return true


# Same-scene convenience: drop both and point the vendor's own wallet_path at the
# wallet sibling. This is a component pointing at its own currency source in the
# same scene — not cross-system UI/trigger wiring (that's Pro).
func wire_shop_and_wallet(root: Node, target: Node, starting: int) -> Node:
	var wallet := wire_wallet(root, target, starting)
	var vendor := _ensure(target, root, "VendorLite", VENDOR_SCRIPT)
	vendor.set("wallet_path", vendor.get_path_to(wallet))
	wire_panel(root, vendor)
	return vendor


# What the player walks into: the shop's node when it's an area with a shape
# already, else a ShopArea on it (made once, 2D or 3D to match), so it moves with
# the shopkeeper. An area with no shape can't be walked into.
func _touch_area(root: Node, host: Node) -> Node:
	if _touchable(host):
		return host
	for c in host.get_children():
		if c.name == SHOP_AREA and (c is Area2D or c is Area3D) and c.owner == root:
			return c
	var area: Node
	var shape: Node
	if host is Node3D or (not (host is Node2D) and root is Node3D):
		area = Area3D.new()
		var s3 := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.0  # a couple of metres: walk up and it opens
		s3.shape = sphere
		shape = s3
	else:
		area = Area2D.new()
		var s2 := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 64.0
		s2.shape = circle
		shape = s2
	area.name = SHOP_AREA
	host.add_child(area, true)
	area.owner = root
	shape.name = "CollisionShape"
	area.add_child(shape, true)
	shape.owner = root
	return area


func _touchable(n: Node) -> bool:
	if not (n is Area2D or n is Area3D):
		return false
	for c in n.get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D or c is CollisionShape3D or c is CollisionPolygon3D:
			return true
	return false


# The owned ShopPanel already showing this shop, if any.
func _find_panel(node: Node, root: Node, vendor: Node) -> Node:
	if (node == root or node.owner == root) and _is_cls(node, "ShopPanelLite"):
		var p: Variant = node.get("vendor_path")
		if p is NodePath and p != NodePath("") and node.get_node_or_null(p) == vendor:
			return node
	for c in node.get_children():
		var f := _find_panel(c, root, vendor)
		if f != null:
			return f
	return null


# An owned CanvasLayer for the panel, so it draws over the level. Exactly
# CanvasLayer: a ParallaxBackground is one too, but it draws behind the game.
func _ui_layer(root: Node) -> Node:
	var found := _find_plain_layer(root, root)
	if found != null:
		return found
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	root.add_child(layer, true)
	layer.owner = root
	return layer


func _find_plain_layer(node: Node, root: Node) -> Node:
	if node.get_class() == "CanvasLayer" and (node == root or node.owner == root):
		return node
	for c in node.get_children():
		var f := _find_plain_layer(c, root)
		if f != null:
			return f
	return null


# Lower middle, 480 wide, from mid-screen down to 16 px off the bottom: the bag,
# paper doll and quest log have the corners, crafting sits top centre. Only while
# it's unplaced, so a spot you picked survives a re-Apply.
func _place_panel(c: Control) -> void:
	if c.anchor_left != 0.0 or c.anchor_top != 0.0 or c.anchor_right != 0.0 or c.anchor_bottom != 0.0 \
			or c.offset_left != 0.0 or c.offset_top != 0.0 or c.offset_right != 0.0 or c.offset_bottom != 0.0:
		return
	c.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	c.anchor_top = 0.5
	c.offset_left = -240.0
	c.offset_right = 240.0
	c.offset_top = 0.0
	c.offset_bottom = -16.0


# ---- stock rows (headless-safe too) ----------------------------------------
# A row is what VendorLite reads: {item, price, stock}, plus sell_price when it
# buys back at a different price. stock -1 means no limit. Every write hands the
# shop a fresh array: in the editor its default stock is read-only, and an edit
# in place would be lost anyway.

func stock_rows(vendor: Node) -> Array:
	var out: Array = []
	var cur: Variant = vendor.get("stock") if vendor != null else null
	if cur is Array:
		for e in cur:
			out.append((e as Dictionary).duplicate() if e is Dictionary else {"item": null, "price": 0, "stock": -1})
	return out


func write_stock(vendor: Node, rows: Array) -> void:
	var out: Array = []
	for r in rows:
		out.append((r as Dictionary).duplicate())
	vendor.set("stock", out)


func add_stock_row(vendor: Node, item: Resource = null) -> int:
	var rows := stock_rows(vendor)
	rows.append({"item": item, "price": NEW_ROW_PRICE, "stock": -1})
	write_stock(vendor, rows)
	return rows.size() - 1


func set_stock_field(vendor: Node, index: int, field: String, value: Variant) -> void:
	var rows := stock_rows(vendor)
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index]
	if field == "sell_price" and int(value) == int(row.get("price", 0)):
		row.erase("sell_price")  # same as the price, so it follows the price
	else:
		row[field] = value
	write_stock(vendor, rows)


func remove_stock_row(vendor: Node, index: int) -> void:
	var rows := stock_rows(vendor)
	if index >= 0 and index < rows.size():
		rows.remove_at(index)
		write_stock(vendor, rows)


# Which shop's stock the rows show: the selected VendorLite, the one on the
# selected node, or the one behind a selected ShopPanel or ShopArea.
func shop_for(n: Node) -> Node:
	if n == null:
		return null
	if _is_cls(n, "VendorLite"):
		return n
	if _is_cls(n, "ShopPanelLite"):
		var p: Variant = n.get("vendor_path")
		var v: Node = n.get_node_or_null(p) if p is NodePath and p != NodePath("") else null
		return v if v != null and _is_cls(v, "VendorLite") else null
	if n.name == SHOP_AREA and (n is Area2D or n is Area3D) and n.get_parent() != null:
		n = n.get_parent()
	for c in n.get_children():
		if _is_cls(c, "VendorLite"):
			return c
	return null


# ---- items -----------------------------------------------------------------

# Your items first, then the demo's as examples: [{item, label}].
func item_choices(own_dir := ITEM_DIR) -> Array:
	var out: Array = []
	for p in scan_items(own_dir):
		var it: Resource = load(p)
		out.append({"item": it, "label": _item_label(it)})
	for d: String in DEMO_ITEM_DIRS:
		if DirAccess.dir_exists_absolute(d):
			for p in scan_items(d):
				var it: Resource = load(p)
				out.append({"item": it, "label": _item_label(it) + "  (example)"})
			break
	return out


# Duck-typed, the way shops and bags see items: a .tres with an id and a name
# (recipes and loot tables have ids too, but no name).
func scan_items(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var res := load(dir_path.path_join(f))
			if res != null and res.get("id") != null and res.get("name") != null and res.get("inputs") == null:
				out.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# A new item with a name already filled in: new_item.tres, new_item_2.tres, ...
# Returns its path, or "" if it couldn't be written.
func make_item(dir := ITEM_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("new_item.tres")
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = dir.path_join("new_item_%d.tres" % n)
	var stem := path.get_file().get_basename()
	var it: Resource = load(item_script()).new()
	it.set("id", stem)
	it.set("name", stem.capitalize())
	if ResourceSaver.save(it, path) != OK:
		return ""
	_register_uid(path)
	return path


func item_script() -> String:
	for p: String in ITEM_SCRIPTS:
		if ResourceLoader.exists(p):
			return p
	return ITEM_SCRIPTS[ITEM_SCRIPTS.size() - 1]


func _item_label(item: Resource) -> String:
	if item == null:
		return "(item)"
	for prop in ["name", "id"]:
		var v: Variant = item.get(prop)
		if v != null and str(v) != "":
			return str(v)
	return item.resource_path.get_file().get_basename()


# ---- helpers -------------------------------------------------------------

func _ensure(parent: Node, root: Node, cls: String, script_path: String) -> Node:
	var found := _find(parent, root, cls)
	if found != null:
		return found  # re-entrant: reuse the existing one, never duplicate
	var n: Node = _inert(load(script_path))
	parent.add_child(n, true)
	n.owner = root
	n.name = cls
	return n


# A runtime script's .new() is a live instance, so its game code would run in the
# editor until the scene is reopened. Attach the script to a plain native node instead:
# that's the inert placeholder a hand-added node gets.
func _inert(script: Script) -> Node:
	var n: Node = ClassDB.instantiate(script.get_instance_base_type())
	n.set_script(script)
	return n


# Re-entrancy search: the target's own children only, and only ones THIS scene
# owns. The whole subtree was too wide: a wallet Applied to the scene root took
# over a shopkeeper's wallet further down. A component inside an instanced child
# scene (owner != root) wouldn't serialize into the buyer's scene anyway.
func _find(parent: Node, root: Node, cls: String) -> Node:
	for c in parent.get_children():
		if c.owner == root and _is_cls(c, cls):
			return c
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
		return _host_of(sel[0], root)
	return null


# Apply selects the component it made, so a second Apply straight after would
# land inside it. Step up to the node it sits on, the one you meant.
# Also keeps the player tag off the wallet itself. A selected ShopPanel or
# ShopArea means its shop too.
func _host_of(n: Node, root: Node) -> Node:
	if _is_cls(n, "ShopPanelLite"):
		var v: Node = n.get_node_or_null(n.get("vendor_path")) if n.get("vendor_path") is NodePath else null
		if v != null and v.get_parent() != null:
			n = v
	elif n != root and n.name == SHOP_AREA and (n is Area2D or n is Area3D):
		n = n.get_parent()
	while n != root and (_is_cls(n, "VendorLite") or _is_cls(n, "WalletLite")):
		n = n.get_parent()
	return n


func _select(n: Node) -> void:
	# Apply adds nodes without the undo manager, so the editor never flags the scene
	# and Play would run the saved file without them. Flag it by hand.
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _on_make_player() -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_say("Select your player node first.", WARN_COLOR)
		return
	var n: Node = sel[0]
	n.add_to_group("player", true)  # persistent, so the group saves with the scene
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % n.name, OK_COLOR)


# ---- stock rows: the UI ------------------------------------------------------

# Follows the selection. With nothing selected (the Inspector showing an item,
# say) it keeps the shop it had, as long as that's still in the open scene.
func _reload_stock() -> void:
	if _stock_box == null:
		return
	var sel := _selected_node()
	var picked := shop_for(sel)
	if picked != null:
		_shop = picked
	elif sel != null or not _in_scene(_shop):
		_shop = null
	_build_stock_rows()


func _build_stock_rows() -> void:
	for c in _stock_box.get_children():
		_stock_box.remove_child(c)
		c.queue_free()
	var on := _shop != null and is_instance_valid(_shop)
	_add_row_btn.disabled = not on
	_new_item_btn.disabled = not on
	if not on:
		_shop = null
		_stock_label.text = "Select a shop (a node with a VendorLite) to fill in what it sells, or Apply \"A shop / vendor\" first."
		return
	var rows := stock_rows(_shop)
	var host: Node = _shop.get_parent() if _shop.get_parent() != null else _shop
	_stock_label.text = "Stock for \"%s\": one row per item. Price is what the player pays, Buys back is what the shop pays for it." % host.name
	_refresh_choices(rows)
	for i in rows.size():
		_stock_box.add_child(_stock_row_ui(i, rows[i]))
	if rows.is_empty():
		var l := Label.new()
		l.text = "(nothing for sale yet: press Add row)"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.modulate = Color(1, 1, 1, 0.6)
		_stock_box.add_child(l)


func _stock_row_ui(i: int, row: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	box.add_child(top)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	# its longest entry used to set the width of the whole tab; the open list still shows every name in full
	pick.fit_to_longest_item = false
	_fill_items(pick, row.get("item"))
	pick.item_selected.connect(_on_row_item.bind(i))
	# an item made in another tab a moment ago is in the list when it opens
	pick.get_popup().about_to_popup.connect(_on_row_list_opening.bind(pick, i))
	top.add_child(pick)
	top.add_child(_btn("Remove", _on_row_remove.bind(i)))
	# Price and Buys back get a line each: side by side they were wider than a default dock
	var mid := HBoxContainer.new()
	box.add_child(mid)
	mid.add_child(_small("Price"))
	var price := _count_spin(0, int(row.get("price", 0)))
	mid.add_child(price)
	var mid2 := HBoxContainer.new()
	box.add_child(mid2)
	mid2.add_child(_small("Buys back"))
	var back := _count_spin(0, int(row.get("sell_price", row.get("price", 0))))
	mid2.add_child(back)
	price.value_changed.connect(_on_row_price.bind(i, back))
	back.value_changed.connect(_on_row_back.bind(i))
	var low := HBoxContainer.new()
	box.add_child(low)
	low.add_child(_small("Stock"))
	var left := int(row.get("stock", -1))
	var count := _count_spin(0, maxi(left, 1))
	count.editable = left >= 0
	low.add_child(count)
	var endless := CheckBox.new()
	endless.text = "No limit"
	endless.button_pressed = left < 0
	low.add_child(endless)
	count.value_changed.connect(_on_row_stock.bind(i))
	endless.toggled.connect(_on_row_endless.bind(i, count))
	box.add_child(HSeparator.new())
	return box


func _fill_items(pick: OptionButton, current: Variant) -> void:
	pick.add_item("(pick an item)")
	var at := 0
	for i in _choices.size():
		pick.add_item(_choices[i]["label"])
		if current != null and _choices[i]["item"] == current:
			at = i + 1
	pick.select(at)


# The items a row can pick: your folder's, then the demo's, then any a row
# already holds from somewhere else.
func _refresh_choices(rows: Array) -> void:
	_choices = item_choices(_item_dir)
	for r in rows:
		var it: Variant = r.get("item")
		if it is Resource and not _has_choice(it):
			_choices.append({"item": it, "label": _item_label(it)})  # one from another folder


# A row's list reads the items again as it opens. The row keeps its item, and
# every other row reads them again when its own list opens, before a pick.
func _on_row_list_opening(pick: OptionButton, row: int) -> void:
	if not _live_shop():
		return
	var rows: Array = stock_rows(_shop)
	if row >= rows.size():
		return
	_refresh_choices(rows)
	pick.clear()
	_fill_items(pick, rows[row].get("item"))


func _has_choice(item: Resource) -> bool:
	for c in _choices:
		if c["item"] == item:
			return true
	return false


func _choice_item(idx: int) -> Resource:
	return _choices[idx - 1]["item"] if idx >= 1 and idx <= _choices.size() else null


func _on_row_item(idx: int, row: int) -> void:
	if _live_shop():
		set_stock_field(_shop, row, "item", _choice_item(idx))
		_stock_changed()


func _on_row_price(v: float, row: int, back: SpinBox) -> void:
	if not _live_shop():
		return
	set_stock_field(_shop, row, "price", int(v))
	var rows := stock_rows(_shop)
	if row < rows.size() and not (rows[row] as Dictionary).has("sell_price"):
		back.set_value_no_signal(v)  # buys back at the price until you set it apart
	_stock_changed()


func _on_row_back(v: float, row: int) -> void:
	if _live_shop():
		set_stock_field(_shop, row, "sell_price", int(v))
		_stock_changed()


func _on_row_stock(v: float, row: int) -> void:
	if _live_shop():
		set_stock_field(_shop, row, "stock", int(v))
		_stock_changed()


func _on_row_endless(on: bool, row: int, count: SpinBox) -> void:
	if not _live_shop():
		return
	count.editable = not on
	set_stock_field(_shop, row, "stock", -1 if on else int(count.value))
	_stock_changed()


func _on_row_remove(row: int) -> void:
	if _live_shop():
		remove_stock_row(_shop, row)
		_stock_changed()
		_build_stock_rows()


func _on_add_row() -> void:
	if _live_shop():
		add_stock_row(_shop)
		_stock_changed()
		_build_stock_rows()


func _on_new_item() -> void:
	if not _live_shop():
		return
	var path := make_item(_item_dir)
	if path == "":
		_say("Couldn't write a new item into %s." % _item_dir, ERR_COLOR)
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	var it: Resource = load(path)
	add_stock_row(_shop, it)
	_stock_changed()
	_build_stock_rows()
	if Engine.is_editor_hint():
		EditorInterface.edit_resource(it)
	_say("Made %s. Name it and pick an icon in the Inspector." % path, OK_COLOR)


# The rows are the shop's stock, so an edit is a scene change: flag it, or Play
# runs the saved file without it.
func _stock_changed() -> void:
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


# The shop the rows were built for, if it's still in the open scene.
func _live_shop() -> bool:
	if _shop != null and is_instance_valid(_shop) and _in_scene(_shop):
		return true
	_reload_stock()
	return false


func _in_scene(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if not Engine.is_editor_hint():
		return true  # headless: no open scene to check against
	var root := EditorInterface.get_edited_scene_root()
	return root != null and (n == root or root.is_ancestor_of(n))


func _selected_node() -> Node:
	if not Engine.is_editor_hint():
		return null
	var sel := EditorInterface.get_selection().get_selected_nodes()
	return sel[0] if not sel.is_empty() else null


func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _count_spin(lo: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = 1000000
	s.step = 1
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


# How the panel opens, for the status line.
func _panel_words(vendor: Node) -> String:
	var host := vendor.get_parent()
	var where := "\"%s\"" % host.name if _touchable(host) else "its ShopArea"
	return "a ShopPanel that opens in the lower middle of the screen when the player walks into %s (hidden until then)" % where


# Only nodes in this scene count: the editor's tree holds more than the scene.
func _scene_player(root: Node) -> Node:
	if not root.is_inside_tree():
		return null
	for n in root.get_tree().get_nodes_in_group("player"):
		if n == root or root.is_ancestor_of(n):
			return n
	return null


func _no_player_note(root: Node) -> String:
	return " " + NO_PLAYER if root.is_inside_tree() and _scene_player(root) == null else ""


# What the shop will look for on the player at Play, said while there's time to add it.
func _player_gaps(root: Node, need_wallet: bool) -> String:
	var player := _scene_player(root)
	if player == null:
		return ""  # the no-player note covers it
	var out := ""
	if need_wallet and _find_match(player, root, ["get_balance", "has_amount", "subtract", "add"]) == null:
		out += " \"%s\" has no wallet yet: select it, pick Give the player a wallet and Apply." % player.name
	if _find_match(player, root, ["add_item", "remove_item", "count_item"]) == null:
		out += " \"%s\" has no bag yet, so bought items have nowhere to go: add one (the Setup tab of Inventory (Lite) does it)." % player.name
	return out


# Duck-typed, the same way the shop finds them at runtime. Scripts are inert in
# the editor but still answer has_method.
func _find_match(node: Node, root: Node, methods: Array) -> Node:
	if node == root or node.owner == root:
		var ok := true
		for m in methods:
			if not node.has_method(m):
				ok = false
				break
		if ok:
			return node
	for c in node.get_children():
		var f := _find_match(c, root, methods)
		if f != null:
			return f
	return null


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


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
