extends Node

# SceneFlowLite autoload: scene travel with fades + spawn placement. The free
# core of Scene Flow (Pro adds checkpoints/respawn, world-state flags, gating).

signal scene_changing(to_path: String)
signal scene_changed(path: String)
signal faded_out
signal faded_in

var fade_time := 0.4
var fade_color := Color.BLACK

var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _changing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # fades keep running if the game pauses


## Fade out, swap scenes, drop the "player" group on the named spawn point,
## fade back in. Fire-and-forget safe (double calls are ignored mid-change).
func change_scene(path: String, spawn: StringName = &"", fade := true) -> void:
	if _changing or path == "":
		return
	_changing = true
	scene_changing.emit(path)
	if fade and fade_time > 0.0:
		await fade_out()
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame               # swap happens at end of frame
	await get_tree().process_frame               # new scene is in and _ready by now
	place_player(spawn)
	scene_changed.emit(path)
	if fade and fade_time > 0.0:
		await fade_in()
	_changing = false


func place_player(spawn: StringName = &"") -> void:
	var sp := _find_spawn(spawn)
	if sp == null:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node2D:
			p.global_position = sp.global_position


func current_path() -> String:
	var cs := get_tree().current_scene
	return cs.scene_file_path if cs != null else ""


func is_changing() -> bool:
	return _changing


func _find_spawn(id: StringName) -> Node2D:
	var pts := get_tree().get_nodes_in_group("scene_spawn")
	if pts.is_empty():
		return null
	if id != &"":
		for pt in pts:
			if pt.get("id") == id:
				return pt
	for pt in pts:
		if pt.get("id") == &"default":
			return pt
	return pts[0]


# ---- fades ---------------------------------------------------------------

func fade_out() -> void:
	_ensure_fade()
	_fade_rect.visible = true
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, fade_time)
	await tw.finished
	faded_out.emit()


func fade_in() -> void:
	_ensure_fade()
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, fade_time)
	await tw.finished
	_fade_rect.visible = false
	faded_in.emit()


func _ensure_fade() -> void:
	if _fade_layer != null:
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)
