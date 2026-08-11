@tool
extends Control

# No-code chooser dock (Lite). Select a node, one click drops a touch-travel
# Door (with shape and target) or a Spawn Point. Pro adds checkpoints, flags,
# press-E doors, and key-gating.

const DOOR: Script = preload("res://addons/scene_flow_lite/door_lite.gd")
const SPAWN: Script = preload("res://addons/scene_flow_lite/spawn_point_lite.gd")

var _scene_path: LineEdit
var _spawn_id: LineEdit
var _status: Label


func _ready() -> void:
	name = "Scene Flow Lite"
	_build()


func _build() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	v.add_child(_header("Scene Flow Lite: bake onto the selected node"))
	_scene_path = LineEdit.new()
	_scene_path.placeholder_text = "res://levels/room_b.tscn"
	v.add_child(_labeled("Door target scene", _scene_path))
	_spawn_id = LineEdit.new()
	_spawn_id.placeholder_text = "default"
	v.add_child(_labeled("Spawn id", _spawn_id))

	var door_btn := Button.new()
	door_btn.text = "Add Door"
	door_btn.pressed.connect(_add_door)
	v.add_child(door_btn)

	var spawn_btn := Button.new()
	spawn_btn.text = "Add Spawn Point"
	spawn_btn.pressed.connect(_add_spawn)
	v.add_child(spawn_btn)

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


func _add_door() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var door: Area2D = DOOR.new()
	door.name = "Door"
	door.set("target_scene", _scene_path.text.strip_edges())
	door.set("target_spawn", StringName(_spawn_id.text.strip_edges()))
	_own(target, door)
	_add_shape(door, Vector2(32, 48))
	if _scene_path.text.strip_edges() == "":
		_say("Added a Door under '%s'. Set its target_scene in the Inspector." % target.name)
	else:
		_say("Added a Door to %s (spawn '%s')." % [_scene_path.text, _spawn_id.text])


func _add_spawn() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var sp: Marker2D = SPAWN.new()
	var id := _spawn_id.text.strip_edges()
	sp.name = "SpawnPoint" if id == "" else "Spawn_" + id
	if id != "":
		sp.set("id", StringName(id))
	_own(target, sp)
	_say("Added spawn point '%s'. Doors land here." % (id if id != "" else "default"))


# ---- editor helpers ------------------------------------------------------

func _selected() -> Node:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	return sel[0] if sel.size() > 0 else null


func _own(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = EditorInterface.get_edited_scene_root()


func _add_shape(parent: Node, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	_own(parent, shape)


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
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	return l


func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg
