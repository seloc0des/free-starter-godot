@tool
extends Control

# The "chooser" panel for Loot (Lite): pick how something drops loot, select it,
# pick a table, hit Apply. It adds a LootDropLite that rolls the table when the
# player touches the node (with a LootArea around it when it needs one) or when
# the node dies, and hands the loot to the player's bag. Re-pick and Apply again
# (it updates in place, never duplicates), tweak it in the Inspector, or open the
# "Loot Tables (Lite)" tab to author the table's entries.

const RESOURCE_SCRIPT := preload("res://addons/loot_lite/loot_table.gd")
const ITEM_SCRIPT := preload("res://addons/loot_lite/item_resource.gd")
const DROP_SCRIPT := preload("res://addons/loot_lite/loot_drop_lite.gd")
const TABLE_DIR := "res://loot"
const DROP_NAME := "LootDrop"
const AREA_NAME := "LootArea"
const NO_PLAYER := "Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Scope { SELECTED, SCENE_ROOT }

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _table_pick: OptionButton
var _status: Label
var _table_paths: PackedStringArray = PackedStringArray()


func _ready() -> void:
	name = "Loot · Setup"
	custom_minimum_size = Vector2(0, 440)
	# Taller than the dock, the tab scrolls. Nothing in it is wider than a default
	# dock at 100% or 125%, so it never has to scroll sideways.
	var page := ScrollContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.minimum_size_changed.connect(update_minimum_size)
	add_child(page)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	page.add_child(root)

	root.add_child(_h("1.  How does it drop loot?"))
	var col := VBoxContainer.new()
	root.add_child(col)
	for id in ["touch", "dies"]:
		var b := Button.new()
		b.text = _pretty(id)
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		col.add_child(b)
		_buttons[id] = b

	root.add_child(_h("2.  Where, and which table?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene's root", Scope.SCENE_ROOT)
	root.add_child(_scope)

	_table_pick = OptionButton.new()
	# its longest entry used to set the width of the whole tab; the open list still shows every name in full
	_table_pick.fit_to_longest_item = false
	_table_pick.clip_text = true
	root.add_child(_table_pick)
	# a table made in the Loot Tables (Lite) tab is in the list the next time it opens
	_table_pick.get_popup().about_to_popup.connect(_refresh_tables)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("New starter table…", _on_new_table))

	# touch drops only fire for the "player" group, and nothing else sets it
	# on a row of its own, so on a narrow dock it wraps its label instead of widening the tab
	var mk := _btn("Make the selected node the player", _on_make_player)
	mk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mk.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	root.add_child(mk)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Re-pick and Apply to update in place, tweak the LootDrop node in the Inspector, or open the \"Loot Tables (Lite)\" tab to author the table's entries."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	root.add_child(HSeparator.new())
	var pro := Label.new()
	pro.text = "🔒 Pro adds nested and conditional tables, guaranteed drops, magic find, pity counters, loot you see on the ground and pick up, and saving what already dropped."
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.modulate = Color(0.85, 0.8, 0.55)
	root.add_child(pro)

	_refresh_tables()


