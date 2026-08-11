@tool
extends Control

# No-code chooser dock (Lite). Select a node, one click makes it a playable
# top-down character or an interactable prop. Pro adds the platformer mover and
# the follow camera.

const MOVER: Script = preload("res://addons/controller_lite/top_down_mover_lite.gd")
const INTERACTOR: Script = preload("res://addons/controller_lite/interactor_lite.gd")
const INTERACTABLE: Script = preload("res://addons/controller_lite/interactable_lite.gd")

var _speed: SpinBox
var _status: Label


func _ready() -> void:
	name = "Controller Lite"
	_build()


func _build() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	v.add_child(_header("Controller Lite: bake onto the selected node"))
	_speed = _num(10, 2000, 200)
	v.add_child(_labeled("Move speed", _speed))

	var td_btn := Button.new()
	td_btn.text = "Make Top-Down Player"
	td_btn.pressed.connect(_make_player)
	v.add_child(td_btn)

	var ir_btn := Button.new()
	ir_btn.text = "Add Interactor (press E reach)"
	ir_btn.pressed.connect(_add_interactor)
	v.add_child(ir_btn)

	var ia_btn := Button.new()
	ia_btn.text = "Make Interactable"
	ia_btn.pressed.connect(_add_interactable)
	v.add_child(ia_btn)

	v.add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a node, click a button."
	v.add_child(_status)

	var pro := Label.new()
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.text = "Pro unlocks: platformer mover (coyote time, jump buffer, variable jump), follow camera (deadzone, look-ahead, shake), touch-input methods."
	pro.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	v.add_child(pro)


func _make_player() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var body: CharacterBody2D = target as CharacterBody2D
	if body == null:
		body = CharacterBody2D.new()
		body.name = "Player"
		_own(target, body)
		_add_shape(body, Vector2(20, 20))
	elif not _has_shape(body):
		_add_shape(body, Vector2(20, 20))
	var mover: Node = MOVER.new()
	mover.name = "TopDownMover"
	mover.set("speed", float(_speed.value))
	_own(body, mover)
	_say("Baked a top-down player (%d px/s). Arrows move it. Press Play." % int(_speed.value))


func _add_interactor() -> void:
	var target := _selected()
	if target == null:
		_say("Select your player body first.")
		return
	var ir: Node = INTERACTOR.new()
	ir.name = "Interactor"
	_own(target, ir)
	_add_shape(ir, Vector2(48, 48))
	_say("Added Interactor to '%s'. It presses ui_accept on the nearest Interactable." % target.name)


func _add_interactable() -> void:
	var target := _selected()
	if target == null:
		_say("Select the prop/NPC node first.")
		return
	var ia: Node = INTERACTABLE.new()
	ia.name = "Interactable"
	_own(target, ia)
	_add_shape(ia, Vector2(40, 40))
	_say("Made '%s' interactable. Set its prompt/event in the Inspector." % target.name)


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
