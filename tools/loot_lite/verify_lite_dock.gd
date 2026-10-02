extends Node

# Headless test for the Loot Tables (Lite) tab: New (numbered, with an id), the
# entry rows (item picker, weight, min, max), New item, Save, a rename made in
# the Inspector surviving Save, and a row made here dropping in a played scene.
# GUI clicks can't be headless; this drives the handlers the buttons call.
# Run: godot --headless --path . res://tools/loot_lite/verify_lite_dock.tscn

const DOCK := preload("res://addons/loot_lite/editor/lite_dock.gd")
const CHOOSER := preload("res://addons/loot_lite/editor/loot_chooser_dock.gd")
const TABLE_SCRIPT := preload("res://addons/loot_lite/loot_table.gd")
const ITEM_SCRIPT := preload("res://addons/loot_lite/item_resource.gd")
const BAG_SCRIPT := preload("res://tools/loot_lite/test_bag.gd")
const TABLE_DIR := "user://loot_lite_tab_test/"
const ITEM_DIR := "user://loot_lite_tab_items/"

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- loot lite tables tab verify ---")
	_wipe(TABLE_DIR)
	_wipe(ITEM_DIR)
	var dock: Control = DOCK.new()
	add_child(dock)
	await get_tree().process_frame
	dock._dir = TABLE_DIR
	dock._item_dir = ITEM_DIR

	# NEW: numbered like the Setup tab, with an id to start from
	dock._on_new()
	var p1: String = dock._current_path
	_assert(p1.get_file() == "new_table.tres", "New made new_table.tres (%s)" % p1.get_file())
	_assert(str(_disk(p1).id) == "new_table", "with the id new_table")
	dock._on_new()
	var p2: String = dock._current_path
	_assert(p2.get_file() == "new_table_2.tres" and str(_disk(p2).id) == "new_table_2", "a second New is new_table_2 (%s)" % p2.get_file())
	_assert(dock._current != null and str(dock._current.id) == "new_table_2", "and it's the table being edited")

	# ITEMS for the pickers: yours first, then the demo's as examples
	var i1: String = dock.make_item(ITEM_DIR)
	var i2: String = dock.make_item(ITEM_DIR)
	_assert(i1.get_file() == "new_item.tres" and i2.get_file() == "new_item_2.tres", "New item makes new_item.tres, then new_item_2.tres")
	var it1: Resource = load(i1)
	_assert(str(it1.get("id")) == "new_item" and str(it1.get("name")) == "New Item", "a new item has an id and a name to start from")
	# Next to an Inventory pack (a bundle, a starter kit) New item takes its script,
	# so the items stack in that bag. On its own it's Loot's.
	var want := ITEM_SCRIPT.resource_path
	for inv in ["res://addons/inventory_lite/item_resource.gd", "res://addons/inventory/resources/item_resource.gd"]:
		if FileAccess.file_exists(inv):
			want = inv
			break
	_assert(it1.get_script().resource_path == want, "New item uses %s" % (
		"the Inventory pack's item script (it's installed)" if want != ITEM_SCRIPT.resource_path else "Loot's own item script (no Inventory pack here)"))
	# The starter kits carry this test without the lite demo, so there are no
	# example items there. Only check them when the demo's items are in the project.
	var has_demo := false
	for d in DOCK.DEMO_ITEM_DIRS:
		has_demo = has_demo or DirAccess.dir_exists_absolute(d)
	var pool: PackedStringArray = dock.item_paths()
	var first_example := -1
	for k in pool.size():
		if not pool[k].begins_with(ITEM_DIR):
			first_example = k
			break
	_assert(pool.size() >= 2 and pool[0] == i1 and pool[1] == i2, "the item list has yours first (%s)" % str(pool))
	if has_demo:
		_assert(pool.size() >= 3 and first_example == 2, "then the demo's as examples (%s)" % str(pool))
	else:
		_skip("no Loot demo in this project, so there are no example items to check")

	# a scene holding the table (a LootDrop, or the Inspector) shares its entries
	# with the tab's working copy, so edits must not reach it before Save
	var held: Resource = load(p2)
	_open(dock, p2)
	await _settle()

	# ROWS: a picker and number boxes, no keys to type
	dock._on_add_row()
	await _settle()
	var rows: Array = dock._current.entries
	_assert(rows.size() == 1 and rows[0].get("item") == null and int(rows[0].get("weight")) == 10 and int(rows[0].get("min")) == 1 and int(rows[0].get("max")) == 1, "Add row adds an empty row: weight 10, count 1 to 1")
	var row0 := _row(dock, 0)
	_assert(row0 != null, "the tab shows the row")
	var pick := _pick(dock, 0)
	_assert(pick != null and pick.get_item_text(pick.selected) == "(pick an item)", "its item picker says to pick one")
	_assert(pick != null and pick.item_count > 1 and pick.get_item_text(1) == "New Item", "the picker lists your items")
	if has_demo:
		_assert(pick != null and pick.get_item_text(pick.item_count - 1).ends_with("(example)"), "then the examples, marked so")
	else:
		_skip("no Loot demo in this project, so the picker has no examples to mark")
	var free_text := 0
	if row0 != null:
		for le in row0.find_children("*", "LineEdit", true, false):
			if not _inside_picker_or_number(le, row0):
				free_text += 1
	_assert(row0 != null and free_text == 0 and row0.find_children("*", "SpinBox", true, false).size() == 3, "nothing to type but numbers: a picker and three number boxes")
	if pick != null and pick.item_count > 1:
		pick.select(1)
		pick.item_selected.emit(1)
	_assert(_entry(dock, 0).get("item") == it1, "picking an item puts it in the row")
	_set_spin(dock, 0, "Weight", 70)
	_set_spin(dock, 0, "Min", 2)
	_set_spin(dock, 0, "Max", 4)
	var e0 := _entry(dock, 0)
	_assert(int(e0.get("weight", -1)) == 70 and int(e0.get("min", -1)) == 2 and int(e0.get("max", -1)) == 4, "weight, min and max go into the row (%s)" % str(e0))
	_assert((held.entries as Array).is_empty(), "a scene holding the table keeps its old rows until Save")
	dock._on_save()
	_assert((held.entries as Array).size() == 1 and int(held.entries[0].get("weight", -1)) == 70, "and gets the new row when you Save")
	var saved: Resource = _disk(p2)
	var se: Dictionary = saved.entries[0] if not (saved.entries as Array).is_empty() else {}
	_assert(se.get("item") is Resource and (se.get("item") as Resource).resource_path == i1, "Save writes the row's item as a link to its file")
	_assert(int(se.get("weight", 0)) == 70 and int(se.get("min", 0)) == 2 and int(se.get("max", 0)) == 4, "and its numbers")
	_assert(FileAccess.get_file_as_string(p2).contains("path=\"%s\"" % i1), "the item isn't copied into the table")

	# NEW ITEM button: a new item, a row for it
	dock._on_new_item()
	await _settle()
	var i3 := ITEM_DIR.path_join("new_item_3.tres")
	_assert(FileAccess.file_exists(i3), "the New item button makes new_item_3.tres in the items folder")
	var rows2: Array = dock._current.entries
	_assert(rows2.size() == 2 and rows2[1].get("item") is Resource and (rows2[1].get("item") as Resource).resource_path == i3, "and gives it a row")

	# REMOVE
	dock._on_remove_row(0)
	await _settle()
	var left: Variant = _entry(dock, 0).get("item")
	_assert(dock._current.entries.size() == 1 and left is Resource and (left as Resource).resource_path == i3, "Remove takes out that row only")
	dock._on_save()
	_assert(_disk(p2).entries.size() == 1, "and Save keeps it out")

	# KEEPS what the tab doesn't edit: other keys on an entry, other table fields
	var keep: Resource = TABLE_SCRIPT.new()
	keep.id = "keep_me"
	keep.rolls = 4
	keep.entries = [{"item": it1, "weight": 5, "min": 1, "max": 1, "note": "hand-set"}]
	ResourceSaver.save(keep, TABLE_DIR.path_join("keep.tres"))
	dock._refresh_list()
	_open(dock, TABLE_DIR.path_join("keep.tres"))
	await _settle()
	_set_spin(dock, 0, "Weight", 9)
	dock._on_save()
	var kd: Resource = _disk(TABLE_DIR.path_join("keep.tres"))
	var ke: Dictionary = kd.entries[0] if not (kd.entries as Array).is_empty() else {}
	_assert(int(ke.get("weight", -1)) == 9 and str(ke.get("note", "")) == "hand-set", "editing a row keeps the entry's other keys (%s)" % str(ke))
	_assert(str(kd.id) == "keep_me" and int(kd.rolls) == 4, "and the table's other fields")

	# A starter table carries its own items: the row shows them as inside the table
	var maker = CHOOSER.new()
	var starter: Resource = maker.make_starter_table("touch")
	maker.free()
	ResourceSaver.save(starter, TABLE_DIR.path_join("starter.tres"))
	dock._refresh_list()
	_open(dock, TABLE_DIR.path_join("starter.tres"))
	await _settle()
	var sp := _pick(dock, 0)
	var sp_text := sp.get_item_text(sp.selected) if sp != null else ""
	_assert(sp_text == "Coin  (in this table)", "an item kept inside the table shows as such (%s)" % sp_text)

	# RENAME in the Inspector (the file's own copy), then Save here: it sticks
	_open(dock, p2)
	await _settle()
	var on_file: Resource = load(p2)
	on_file.id = "silver_drop"
	dock.sync_from(on_file, "id")
	dock._on_save()
	_assert(str(_disk(p2).id) == "silver_drop", "a rename made in the Inspector survives the tab's Save")
	var other: Resource = load(p1)
	other.id = "not_this_one"
	dock.sync_from(other, "id")
	_assert(str(dock._current.id) == "silver_drop", "an edit to a different file leaves the working copy alone")
	var item3: Resource = load(i3)
	item3.name = "Silver Coin"
	dock.sync_from(item3, "name")
	await _settle()
	var rp := _pick(dock, 0)
	var rp_text := rp.get_item_text(rp.selected) if rp != null else ""
	_assert(rp_text == "Silver Coin", "renaming an item in the Inspector updates its row (%s)" % rp_text)
	ResourceSaver.save(item3, i3)

	# PLAYED: the row made in this tab drops in a scene the Setup tab wired
	_set_spin(dock, 0, "Weight", 100)
	_set_spin(dock, 0, "Min", 3)
	_set_spin(dock, 0, "Max", 3)
	dock._on_save()
	await _played(load(p2), item3)

	dock.queue_free()
	_wipe(TABLE_DIR)
	_wipe(ITEM_DIR)
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _played(table: Resource, item: Resource) -> void:
	var setup = CHOOSER.new()
	var lvl := Node2D.new()
	var chest := Sprite2D.new()
	chest.name = "Chest"
	chest.position = Vector2(300, 200)
	lvl.add_child(chest)
	chest.owner = lvl
	setup.wire_drop(lvl, chest, "touch", table)
	var pk := PackedScene.new()
	pk.pack(lvl)
	lvl.free()
	setup.free()
	var run := pk.instantiate()
	get_tree().root.add_child(run)
	var hero := CharacterBody2D.new()
	hero.add_to_group("player")
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(16, 16)
	cs.shape = box
	hero.add_child(cs)
	var bag: Node = BAG_SCRIPT.new()
	hero.add_child(bag)
	hero.position = Vector2(40, 40)
	run.add_child(hero)
	for i in 3:
		await get_tree().physics_frame
	hero.position = Vector2(300, 200)
	for i in 4:
		await get_tree().physics_frame
	_assert(bag.count_item(item) == 3, "played: the row made in the tab drops 3 Silver Coins into the bag (got %d)" % bag.count_item(item))
	var shown := false
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if (t as Label).text.contains("Found: Silver Coin x3"):
			shown = true
	_assert(shown, "played: and the message names it")
	run.queue_free()


