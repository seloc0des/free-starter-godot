extends Node

# Headless test for the Vendor Lite chooser's wiring logic (the part behind the
# Apply button). Editor-only calls (get_edited_scene_root/selection) are split out;
# this drives the pure wire_* helpers against a real scene tree and asserts the
# result is baked-in and re-entrant.
# Run: godot --headless --path . res://tools/vendor_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/vendor_lite/editor/vendor_chooser_dock.gd")

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- vendor lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# SHOP — drops a VendorLite on the target, owned by the scene root
	var target := Node.new()
	target.name = "ShopNPC"
	root.add_child(target); target.owner = root
	var shop = dock.wire_shop(root, target)
	_assert(shop != null and _is_vendor(shop), "wire_shop created a VendorLite")
	_assert(shop.get_parent() == target, "shop dropped under the selected node")
	_assert(shop.owner == root, "shop owned by scene root: bakes into the .tscn")

	# RE-ENTRANT — applying again reuses the same VendorLite, never a second one
	var shop2 = dock.wire_shop(root, target)
	_assert(shop2 == shop, "second Apply reused the same VendorLite (no duplicate)")
	_assert(_count_cls(target, "VendorLite") == 1, "exactly one VendorLite after two Applies (got %d)" % _count_cls(target, "VendorLite"))

	# WALLET — drops a WalletLite carrying the chosen starting balance
	var wallet = dock.wire_wallet(root, target, 250)
	_assert(wallet != null and _is_wallet(wallet), "wire_wallet created a WalletLite")
	_assert(int(wallet.get("starting_balance")) == 250, "wallet carries the chosen starting balance (got %d)" % int(wallet.get("starting_balance")))
	_assert(wallet.owner == root, "wallet owned by scene root")
	# re-entrant + option preserved: re-apply with a new balance updates in place
	var wallet2 = dock.wire_wallet(root, target, 500)
	_assert(wallet2 == wallet, "second wallet Apply reused the same node")
	_assert(int(wallet2.get("starting_balance")) == 500, "re-apply updated the starting balance in place (got %d)" % int(wallet2.get("starting_balance")))
	_assert(_count_cls(target, "WalletLite") == 1, "exactly one WalletLite after two Applies (got %d)" % _count_cls(target, "WalletLite"))

	# PLAYER TAG — "Give the player a wallet" marks its node as the player (saved
	# with the scene); a plain scene root isn't tagged.
	var hero := CharacterBody2D.new()
	hero.name = "Hero"
	root.add_child(hero); hero.owner = root
	_assert(dock.tag_player(root, hero) and hero.is_in_group("player"), "the wallet's node is tagged as the player")
	var hw = dock.wire_wallet(root, hero, 10)
	_assert(dock._host_of(hw, root) == hero, "a selected WalletLite counts as the node it sits on, so the player tag never lands on the wallet")
	_assert(not dock.tag_player(root, root) and not root.is_in_group("player"), "a plain scene root isn't tagged as the player")
	var ps := PackedScene.new()
	ps.pack(root)
	var copy := ps.instantiate()
	_assert(copy.get_node("Hero").is_in_group("player"), "the player tag is saved with the scene")
	copy.free()

	# SCENE-ROOT scope — dropping onto the root itself works (target == root)
	var root_only := Node.new()
	get_tree().root.add_child(root_only)
	var shop_on_root = dock.wire_shop(root_only, root_only)
	_assert(shop_on_root.get_parent() == root_only and shop_on_root.owner == root_only, "scene-root scope drops the component on the root, owned by it")
	root_only.queue_free()

	# SHOP + WALLET — both dropped, and the vendor's wallet_path points at the sibling
	var pair_root := Node.new()
	get_tree().root.add_child(pair_root)
	var pair_target := Node.new()
	pair_root.add_child(pair_target); pair_target.owner = pair_root
	var vendor = dock.wire_shop_and_wallet(pair_root, pair_target, 300)
	_assert(_is_vendor(vendor), "shop+wallet returned the VendorLite")
	var wpath: NodePath = vendor.get("wallet_path")
	var linked_wallet: Node = vendor.get_node_or_null(wpath)
	_assert(linked_wallet != null and _is_wallet(linked_wallet), "vendor's wallet_path resolves to a WalletLite sibling")
	_assert(int(linked_wallet.get("starting_balance")) == 300, "paired wallet carries the chosen balance (got %d)" % int(linked_wallet.get("starting_balance")))
	# re-entrant: applying the pair again reuses both nodes
	var vendor2 = dock.wire_shop_and_wallet(pair_root, pair_target, 300)
	_assert(vendor2 == vendor, "second shop+wallet Apply reused the vendor")
	_assert(_count_cls(pair_target, "VendorLite") == 1 and _count_cls(pair_target, "WalletLite") == 1, "shop+wallet stays a single pair after two Applies")
	pair_root.queue_free()

	# OWNERSHIP — a VendorLite inside an instanced sub-scene (owner != root) must NOT
	# be hijacked; Apply should make a fresh one the scene actually owns. Fresh root so
	# the ONLY VendorLite present is the non-owned, buried one.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var sub := Node.new()
	root2.add_child(sub); sub.owner = root2
	var buried = load("res://addons/vendor_lite/vendor_lite.gd").new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	var fresh = dock.wire_shop(root2, root2)
	_assert(fresh != buried, "did not hijack a VendorLite owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh VendorLite the scene root owns")
	root2.queue_free()

	# PARENT vs CHILD — a wallet Applied to the level root is its own, not the
	# shopkeeper's further down
	var root3 := Node.new()
	get_tree().root.add_child(root3)
	var keeper := Node2D.new(); keeper.name = "Keeper"
	root3.add_child(keeper); keeper.owner = root3
	var keeper_shop = dock.wire_shop_and_wallet(root3, keeper, 50)
	var keeper_wallet: Node = keeper_shop.get_node(keeper_shop.get("wallet_path"))
	var root_wallet = dock.wire_wallet(root3, root3, 75)
	_assert(root_wallet != keeper_wallet and root_wallet.get_parent() == root3, "a wallet on the root is its own, not the shopkeeper's")
	_assert(int(keeper_wallet.get("starting_balance")) == 50, "the shopkeeper's wallet keeps its balance (got %d)" % int(keeper_wallet.get("starting_balance")))
	_assert(dock.wire_wallet(root3, root3, 80) == root_wallet, "re-Apply on the root reuses its own wallet")
	root3.queue_free()

	root.queue_free()

	_panel_checks(dock)
	await _layout_checks(dock)
	await _dock_ui_checks()
	_stock_checks(dock)
	await _stock_ui_checks()
	dock.free()
	await _run_row_list_refresh()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# ---- the walk-up shop panel ------------------------------------------------

