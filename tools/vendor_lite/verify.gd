extends Node

# Headless test for Vendor — Lite.
# Run: godot --headless --path . res://tools/vendor_lite/verify.tscn

const CHOOSER := preload("res://addons/vendor_lite/editor/vendor_chooser_dock.gd")
const FixtureBag := preload("res://tools/vendor_lite/fixture_bag.gd")

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- vendor lite verify ---")
	await _run_wallet_basics()
	await _run_buy_happy_path()
	await _run_buy_insufficient_funds()
	await _run_buy_out_of_stock()
	await _run_sell_listed_item()
	await _run_sell_unlisted_rejected_without_accept_any()
	await _run_buy_bag_full()
	await _run_link_player()
	await _run_shop_play()
	await _run_shop_play_3d()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/vendor_lite/acceptance_report.gd").new()
		get_tree().root.add_child(report)
		report.render(_passes, _failures, _log)


func _assert(cond: bool, msg: String) -> void:
	_log.append([cond, msg])
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# ---- helpers -------------------------------------------------------------

class _MiniBag extends Node:
	var items: Dictionary = {}
	func count_item(item: Resource) -> int: return int(items.get(str(item.id), 0))
	func has_item(item: Resource, amount: int = 1) -> bool: return count_item(item) >= amount
	func add_item(item: Resource, amount: int) -> int:
		items[str(item.id)] = count_item(item) + amount
		return 0
	func remove_item(item: Resource, amount: int) -> int:
		var have: int = count_item(item)
		var take: int = mini(have, amount)
		items[str(item.id)] = have - take
		if items[str(item.id)] <= 0:
			items.erase(str(item.id))
		return take


class _Item extends Resource:
	@export var id: String = ""
	@export var name: String = ""


func _item(id: String, display := "") -> Resource:
	var it := _Item.new()
	it.id = id
	it.name = display
	return it


func _make_wallet(starting: int) -> WalletLite:
	var w := WalletLite.new()
	w.starting_balance = starting
	add_child(w)
	return w


# ---- tests ---------------------------------------------------------------

func _run_wallet_basics() -> void:
	await get_tree().process_frame
	var w := _make_wallet(100)
	_assert(w.get_balance() == 100, "Wallet: starting balance loaded")
	w.add(25)
	_assert(w.get_balance() == 125, "Wallet: add() increments")
	_assert(w.subtract(50), "Wallet: subtract succeeds with funds")
	_assert(w.get_balance() == 75, "Wallet: subtract decremented correctly")
	_assert(not w.subtract(1000), "Wallet: subtract refuses when broke")
	_assert(w.get_balance() == 75, "Wallet: failed subtract left balance untouched")
	w.queue_free()


func _run_buy_happy_path() -> void:
	await get_tree().process_frame
	var w := _make_wallet(100)
	var bag := _MiniBag.new()
	add_child(bag)
	var potion := _item("potion")
	var v := VendorLite.new()
	v._wallet = w
	v._inventory = bag
	v.stock = [{"item": potion, "price": 20, "stock": 3}]
	add_child(v)
	var ok := v.buy(potion, 2)
	_assert(ok, "BuyHappy: buy returned true")
	_assert(w.get_balance() == 60, "BuyHappy: 40 spent (got %d)" % w.get_balance())
	_assert(bag.count_item(potion) == 2, "BuyHappy: 2 potions in bag")
	_assert(int(v.get_stock(potion)) == 1, "BuyHappy: stock 1 left (got %d)" % v.get_stock(potion))
	v.queue_free(); w.queue_free(); bag.queue_free()


func _run_buy_insufficient_funds() -> void:
	await get_tree().process_frame
	var w := _make_wallet(5)
	var bag := _MiniBag.new()
	add_child(bag)
	var potion := _item("potion")
	var v := VendorLite.new()
	v._wallet = w
	v._inventory = bag
	v.stock = [{"item": potion, "price": 20, "stock": 3}]
	add_child(v)
	# GDScript lambdas capture scalars by value; use an Array sink so the
	# inner assignment is visible after the call.
	var reasons: Array = []
	v.transaction_rejected.connect(func(r): reasons.append(r))
	var ok := v.buy(potion, 1)
	_assert(not ok, "BuyFunds: buy returns false")
	_assert(reasons.size() == 1 and String(reasons[0]) == VendorLite.REASON_NO_FUNDS,
		"BuyFunds: rejection is not_enough_funds (got %s)" % str(reasons))
	_assert(w.get_balance() == 5, "BuyFunds: wallet untouched")
	v.queue_free(); w.queue_free(); bag.queue_free()


func _run_buy_out_of_stock() -> void:
	await get_tree().process_frame
	var w := _make_wallet(1000)
	var bag := _MiniBag.new()
	add_child(bag)
	var sword := _item("sword")
	var v := VendorLite.new()
	v._wallet = w
	v._inventory = bag
	v.stock = [{"item": sword, "price": 50, "stock": 0}]
	add_child(v)
	var reasons: Array = []
	v.transaction_rejected.connect(func(r): reasons.append(r))
	var ok := v.buy(sword, 1)
	_assert(not ok, "BuyStock: buy refused when stock=0")
	_assert(reasons.size() == 1 and String(reasons[0]) == VendorLite.REASON_OUT_OF_STOCK,
		"BuyStock: reason is out_of_stock (got %s)" % str(reasons))
	v.queue_free(); w.queue_free(); bag.queue_free()


func _run_sell_listed_item() -> void:
	await get_tree().process_frame
	var w := _make_wallet(0)
	var bag := _MiniBag.new()
	add_child(bag)
	var ore := _item("ore")
	bag.add_item(ore, 5)
	var v := VendorLite.new()
	v._wallet = w
	v._inventory = bag
	v.stock = [{"item": ore, "price": 10, "stock": 0, "sell_price": 3}]
	add_child(v)
	var ok := v.sell(ore, 4)
	_assert(ok, "SellListed: sell returned true")
	_assert(bag.count_item(ore) == 1, "SellListed: 4 ore removed (1 left, got %d)" % bag.count_item(ore))
	_assert(w.get_balance() == 12, "SellListed: 4 × 3 = 12 gp received (got %d)" % w.get_balance())
	v.queue_free(); w.queue_free(); bag.queue_free()


func _run_sell_unlisted_rejected_without_accept_any() -> void:
	await get_tree().process_frame
	var w := _make_wallet(0)
	var bag := _MiniBag.new()
	add_child(bag)
	var junk := _item("junk")
	bag.add_item(junk, 1)
	var v := VendorLite.new()
	v._wallet = w
	v._inventory = bag
	v.stock = []  # no listings
	v.accept_any_sale = false
	add_child(v)
	var reasons: Array = []
	v.transaction_rejected.connect(func(r): reasons.append(r))
	var ok := v.sell(junk, 1)
	_assert(not ok, "SellUnlisted: refused when accept_any_sale=false and item not listed")
	_assert(reasons.size() == 1 and String(reasons[0]) == VendorLite.REASON_NOT_LISTED,
		"SellUnlisted: reason is item_not_in_stock (got %s)" % str(reasons))
	v.queue_free(); w.queue_free(); bag.queue_free()


# A bag with no room used to keep the gold and lose the item.
func _run_buy_bag_full() -> void:
	await get_tree().process_frame
	var w := _make_wallet(100)
	var bag = FixtureBag.new()
	bag.capacity = 1
	add_child(bag)
	var ore := _item("ore")
	var gem := _item("gem")
	bag.add_item(ore, 1)  # the only slot
	var v := VendorLite.new()
	v._wallet = w
	v._inventory = bag
	v.stock = [{"item": gem, "price": 30, "stock": 2}]
	add_child(v)
	var reasons: Array = []
	v.transaction_rejected.connect(func(r): reasons.append(r))
	var ok := v.buy(gem, 1)
	_assert(not ok and reasons == [VendorLite.REASON_BAG_FULL], "BagFull: a full bag turns the buy down as bag_full (got %s)" % str(reasons))
	_assert(w.get_balance() == 100, "BagFull: the gold comes back (got %d)" % w.get_balance())
	_assert(int(v.get_stock(gem)) == 2 and bag.count_item(gem) == 0, "BagFull: stock and bag are as they were")
	v.queue_free(); w.queue_free(); bag.queue_free()


# No paths set: the shop finds the wallet and bag on the "player" group's node.
func _run_link_player() -> void:
	await get_tree().process_frame
	var v := VendorLite.new()
	add_child(v)
	_assert(v.link_player() == VendorLite.REASON_NO_PLAYER, "LinkPlayer: nothing in the player group says no_player")
	var hero := Node2D.new()
	hero.add_to_group("player")
	add_child(hero)
	_assert(v.link_player() == VendorLite.REASON_NO_WALLET, "LinkPlayer: a player with no wallet says no_wallet")
	var w := WalletLite.new()
	hero.add_child(w)
	var bag := _MiniBag.new()
	hero.add_child(bag)
	_assert(v.link_player() == "" and v.get_wallet() == w and v.get_inventory() == bag, "LinkPlayer: it finds the player's WalletLite and bag")
	var till := _make_wallet(5)
	var v2 := VendorLite.new()
	v2.bind_wallet(till)
	add_child(v2)
	v2.link_player()
	_assert(v2.get_wallet() == till and v2.get_inventory() == bag, "LinkPlayer: a wallet set on the shop wins, the bag still comes from the player")
	v.queue_free(); v2.queue_free(); till.queue_free(); hero.queue_free()


# End to end, the way a buyer gets it: the Setup tab's wiring on a level, packed
# and played. Walk in, buy, get turned down, sell, walk out.
func _run_shop_play() -> void:
	await get_tree().process_frame
	var dock = CHOOSER.new()
	var level := Node2D.new()
	level.name = "Level"
	var player := _body_2d(level, "Player", Vector2(100, 100))
	var bag = FixtureBag.new()
	bag.name = "Bag"
	bag.capacity = 2
	player.add_child(bag)
	bag.owner = level
	var keeper := Node2D.new()
	keeper.name = "Keeper"
	keeper.position = Vector2(500, 300)
	level.add_child(keeper)
	keeper.owner = level
	dock.wire_wallet(level, player, 100)
	dock.tag_player(level, player)
	var potion := _item("potion", "Health Potion")
	var sword := _item("sword", "Iron Sword")
	var ore := _item("ore", "Ore")
	var gem := _item("gem", "Gem")
	var vendor = dock.wire_shop(level, keeper)
	# the stock the way the Setup tab's rows write it: item, price, stock, buys back
	for spec in [[potion, 25, 5, 10], [sword, 150, 1, 75], [ore, 10, -1, 4], [gem, 30, 2, 12]]:
		var r: int = dock.add_stock_row(vendor, spec[0])
		dock.set_stock_field(vendor, r, "price", spec[1])
		dock.set_stock_field(vendor, r, "stock", spec[2])
		dock.set_stock_field(vendor, r, "sell_price", spec[3])
	var ps := PackedScene.new()
	_assert(vendor.get("stock").size() == 4 and vendor.get("stock")[1] == {"item": sword, "price": 150, "stock": 1, "sell_price": 75},
		"ShopPlay: the stock rows are written the way the shop reads them")
	_assert(ps.pack(level) == OK, "ShopPlay: the scene the Setup tab built packs")
	level.free()
	dock.free()

	var vp := SubViewport.new()
	vp.size = Vector2i(1152, 648)  # a new project's window
	add_child(vp)
	var game: Node = ps.instantiate()
	vp.add_child(game)
	await get_tree().process_frame
	var hero: Node2D = game.get_node("Player")
	var panel: Control = game.get_node_or_null("UILayer/ShopPanel")
	var wallet: Node = hero.get_node("WalletLite")
	var gbag: Node = hero.get_node("Bag")
	gbag.add_item(ore, 2)
	_assert(panel is ShopPanelLite and not panel.visible, "ShopPlay: the ShopPanel starts hidden")
	if not (panel is ShopPanelLite):
		vp.queue_free()
		return
	var near: Vector2 = game.get_node("Keeper").global_position + Vector2(30, 0)
	hero.global_position = near
	await _physics(4)
	_assert(panel.visible, "ShopPlay: walking into the ShopArea opens it")
	await get_tree().process_frame
	var r := panel.get_global_rect()
	_assert(Rect2(Vector2.ZERO, Vector2(1152, 648)).encloses(r) and r.size.x >= 400.0 and r.size.y >= 250.0 and r.position.y >= 300.0,
		"ShopPlay: it opens in the lower middle of a 1152x648 window, with a real size (%s)" % r)
	var need: Vector2 = panel.get_child(0).get_combined_minimum_size()
	_assert(need.x <= r.size.x and need.y <= r.size.y, "ShopPlay: its content fits inside it (needs %s)" % need)
	_assert(_has_text(panel, "Gold: 100"), "ShopPlay: it shows the player's 100 gold")
	var buy_potion := _row_button(panel, "Health Potion", "Buy")
	var buy_sword := _row_button(panel, "Iron Sword", "Buy")
	_assert(buy_potion != null and not buy_potion.disabled, "ShopPlay: Health Potion (25) can be bought")
	_assert(buy_sword != null and buy_sword.disabled, "ShopPlay: Iron Sword (150) is greyed out, too dear")
	_assert(_row_button(panel, "Ore x2", "Sell") != null, "ShopPlay: the Sell list has the 2 ore from the bag")
	if buy_potion == null or buy_sword == null:
		vp.queue_free()
		return
	buy_potion.pressed.emit()
	await get_tree().process_frame
	_assert(wallet.get_balance() == 75 and gbag.count_item(potion) == 1,
		"ShopPlay: Buy took 25 gold and put the potion in the bag (%d gold, %d potion)" % [wallet.get_balance(), gbag.count_item(potion)])
	_assert(_has_text(panel, "Gold: 75") and _has_text(panel, "(4 left)"), "ShopPlay: the panel shows the new balance and stock")
	_assert(_toast("+1 Health Potion"), "ShopPlay: a \"+1 Health Potion\" message shows top centre")

	# two slots, ore and potion: a new kind of item doesn't fit
	var buy_gem := _row_button(panel, "Gem", "Buy")
	_assert(buy_gem != null and not buy_gem.disabled, "ShopPlay: Gem (30) can be clicked")
	if buy_gem != null:
		buy_gem.pressed.emit()
	await get_tree().process_frame
	_assert(_has_text(panel, "Your bag is full."), "ShopPlay: a buy the full bag can't take is turned down, with the reason")
	_assert(wallet.get_balance() == 75 and gbag.count_item(gem) == 0, "ShopPlay: and it costs nothing")
	# a click can't reach a greyed-out button, so press its handler
	_click(_row_button(panel, "Iron Sword", "Buy"))
	await get_tree().process_frame
	_assert(_has_text(panel, "Not enough gold."), "ShopPlay: turned down for money, it says so")

	_click(_row_button(panel, "Ore x2", "Sell"))
	await get_tree().process_frame
	_assert(wallet.get_balance() == 79 and gbag.count_item(ore) == 1,
		"ShopPlay: Sell paid 4 gold for one ore (%d gold, %d ore)" % [wallet.get_balance(), gbag.count_item(ore)])
	_assert(_row_button(panel, "Ore x1", "Sell") != null and _row_button(panel, "Health Potion x1", "Sell") != null,
		"ShopPlay: the Sell list follows the bag")

	# a long stock list scrolls inside the panel instead of growing it
	var gvendor: Node = game.get_node("Keeper/VendorLite")
	var kept: Array = gvendor.get("stock")
	var many: Array = []
	for i in 14:
		many.append({"item": _item("thing%d" % i, "Thing %d" % i), "price": 1, "stock": -1})
	gvendor.set("stock", many)
	gvendor.stock_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = panel.find_children("*", "ScrollContainer", true, false)[0]
	_assert(panel.get_global_rect().is_equal_approx(r) and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,
		"ShopPlay: 14 items scroll inside the same panel")
	gvendor.set("stock", kept)
	gvendor.stock_changed.emit()

	hero.global_position = Vector2(100, 100)
	await _physics(4)
	_assert(not panel.visible, "ShopPlay: walking out closes it")
	hero.global_position = near
	await _physics(4)
	_assert(panel.visible, "ShopPlay: walking back in opens it again")
	var shut := _button(panel, "Close")
	if shut != null:
		shut.pressed.emit()
	_assert(not panel.visible, "ShopPlay: Close shuts it")
	await get_tree().create_timer(2.3).timeout
	_assert(not _toast("+1 Health Potion"), "ShopPlay: the message goes away after about two seconds")
	vp.queue_free()


# 3D, and the working pair: the shop pays from the wallet beside it.
func _run_shop_play_3d() -> void:
	await get_tree().process_frame
	var dock = CHOOSER.new()
	var level := Node3D.new()
	level.name = "Level3D"
	var player := CharacterBody3D.new()
	player.name = "Player"
	level.add_child(player)
	player.owner = level
	var col := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.4
	col.shape = ball
	player.add_child(col)
	col.owner = level
	var bag = FixtureBag.new()
	bag.name = "Bag"
	player.add_child(bag)
	bag.owner = level
	dock.tag_player(level, player)
	var keeper := Node3D.new()
	keeper.name = "Keeper"
	keeper.position = Vector3(10, 0, 0)
	level.add_child(keeper)
	keeper.owner = level
	var bread := _item("bread", "Bread")
	var vendor = dock.wire_shop_and_wallet(level, keeper, 20)
	dock.set_stock_field(vendor, dock.add_stock_row(vendor, bread), "price", 5)
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	dock.free()

	var game: Node3D = ps.instantiate()
	add_child(game)
	await get_tree().process_frame
	var panel: Control = game.get_node_or_null("UILayer/ShopPanel")
	var hero: Node3D = game.get_node("Player")
	_assert(game.get_node_or_null("Keeper/ShopArea") is Area3D, "ShopPlay3D: a 3D shopkeeper gets an Area3D ShopArea")
	hero.global_position = Vector3(10.5, 0, 0)
	await _physics(4)
	_assert(panel != null and panel.visible, "ShopPlay3D: walking into it opens the panel")
	await get_tree().process_frame
	var buy := _row_button(panel, "Bread", "Buy") if panel != null else null
	if buy != null:
		buy.pressed.emit()
	await get_tree().process_frame
	var till: Node = game.get_node("Keeper/WalletLite")
	_assert(till.get_balance() == 15 and hero.get_node("Bag").count_item(bread) == 1,
		"ShopPlay3D: the working pair's wallet paid 5 and the bread went in the player's bag (%d)" % till.get_balance())
	hero.global_position = Vector3(0, 0, 0)
	await _physics(4)
	_assert(panel != null and not panel.visible, "ShopPlay3D: walking away closes it")
	game.queue_free()


func _body_2d(level: Node, n: String, at: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = n
	body.position = at
	level.add_child(body)
	body.owner = level
	var col := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(24, 24)
	col.shape = box
	body.add_child(col)
	col.owner = level
	return body


func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


# The row's button whose label mentions `text`.
func _row_button(root: Node, text: String, verb: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text != verb or not (b.get_parent() is HBoxContainer):
			continue
		for c in b.get_parent().get_children():
			if c is Label and (c as Label).text.contains(text):
				return b
	return null


# null-safe, so a broken panel reports FAIL lines instead of stopping the run
func _click(b: Button) -> void:
	if b != null:
		b.pressed.emit()


func _button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _has_text(root: Node, text: String) -> bool:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text.contains(text):
			return true
	return false


# A lite toast: a Label in group lite_toast, top centre on a layer-100 CanvasLayer.
func _toast(text: String) -> bool:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Label and (t as Label).text == text and not t.is_queued_for_deletion():
			var layer: Node = t.get_parent()
			return layer is CanvasLayer and (layer as CanvasLayer).layer == 100 and is_equal_approx((t as Label).anchor_left, 0.5)
	return false
