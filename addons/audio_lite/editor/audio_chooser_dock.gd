@tool
extends Control

# No-code chooser dock (Lite). Drag a track or a sound into its slot, select a
# node, one click: music for the whole scene, a walk-in music zone, or a sound
# when the player touches something. 2D or 3D is read off the selection. Pro
# adds layered intensity music, ambience, emitters, occlusion and snapshots.

const ZONE: Script = preload("res://addons/audio_lite/zone_lite.gd")
const ZONE_3D: Script = preload("res://addons/audio_lite/zone_lite_3d.gd")
const SCENE_MUSIC: Script = preload("res://addons/audio_lite/scene_music_lite.gd")
const TOUCH_SOUND: Script = preload("res://addons/audio_lite/sound_on_touch_lite.gd")
const NO_PLAYER := "Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."
const SOUND_AREA := "SoundArea"
# a music zone is room sized, a touch area hugs the thing you touch
const ZONE_RADIUS_2D := 80.0
const ZONE_RADIUS_3D := 4.0
const TOUCH_RADIUS_2D := 40.0
const TOUCH_RADIUS_3D := 1.5

var _status: Label
var _track: EditorResourcePicker
var _sound: EditorResourcePicker
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Audio Lite"
	_build()


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0) if _scroll != null else Vector2.ZERO


func _build() -> void:
	# taller than a short dock slot now, so let it scroll
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.minimum_size_changed.connect(update_minimum_size)
	add_child(_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)

	v.add_child(_header("Audio Lite: bake onto the selected node"))

	v.add_child(_header("Music"))
	_track = _stream_picker()
	v.add_child(_labeled("Track (drag a file from the FileSystem dock)", _track))
	v.add_child(_button("Play it when the scene starts", _add_scene_music,
		"Music for this scene. It crossfades in from whatever the last scene was playing."))
	v.add_child(_button("Add Audio Zone (music)", _add_zone,
		"A circle (a sphere in 3D) around the selected node. Walking in plays the track, walking out brings back what played before."))

	v.add_child(HSeparator.new())
	v.add_child(_header("Sound effect"))
	_sound = _stream_picker()
	v.add_child(_labeled("Sound (drag a file from the FileSystem dock)", _sound))
	v.add_child(_button("Play it when the player touches the selected node", _add_touch_sound,
		"Plays once each time the player walks in. A node with nothing to touch gets a SoundArea around it."))

	v.add_child(HSeparator.new())
	v.add_child(_button("Make the selected node the player", _make_player,
		"Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."))

	v.add_child(HSeparator.new())
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Music/SFX buses are created at runtime. The Settings pack's sliders find them by name."
	v.add_child(info)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Drag a track or a sound into its slot, select a node, click a button."
	v.add_child(_status)

	var pro := Label.new()
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.text = "Pro unlocks: layered intensity music (explore to combat, driven by Combat hits), sounds and music when something dies, ambience by time of day, zones with ambience, 2D and 3D ambient emitters, sounds that muffle behind walls, mix snapshots, and Dialogue, UI and Ambience buses."
	pro.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	v.add_child(pro)


func _add_scene_music() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first.")
		return
	var stream := _track.edited_resource as AudioStream
	if stream == null:
		_say("Drag a music file from the FileSystem dock onto the Track slot first.")
		return
	var had := _find_script(root, root, SCENE_MUSIC) != null
	var m := wire_scene_music(root, stream)
	# no undo manager here, so flag the scene or Play runs the old file without this
	EditorInterface.mark_scene_as_unsaved()
	var what := _file_of(stream, "the track")
	var msg := ""
	if had:
		msg = "%s on '%s' now plays %s when the scene starts." % [m.name, root.name, what]
	else:
		msg = "Added %s to '%s': %s plays when the scene starts, crossfading from whatever played before." % [m.name, root.name, what]
	# no Loop tip any more: AudioLite loops music itself, whatever the Import dock says
	_say(msg)


func _add_zone() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var stream := _track.edited_resource as AudioStream
	if _is_zone(target) and stream == null:
		_say("'%s' is already an Audio Zone. Drag a track onto the Track slot to change its music, or onto its Music field in the Inspector." % target.name)
		return
	var was_zone := _is_zone(target)
	var z := wire_zone(EditorInterface.get_edited_scene_root(), target, stream)
	EditorInterface.mark_scene_as_unsaved()
	var msg := ""
	if was_zone:
		msg = "%s now plays %s while the player is inside." % [z.name, _file_of(stream, "the track")]
	elif stream != null:
		msg = "Added %s under '%s': walking in plays %s, walking out brings back what played before. Resize its shape to cover the area." % [z.name, target.name, _file_of(stream, "the track")]
	else:
		msg = "Added %s under '%s'. Drag a track onto its Music field in the Inspector; walking in swaps, walking out restores. Resize its shape to cover the area." % [z.name, target.name]
	_say(msg + _player_note())


func _add_touch_sound() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first.")
		return
	var stream := _sound.edited_resource as AudioStream
	if stream == null:
		_say("Drag a sound file from the FileSystem dock onto the Sound slot first.")
		return
	var target := _selected()
	if target == null:
		_say("Select the node the player touches first.")
		return
	var had_area := touch_ready(target) or target.get_node_or_null(SOUND_AREA) != null
	wire_touch_sound(root, target, stream)
	EditorInterface.mark_scene_as_unsaved()
	var msg := "%s plays when the player touches '%s', once each time they walk in." % [_file_of(stream, "The sound"), target.name]
	if not had_area:
		msg += " Added a SoundArea around it to touch. Resize its shape if it's too big or small."
	_say(msg + _player_note())