func _panel_checks(dock) -> void:
	var lvl := Node2D.new()
	lvl.name = "Town"
	get_tree().root.add_child(lvl)
	var keeper := _child(lvl, Node2D.new(), "Keeper")
	var v = dock.wire_shop(lvl, keeper)
	var panel: Node = lvl.get_node_or_null("UILayer/ShopPanel")
	_assert(panel != null and _script_is(panel, "ShopPanelLite") and panel.owner == lvl, "A shop adds a ShopPanel on a UILayer, saved with the scene")
	if panel == null:
		lvl.queue_free()
		return
	_assert(not panel.visible, "the ShopPanel starts hidden")
	_assert(panel.get_node_or_null(panel.get("vendor_path")) == v, "it shows this shop")
	var area: Node = keeper.get_node_or_null("ShopArea")
	_assert(area is Area2D and area.owner == lvl and area.get_child_count() == 1 and area.get_child(0) is CollisionShape2D and area.get_child(0).owner == lvl,
		"a shopkeeper with nothing to touch gets a ShopArea (Area2D and its shape), saved")
	_assert(panel.get_node_or_null(panel.get("area_path")) == area, "the panel opens from that ShopArea")
	dock.wire_shop(lvl, keeper)
	var areas := 0
	for c in keeper.get_children():
		if c is Area2D:
			areas += 1
	_assert(_count_script(lvl, "ShopPanelLite") == 1 and areas == 1, "Apply again keeps one panel and one area for the shop")
	var smith := _child(lvl, Node2D.new(), "Smith")
	var v2 = dock.wire_shop(lvl, smith)
	var p2: Node = lvl.get_node_or_null("UILayer/SmithShopPanel")
	_assert(p2 != null and p2.get_node(p2.get("vendor_path")) == v2 and _count_script(lvl, "ShopPanelLite") == 2, "a second shop gets its own panel, SmithShopPanel")
	var stall := _child(lvl, Area2D.new(), "Stall")
	var sh := CollisionShape2D.new()
	sh.shape = CircleShape2D.new()
	_child(stall, sh, "Shape", lvl)
	var v3 = dock.wire_shop(lvl, stall)
	var p3 := _panel_for(lvl, v3)
	_assert(stall.get_node_or_null("ShopArea") == null and p3 != null and p3.get_node(p3.get("area_path")) == stall, "a shop on an Area2D with a shape opens from the area itself, no extra ShopArea")
	var sign := _child(lvl, Area2D.new(), "Sign")
	var p5 := _panel_for(lvl, dock.wire_shop(lvl, sign))
	_assert(sign.get_node_or_null("ShopArea") is Area2D and p5 != null and p5.get_node(p5.get("area_path")) == sign.get_node("ShopArea"),
		"an Area2D with no shape can't be walked into, so it gets a ShopArea")
	var pair := _child(lvl, Node2D.new(), "Pair")
	var v4 = dock.wire_shop_and_wallet(lvl, pair, 30)
	_assert(_panel_for(lvl, v4) != null and pair.get_node_or_null("ShopArea") is Area2D, "Shop + wallet adds the panel and area too")
	_assert(not _any_name_has(lvl, "@"), "every node the Setup tab added has a readable name (%s)" % _names_with(lvl, "@"))
	var saved_inside := 0
	for n in panel.find_children("*", "", true, false):
		if n.owner != null:
			saved_inside += 1
	_assert(saved_inside == 0, "the panel builds its buttons at runtime, so none of them is saved into the scene")
	_assert(dock._host_of(panel, lvl) == keeper and dock._host_of(area, lvl) == keeper, "with the ShopPanel or ShopArea selected, Apply means its shopkeeper")
	var lvl3 := Node3D.new()
	get_tree().root.add_child(lvl3)
	var k3 := _child(lvl3, Node3D.new(), "Keeper3D")
	dock.wire_shop(lvl3, k3)
	var a3: Node = k3.get_node_or_null("ShopArea")
	_assert(a3 is Area3D and a3.get_child(0) is CollisionShape3D, "a 3D shopkeeper gets an Area3D ShopArea")
	lvl3.queue_free()

	# the status line: who's the player, and what they still lack
	_assert(dock._no_player_note(lvl).contains("Make the selected node the player"), "no player in the scene: the status says how to mark one")
	var hero := _child(lvl, CharacterBody2D.new(), "Hero")
	dock.tag_player(lvl, hero)
	var gaps: String = dock._player_gaps(lvl, true)
	_assert(dock._no_player_note(lvl) == "" and gaps.contains("no wallet") and gaps.contains("no bag"), "with a player marked, it names what the player still lacks: '%s'" % gaps)
	dock.wire_wallet(lvl, hero, 10)
	var bag := Node.new()
	bag.set_script(load("res://addons/vendor_lite/_demo_bag.gd"))
	_child(hero, bag, "Bag", lvl)
	_assert(dock._player_gaps(lvl, true) == "", "a player with a wallet and a bag needs nothing more")
	lvl.queue_free()


# The Setup tab places the panel, so Play shows it right away (it doesn't lay
# itself out when it's been placed).
func _layout_checks(dock) -> void:
	# not in the tree, so the panel can't lay itself out: this is the dock's placement
	var lvl := Node2D.new()
	lvl.name = "Market"
	var npc := _child(lvl, Node2D.new(), "NPC")
	var panel: Control = _panel_for(lvl, dock.wire_shop(lvl, npc))
	_assert(panel.anchor_left == 0.5 and panel.anchor_right == 0.5 and panel.anchor_top == 0.5 and panel.anchor_bottom == 1.0, "the panel's anchors are set: lower middle")
	panel.offset_top = 40.0
	dock.wire_shop(lvl, npc)
	_assert(panel.offset_top == 40.0, "a spot you picked survives Apply again")
	panel.offset_top = 0.0
	var ps := PackedScene.new()
	ps.pack(lvl)
	lvl.free()
	for size in [Vector2i(1280, 720), Vector2i(1152, 648)]:
		var vp := SubViewport.new()
		vp.size = size
		add_child(vp)
		var copy := ps.instantiate()
		vp.add_child(copy)
		await get_tree().process_frame
		var r: Rect2 = (copy.get_node("UILayer/ShopPanel") as Control).get_global_rect()
		_assert(r.size.x > 0.0 and r.size.y > 0.0 and Rect2(Vector2.ZERO, Vector2(size)).encloses(r)
			and is_equal_approx(r.get_center().x, size.x / 2.0) and r.position.y >= size.y / 2.0 - 1.0,
			"at %dx%d the panel has a real size in the lower middle (%s)" % [size.x, size.y, r])
		vp.queue_free()


func _dock_ui_checks() -> void:
	var d = CHOOSER.new()
	add_child(d)  # builds its UI in _ready, no editor calls there
	await get_tree().process_frame
	var mk: Button = null
	var text := ""
	for n in d.find_children("*", "", true, false):
		if n is Button and (n as Button).text == "Make the selected node the player":
			mk = n
		elif n is Label:
			text += (n as Label).text + " "
	_assert(mk != null and mk.tooltip_text == "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group.",
		"the Setup tab has the Make the selected node the player button, with its tooltip")
	_assert(not text.contains("drop-in ShopUI") and not text.contains("open-on-interact") and text.contains("styled shop"),
		"the Pro note says what Pro adds and no longer says Lite has no shop window")
	d.queue_free()


func _child(parent: Node, n: Node, n_name: String, owner_root: Node = null) -> Node:
	n.name = n_name
	parent.add_child(n)
	n.owner = owner_root if owner_root != null else parent
	return n


func _panel_for(root: Node, vendor: Node) -> Node:
	for n in root.find_children("*", "", true, false):
		if _script_is(n, "ShopPanelLite") and n.get_node_or_null(n.get("vendor_path")) == vendor:
			return n
	return null


func _script_is(n: Node, cls: String) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.get_global_name() == cls


func _count_script(root: Node, cls: String) -> int:
	var k := 0
	for n in root.find_children("*", "", true, false):
		if _script_is(n, cls):
			k += 1
	return k


# Scene nodes only: the panel's own controls are built at runtime and never saved.
func _names_with(root: Node, bit: String) -> String:
	var out := PackedStringArray()
	for n in root.find_children("*", "", true, true):
		if String(n.name).contains(bit):
			out.append(String(root.get_path_to(n)))
	return ", ".join(out)


func _any_name_has(root: Node, bit: String) -> bool:
	for n in root.find_children("*", "", true, true):
		if String(n.name).contains(bit):
			return true
	return false


# ---- helpers -------------------------------------------------------------

func _is_vendor(n: Node) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.get_global_name() == "VendorLite"


func _is_wallet(n: Node) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.get_global_name() == "WalletLite"


func _count_cls(parent: Node, cls: String) -> int:
	var n := 0
	for c in parent.get_children():
		var scr: Script = c.get_script()
		if scr != null and scr.get_global_name() == cls:
			n += 1
	return n


# An item made while a stock row is on screen is in that row's list the next time
# it opens, and the row keeps the item it had.
func _run_row_list_refresh() -> void:
	var dir := "user://f12b_row_items"
	DirAccess.make_dir_recursive_absolute(dir)
	var d = CHOOSER.new()
	add_child(d)
	await get_tree().process_frame
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var v: Node = d.wire_shop(lvl, _child(lvl, Node2D.new(), "Baker"))
	d._item_dir = dir
	d._shop = v
	d._reload_stock()
	d._add_row_btn.pressed.emit()
	await get_tree().process_frame
	var pick: OptionButton = _first(d._stock_box, "OptionButton")
	var had := pick.get_item_text(pick.selected) if pick != null else ""
	var made: String = d.make_item(dir)
	var made_name := String(load(made).get("name")) if made != "" else "?"
	if pick != null:
		pick.get_popup().about_to_popup.emit()
	var names := PackedStringArray()
	if pick != null:
		for k in pick.item_count:
			names.append(pick.get_item_text(k))
	_assert(pick != null and made != "" and names.has(made_name), "an item made while the row is on screen is in its list when it opens (%s in %s)" % [made_name, names])
	_assert(pick != null and pick.get_item_text(pick.selected) == had, "and the row keeps the item it had (%s)" % had)
	lvl.queue_free()
	d.queue_free()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# ---- the stock rows --------------------------------------------------------

const TMP_ITEMS := "user://vc_items"  # never the project's res://items
const TMP_FIX := "user://vc_fixture_items"
const TMP_SCENE := "user://vc_shop.tscn"
const OWN_ITEM_SCRIPT := "res://addons/vendor_lite/item_resource.gd"

var _fix := {}  # id -> item saved in TMP_FIX


