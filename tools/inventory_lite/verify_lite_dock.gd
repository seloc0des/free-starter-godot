extends Node

# Headless data-path test for the Lite authoring dock: create → edit → save →
# reload round-trip, duplicate, delete. (GUI clicking can't be headless-tested;
# this covers the resource plumbing behind the buttons.)
# Run: godot --headless --path . res://tools/inventory_lite/verify_lite_dock.tscn

const DOCK := preload("res://addons/inventory_lite/editor/lite_dock.gd")
const TEST_DIR := "user://lite_dock_test/"

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- inventory lite dock verify ---")
	_reset_dir()

	var dock: Control = DOCK.new()
	add_child(dock)
	await get_tree().process_frame
	dock._dir = TEST_DIR

	# create
	dock._on_new()
	_assert(dock._current != null, "New created a working resource")
	var made := _count_tres()
	_assert(made == 1, "New wrote one .tres (got %d)" % made)

	# edit + save
	dock._set_prop("id", "sword")
	dock._set_prop("max_stack", 5)
	dock._on_save()
	await get_tree().process_frame
	var saved_path: String = dock._current_path
	var reloaded := load(saved_path)
	_assert(reloaded != null and str(reloaded.id) == "sword", "saved id persisted (got '%s')" % (reloaded.id if reloaded else "<null>"))
	_assert(int(reloaded.max_stack) == 5, "saved max_stack persisted (got %d)" % (reloaded.max_stack if reloaded else -1))

	# the list shows the name typed into the form, not the file, and keeps up with a rename
	dock._set_prop("name", "Iron Sword")
	dock._on_save()
	await get_tree().process_frame
	var idx: int = Array(dock._paths).find(dock._current_path)
	var label: String = dock._list.get_item_text(idx) if idx >= 0 else "<missing>"
	_assert(label == "Iron Sword", "the list shows the item's name, not its file name (got '%s')" % label)
	dock._set_prop("name", "")
	dock._on_save()
	await get_tree().process_frame
	label = dock._list.get_item_text(idx) if idx >= 0 else "<missing>"
	_assert(label == dock._current_path.get_file().get_basename(), "a blank name falls back to the file name (got '%s')" % label)

	# duplicate
	dock._on_duplicate()
	await get_tree().process_frame
	_assert(_count_tres() == 2, "Duplicate produced a second .tres")

	# delete
	dock._on_delete()
	await get_tree().process_frame
	_assert(_count_tres() == 1, "Delete removed one .tres")

	await _new_names_and_numbers(dock)

	dock.queue_free()
	_reset_dir()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _count_tres() -> int:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return 0
	var n := 0
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.get_extension() == "tres":
			n += 1
		f = dir.get_next()
	dir.list_dir_end()
	return n


func _reset_dir() -> void:
	if DirAccess.dir_exists_absolute(TEST_DIR):
		var dir := DirAccess.open(TEST_DIR)
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f != "." and f != "..":
				dir.remove(f)
			f = dir.get_next()
		dir.list_dir_end()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# New starts from a name and an id, and counts new_item, new_item_2, ... the
# same way the Setup tab's New item does, so the two carry on from each other.
func _new_names_and_numbers(dock: Control) -> void:
	var dir := "user://lite_dock_new_test/"
	_wipe(dir)
	dock._dir = dir
	dock._on_new()
	var first: String = dock._current_path
	var it1: Resource = _fresh(first)
	_assert(first.get_file() == "new_item.tres" and it1 != null and str(it1.id) == "new_item" and str(it1.name) == "New Item",
		"New gives its item an id and a name (%s: %s / %s)" % [first.get_file(), it1.id if it1 else "?", it1.name if it1 else "?"])
	_assert(dock._current != null and str(dock._current.name) == "New Item", "the form shows that name straight away")
	_assert(String(dock._status.text).begins_with("Made " + first), "the status says where it went (%s)" % dock._status.text)
	var setup: Object = load("res://addons/inventory_lite/editor/inventory_chooser_dock.gd").new()
	var second: String = setup.make_item(dir)
	_assert(second.get_file() == "new_item_2.tres", "the Setup tab's New item takes the next number (%s)" % second.get_file())
	dock._on_new()
	var third: String = dock._current_path
	var it3: Resource = _fresh(third)
	_assert(third.get_file() == "new_item_3.tres" and it3 != null and str(it3.id) == "new_item_3" and str(it3.name) == "New Item 3",
		"and this tab carries on after it (%s: %s)" % [third.get_file(), it3.name if it3 else "?"])
	setup.free()
	_wipe(dir)
	dock._dir = TEST_DIR


# Straight from disk, past anything an earlier step left in the cache.
func _fresh(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