# ---- wiring (no EditorInterface, so the verify can run it headless) -------

## The scene's one SceneMusic, on its root. Pressing again gives the one that's
## there the new track instead of stacking a second.
func wire_scene_music(root: Node, stream: AudioStream) -> Node:
	var m := _find_script(root, root, SCENE_MUSIC)
	if m == null:
		m = _inert(Node.new(), SCENE_MUSIC)
		m.name = "SceneMusic"
		root.add_child(m, true)
		m.owner = root
	m.set("music", stream)
	return m


## A walk-in music zone under target: a circle in 2D, a sphere in 3D. A zone
## that's selected itself just takes the new track. Returns the zone.
func wire_zone(root: Node, target: Node, stream: AudioStream) -> Node:
	if _is_zone(target):
		if stream != null:
			target.set("music", stream)
		return target
	var z: Node
	if is_3d(root, target):
		z = _inert(Area3D.new(), ZONE_3D)
		z.name = "AudioZone3D"
	else:
		z = _inert(Area2D.new(), ZONE)
		z.name = "AudioZone"
	z.set("music", stream)
	target.add_child(z, true)
	z.owner = root
	_add_shape(root, z, ZONE_RADIUS_3D if z is Area3D else ZONE_RADIUS_2D)
	return z


## A SoundOnTouch that plays stream when the player walks into target. An area
## with a shape is used as is, anything else gets a SoundArea around it. Again
## on the same node swaps the sound instead of stacking a second.
func wire_touch_sound(root: Node, target: Node, stream: AudioStream) -> Node:
	var area := _touch_area(root, target)
	var s: Node = null
	for c in area.get_children():
		if c.get_script() == TOUCH_SOUND:
			s = c
			break
	if s == null:
		s = _inert(Node.new(), TOUCH_SOUND)
		s.name = "SoundOnTouch"
		area.add_child(s, true)
		s.owner = root
	s.set("sound", stream)
	return s


# Which half the buyer is working in. A plain Node (no position of its own)
# falls back to the scene's root, because one picked in a 3D level means 3D.
func is_3d(root: Node, target: Node) -> bool:
	if target is Node3D:
		return true
	if target is CanvasItem:
		return false
	return root is Node3D


func touch_ready(node: Node) -> bool:
	if not (node is Area2D or node is Area3D):
		return false
	for c in node.get_children():
		if (c is CollisionShape2D or c is CollisionShape3D) and c.get("shape") != null:
			return true
		if (c is CollisionPolygon2D or c is CollisionPolygon3D) and c.get("polygon").size() > 0:
			return true
	return false


## Whether a track keeps going on its own. Types we can't tell count as looping.
func loops(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	var v: Variant = stream.get("loop")
	return v == null or bool(v)


func _touch_area(root: Node, target: Node) -> Node:
	if touch_ready(target):
		return target
	var old := target.get_node_or_null(SOUND_AREA)
	if old is Area2D or old is Area3D:
		return old
	var area: Node = Area3D.new() if is_3d(root, target) else Area2D.new()
	area.name = SOUND_AREA
	target.add_child(area, true)
	area.owner = root
	_add_shape(root, area, TOUCH_RADIUS_3D if area is Area3D else TOUCH_RADIUS_2D)
	return area


# circle in 2D, sphere in 3D
func _add_shape(root: Node, area: Node, radius: float) -> void:
	var col: Node
	if area is Area3D:
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		col = CollisionShape3D.new()
		col.set("shape", sphere)
	else:
		var circle := CircleShape2D.new()
		circle.radius = radius
		col = CollisionShape2D.new()
		col.set("shape", circle)
	col.name = "Shape"
	area.add_child(col, true)
	col.owner = root


func _is_zone(node: Node) -> bool:
	var scr: Script = node.get_script()
	return scr != null and (scr == ZONE or scr == ZONE_3D)


# Only nodes this scene owns: one inside an instanced child scene wouldn't save.
# Placeholders report their script too, so this finds ones the dock just added.
func _find_script(node: Node, root: Node, script: Script) -> Node:
	if (node == root or node.owner == root) and node.get_script() == script:
		return node
	for c in node.get_children():
		var f := _find_script(c, root, script)
		if f != null:
			return f
	return null


func _file_of(stream: AudioStream, fallback: String) -> String:
	var path := stream.resource_path if stream != null else ""
	# made inline in the slot, so it lives in the scene and has no file name
	if path == "" or path.contains("::"):
		return fallback
	return path.get_file()


# ---- editor helpers ------------------------------------------------------

func _selected() -> Node:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	return sel[0] if sel.size() > 0 else null


# ZONE.new() from a tool script is a live instance that runs its game code in
# the editor. set_script gives the same inert placeholder a hand-added node
# gets, and saves the same.
func _inert(node: Node, script: Script) -> Node:
	node.set_script(script)
	return node


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


func _stream_picker() -> EditorResourcePicker:
	var p := EditorResourcePicker.new()
	p.base_type = "AudioStream"
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _button(text: String, on_press: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	# long labels wrap instead of forcing the dock wider
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(on_press)
	return b


func _labeled(text: String, field: Control) -> Control:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	box.add_child(field)
	return box


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	# wraps too, or the longest header sets the dock's width and a narrow slot clips it
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	return l


func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg
