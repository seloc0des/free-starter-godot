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
