@tool
extends Control

# No-code chooser dock (Lite). Select a node, one click drops a walk-in music
# zone. Pro adds ambience zones, ambient emitters, and the intensity layer.

const ZONE: Script = preload("res://addons/audio_lite/zone_lite.gd")

var _status: Label


func _ready() -> void:
	name = "Audio Lite"
	_build()


func _build() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	v.add_child(_header("Audio Lite: bake onto the selected node"))

	var zone_btn := Button.new()
	zone_btn.text = "Add Audio Zone (music)"
	zone_btn.pressed.connect(_add_zone)
	v.add_child(zone_btn)

	v.add_child(HSeparator.new())
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Music/SFX buses are created at runtime. The Settings pack's sliders find them by name."
	v.add_child(info)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a node, click the button."
	v.add_child(_status)

	var pro := Label.new()
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.text = "Pro unlocks: layered intensity track (explore→combat, auto-driven by Combat hits), ambience channel, positional 2D SFX, ambient emitters, Day/Night ambience hook."
	pro.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	v.add_child(pro)


func _add_zone() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var z: Area2D = ZONE.new()
	z.name = "AudioZone"
	_own(target, z)
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(160, 120)
	shape.shape = rect
	_own(z, shape)
	_say("Added an AudioZone under '%s'. Assign its music stream in the Inspector; walking in swaps, walking out restores." % target.name)


# ---- editor helpers ------------------------------------------------------

func _selected() -> Node:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	return sel[0] if sel.size() > 0 else null


func _own(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = EditorInterface.get_edited_scene_root()


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	return l


func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg
