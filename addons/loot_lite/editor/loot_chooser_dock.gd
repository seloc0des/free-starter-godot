@tool
extends Control

# The "chooser" panel for Loot — Lite: pick what drops loot in YOUR game, pick
# WHERE, hit Apply — it bakes a loot source onto the node you chose. Re-pick and
# Apply again (it updates in place, never duplicates), tweak it in the Inspector,
# or open the "Loot Tables — Lite" tab to author the table's entries.
#
# Lite has no runtime component — just the LootTableLite Resource. So a source is
# a plain Node carrying the chosen table in its metadata (serializes into your
# .tscn, editable in the Inspector's Metadata section). It's the handle you call
# roll() on from gameplay code. Pro turns this into a LootDropSource + EventTrigger
# that drop on death / on touch with zero code — see the note at the bottom.

const RESOURCE_SCRIPT := preload("res://addons/loot_lite/loot_table.gd")
const ITEM_SCRIPT := preload("res://addons/loot_lite/item_resource.gd")
const TABLE_DIR := "res://loot"
const SOURCE_NAME := "LootSource"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

# Lite outcomes: both bake a LootSource marker, they just differ in the starter
# table + rolls the buyer starts from. No triggers here — that's Pro.
enum Scope { SELECTED, SCENE_ROOT }

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _table_pick: OptionButton
var _rolls: SpinBox
var _status: Label
var _table_paths: PackedStringArray = PackedStringArray()


func _ready() -> void:
	name = "Loot · Setup"
	custom_minimum_size = Vector2(320, 440)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  What drops loot?"))
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	for id in ["monster", "chest"]:
		var b := Button.new()
		b.text = _pretty(id)
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		grid.add_child(b)
		_buttons[id] = b

	root.add_child(_h("2.  Where, and which table?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene's root", Scope.SCENE_ROOT)
	root.add_child(_scope)

	_table_pick = OptionButton.new()
	root.add_child(_table_pick)

	var roll_row := HBoxContainer.new()
	root.add_child(roll_row)
	roll_row.add_child(_h("Rolls per drop"))
	_rolls = SpinBox.new()
	_rolls.min_value = 1
	_rolls.max_value = 99
	_rolls.value = 1
	roll_row.add_child(_rolls)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("New starter table…", _on_new_table))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Re-pick and Apply to update in place, tweak the node in the Inspector, or open the \"Loot Tables (Lite)\" tab to author the table's entries."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	root.add_child(HSeparator.new())
	var pro := Label.new()
	pro.text = "🔒 Lite bakes the table onto the node. You call roll() from code. Pro unlocks no-code wiring: a LootDropSource + EventTrigger that drop on death / on touch and route into an inventory. No scripting."
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.modulate = Color(0.85, 0.8, 0.55)
	root.add_child(pro)

	_refresh_tables()


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	# a chest usually opens once for a fatter reward; a monster drops a little.
	_rolls.value = 3 if id == "chest" else 1
	_say("Picked \"%s\". Choose where + a table, then Apply." % _pretty(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick what drops loot first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var target: Node = root
	if _scope.get_selected_id() == Scope.SELECTED:
		var sel := EditorInterface.get_selection().get_selected_nodes()
		if sel.is_empty():
			_say("Select a node in the scene (or switch scope to \"This scene's root\").", WARN_COLOR)
			return
		target = sel[0]
	var table: Resource = _selected_table()
	var src := wire_source(root, target, table, int(_rolls.value))
	_select(src)
	var table_msg := " with %s" % table.resource_path.get_file() if table != null else " (no table yet: author one in the Loot Tables tab)"
	_say("%s on \"%s\"%s. Call src.roll_loot() from code, or tweak it in the Inspector." % [_pretty(_chosen), target.name, table_msg], OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses the existing LootSource under `target` rather than adding a
# second one. The chosen table + rolls live in metadata so they serialize into
# the buyer's .tscn and stay editable in the Inspector's Metadata section.

func wire_source(root: Node, target: Node, table: Resource, rolls: int) -> Node:
	var src := _ensure(target, root, SOURCE_NAME)
	src.set_meta("loot_kind", _chosen if _chosen != "" else str(src.get_meta("loot_kind", "monster")))
	if table != null:
		src.set_meta("loot_table", table)
	src.set_meta("rolls", max(1, rolls))
	return src


func _ensure(target: Node, root: Node, node_name: String) -> Node:
	var found := _find(target, root, node_name)
	if found != null:
		return found  # re-entrant: reuse it, never duplicate
	var n := Node.new()
	n.name = node_name
	target.add_child(n)
	# owner must be the scene ROOT so it bakes into the .tscn — even when the
	# target is a nested owned node, its owner is still the scene root.
	n.owner = root
	return n


# Re-entrancy search scoped to nodes the scene owns. A LootSource inside an
# instanced child scene (owner != root) is skipped — updating it wouldn't
# serialize into the buyer's scene, so we'd silently no-op. Same trap the save
# dock's CanvasLayer search had.
func _find(target: Node, root: Node, node_name: String) -> Node:
	for c in target.get_children():
		if (c == root or c.owner == root) and c.name == node_name and _is_loot_source(c):
			return c
	return null


# A LootSource is our bare marker Node (no script, no native subclass) carrying
# the loot metadata — match on that, not on class, so we don't grab an unrelated
# node the buyer happened to name "LootSource".
func _is_loot_source(node: Node) -> bool:
	return node.get_class() == "Node" and node.has_meta("loot_kind")


# ---- new starter table ----------------------------------------------------

func _on_new_table() -> void:
	if not DirAccess.dir_exists_absolute(TABLE_DIR):
		DirAccess.make_dir_recursive_absolute(TABLE_DIR)
	var table := make_starter_table(_chosen)
	var path := _unique(TABLE_DIR.path_join("%s_loot" % (_chosen if _chosen != "" else "starter")))
	var err := ResourceSaver.save(table, path)
	if err != OK:
		_say("Could not create the table (err %d)." % err, ERR_COLOR)
		return
	table.take_over_path(path)
	_scan_fs()
	_refresh_tables()
	_select_table_path(path)
	_say("Made a starter table: %s. Pick it above, then Apply, or open the Loot Tables tab to add entries." % path.get_file(), OK_COLOR)


# Pure so the test can drive it. A minimal 2-entry table the buyer can roll right
# away, then re-weight in the authoring dock.
func make_starter_table(kind: String) -> Resource:
	var t: Resource = RESOURCE_SCRIPT.new()
	t.id = "%s_loot" % (kind if kind != "" else "starter")
	var common: Resource = ITEM_SCRIPT.new()
	common.id = "coin"
	common.name = "Coin"
	var rare: Resource = ITEM_SCRIPT.new()
	rare.id = "gem"
	rare.name = "Gem"
	t.entries = [
		RESOURCE_SCRIPT.entry(common, 80, 1, 5),
		RESOURCE_SCRIPT.entry(rare, 20, 1, 1),
	]
	t.rolls = 3 if kind == "chest" else 1
	return t


# ---- table list ----------------------------------------------------------

func _refresh_tables() -> void:
	_table_paths = _scan_tables(TABLE_DIR)
	_table_pick.clear()
	_table_pick.add_item("(no table yet)", 0)
	for i in _table_paths.size():
		_table_pick.add_item(_table_paths[i].get_file().get_basename(), i + 1)


func _scan_tables(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var res := load(dir_path.path_join(f))
			if res != null and res.get_script() == RESOURCE_SCRIPT:
				out.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	return out


func _selected_table() -> Resource:
	var id := _table_pick.get_selected_id()
	if id <= 0 or id - 1 >= _table_paths.size():
		return null
	return load(_table_paths[id - 1])


func _select_table_path(path: String) -> void:
	for i in _table_paths.size():
		if _table_paths[i] == path:
			_table_pick.select(i + 1)
			return


# ---- helpers -------------------------------------------------------------

func _select(n: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _unique(base: String) -> String:
	var p := base + ".tres"
	var n := 1
	while FileAccess.file_exists(p):
		p = "%s_%d.tres" % [base, n]
		n += 1
	return p


func _scan_fs() -> void:
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()


func _pretty(id: String) -> String:
	match id:
		"monster": return "A monster that drops loot"
		"chest": return "A treasure chest"
	return id.replace("_", " ").capitalize()


func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


func _btn(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _say(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text
