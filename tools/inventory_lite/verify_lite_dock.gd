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

	# duplicate
	dock._on_duplicate()
	await get_tree().process_frame
	_assert(_count_tres() == 2, "Duplicate produced a second .tres")

	# delete
	dock._on_delete()
	await get_tree().process_frame
	_assert(_count_tres() == 1, "Delete removed one .tres")

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