func _stock_checks(dock) -> void:
	_wipe(TMP_ITEMS)
	# Rows need items with a path, to come back from a saved scene. Made here, not
	# taken from the demo: the starter kits carry these tests without the demo.
	_fix = _fixtures([["potion", "Health Potion"], ["apple", "Apple"], ["ring", "Magic Ring"]])
	var potion: Resource = _fix["potion"]
	var apple: Resource = _fix["apple"]
	var has_demo := _has_demo()
	if has_demo:
		var ex: Array = dock.item_choices(TMP_ITEMS)
		var tagged := ex.size() == 4 and _pick(ex, "Health Potion") != null and _pick(ex, "Apple") != null
		for c in ex:
			tagged = tagged and String(c["label"]).ends_with("(example)")
		_assert(tagged, "the item picker offers the demo's 4 items, marked as examples")
	else:
		print("[--] item picker: no demo in this project, so there are no examples to check")
	var p1: String = dock.make_item(TMP_ITEMS)
	var p2: String = dock.make_item(TMP_ITEMS)
	var i1: Resource = load(p1)
	var i2: Resource = load(p2)
	_assert(p1 == TMP_ITEMS + "/new_item.tres" and p2 == TMP_ITEMS + "/new_item_2.tres", "New item makes new_item.tres, then new_item_2.tres")
	_assert(str(i1.get("id")) == "new_item" and str(i1.get("name")) == "New Item" and str(i2.get("name")) == "New Item 2", "with a name and an id already")
	# next to an Inventory addon New item takes its script, so bags and shops share items
	var want := _want_item_script()
	_assert(i1.get_script().resource_path == want, "on %s" % ("the pack's own item script (no Inventory here)" if want == OWN_ITEM_SCRIPT else "the Inventory item script, since it's installed (%s)" % want))
	var mine: Array = dock.item_choices(TMP_ITEMS)
	var own_first: bool = mine.size() >= 2 and mine[0]["item"] == i1 and mine[1]["item"] == i2 and not String(mine[0]["label"]).contains("example")
	_assert(own_first and (not has_demo or (mine.size() == 6 and String(mine[2]["label"]).ends_with("(example)"))),
		"your own items come first, then the examples" if has_demo else "your own items are listed (no demo here, so no examples after them)")

	var lvl := Node2D.new()
	lvl.name = "Bazaar"
	get_tree().root.add_child(lvl)
	var v: Node = dock.wire_shop(lvl, _child(lvl, Node2D.new(), "Trader"))
	# the editor hands a fresh shop's stock back read-only
	var ro: Array = []
	ro.make_read_only()
	v.set("stock", ro)
	var r0: int = dock.add_stock_row(v, potion)
	_assert(r0 == 0 and ro.is_empty() and v.get("stock").size() == 1 and not v.get("stock").is_read_only(), "Add row writes a fresh stock list and leaves the read-only one alone")
	_assert(v.get("stock")[0] == {"item": potion, "price": 10, "stock": -1}, "a new row is {item, price 10, stock -1}: no limit (%s)" % str(v.get("stock")[0]))
	dock.set_stock_field(v, 0, "price", 25)
	dock.set_stock_field(v, 0, "stock", 5)
	dock.set_stock_field(v, 0, "sell_price", 10)
	_assert(v.get("stock")[0] == {"item": potion, "price": 25, "stock": 5, "sell_price": 10}, "price, stock and buys back land in the keys the shop reads")
	_assert(v.get_price(potion) == 25 and v.get_stock(potion) == 5 and v.get_sell_price(potion) == 10, "and VendorLite reads them: 25, 5 left, buys back at 10")
	dock.set_stock_field(v, 0, "sell_price", 25)
	_assert(not v.get("stock")[0].has("sell_price") and v.get_sell_price(potion) == 25, "buys back at the price itself: the key goes, so it follows the price")
	dock.set_stock_field(v, 0, "stock", -1)
	_assert(v.get_stock(potion) == -1, "No limit is stock -1")
	dock.set_stock_field(v, 0, "stock", 5)
	var r1: int = dock.add_stock_row(v, apple)
	dock.set_stock_field(v, r1, "price", 3)
	dock.add_stock_row(v)
	dock.remove_stock_row(v, 2)
	_assert(v.get("stock").size() == 2 and v.get("stock")[1]["item"] == apple, "Remove takes the row out")

	# saved and loaded back, as when the scene is reopened
	var ps := PackedScene.new()
	ps.pack(lvl)
	_assert(ResourceSaver.save(ps, TMP_SCENE) == OK, "the scene saves")
	var again: Node = ResourceLoader.load(TMP_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	var rows: Array = dock.stock_rows(again.get_node("Trader/VendorLite"))
	_assert(rows.size() == 2 and rows[0]["item"].resource_path == potion.resource_path and int(rows[0]["price"]) == 25 and int(rows[0]["stock"]) == 5
		and rows[1]["item"].resource_path == apple.resource_path and int(rows[1]["price"]) == 3 and int(rows[1]["stock"]) == -1,
		"reopened from the saved scene, the rows read back the same")
	_assert(dock.shop_for(lvl.get_node("Trader")) == v and dock.shop_for(v) == v and dock.shop_for(lvl.get_node("UILayer/ShopPanel")) == v
		and dock.shop_for(lvl.get_node("Trader/ShopArea")) == v and dock.shop_for(lvl) == null,
		"the rows follow the shopkeeper, its VendorLite, its ShopPanel or its ShopArea")
	again.free()
	lvl.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SCENE))
	_wipe(TMP_ITEMS)


