class_name SaveKeysLite
extends Node

# Quick save and load on a key press. The Setup tab drops one on your scene root:
# F5 saves, F9 loads, and a short message says so. Pick other keys in the Inspector.

@export var save_key: Key = KEY_F5
@export var load_key: Key = KEY_F9
## Load the save when the scene starts (only if there is one).
@export var load_on_start: bool = false
## Show "Game saved" and "Game loaded" on screen.
@export var show_messages: bool = true

var _warned := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if load_on_start:
		# deferred, so every Saveable in the scene has joined its group by then
		_load_on_start.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == save_key:
		get_viewport().set_input_as_handled()
		quick_save()
	elif key.physical_keycode == load_key:
		get_viewport().set_input_as_handled()
		quick_load()


func quick_save() -> bool:
	var sl := _save_lite()
	if sl == null:
		return false
	var why: Array = []
	var cb := func(reason: String) -> void: why.append(reason)
	sl.connect("save_failed", cb)
	var ok: bool = sl.call("save")
	sl.disconnect("save_failed", cb)
	_toast("Game saved" if ok else "Save failed: %s" % _plain(why))
	return ok


func quick_load() -> bool:
	var sl := _save_lite()
	if sl == null:
		return false
	if not sl.call("has_save"):
		_toast("No save to load yet")
		return false
	var why: Array = []
	var cb := func(reason: String) -> void: why.append(reason)
	sl.connect("load_failed", cb)
	var ok: bool = sl.call("load")
	sl.disconnect("load_failed", cb)
	_toast("Game loaded" if ok else "Load failed: %s" % _plain(why))
	return ok


func _load_on_start() -> void:
	var sl := _save_lite()
	if sl != null and sl.call("has_save"):
		quick_load()


# looked up at runtime so a missing autoload is a warning, not a broken scene
func _save_lite() -> Node:
	var sl := get_node_or_null("/root/SaveLite")
	if sl == null and not _warned:
		_warned = true
		push_warning("SaveKeysLite: the SaveLite autoload is missing. Turn on Save / Load (Lite) in Project Settings > Plugins.")
	return sl


# SaveLite's reasons look like "cannot_open: user://save.json", so put them in words
func _plain(why: Array) -> String:
	if why.is_empty():
		return "unknown error"
	var reason := String(why[0])
	var path := reason.get_slice(": ", 1)
	match reason.get_slice(": ", 0):
		"cannot_open": return "can't open %s" % path
		"malformed_json": return "%s isn't a save this game can read" % path
		"not_found": return "there's no save at %s" % path
	return reason


# Lites are standalone, so this carries its own little toast: a label at the top
# centre, under any toast that's already up, gone after 2 seconds.
func _toast(text: String) -> void:
	if not show_messages or not is_inside_tree():
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	var shown := 0
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if not t.is_queued_for_deletion():
			shown += 1
	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.text = text
	label.add_to_group("lite_toast")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.offset_top = 16 + shown * 32
	label.offset_bottom = label.offset_top + 28
	# an outline keeps it readable on any background
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	host.add_child(layer)
	get_tree().create_timer(2.0).timeout.connect(layer.queue_free)
