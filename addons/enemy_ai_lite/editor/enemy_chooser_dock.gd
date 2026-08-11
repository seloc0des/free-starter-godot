@tool
extends Control

# No-code chooser dock (Lite). Select a node, one click makes it an enemy that
# chases the "player" group. Pro adds patrol routes, flee, hitbox activation,
# and the wave spawner.

const BRAIN: Script = preload("res://addons/enemy_ai_lite/brain_lite.gd")

var _detect: SpinBox
var _speed: SpinBox
var _status: Label


func _ready() -> void:
	name = "Enemy AI Lite"
	_build()


func _build() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	v.add_child(_header("Enemy AI Lite: bake onto the selected node"))
	_detect = _num(20, 2000, 160)
	v.add_child(_labeled("Detect radius", _detect))
	_speed = _num(10, 1000, 140)
	v.add_child(_labeled("Chase speed", _speed))

	var brain_btn := Button.new()
	brain_btn.text = "Make Enemy (brain)"
	brain_btn.pressed.connect(_make_enemy)
	v.add_child(brain_btn)

	v.add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a node, click the button."
	v.add_child(_status)

	var pro := Label.new()
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.text = "Pro unlocks: waypoint patrol routes, flee at low health, CombatHitbox attack activation, and the spawner (endless + waves)."
	pro.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	v.add_child(pro)


func _make_enemy() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var body: CharacterBody2D = target as CharacterBody2D
	if body == null:
		body = CharacterBody2D.new()
		body.name = "Enemy"
		_own(target, body)
		_add_shape(body, Vector2(18, 18))
	elif not _has_shape(body):
		_add_shape(body, Vector2(18, 18))
	var brain: Node = BRAIN.new()
	brain.name = "Brain"
	brain.set("detect_radius", float(_detect.value))
	brain.set("chase_speed", float(_speed.value))
	_own(body, brain)
	_say("Baked a Brain. It hunts the 'player' group; tune radii in the Inspector.")


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


func _has_shape(node: Node) -> bool:
	for c in node.get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			return true
	return false


# ---- ui helpers ----------------------------------------------------------

func _num(min_v: float, max_v: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = value
	return s


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
