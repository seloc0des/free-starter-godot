extends Node

# Headless test for Save / Load — Lite.
# Run: godot --headless --path . res://tools/save_load_lite/verify.tscn

const TEST_PATH := "user://verify_save_lite.json"
const CHOOSER := preload("res://addons/save_load_lite/editor/save-load_chooser_dock.gd")
const SAVEABLE := preload("res://addons/save_load_lite/saveable.gd")

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report
var _stashed: PackedByteArray
var _had_save := false


func _ready() -> void:
	await get_tree().process_frame
	print("--- save/load lite verify ---")
	await _run_roundtrip_dictionary_state()
	await _run_missing_file_fails_cleanly()
	await _run_malformed_json_fails_cleanly()
	await _run_delete_save()
	await _run_only_contract_group_participates()
	await _run_typed_values_roundtrip()
	# the quick keys write SaveLite's default file, so park any real save first
	_stash_default_save()
	await _run_quick_keys()
	await _run_load_on_start()
	await _run_keys_messages()
	_restore_default_save()
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
	n.add_to_group(SAVE_LITE.CONTRACT_GROUP)
	get_tree().root.add_child(n)
	return n


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	for n in get_tree().get_nodes_in_group(SAVE_LITE.CONTRACT_GROUP):
		n.queue_free()


# Stands behind SaveKeys in input order: it only hears a key SaveKeys let through.
class _KeySpy extends Node:
	var heard: Array = []
	func _unhandled_input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k != null and k.pressed:
			heard.append(k.physical_keycode)


# a buyer's player script: an int, a colour, a typed array, plus an untyped var
func _hero_script() -> GDScript:
	var gs := GDScript.new()
	gs.source_code = "extends Node2D\n\n@export var coins: int = 0\n@export var tint: Color = Color.WHITE\n@export var tags: Array[String] = []\nvar lives = 3\n"
	gs.reload()
	return gs


# The scene the Setup tab builds: Apply "Save this node's state" on Hero, then
# "Quick save and load keys". Packed and played like a real scene.
func _quick_scene(load_on_start: bool, keys_first := false) -> PackedScene:
	var dock = CHOOSER.new()
	var game := Node2D.new()
	game.name = "Game"
	var hero := Node2D.new()
	hero.name = "Hero"
	hero.set_script(_hero_script())
	game.add_child(hero)
	hero.owner = game
	dock.wire_saveable(game, hero)
	var keys: Node = dock.wire_keys(game, load_on_start)
	if keys_first:
		game.move_child(keys, 0)  # a buyer dragged it to the top of the tree
	var ps := PackedScene.new()
	ps.pack(game)
	game.free()
	dock.free()
	return ps


func _play(ps: PackedScene) -> Node:
	var game: Node = ps.instantiate()
	var spy := _KeySpy.new()
	spy.name = "Spy"
	game.add_child(spy)
	game.move_child(spy, 0)
	get_tree().root.add_child(game)
	return game


func _press(code: Key, echo := false) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.keycode = code
	down.pressed = true
	down.echo = echo
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.keycode = code
	Input.parse_input_event(up)
	await get_tree().process_frame
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
		t.get_parent().free()


func _stash_default_save() -> void:
	_had_save = FileAccess.file_exists(SAVE_LITE.DEFAULT_PATH)
	if _had_save:
		_stashed = FileAccess.get_file_as_bytes(SAVE_LITE.DEFAULT_PATH)
		DirAccess.remove_absolute(SAVE_LITE.DEFAULT_PATH)


func _restore_default_save() -> void:
	if FileAccess.file_exists(SAVE_LITE.DEFAULT_PATH):
		DirAccess.remove_absolute(SAVE_LITE.DEFAULT_PATH)
	if _had_save:
		var f := FileAccess.open(SAVE_LITE.DEFAULT_PATH, FileAccess.WRITE)
		f.store_buffer(_stashed)
		f.close()