# The rows as a buyer clicks them.
func _stock_ui_checks() -> void:
	var d = CHOOSER.new()
	add_child(d)
	await get_tree().process_frame
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var v: Node = d.wire_shop(lvl, _child(lvl, Node2D.new(), "Grocer"))
	d._item_dir = TMP_FIX  # the fixtures stand in for res://items
	_assert(d._add_row_btn.disabled and d._stock_label.text.begins_with("Select a shop"), "with no shop picked the rows ask for one")
	d._shop = v
	d._reload_stock()
	_assert(not d._add_row_btn.disabled and d._stock_label.text.contains("Grocer"), "with the shop picked they show its stock")
	d._add_row_btn.pressed.emit()
	await get_tree().process_frame
	var pick: OptionButton = _first(d._stock_box, "OptionButton")
	_assert(v.get("stock").size() == 1 and pick != null and pick.get_item_text(pick.selected) == "(pick an item)", "Add row adds a row waiting for an item")
	if pick == null:
		lvl.queue_free()
		d.queue_free()
		return
	var at := -1
	for k in pick.item_count:
		if at < 0 and pick.get_item_text(k).begins_with("Magic Ring"):
			at = k
	pick.select(at)
	pick.item_selected.emit(at)
	var spins: Array = d._stock_box.find_children("*", "SpinBox", true, false)
	(spins[0] as SpinBox).value = 300
	var endless: CheckBox = _first(d._stock_box, "CheckBox")
	endless.button_pressed = false
	(spins[2] as SpinBox).value = 2
	var e: Dictionary = v.get("stock")[0]
	_assert(e["item"] != null and str(e["item"].get("id")) == "ring" and int(e["price"]) == 300 and int(e["stock"]) == 2,
		"picking an item, a price and a stock count in the row writes them (%s)" % str(e))
	_assert(int((spins[1] as SpinBox).value) == 300, "Buys back follows the price until you set it apart")
	(spins[1] as SpinBox).value = 120
	_assert(int(v.get("stock")[0].get("sell_price", -1)) == 120, "and setting it writes sell_price")
	endless.button_pressed = true
	_assert(int(v.get("stock")[0]["stock"]) == -1 and not (spins[2] as SpinBox).editable, "No limit writes -1 and locks the count")
	var rm: Button = null
	for b in d._stock_box.find_children("*", "Button", true, false):
		if (b as Button).text == "Remove":
			rm = b
	rm.pressed.emit()
	await get_tree().process_frame
	_assert(v.get("stock").is_empty() and _first(d._stock_box, "OptionButton") == null, "Remove empties it again")
	lvl.queue_free()
	d.queue_free()
	_wipe(TMP_FIX)


func _pick(choices: Array, label: String) -> Resource:
	for c in choices:
		if String(c["label"]).begins_with(label):
			return c["item"]
	return null


func _first(root: Node, type: String) -> Node:
	var all := root.find_children("*", type, true, false)
	return all[0] if not all.is_empty() else null


func _fixtures(specs: Array) -> Dictionary:
	_wipe(TMP_FIX)
	DirAccess.make_dir_recursive_absolute(TMP_FIX)
	var scr: Script = load(OWN_ITEM_SCRIPT)
	var out := {}
	for spec in specs:
		var it: Resource = scr.new()
		it.set("id", spec[0])
		it.set("name", spec[1])
		var path := TMP_FIX.path_join(spec[0] + ".tres")
		ResourceSaver.save(it, path)
		out[spec[0]] = load(path)
	return out


func _has_demo() -> bool:
	for d: String in CHOOSER.DEMO_ITEM_DIRS:
		if DirAccess.dir_exists_absolute(d):
			return true
	return false


# What New item should use here: Inventory's script when it's installed.
func _want_item_script() -> String:
	for p in ["res://addons/inventory/resources/item_resource.gd", "res://addons/inventory_lite/item_resource.gd"]:
		if FileAccess.file_exists(p):
			return p
	return OWN_ITEM_SCRIPT


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
