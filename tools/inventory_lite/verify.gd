extends Node

# Headless test for Inventory — Lite.
# Run: godot --headless --path . res://tools/inventory_lite/verify.tscn

const ItemLiteScript := preload("res://addons/inventory_lite/item_resource.gd")

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- inventory lite verify ---")
	await _run_basic_stacking()
	await _run_capacity_overflow()
	await _run_remove_partial_and_full()
	await _run_signals_fire()
	await _run_snapshot_roundtrip()
	await _run_null_slot_does_not_crash()
	await _run_max_stack_default()
	await _run_pickup_fills_bag()
	await _run_pickup_full_bag()
	await _run_pickup_partial_and_quiet()
	await _run_pickup_ignores_strangers()
	await _run_bag_list_toggles()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/inventory_lite/acceptance_report.gd").new()
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

func _item(id: String, max_stack: int = 99) -> Resource:
	var it: Resource = ItemLiteScript.new()
	it.id = id
	it.name = id.capitalize()
	it.max_stack = max_stack
	return it


func _make_inv(capacity: int = 8) -> InventoryLite:
	var inv := InventoryLite.new()
	inv.capacity = capacity
	add_child(inv)
	return inv


# ---- tests ---------------------------------------------------------------

func _run_basic_stacking() -> void:
	await get_tree().process_frame
	var inv := _make_inv(4)
	var apple := _item("apple", 99)
	var leftover := inv.add_item(apple, 30)
	_assert(leftover == 0, "Stacking: 30 fits in one slot (leftover %d)" % leftover)
	_assert(inv.count_item(apple) == 30, "Stacking: count_item == 30")
	leftover = inv.add_item(apple, 100)
	_assert(leftover == 0, "Stacking: 100 more spills into new slot")
	_assert(inv.count_item(apple) == 130, "Stacking: total 130 (got %d)" % inv.count_item(apple))
	inv.queue_free()


func _run_capacity_overflow() -> void:
	await get_tree().process_frame
	var inv := _make_inv(2)
	var sword := _item("sword", 1)
	inv.add_item(sword, 1)
	inv.add_item(sword, 1)
	var leftover := inv.add_item(sword, 1)
	_assert(leftover == 1, "Capacity: third sword rejected (leftover %d)" % leftover)
	inv.queue_free()


func _run_remove_partial_and_full() -> void:
	await get_tree().process_frame
	var inv := _make_inv(4)
	var ore := _item("ore", 99)
	inv.add_item(ore, 10)
	var removed := inv.remove_item(ore, 7)
	_assert(removed == 7, "Remove: partial returns 7 (got %d)" % removed)
	_assert(inv.count_item(ore) == 3, "Remove: 3 ore remaining")
	removed = inv.remove_item(ore, 100)
	_assert(removed == 3, "Remove: over-request returns actual 3 (got %d)" % removed)
	_assert(inv.count_item(ore) == 0, "Remove: bag now empty")
	inv.queue_free()


func _run_signals_fire() -> void:
	await get_tree().process_frame
	var inv := _make_inv(2)
	var sword := _item("sword", 1)
	var added_payloads: Array = []
	var full_payloads: Array = []
	inv.item_added.connect(func(item, amount): added_payloads.append([item.id, amount]))
	inv.slot_full.connect(func(item): full_payloads.append(item.id))
	inv.add_item(sword, 1)
	inv.add_item(sword, 1)
	inv.add_item(sword, 1)  # over capacity → slot_full
	_assert(added_payloads.size() == 2, "Signals: item_added fired twice (got %d)" % added_payloads.size())
	_assert(full_payloads.size() == 1 and full_payloads[0] == "sword", "Signals: slot_full fired for sword (got %s)" % str(full_payloads))
	inv.queue_free()


func _run_snapshot_roundtrip() -> void:
	await get_tree().process_frame
	# Snapshot needs an item with a resource_path (the demo has .tres items).
	# Use a built-in icon's path as a stand-in stable path.
	var inv := _make_inv(4)
	# Construct an item Resource without a path; snapshot will skip it cleanly
	# thanks to the null/empty-path guards.
	var ghost := _item("ghost", 99)
	inv.add_item(ghost, 5)
	var snap := inv.snapshot()
	_assert(snap.size() == 1, "Snapshot: 1 entry returned (got %d)" % snap.size())
	# Empty resource_path means item_path is empty — restore should skip it
	# without crashing.
	inv.clear()
	inv.restore(snap)
	_assert(inv.slot_count() == 0, "Snapshot: empty path entries safely skipped on restore")
	inv.queue_free()


func _run_null_slot_does_not_crash() -> void:
	await get_tree().process_frame
	# Regression: defensive guards must keep count_item / remove_item /
	# snapshot safe even if a slot's `item` somehow becomes null (corrupted
	# state, third-party manipulation). The lite addon was vulnerable per the
	# code review; the guards added here are what we're proving.
	var inv := _make_inv(4)
	var apple := _item("apple", 99)
	inv.add_item(apple, 3)
	# Forcefully poison one slot to simulate corruption.
	var slots := inv._slots
	slots.append({"item": null, "count": 99})
	# All these calls would have crashed without the null guards.
	var ok := true
	if inv.count_item(apple) != 3:
		ok = false
	if inv.remove_item(apple, 1) != 1:
		ok = false
	# snapshot must filter out the poisoned slot rather than dereference its null item.
	var snap := inv.snapshot()
	for entry in snap:
		if entry.get("item_path", null) == null:
			ok = false
	_assert(ok, "NullSlot: poisoned slot didn't crash count/remove/snapshot")
	inv.queue_free()


func _run_max_stack_default() -> void:
	await get_tree().process_frame
	# Document the Lite-tier default: 99. Pro tier defaults to 1 (non-stackable).
	# Locking this in a test so the upgrade migration page stays accurate.
	var fresh: Resource = ItemLiteScript.new()
	_assert(int(fresh.max_stack) == 99,
		"Default: ItemLite.max_stack = 99 (got %d)" % int(fresh.max_stack))


# ---- pickups + bag list (what the Setup tab builds, put together by hand) ----

# A level with a player (in the "player" group, with a bag) and a coin lying
# somewhere else: a Node2D holding a PickupArea and a PickupLite.
func _level(capacity: int, item: Resource, amount: int) -> Dictionary:
	var level := Node2D.new()
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group("player")
	player.add_child(_shape(10.0))
	var bag := InventoryLite.new()
	bag.capacity = capacity
	player.add_child(bag)
	level.add_child(player)
	var coin := Node2D.new()
	coin.name = "Coin"
	coin.position = Vector2(400, 100)
	var area := Area2D.new()
	area.name = "PickupArea"
	area.add_child(_shape(24.0))
	coin.add_child(area)
	var pickup := PickupLite.new()
	pickup.item = item
	pickup.amount = amount
	coin.add_child(pickup)
	level.add_child(coin)
	add_child(level)
	return {"level": level, "player": player, "bag": bag, "coin": coin, "pickup": pickup}


func _shape(r: float) -> CollisionShape2D:
	var col := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = r
	col.shape = c
	return col


# Teleport into the coin and give physics a few frames to notice.
func _walk_in(body: Node2D, to: Node2D) -> void:
	body.global_position = to.global_position
	for i in 6:
		await get_tree().physics_frame
	await get_tree().process_frame


func _toasts() -> Array:
	var out: Array = []
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if not t.is_queued_for_deletion():
			out.append(t)
	return out


func _toast_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for t in _toasts():
		out.append(String(t.text))
	return out


func _clear_toasts() -> void:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		t.get_parent().queue_free()
	await get_tree().process_frame


func _press(key: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _run_pickup_fills_bag() -> void:
	await _clear_toasts()
	var apple := _item("apple", 99)
	apple.name = "Apple"
	var l := _level(4, apple, 2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(l.bag.count_item(apple) == 0 and is_instance_valid(l.coin), "Pickup: nothing happens before the player touches it")
	await _walk_in(l.player, l.coin)
	_assert(l.bag.count_item(apple) == 2, "Pickup: walking into it puts 2 apples in the bag (got %d)" % l.bag.count_item(apple))
	_assert(not is_instance_valid(l.coin), "Pickup: the coin it sat on is gone")
	_assert(_toast_texts().has("+2 Apple"), "Pickup: a toast says +2 Apple (got %s)" % str(_toast_texts()))
	var t: Array = _toasts()
	var ok := false
	if t.size() > 0:
		var lab: Label = t[0]
		ok = lab.get_parent() is CanvasLayer and (lab.get_parent() as CanvasLayer).layer == 100 \
			and is_equal_approx(lab.anchor_left, 0.5) and is_equal_approx(lab.anchor_top, 0.0)
	_assert(ok, "Pickup: the toast is top centre on CanvasLayer 100")
	await get_tree().create_timer(2.3).timeout
	_assert(_toasts().is_empty(), "Pickup: the toast is gone after about 2 seconds")
	l.level.queue_free()


func _run_pickup_full_bag() -> void:
	await _clear_toasts()
	var sword := _item("sword", 1)
	var apple := _item("apple", 99)
	apple.name = "Apple"
	var l := _level(1, apple, 1)
	l.bag.add_item(sword, 1)  # one slot, taken
	await _walk_in(l.player, l.coin)
	_assert(l.bag.count_item(apple) == 0, "FullBag: nothing went in")
	_assert(is_instance_valid(l.coin) and not l.coin.is_queued_for_deletion(), "FullBag: the pickup stays where it is")
	_assert(_toast_texts().has("Bag is full"), "FullBag: a toast says Bag is full (got %s)" % str(_toast_texts()))
	# make room, step out and back in: now it's taken
	l.bag.remove_item(sword, 1)
	l.player.global_position = Vector2(-500, -500)
	for i in 4:
		await get_tree().physics_frame
	await _walk_in(l.player, l.coin)
	_assert(l.bag.count_item(apple) == 1 and not is_instance_valid(l.coin), "FullBag: after making room, walking in again takes it")
	l.level.queue_free()


func _run_pickup_partial_and_quiet() -> void:
	await _clear_toasts()
	var apple := _item("apple", 5)
	apple.name = "Apple"
	var l := _level(1, apple, 3)
	l.bag.add_item(apple, 4)  # room for one more
	await _walk_in(l.player, l.coin)
	_assert(l.bag.count_item(apple) == 5, "Partial: the one that fits goes in (got %d)" % l.bag.count_item(apple))
	_assert(is_instance_valid(l.coin) and int(l.pickup.amount) == 2, "Partial: the other 2 stay on the ground")
	var t: Array = _toasts()
	var stacked := t.size() == 2 and String(t[0].text) == "+1 Apple" and String(t[1].text) == "Bag is full" \
		and (t[1] as Control).get_global_rect().position.y > (t[0] as Control).get_global_rect().position.y
	_assert(stacked, "Partial: +1 Apple, then Bag is full below it (got %s)" % str(_toast_texts()))
	l.level.queue_free()
	await _clear_toasts()
	var quiet := _level(4, apple, 1)
	quiet.pickup.show_messages = false
	await _walk_in(quiet.player, quiet.coin)
	_assert(quiet.bag.count_item(apple) == 1 and _toasts().is_empty(), "Quiet: show_messages off still picks up, with no toast")
	quiet.level.queue_free()


func _run_pickup_ignores_strangers() -> void:
	await _clear_toasts()
	var apple := _item("apple", 99)
	var l := _level(4, apple, 1)
	var goblin := CharacterBody2D.new()
	goblin.add_child(_shape(10.0))
	var loot_bag := InventoryLite.new()  # a bag of its own, so only the group keeps it out
	goblin.add_child(loot_bag)
	l.level.add_child(goblin)
	await _walk_in(goblin, l.coin)
	_assert(is_instance_valid(l.coin) and l.bag.count_item(apple) == 0 and loot_bag.count_item(apple) == 0, "Strangers: a body outside the player group doesn't take it, even with a bag")
	l.level.queue_free()


func _run_bag_list_toggles() -> void:
	await _clear_toasts()
	var fresh := BagListLite.new()
	_assert(fresh.toggle_action == &"inventory", "BagList: it toggles on the \"inventory\" action unless told otherwise")
	fresh.free()
	# its own action on I, so a project that already binds "inventory" elsewhere
	# still passes (the Setup tab's real action is covered in verify_chooser)
	InputMap.add_action(&"verify_bag_toggle")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_I
	ev.device = -1
	InputMap.action_add_event(&"verify_bag_toggle", ev)
	var apple := _item("apple", 99)
	apple.name = "Apple"
	var sword := _item("sword", 1)
	sword.name = "Iron Sword"
	var l := _level(24, apple, 1)
	l.bag.add_item(apple, 3)
	l.bag.add_item(sword, 1)
	var layer := CanvasLayer.new()
	var list := BagListLite.new()
	list.toggle_action = &"verify_bag_toggle"
	list.visible = false
	layer.add_child(list)
	l.level.add_child(layer)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	var r := list.get_global_rect()
	_assert(r.size.x > 0 and r.size.y > 0 and is_equal_approx(r.position.x, 16.0) and is_equal_approx(r.end.y, vp.y - 16.0),
		"BagList: a hand-added list places itself bottom-left (%s in %s)" % [str(r), str(vp)])
	await _press(KEY_I)
	_assert(list.visible, "BagList: I opens it")
	_assert(_rows(list) == PackedStringArray(["Apple x3", "Iron Sword x1"]), "BagList: it lists the bag (got %s)" % str(_rows(list)))
	l.bag.add_item(apple, 2)
	await get_tree().process_frame
	_assert(_rows(list) == PackedStringArray(["Apple x5", "Iron Sword x1"]), "BagList: it follows the bag's changes (got %s)" % str(_rows(list)))
	await _press(KEY_I)
	_assert(not list.visible, "BagList: I again closes it")
	l.level.queue_free()
	InputMap.erase_action(&"verify_bag_toggle")


# The list's row texts, skipping rows already on their way out.
func _rows(list: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in list._rows.get_children():
		if not n.is_queued_for_deletion():
			out.append(String(n.text))
	return out