func _drop_default_save() -> void:
	if FileAccess.file_exists(SAVE_LITE.DEFAULT_PATH):
		DirAccess.remove_absolute(SAVE_LITE.DEFAULT_PATH)


# ---- tests ---------------------------------------------------------------

func _run_roundtrip_dictionary_state() -> void:
	await get_tree().process_frame
	_cleanup()
	var s := _make_saver("player", {"hp": 88, "name": "Hero"})
	var ok := _save_lite().save(TEST_PATH)
	_assert(ok, "Roundtrip: save() returned true")
	_assert(FileAccess.file_exists(TEST_PATH), "Roundtrip: file exists on disk")
	# Wipe state, reload.
	s.payload = {}
	var loaded := _save_lite().load(TEST_PATH)
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
	_save_lite().load_failed.connect(cb)
	var ok := _save_lite().load(TEST_PATH)
	_save_lite().load_failed.disconnect(cb)
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
	_save_lite().load_failed.connect(cb)
	var ok := _save_lite().load(TEST_PATH)
	_save_lite().load_failed.disconnect(cb)
	_assert(not ok, "Malformed: load returns false")
	_assert(reasons.size() == 1 and String(reasons[0]).begins_with("malformed_json"),
		"Malformed: load_failed emits malformed_json (got %s)" % str(reasons))
	_cleanup()


