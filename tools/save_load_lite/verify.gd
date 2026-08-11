extends Node

# Headless test for Save / Load — Lite.
# Run: godot --headless --path . res://tools/save_load_lite/verify.tscn

const TEST_PATH := "user://verify_save_lite.json"

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- save/load lite verify ---")
	await _run_roundtrip_dictionary_state()
	await _run_missing_file_fails_cleanly()
	await _run_malformed_json_fails_cleanly()
	await _run_delete_save()
	await _run_only_contract_group_participates()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/save_load_lite/acceptance_report.gd").new()
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

class _Saver extends Node:
	var save_id: String = ""
	var payload: Dictionary = {}
	func get_save_id() -> String:
		return save_id
	func save_state() -> Dictionary:
		return payload.duplicate(true)
	func load_state(data: Dictionary) -> void:
		payload = data.duplicate(true)


func _make_saver(id: String, payload: Dictionary) -> _Saver:
	var n := _Saver.new()
	n.name = "Saver_%s_%d" % [id, Time.get_ticks_usec()]
	n.save_id = id
	n.payload = payload.duplicate(true)
	n.add_to_group(SaveLite.CONTRACT_GROUP)
	get_tree().root.add_child(n)
	return n


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	for n in get_tree().get_nodes_in_group(SaveLite.CONTRACT_GROUP):
		n.queue_free()


# ---- tests ---------------------------------------------------------------

func _run_roundtrip_dictionary_state() -> void:
	await get_tree().process_frame
	_cleanup()
	var s := _make_saver("player", {"hp": 88, "name": "Hero"})
	var ok := SaveLite.save(TEST_PATH)
	_assert(ok, "Roundtrip: save() returned true")
	_assert(FileAccess.file_exists(TEST_PATH), "Roundtrip: file exists on disk")
	# Wipe state, reload.
	s.payload = {}
	var loaded := SaveLite.load(TEST_PATH)
	_assert(loaded, "Roundtrip: load() returned true")
	_assert(int(s.payload.get("hp", 0)) == 88, "Roundtrip: hp restored (got %d)" % int(s.payload.get("hp", 0)))
	_assert(String(s.payload.get("name", "")) == "Hero", "Roundtrip: name restored")
	_cleanup()


func _run_missing_file_fails_cleanly() -> void:
	await get_tree().process_frame
	_cleanup()
	# GDScript lambdas capture scalars by value — accumulate into an Array so
	# the assignment from inside the callback survives.
	var reasons: Array = []
	var cb := func(r: String):
		reasons.append(r)
	SaveLite.load_failed.connect(cb)
	var ok := SaveLite.load(TEST_PATH)
	SaveLite.load_failed.disconnect(cb)
	_assert(not ok, "MissingFile: load returns false for absent file")
	_assert(reasons.size() == 1 and String(reasons[0]).begins_with("not_found"),
		"MissingFile: load_failed emits not_found (got %s)" % str(reasons))


func _run_malformed_json_fails_cleanly() -> void:
	await get_tree().process_frame
	_cleanup()
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("not json at all {{{")
	f.close()
	var reasons: Array = []
	var cb := func(r: String):
		reasons.append(r)
	SaveLite.load_failed.connect(cb)
	var ok := SaveLite.load(TEST_PATH)
	SaveLite.load_failed.disconnect(cb)
	_assert(not ok, "Malformed: load returns false")
	_assert(reasons.size() == 1 and String(reasons[0]).begins_with("malformed_json"),
		"Malformed: load_failed emits malformed_json (got %s)" % str(reasons))
	_cleanup()


func _run_delete_save() -> void:
	await get_tree().process_frame
	_cleanup()
	var s := _make_saver("dummy", {"x": 1})
	SaveLite.save(TEST_PATH)
	_assert(SaveLite.has_save(TEST_PATH), "Delete: save exists pre-delete")
	_assert(SaveLite.delete_save(TEST_PATH), "Delete: delete_save returns true")
	_assert(not SaveLite.has_save(TEST_PATH), "Delete: save gone post-delete")
	_assert(not SaveLite.delete_save(TEST_PATH), "Delete: second delete returns false")
	s.queue_free()


func _run_only_contract_group_participates() -> void:
	await get_tree().process_frame
	_cleanup()
	# Node with save methods but NOT in the contract group must be ignored.
	var s := _make_saver("in_group", {"v": 1})
	var orphan := _Saver.new()
	orphan.save_id = "orphan"
	orphan.payload = {"should_not_save": true}
	# Intentionally do NOT add_to_group
	get_tree().root.add_child(orphan)
	SaveLite.save(TEST_PATH)
	# Reload the JSON and inspect the keys directly.
	var f := FileAccess.open(TEST_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var nodes: Dictionary = parsed.get("nodes", {})
	_assert(nodes.has("in_group"), "Group: contract-group saver persisted")
	_assert(not nodes.has("orphan"), "Group: non-contract saver ignored")
	orphan.queue_free()
	_cleanup()
