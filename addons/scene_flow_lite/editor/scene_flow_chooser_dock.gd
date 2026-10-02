@tool
extends Control

# No-code chooser dock (Lite). Select a node, one click drops a touch-travel
# Door (with shape and target) or a Spawn Point. Pro adds checkpoints, flags,
# press-E doors, and key-gating.

const DOOR: Script = preload("res://addons/scene_flow_lite/door_lite.gd")
const SPAWN: Script = preload("res://addons/scene_flow_lite/spawn_point_lite.gd")
const NO_PLAYER := "Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."

var _scene_path: LineEdit
var _spawn_id: LineEdit
var _spawn_pick: OptionButton
var _scene_dialog: EditorFileDialog
var _status: Label
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Scene Flow Lite"
	_build()


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0) if _scroll != null else Vector2.ZERO


func _build() -> void:
	# The whole tab scrolls, so a short screen or a big editor scale can't push the
	# status line off the bottom. Sideways it wraps instead.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.minimum_size_changed.connect(update_minimum_size)
	add_child(_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)

	v.add_child(_header("Scene Flow Lite: bake onto the selected node"))
	_scene_path = LineEdit.new()
	_scene_path.placeholder_text = "res://levels/room_b.tscn"
	_scene_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_path.text_submitted.connect(func(_t: String) -> void: _refresh_spawns())
	var pick_btn := Button.new()
	pick_btn.text = "Pick…"
	pick_btn.tooltip_text = "Choose the scene this door leads to."
	pick_btn.pressed.connect(_pick_scene)
	var row := HBoxContainer.new()
	row.add_child(_scene_path)
	row.add_child(pick_btn)
	v.add_child(_labeled("Door target scene", row))
	_spawn_pick = OptionButton.new()
	_spawn_pick.tooltip_text = "Spawn points in the target scene. Picking one fills Spawn id."
	# a long entry ends in "…" in a narrow dock; the open list shows it whole
	_spawn_pick.fit_to_longest_item = false
	_spawn_pick.clip_text = true
	_spawn_pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_spawn_pick.item_selected.connect(_on_spawn_picked)
	v.add_child(_labeled("Door lands on", _spawn_pick))
	_spawn_id = LineEdit.new()
	_spawn_id.placeholder_text = "default"
	_spawn_id.text_changed.connect(_sync_spawn_pick)
	v.add_child(_labeled("Spawn id", _spawn_id))
	_refresh_spawns()

	var door_btn := Button.new()
	door_btn.text = "Add Door"
	door_btn.pressed.connect(_add_door)
	v.add_child(door_btn)

	var spawn_btn := Button.new()
	spawn_btn.text = "Add Spawn Point"
	spawn_btn.pressed.connect(_add_spawn)
	v.add_child(spawn_btn)

	v.add_child(HSeparator.new())
	var player_btn := Button.new()
	player_btn.text = "Make the selected node the player"
	player_btn.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	player_btn.pressed.connect(_make_player)
	v.add_child(player_btn)

	v.add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a node, click a button."
	v.add_child(_status)

	var pro := Label.new()
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.text = "Pro unlocks: checkpoints + respawn(), world-state flags (global & per-scene, save-aware), press-E doors, locked/key-gated doors."
	pro.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	v.add_child(pro)

	# long button labels wrap onto a second line instead of widening the dock
	for c in v.get_children():
		if c is Button:
			(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _add_door() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var path := _scene_path.text.strip_edges()
	var spawn := _spawn_id.text.strip_edges()
	var door := _inert(Area2D.new(), DOOR) as Area2D
	door.name = "Door"
	door.set("target_scene", path)
	door.set("target_spawn", StringName(spawn))
	_own(target, door)
	_add_shape(door, Vector2(32, 48))
	if path == "":
		_say("Added a Door under '%s'. Set its target_scene in the Inspector.%s" % [target.name, _player_note()])
	else:
		_say("Added a Door to %s (spawn '%s').%s%s" % [path, spawn, _landing_note(path, spawn), _player_note()])


func _add_spawn() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var sp := _inert(Marker2D.new(), SPAWN) as Marker2D
	var id := _spawn_id.text.strip_edges()
	sp.name = "SpawnPoint" if id == "" else "Spawn_" + id
	if id != "":
		sp.set("id", StringName(id))
	_own(target, sp)
	_say("Added spawn point '%s'. Doors land here.%s" % [id if id != "" else "default", _player_note()])


# ---- door target ---------------------------------------------------------

func _pick_scene() -> void:
	if _scene_dialog == null:
		_scene_dialog = EditorFileDialog.new()
		_scene_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_scene_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_scene_dialog.title = "Pick the scene this door leads to"
		_scene_dialog.add_filter("*.tscn", "Scenes")
		_scene_dialog.file_selected.connect(_on_scene_picked)
		add_child(_scene_dialog)
	_scene_dialog.popup_centered_ratio(0.6)


func _on_scene_picked(path: String) -> void:
	_scene_path.text = path
	_refresh_spawns()
	if _spawn_pick.disabled:
		_say("%s has no spawn points yet. Type an id under Spawn id, then give that scene a spawn point with the same id." % path.get_file())
	else:
		_say("Doors to %s will land on '%s'. Pick another spot under Door lands on, then click Add Door." % [path.get_file(), _spawn_id.text])


# Nothing found = whatever's typed in Spawn id goes on the door.
func _refresh_spawns() -> void:
	_spawn_pick.clear()
	var path := _scene_path.text.strip_edges()
	var ids := _spawn_ids_in(path)
	if ids.is_empty():
		_spawn_pick.add_item("(pick a target scene first)" if path == "" else "(no spawn points there, type the id below)")
		_spawn_pick.disabled = true
		return
	_spawn_pick.disabled = false
	for id in ids:
		_spawn_pick.add_item(id)
	# keep a typed id that's really there, otherwise land on the first one
	var at := ids.find(_spawn_id.text.strip_edges())
	if at < 0:
		at = 0
		_spawn_id.text = ids[0]
	_spawn_pick.select(at)


func _on_spawn_picked(idx: int) -> void:
	_spawn_id.text = _spawn_pick.get_item_text(idx)


func _sync_spawn_pick(text: String) -> void:
	if _spawn_pick.disabled:
		return
	var at := -1
	for i in _spawn_pick.item_count:
		if _spawn_pick.get_item_text(i) == text.strip_edges():
			at = i
	_spawn_pick.select(at)


func _spawn_ids_in(path: String) -> PackedStringArray:
	var ids := PackedStringArray()
	if path == "" or not ResourceLoader.exists(path):
		return ids
	var ps := load(path) as PackedScene
	if ps == null:
		return ids
	# throwaway copy; the editor gives its scripts inert placeholders, so
	# nothing in it runs
	var inst := ps.instantiate()
	if inst == null:
		return ids
	var nodes: Array[Node] = [inst]
	nodes.append_array(inst.find_children("*", "", true, false))
	for n in nodes:
		if n.get_script() == SPAWN:
			var raw: Variant = n.get("id")
			var id := String(raw) if raw != null else ""
			if id != "" and not ids.has(id):
				ids.append(id)
	inst.free()
	return ids


# the door still works, but say so when it can't land where it points
func _landing_note(path: String, spawn: String) -> String:
	if not ResourceLoader.exists(path):
		return " There's no scene at that path yet."
	if spawn == "" or _spawn_ids_in(path).has(spawn):
		return ""
	return " %s has no spawn point '%s' yet. Open it and add one with that id." % [path.get_file(), spawn]


# ---- editor helpers ------------------------------------------------------

func _selected() -> Node:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	return sel[0] if sel.size() > 0 else null


func _own(parent: Node, child: Node) -> void:
	# readable, so a second route or door is Door2 rather than @Area2D@1234
	parent.add_child(child, true)
	child.owner = EditorInterface.get_edited_scene_root()
	# no undo manager here, so flag the scene or Play runs the old file without this node
	EditorInterface.mark_scene_as_unsaved()


# DOOR.new() from a tool script is a live instance that runs its game code in
# the editor. set_script gives the same inert placeholder a hand-added node
# gets, and saves the same.
func _inert(node: Node, script: Script) -> Node:
	node.set_script(script)
	return node


func _add_shape(parent: Node, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	_own(parent, shape)


# ---- player group --------------------------------------------------------

func _player_note() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not root.is_inside_tree():
		return ""
	for n in root.get_tree().get_nodes_in_group("player"):
		if n == root or root.is_ancestor_of(n):
			return ""
	return " " + NO_PLAYER


func _make_player() -> void:
	var target := _selected()
	if target == null:
		_say("Select your player node first.")
		return
	# persistent, so the group saves with the scene. Re-added because a
	# membership from a live script isn't persistent and add_to_group() won't
	# upgrade it.
	if target.is_in_group("player"):
		target.remove_from_group("player")
	target.add_to_group("player", true)
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % target.name)


# ---- ui helpers ----------------------------------------------------------

func _labeled(text: String, field: Control) -> Control:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = text
	box.add_child(l)
	box.add_child(field)
	return box


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	return l


func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg
