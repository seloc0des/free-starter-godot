extends Node

# Headless test for Vendor — Lite.
# Run: godot --headless --path . res://tools/vendor_lite/verify.tscn

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


func _item(id: String) -> Resource:
	var it := _Item.new()
	it.id = id
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
