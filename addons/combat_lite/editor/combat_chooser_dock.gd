@tool
extends Control

# No-code chooser. Select a node in your scene, set values, and one click bakes the
# combat components onto it — with a CollisionShape2D so it works immediately.

const HEALTH := preload("res://addons/combat_lite/health_lite.gd")
const HURTBOX := preload("res://addons/combat_lite/hurtbox_lite.gd")
const HITBOX := preload("res://addons/combat_lite/hitbox_lite.gd")

var _hp: SpinBox
var _team: SpinBox
var _dmg: SpinBox
var _status: Label


func _ready() -> void:
	name = "Combat"
	_build()


func _build() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	v.add_child(_header("Combat: bake onto the selected node"))
	_hp = _num(1, 9999, 100)
	v.add_child(_labeled("Max health", _hp))
	_team = _num(0, 32, 0)
	v.add_child(_labeled("Team", _team))
	var enemy_btn := Button.new()
	enemy_btn.text = "Add Health + Hurtbox"
	enemy_btn.pressed.connect(_add_hurtable)
	v.add_child(enemy_btn)

	v.add_child(HSeparator.new())

	_dmg = _num(0, 9999, 10)
	v.add_child(_labeled("Damage", _dmg))
	var hit_btn := Button.new()
	hit_btn.text = "Add Hitbox"
	hit_btn.pressed.connect(_add_hitbox)
	v.add_child(hit_btn)

	v.add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a node, set values, click a button."
	v.add_child(_status)


func _add_hurtable() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var h: Node = HEALTH.new()
	h.name = "HealthLite"
	h.set("max_health", float(_hp.value))
	_own(target, h)
	var hb: Node = HURTBOX.new()
	hb.name = "HurtboxLite"
	hb.set("team", int(_team.value))
	_own(target, hb)
	_add_shape(hb)
	_say("Added Health + Hurtbox (team %d) to '%s'." % [int(_team.value), target.name])


func _add_hitbox() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var hb: Node = HITBOX.new()
	hb.name = "HitboxLite"
	hb.set("damage", float(_dmg.value))
	hb.set("team", int(_team.value))
	_own(target, hb)
	_add_shape(hb)
	_say("Added Hitbox (%d dmg, team %d) to '%s'." % [int(_dmg.value), int(_team.value), target.name])


func _selected() -> Node:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	return sel[0] if sel.size() > 0 else null


func _own(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = EditorInterface.get_edited_scene_root()


func _add_shape(area: Node) -> void:
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 32)
	shape.shape = rect
	_own(area, shape)


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
