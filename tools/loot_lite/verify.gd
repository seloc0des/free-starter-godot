extends Node

# Headless test for Loot — Lite.
# Run: godot --headless --path . res://tools/loot_lite/verify.tscn

const ItemLiteScript := preload("res://addons/loot_lite/item_resource.gd")

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- loot lite verify ---")
	await _run_basic_weighted_roll()
	await _run_count_range_respected()
	await _run_empty_table_returns_empty()
	await _run_zero_weight_filtered()
	await _run_deterministic_with_seed()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/loot_lite/acceptance_report.gd").new()
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

func _item(id: String) -> Resource:
	var it: Resource = ItemLiteScript.new()
	it.id = id
	it.name = id.capitalize()
	return it


func _make_table(entries: Array, rolls: int = 1) -> LootTableLite:
	var t := LootTableLite.new()
	t.entries = entries
	t.rolls = rolls
	return t


# ---- tests ---------------------------------------------------------------

func _run_basic_weighted_roll() -> void:
	await get_tree().process_frame
	# 50/50 between coin and ruby over 2000 rolls should land within ~5%.
	var coin := _item("coin")
	var ruby := _item("ruby")
	var t := _make_table([
		{"item": coin, "weight": 50, "min": 1, "max": 1},
		{"item": ruby, "weight": 50, "min": 1, "max": 1},
	])
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var coin_count := 0
	var ruby_count := 0
	for i in range(2000):
		for r in t.roll(rng):
			if str(r.item.id) == "coin":
				coin_count += 1
			elif str(r.item.id) == "ruby":
				ruby_count += 1
	var ratio: float = float(coin_count) / float(maxi(ruby_count, 1))
	_assert(ratio > 0.85 and ratio < 1.15,
		"Weights: ~50/50 distribution (ratio %.2f, coin %d, ruby %d)" % [ratio, coin_count, ruby_count])


func _run_count_range_respected() -> void:
	await get_tree().process_frame
	var coin := _item("coin")
	var t := _make_table([
		{"item": coin, "weight": 100, "min": 3, "max": 5},
	])
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var min_seen := 100
	var max_seen := 0
	for i in range(200):
		for r in t.roll(rng):
			min_seen = mini(min_seen, int(r.count))
			max_seen = maxi(max_seen, int(r.count))
	_assert(min_seen >= 3 and max_seen <= 5,
		"CountRange: counts stay in [3..5] (seen %d..%d)" % [min_seen, max_seen])


func _run_empty_table_returns_empty() -> void:
	await get_tree().process_frame
	var t := _make_table([])
	_assert(t.roll().is_empty(), "Empty: empty entries → empty Array")
	var t2 := _make_table([{"item": _item("x"), "weight": 100}], 0)
	_assert(t2.roll().is_empty(), "Empty: rolls=0 → empty Array")


func _run_zero_weight_filtered() -> void:
	await get_tree().process_frame
	# Only zero-weight entries → total weight is 0 → empty result.
	var coin := _item("coin")
	var t := _make_table([
		{"item": coin, "weight": 0, "min": 1, "max": 1},
	])
	_assert(t.roll().is_empty(), "ZeroWeight: total weight 0 → empty result")


func _run_deterministic_with_seed() -> void:
	await get_tree().process_frame
	var a := _item("a")
	var b := _item("b")
	var c := _item("c")
	var t := _make_table([
		{"item": a, "weight": 30, "min": 1, "max": 1},
		{"item": b, "weight": 30, "min": 1, "max": 1},
		{"item": c, "weight": 40, "min": 1, "max": 1},
	], 3)
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var ids1: Array = []
	var ids2: Array = []
	for r in t.roll(rng1): ids1.append(str(r.item.id))
	for r in t.roll(rng2): ids2.append(str(r.item.id))
	_assert(ids1 == ids2, "Seed: same seed → same drops (%s vs %s)" % [str(ids1), str(ids2)])