# a number box's own text field, or the item picker's popup search, isn't a field to type into
func _inside_picker_or_number(n: Node, stop: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != stop:
		if p is SpinBox or p is OptionButton:
			return true
		p = p.get_parent()
	return false


func _settle() -> void:
	await get_tree().process_frame


func _open(dock: Control, path: String) -> void:
	for k in dock._paths.size():
		if dock._paths[k] == path:
			dock._on_selected(k)
			return


func _row(dock: Control, i: int) -> Node:
	return dock._fields.find_child("Row%d" % i, true, false)


# null-safe, so a broken row fails its own check instead of stopping the run
func _pick(dock: Control, i: int) -> OptionButton:
	var row := _row(dock, i)
	return row.find_child("Item", true, false) as OptionButton if row != null else null


func _set_spin(dock: Control, i: int, spin_name: String, v: float) -> void:
	var row := _row(dock, i)
	var s: SpinBox = row.find_child(spin_name, true, false) as SpinBox if row != null else null
	if s != null:
		s.value = v


func _entry(dock: Control, i: int) -> Dictionary:
	var rows: Array = dock._current.entries
	if i < rows.size() and rows[i] is Dictionary:
		return rows[i]
	return {}


# what's really on disk, not the copy in memory
func _disk(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _wipe(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for f in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(f))
	DirAccess.remove_absolute(dir_path)


func _skip(msg: String) -> void:
	print("[--] " + msg)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)