# As wide as what's in it and no wider. The old fixed width pushed a laptop's
# default dock (270 px) wider whenever this tab was open.
func _get_minimum_size() -> Vector2:
	if get_child_count() == 0 or not (get_child(0) is Control):
		return Vector2.ZERO
	return Vector2((get_child(0) as Control).get_combined_minimum_size().x, 0.0)


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_refresh_tables()
	_say("Picked \"%s\". Select the node, pick a table, then Apply." % _pretty(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick how it drops loot first.", WARN_COLOR)
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
		target = _host_of(sel[0], root)
	var table: Resource = _selected_table()
	# where the player has to walk, worked out before Apply adds a LootArea
	var zone := "\"%s\"" % target.name if _is_touch_ready(target) else "the LootArea around \"%s\"" % target.name
	var drop := wire_drop(root, target, _chosen, table)
	_select(drop)
	var from := " from %s" % table.resource_path.get_file().get_basename() if table != null else ""
	var tail := "" if table != null else " No table picked yet: press \"New starter table…\" or make one in the Loot Tables (Lite) tab, pick it above and Apply again."
	var color := OK_COLOR if table != null else WARN_COLOR
	if _chosen == "dies":
		if not has_died_signal(target):
			tail += " \"%s\" has no \"died\" signal yet, so it won't drop. It needs a Health, such as the Combat pack's." % target.name
			color = WARN_COLOR
		_say("\"%s\" drops loot%s when it dies. %s%s" % [target.name, from, bag_line(root), tail], color)
		return
	var note := no_player_note(root)
	if note != "":
		color = WARN_COLOR
	_say("\"%s\" drops loot%s when the player walks into %s. %s%s%s" % [target.name, from, zone, bag_line(root), tail, note], color)


func _on_make_player() -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_say("Select your player node first.", WARN_COLOR)
		return
	var n: Node = sel[0]
	n.add_to_group("player", true)  # persistent, so the group saves with the scene
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % n.name, OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses the LootDrop (and LootArea) already on `target` rather than
# adding a second one. Returns the LootDrop.

func wire_drop(root: Node, target: Node, outcome: String, table: Resource) -> Node:
	if outcome == "touch":
		_touch_area(root, target)
	var drop := _find_drop(target, root)
	var fresh := drop == null
	if fresh:
		drop = _inert(DROP_SCRIPT)
		drop.name = DROP_NAME
	drop.set("trigger", 1 if outcome == "dies" else 0)
	if table != null:
		drop.set("table", table)
	if fresh:
		target.add_child(drop, true)
		# owner must be the scene ROOT so it bakes into the .tscn — even when the
		# target is a nested owned node, its owner is still the scene root.
		drop.owner = root
	return drop


# Touch listens to an Area's body_entered, so on a sprite or a body it never
# fired. Your own Area with a shape works as is; anything else gets a LootArea.
func _touch_area(root: Node, target: Node) -> Node:
	if _is_touch_ready(target):
		return target
	for c in target.get_children():
		if c.name == AREA_NAME and (c is Area2D or c is Area3D) and c.owner == root:
			return c  # from an earlier Apply
	var area: Node
	var shape: Node
	if target is Node3D or (not (target is Node2D) and root is Node3D):
		area = Area3D.new()
		var s3 := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.0  # about a chest's reach
		s3.shape = sphere
		shape = s3
	else:
		area = Area2D.new()
		var s2 := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 32.0
		s2.shape = circle
		shape = s2
	area.name = AREA_NAME
	target.add_child(area, true)
	area.owner = root
	shape.name = "CollisionShape"
	area.add_child(shape, true)
	shape.owner = root
	return area


# An Area that already has a shape to touch. An Area with no shape never
# reports a body entering, so it gets a LootArea like anything else.
func _is_touch_ready(node: Node) -> bool:
	if not (node is Area2D or node is Area3D):
		return false
	for c in node.get_children():
		if (c is CollisionShape2D or c is CollisionShape3D) and c.get("shape") != null:
			return true
		if (c is CollisionPolygon2D or c is CollisionPolygon3D) and c.get("polygon").size() > 0:
			return true
	return false


# Re-entrancy search scoped to nodes the scene owns. A LootDrop inside an
# instanced child scene (owner != root) is skipped — updating it wouldn't
# serialize into the buyer's scene, so we'd silently no-op.
func _find_drop(target: Node, root: Node) -> Node:
	for c in target.get_children():
		if (c == root or c.owner == root) and c.get_script() == DROP_SCRIPT:
			return c
	return null


# A runtime script's .new() is a live instance, so its game code would run in the
# editor until the scene is reopened. Attach the script to a plain native node instead:
# that's the inert placeholder a hand-added node gets.
func _inert(script: Script) -> Node:
	var n: Node = ClassDB.instantiate(script.get_instance_base_type())
	n.set_script(script)
	return n


# Same search the LootDrop does at runtime: the node itself, then anything under it.
func has_died_signal(target: Node) -> bool:
	if target.has_signal("died"):
		return true
	for n in target.find_children("*", "", true, false):
		if n.get_script() != DROP_SCRIPT and n.has_signal("died"):
			return true
	return false


# The loot only lands in a bag the player carries. Without one it's a message and
# nothing kept, so don't promise the bag: say which it'll be. Same bag test as the
# LootDrop's at runtime.
func bag_line(root: Node) -> String:
	var player: Node = null
	if root.is_inside_tree():
		for n in root.get_tree().get_nodes_in_group("player"):
			if n == root or root.is_ancestor_of(n):
				player = n
				break
	if player == null:
		return "It goes into the player's bag if they have one, and a message shows what dropped."
	for n in [player] + player.find_children("*", "", true, false):
		if n.has_method("add_item") and n.has_method("remove_item") and n.has_method("count_item"):
			return "It goes into the player's bag, and a message shows what dropped."
	return "A message shows what dropped. Give your player a bag (Inventory Lite, free) to keep it."


# Only nodes in this scene count: the editor's tree holds more than the scene.
func no_player_note(root: Node) -> String:
	if not root.is_inside_tree():
		return ""
	for n in root.get_tree().get_nodes_in_group("player"):
		if n == root or root.is_ancestor_of(n):
			return ""
	return " " + NO_PLAYER


# Apply selects the LootDrop it made, so a second Apply straight after would land
# inside it. Step up to the node it sits on, the one you meant.
func _host_of(n: Node, root: Node) -> Node:
	while n != root and (n.get_script() == DROP_SCRIPT or String(n.name) == AREA_NAME \
			or String(n.get_parent().name) == AREA_NAME):
		n = n.get_parent()
	return n


# ---- new starter table ----------------------------------------------------

func _on_new_table() -> void:
	if not DirAccess.dir_exists_absolute(TABLE_DIR):
		DirAccess.make_dir_recursive_absolute(TABLE_DIR)
	var table := make_starter_table(_chosen)
	var path := _unique(TABLE_DIR.path_join(str(table.id)))
	var err := ResourceSaver.save(table, path)
	if err != OK:
		_say("Could not create the table (err %d)." % err, ERR_COLOR)
		return
	table.take_over_path(path)
	_register_uid(path)
	_scan_fs()
	_refresh_tables()
	_select_table_path(path)
	_say("Made a starter table: %s. It's picked above; Apply to use it, or open the Loot Tables tab to add entries." % path.get_file(), OK_COLOR)


# Pure so the test can drive it. A minimal 2-entry table the buyer can roll right
# away, then re-weight in the authoring dock.
func make_starter_table(kind: String) -> Resource:
	var t: Resource = RESOURCE_SCRIPT.new()
	t.id = {"touch": "chest_loot", "dies": "enemy_loot"}.get(kind, "starter_loot")
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
	# a chest opens once for a fatter reward; an enemy drops a little
	t.rolls = 3 if kind == "touch" else 1
	return t


# ---- table list ----------------------------------------------------------

# Your tables first, then the example ones that ship with the demo.
func _refresh_tables() -> void:
	var keep := ""
	var cur := _table_pick.get_selected_id()
	if cur > 0 and cur - 1 < _table_paths.size():
		keep = _table_paths[cur - 1]
	_table_paths = table_paths([TABLE_DIR], _demo_dirs())
	_table_pick.clear()
	_table_pick.add_item("(no table yet)", 0)
	for i in _table_paths.size():
		var p := _table_paths[i]
		var label := p.get_file().get_basename()
		if not p.begins_with(TABLE_DIR + "/"):
			label += " (example)"
		_table_pick.add_item(label, i + 1)
	if keep != "":
		_select_table_path(keep)


# Pure (dirs in, paths out) so the test can point it at user:// folders.
func table_paths(own_dirs: Array, demo_dirs: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for d in own_dirs:
		out.append_array(_scan_tables(str(d)))
	for d in demo_dirs:
		out.append_array(_scan_tables(str(d)))
	return out


func _demo_dirs() -> Array:
	if DirAccess.dir_exists_absolute("res://demo/loot_lite"):
		return ["res://demo/loot_lite"]
	return ["res://demo"]  # repo layout


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
	# Apply adds nodes without the undo manager, so the editor never flags the scene
	# and Play would run the saved file without them. Flag it by hand.
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


# base.tres, then base_2.tres, base_3.tres, the same count the tables tab uses.
func _unique(base: String) -> String:
	var p := base + ".tres"
	var n := 1
	while FileAccess.file_exists(p):
		n += 1
		p = "%s_%d.tres" % [base, n]
	return p


func _scan_fs() -> void:
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()


func _pretty(id: String) -> String:
	match id:
		"touch": return "Drops when the player touches this"
		"dies": return "Drops when this dies"
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


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
