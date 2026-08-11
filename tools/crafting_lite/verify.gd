extends Node

# Headless test for Crafting — Lite.
# Run: godot --headless --path . res://tools/crafting_lite/verify.tscn

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- crafting lite verify ---")
	await _run_happy_path_craft()
	await _run_missing_inputs_rejected()
	await _run_no_inventory_rejected()
	await _run_craft_completed_alias()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/crafting_lite/acceptance_report.gd").new()
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

# Minimal duck-typed bag for the crafting tests. The Lite crafting addon
# expects has_item / remove_item / add_item.
class _MiniBag extends Node:
	var items: Dictionary = {}  # id -> count
	func count_item(item: Resource) -> int:
		return int(items.get(str(item.id), 0))
	func has_item(item: Resource, amount: int = 1) -> bool:
		return count_item(item) >= amount
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


# Resources that quack like ItemLite — anything with `.id` works.
class _Item extends Resource:
	@export var id: String = ""


func _item(id: String) -> Resource:
	var it := _Item.new()
	it.id = id
	return it


func _recipe(inputs: Array, outputs: Array) -> RecipeLite:
	var r := RecipeLite.new()
	r.id = "test_recipe"
	r.inputs = inputs
	r.outputs = outputs
	return r


func _make_component(bag: Node) -> CraftingLite:
	var c := CraftingLite.new()
	c._inventory = bag
	add_child(c)
	return c


# ---- tests ---------------------------------------------------------------

func _run_happy_path_craft() -> void:
	await get_tree().process_frame
	var bag := _MiniBag.new()
	add_child(bag)
	var wood := _item("wood")
	var stick := _item("stick")
	bag.add_item(wood, 5)
	var comp := _make_component(bag)
	var ok := comp.craft(_recipe(
		[RecipeLite.io(wood, 1)],
		[RecipeLite.io(stick, 4)],
	))
	_assert(ok, "Happy: craft returns true")
	_assert(bag.count_item(wood) == 4, "Happy: 1 wood consumed (4 left, got %d)" % bag.count_item(wood))
	_assert(bag.count_item(stick) == 4, "Happy: 4 sticks produced (got %d)" % bag.count_item(stick))
	comp.queue_free(); bag.queue_free()


func _run_missing_inputs_rejected() -> void:
	await get_tree().process_frame
	var bag := _MiniBag.new()
	add_child(bag)
	var wood := _item("wood")
	var stick := _item("stick")
	# Empty bag — no wood.
	var comp := _make_component(bag)
	# GDScript lambdas capture scalars by value, so accumulate into an Array
	# (reference-typed) and read the last entry instead.
	var reason_box: Array = []
	comp.craft_failed.connect(func(_r, r): reason_box.append(r))
	var ok := comp.craft(_recipe(
		[RecipeLite.io(wood, 1)],
		[RecipeLite.io(stick, 1)],
	))
	_assert(not ok, "Missing: craft returns false")
	_assert(reason_box.size() == 1 and String(reason_box[0]) == CraftingLite.REASON_MISSING_INPUTS,
		"Missing: reason is missing_inputs (got %s)" % str(reason_box))
	comp.queue_free(); bag.queue_free()


func _run_no_inventory_rejected() -> void:
	await get_tree().process_frame
	var wood := _item("wood")
	var stick := _item("stick")
	var comp := CraftingLite.new()
	comp._inventory = null
	add_child(comp)
	var reason_box: Array = []
	comp.craft_failed.connect(func(_r, r): reason_box.append(r))
	var ok := comp.craft(_recipe(
		[RecipeLite.io(wood, 1)],
		[RecipeLite.io(stick, 1)],
	))
	_assert(not ok, "NoInv: craft returns false")
	_assert(reason_box.size() == 1 and String(reason_box[0]) == CraftingLite.REASON_NO_INVENTORY,
		"NoInv: reason is no_inventory_bound (got %s)" % str(reason_box))
	comp.queue_free()


# Regression: the `craft_completed` alias was added to align Lite with Pro
# (which uses `craft_completed` exclusively). Both names must continue to
# fire so existing Lite consumers don't break.
func _run_craft_completed_alias() -> void:
	await get_tree().process_frame
	var bag := _MiniBag.new()
	add_child(bag)
	var wood := _item("wood")
	var stick := _item("stick")
	bag.add_item(wood, 1)
	var comp := _make_component(bag)
	var saw: Array = []
	comp.crafted.connect(func(_r, _o): saw.append("legacy"))
	comp.craft_completed.connect(func(_r, _o): saw.append("aligned"))
	comp.craft(_recipe(
		[RecipeLite.io(wood, 1)],
		[RecipeLite.io(stick, 1)],
	))
	_assert("legacy" in saw, "Alias: legacy `crafted` still fires (saw %s)" % str(saw))
	_assert("aligned" in saw, "Alias: aligned `craft_completed` also fires (saw %s)" % str(saw))
	comp.queue_free(); bag.queue_free()
