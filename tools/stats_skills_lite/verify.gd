extends Node

# Headless test for Stats / Skills — Lite.
# Run: godot --headless --path . res://tools/stats_skills_lite/verify.tscn

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- stats lite verify ---")
	await _run_base_value()
	await _run_set_base_override()
	await _run_flat_modifier()
	await _run_percent_add_modifier()
	await _run_percent_mult_modifier()
	await _run_combined_modifiers()
	await _run_clamp_min_max()
	await _run_remove_modifier_by_source_id()
	await _run_signal_fires()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/stats_skills_lite/acceptance_report.gd").new()
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

func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return abs(a - b) < eps


func _def(id: String, base: float, mn: float = -1.0e9, mx: float = 1.0e9) -> StatDefinitionLite:
	var d := StatDefinitionLite.new()
	d.id = id
	d.display_name = id.capitalize()
	d.base_value = base
	d.min_value = mn
	d.max_value = mx
	return d


func _make_stats(defs: Array) -> StatsComponentLite:
	var s := StatsComponentLite.new()
	# Typed Array[StatDefinitionLite] doesn't accept a plain Array; build the
	# typed array explicitly.
	var typed: Array[StatDefinitionLite] = []
	for d in defs:
		typed.append(d)
	s.definitions = typed
	add_child(s)
	return s


# ---- tests ---------------------------------------------------------------

func _run_base_value() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("strength", 10.0)])
	_assert(_approx(s.get_stat("strength"), 10.0), "Base: strength = 10")
	_assert(_approx(s.get_stat("unknown"), 0.0), "Base: missing def returns 0")
	s.queue_free()


func _run_set_base_override() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("hp", 100.0)])
	s.set_base("hp", 75.0)
	_assert(_approx(s.get_stat("hp"), 75.0), "Override: base override applied")
	s.queue_free()


func _run_flat_modifier() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 5.0)])
	s.add_modifier({"stat": "damage", "op": "flat", "amount": 8.0, "source_id": "sword"})
	_assert(_approx(s.get_stat("damage"), 13.0), "Flat: 5 + 8 = 13 (got %f)" % s.get_stat("damage"))
	s.queue_free()


func _run_percent_add_modifier() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 10.0)])
	s.add_modifier({"stat": "damage", "op": "percent_add", "amount": 25.0, "source_id": "buff"})
	_assert(_approx(s.get_stat("damage"), 12.5),
		"PercentAdd: 10 × (1 + 0.25) = 12.5 (got %f)" % s.get_stat("damage"))
	s.queue_free()


func _run_percent_mult_modifier() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 10.0)])
	s.add_modifier({"stat": "damage", "op": "percent_mult", "amount": 50.0, "source_id": "rage"})
	s.add_modifier({"stat": "damage", "op": "percent_mult", "amount": 20.0, "source_id": "haste"})
	# 10 × 1.5 × 1.2 = 18.0
	_assert(_approx(s.get_stat("damage"), 18.0),
		"PercentMult: 10 × 1.5 × 1.2 = 18 (got %f)" % s.get_stat("damage"))
	s.queue_free()


func _run_combined_modifiers() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 10.0)])
	s.add_modifier({"stat": "damage", "op": "flat", "amount": 5.0, "source_id": "a"})
	s.add_modifier({"stat": "damage", "op": "percent_add", "amount": 20.0, "source_id": "b"})
	s.add_modifier({"stat": "damage", "op": "percent_mult", "amount": 10.0, "source_id": "c"})
	# (10 + 5) × (1 + 0.20) × 1.10 = 19.8
	_assert(_approx(s.get_stat("damage"), 19.8),
		"Combo: (10+5)*1.2*1.1 = 19.8 (got %f)" % s.get_stat("damage"))
	s.queue_free()


func _run_clamp_min_max() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("hp", 50.0, 0.0, 100.0)])
	s.add_modifier({"stat": "hp", "op": "flat", "amount": 999.0, "source_id": "heal"})
	_assert(_approx(s.get_stat("hp"), 100.0), "Clamp: hp caps at max (got %f)" % s.get_stat("hp"))
	s.add_modifier({"stat": "hp", "op": "flat", "amount": -9999.0, "source_id": "wipe"})
	_assert(_approx(s.get_stat("hp"), 0.0), "Clamp: hp floors at min (got %f)" % s.get_stat("hp"))
	s.queue_free()


func _run_remove_modifier_by_source_id() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 10.0)])
	s.add_modifier({"stat": "damage", "op": "flat", "amount": 5.0, "source_id": "sword"})
	s.add_modifier({"stat": "damage", "op": "flat", "amount": 3.0, "source_id": "ring"})
	_assert(_approx(s.get_stat("damage"), 18.0), "RemovePre: 10+5+3 = 18")
	var n := s.remove_modifier("sword")
	_assert(n == 1, "Remove: 1 entry removed (got %d)" % n)
	_assert(_approx(s.get_stat("damage"), 13.0), "Remove: 10+3 = 13 after sword off")
	s.queue_free()


func _run_signal_fires() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("hp", 50.0)])
	var seen: Array = []
	var cb := func(stat_id: String, v: float):
		if stat_id == "hp":
			seen.append(v)
	s.stat_changed.connect(cb)
	s.add_modifier({"stat": "hp", "op": "flat", "amount": 25.0, "source_id": "buff"})
	s.stat_changed.disconnect(cb)
	_assert(seen.size() >= 1 and _approx(float(seen[seen.size() - 1]), 75.0),
		"Signal: stat_changed fired with 75 (got %s)" % str(seen))
	s.queue_free()