func _run_delete_save() -> void:
	await get_tree().process_frame
	_cleanup()
	var s := _make_saver("dummy", {"x": 1})
	_save_lite().save(TEST_PATH)
	_assert(_save_lite().has_save(TEST_PATH), "Delete: save exists pre-delete")
	_assert(_save_lite().delete_save(TEST_PATH), "Delete: delete_save returns true")
	_assert(not _save_lite().has_save(TEST_PATH), "Delete: save gone post-delete")
	_assert(not _save_lite().delete_save(TEST_PATH), "Delete: second delete returns false")
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
	_save_lite().save(TEST_PATH)
	# Reload the JSON and inspect the keys directly.
	var f := FileAccess.open(TEST_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var nodes: Dictionary = parsed.get("nodes", {})
	_assert(nodes.has("in_group"), "Group: contract-group saver persisted")
	_assert(not nodes.has("orphan"), "Group: non-contract saver ignored")
	orphan.queue_free()
	_cleanup()


# JSON has no Vector2 or Color, and hands numbers back as floats. The Saveable used
# to lose position outright and load a Color as black.
func _run_typed_values_roundtrip() -> void:
	await get_tree().process_frame
	_cleanup()
	var hero := Node2D.new()
	hero.name = "TypedHero"
	hero.set_script(_hero_script())
	get_tree().root.add_child(hero)
	var sv: Node = SAVEABLE.new()
	sv.save_id = "typed"
	sv.save_properties = PackedStringArray(["position", "coins", "tint", "tags", "lives"])
	hero.add_child(sv)
	var body := Node3D.new()
	body.name = "TypedBody"
	get_tree().root.add_child(body)
	var sv3: Node = SAVEABLE.new()
	sv3.save_id = "typed3d"
	sv3.save_properties = PackedStringArray(["position"])
	body.add_child(sv3)
	await get_tree().process_frame
	hero.position = Vector2(12.5, -40)
	hero.set("coins", 9)
	hero.set("tint", Color(0.2, 0.4, 0.6))
	var picked: Array[String] = ["red_key", "map"]
	hero.set("tags", picked)
	hero.set("lives", 5)
	body.position = Vector3(1, 2, 3)
	_save_lite().save(TEST_PATH)
	hero.position = Vector2.ZERO
	hero.set("coins", 0)
	hero.set("tint", Color.WHITE)
	var none: Array[String] = []
	hero.set("tags", none)  # typed, or set() quietly refuses it
	hero.set("lives", 0)
	body.position = Vector3.ZERO
	_save_lite().load(TEST_PATH)
	_assert(hero.position == Vector2(12.5, -40), "Typed: a 2D position comes back (got %s)" % hero.position)
	_assert(body.position == Vector3(1, 2, 3), "Typed: a 3D position comes back (got %s)" % body.position)
	var tint: Color = hero.get("tint")
	_assert(tint.is_equal_approx(Color(0.2, 0.4, 0.6)), "Typed: a Color comes back (got %s)" % tint)
	var tags: Array = hero.get("tags")
	_assert(tags.size() == 2 and tags[0] == "red_key" and tags.is_typed(), "Typed: an Array[String] export comes back (got %s)" % str(tags))
	_assert(typeof(hero.get("lives")) == TYPE_INT and int(hero.get("lives")) == 5, "Typed: a whole number stays a whole number (got %s)" % str(hero.get("lives")))
	_assert(int(hero.get("coins")) == 9, "Typed: an int export comes back")
	hero.free()
	body.free()
	_cleanup()


# F5 / F9 on the scene the Setup tab builds, fed as real key events.
func _run_quick_keys() -> void:
	await get_tree().process_frame
	_cleanup()
	_drop_default_save()
	_clear_toasts()
	var game := _play(_quick_scene(false))
	await get_tree().process_frame
	var hero: Node2D = game.get_node("Hero")
	var spy = game.get_node("Spy")
	hero.position = Vector2(321, 123)
	hero.set("coins", 7)
	await _press(KEY_F5)
	_assert(_save_lite().has_save(), "QuickKeys: F5 writes the save")
	_assert(_toast_texts().has("Game saved"), "QuickKeys: F5 says \"Game saved\" (got %s)" % str(_toast_texts()))
	_assert(not spy.heard.has(KEY_F5), "QuickKeys: F5 is marked handled, nothing behind SaveKeys gets it")
	hero.position = Vector2.ZERO
	hero.set("coins", 0)
	_clear_toasts()
	await _press(KEY_F9)
	_assert(int(hero.get("coins")) == 7, "QuickKeys: F9 restores the saved value (got %s)" % str(hero.get("coins")))
	_assert(hero.position == Vector2(321, 123), "QuickKeys: F9 restores the position (got %s)" % hero.position)
	_assert(_toast_texts().has("Game loaded"), "QuickKeys: F9 says \"Game loaded\" (got %s)" % str(_toast_texts()))
	_assert(not spy.heard.has(KEY_F9), "QuickKeys: F9 is marked handled too")
	# negatives: someone else's key, a held-key echo and a key release do nothing
	_drop_default_save()
	_clear_toasts()
	await _press(KEY_F6)
	_assert(spy.heard.has(KEY_F6), "QuickKeys: a key that isn't ours passes through untouched")
	await _press(KEY_F5, true)
	_assert(not _save_lite().has_save() and _toasts().is_empty(), "QuickKeys: a held-key echo doesn't save")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_F5
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not _save_lite().has_save(), "QuickKeys: releasing F5 doesn't save")
	# a buyer picks another key in the Inspector
	var keys: Node = game.get_node("SaveKeys")
	keys.set("save_key", KEY_F6)
	await _press(KEY_F5)
	_assert(not _save_lite().has_save(), "QuickKeys: after save_key = F6, F5 no longer saves")
	await _press(KEY_F6)
	_assert(_save_lite().has_save(), "QuickKeys: after save_key = F6, F6 saves")
	game.queue_free()
	await get_tree().process_frame
	_clear_toasts()


