extends Node

# Headless data-path test for the Lite authoring dock: create → edit → save →
# reload round-trip, duplicate, delete. (GUI clicking can't be headless-tested;
# this covers the resource plumbing behind the buttons.)
# Run: godot --headless --path . res://tools/stats_skills_lite/verify_lite_dock.tscn

const DOCK := preload("res://addons/stats_skills_lite/editor/lite_dock.gd")
const TEST_DIR := "user://lite_dock_test/"
const NEW_DIR := "user://lite_dock_test_new/"

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- stats lite dock verify ---")
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
	dock._set_prop("id", "strength")
	dock._set_prop("base_value", 12.5)
	dock._on_save()
	await get_tree().process_frame
	var saved_path: String = dock._current_path
	var reloaded := load(saved_path)
	_assert(reloaded != null and str(reloaded.id) == "strength", "saved id persisted (got '%s')" % (reloaded.id if reloaded else "<null>"))
	_assert(absf(float(reloaded.base_value) - 12.5) < 0.001, "saved base_value persisted (got %s)" % (str(reloaded.base_value) if reloaded else "<null>"))

	# duplicate
	dock._on_duplicate()
	await get_tree().process_frame
	_assert(_count_tres() == 2, "Duplicate produced a second .tres")

	# delete
	dock._on_delete()
	await get_tree().process_frame
	_assert(_count_tres() == 1, "Delete removed one .tres")

	# New over the name of a file that's gone, while something still holds the old
	# copy (reloaded, above): it has to start fresh, not hand back the old one
	DirAccess.remove_absolute(saved_path)
	dock._on_new()
	_assert(dock._current_path == saved_path and str(dock._current.id) == "new_stat", "New over a deleted file's name starts fresh (id %s)" % str(dock._current.id))

	# NEW: numbered, with an id and a name to start from
	_wipe(NEW_DIR)
	dock._dir = NEW_DIR
	dock._on_new()
	var n1: String = dock._current_path
	var r1 := _disk(n1)
	_assert(n1.get_file() == "new_stat.tres" and str(r1.id) == "new_stat" and str(r1.display_name) == "New Stat", "New makes new_stat.tres with the id new_stat and the name New Stat")
	dock._on_new()
	var n2: String = dock._current_path
	_assert(n2.get_file() == "new_stat_2.tres" and str(_disk(n2).id) == "new_stat_2" and str(dock._current.id) == "new_stat_2", "a second New is new_stat_2, and it's the one being edited")

	# RENAME in the Inspector (the file's own copy), then Save here: it sticks
	var on_file: Resource = load(n2)
	on_file.display_name = "Stamina"
	dock.sync_from(on_file, "display_name")
	dock._on_save()
	_assert(str(_disk(n2).display_name) == "Stamina", "a rename made in the Inspector survives the tab's Save")
	var other: Resource = load(n1)
	other.display_name = "Nope"
	dock.sync_from(other, "display_name")
	_assert(str(dock._current.display_name) == "Stamina", "an edit to a different file leaves the working copy alone")
	_wipe(NEW_DIR)

	dock.queue_free()
	_reset_dir()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# what's really on disk, not the copy in memory
func _disk(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _wipe(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for f in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(f))
	DirAccess.remove_absolute(dir_path)


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