func _run_load_on_start() -> void:
	await get_tree().process_frame
	_cleanup()
	_drop_default_save()
	# a save from an earlier session
	var first := _play(_quick_scene(false))
	await get_tree().process_frame
	first.get_node("Hero").set("coins", 42)
	first.get_node("Hero").position = Vector2(50, 60)
	await _press(KEY_F5)
	first.queue_free()
	await get_tree().process_frame
	_clear_toasts()
	# a fresh instance with the box ticked picks it up
	var fresh := _play(_quick_scene(true))
	await get_tree().process_frame
	await get_tree().process_frame
	var hero: Node2D = fresh.get_node("Hero")
	_assert(int(hero.get("coins")) == 42 and hero.position == Vector2(50, 60), "LoadOnStart: a fresh scene starts from the save (coins %s, position %s)" % [str(hero.get("coins")), hero.position])
	fresh.queue_free()
	await get_tree().process_frame
	# SaveKeys above the saved node: its _ready runs before the Saveable joins the group
	var top := _play(_quick_scene(true, true))
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(int(top.get_node("Hero").get("coins")) == 42, "LoadOnStart: still works with SaveKeys at the top of the tree")
	top.queue_free()
	await get_tree().process_frame
	# and the box left unticked doesn't
	var plain := _play(_quick_scene(false))
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(int(plain.get_node("Hero").get("coins")) == 0, "LoadOnStart: unticked, the scene starts fresh")
	plain.queue_free()
	await get_tree().process_frame
	# ticked but nothing saved yet: starts fresh, no message
	_drop_default_save()
	_clear_toasts()
	var empty := _play(_quick_scene(true))
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(int(empty.get_node("Hero").get("coins")) == 0 and _toasts().is_empty(), "LoadOnStart: with no save yet it starts fresh and says nothing")
	empty.queue_free()
	await get_tree().process_frame
	_clear_toasts()


func _run_keys_messages() -> void:
	await get_tree().process_frame
	_cleanup()
	_drop_default_save()
	_clear_toasts()
	var game := _play(_quick_scene(false))
	await get_tree().process_frame
	game.get_node("Hero").set("coins", 5)
	await _press(KEY_F9)
	_assert(_toast_texts() == PackedStringArray(["No save to load yet"]), "Messages: F9 with no save says \"No save to load yet\" (got %s)" % str(_toast_texts()))
	_assert(int(game.get_node("Hero").get("coins")) == 5, "Messages: F9 with no save leaves the game alone")
	var first: Array = _toasts()
	var t: Label = first[0] if not first.is_empty() else null
	var layer: CanvasLayer = t.get_parent() as CanvasLayer if t != null else null
	_assert(layer != null and layer.layer == 100, "Messages: the message sits on CanvasLayer 100")
	_assert(t != null and is_equal_approx(t.anchor_left, 0.5) and is_equal_approx(t.anchor_right, 0.5) and t.offset_top >= 0.0, "Messages: anchored top centre")
	await _press(KEY_F5)
	var shown := _toasts()
	_assert(shown.size() == 2 and shown[1].text == "Game saved" and shown[1].offset_top > shown[0].offset_top, "Messages: a second message stacks below the first")
	await get_tree().create_timer(2.3).timeout
	_assert(_toasts().is_empty(), "Messages: they're gone after about 2 seconds")
	# a damaged save: a plain failure line, not a silent no-op
	var f := FileAccess.open(SAVE_LITE.DEFAULT_PATH, FileAccess.WRITE)
	f.store_string("not a save {{{")
	f.close()
	await _press(KEY_F9)
	var texts := _toast_texts()
	_assert(texts.size() == 1 and texts[0].begins_with("Load failed: ") and texts[0].contains("save.json"), "Messages: a damaged save says why the load failed (got %s)" % str(texts))
	_clear_toasts()
	# show_messages off: still saves, says nothing
	game.get_node("SaveKeys").set("show_messages", false)
	_drop_default_save()
	await _press(KEY_F5)
	_assert(_save_lite().has_save() and _toasts().is_empty(), "Messages: show_messages off still saves, quietly")
	game.queue_free()
	await get_tree().process_frame
	_drop_default_save()


# SaveLite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const SAVE_LITE := preload("res://addons/save_load_lite/save_lite.gd")


static func _save_lite() -> SAVE_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"SaveLite") as SAVE_LITE
