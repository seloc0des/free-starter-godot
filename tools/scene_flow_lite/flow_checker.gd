extends Node

# The scene-swap leg of the Lite verify. Lives on /root so it survives the
# swaps it causes: travels to room B (spawn placement), where the player lands
# on a door that travels to room C (touch travel + fades along the way).

signal done(ok: bool, lines: Array)

var _lines: Array[String] = []
var _ok := true
var _step := 0
var _fades := {"out": 0, "in": 0}
var _finished := false


func start() -> void:
	_scene_flow_lite().fade_time = 0.05
	_scene_flow_lite().faded_out.connect(func() -> void: _fades["out"] += 1)
	_scene_flow_lite().faded_in.connect(func() -> void: _fades["in"] += 1)
	_scene_flow_lite().scene_changed.connect(_on_changed)
	get_tree().create_timer(10.0, true, false, true).timeout.connect(_timeout)
	_scene_flow_lite().change_scene("res://tools/scene_flow_lite/flow_room_b.tscn", &"east")


func _on_changed(path: String) -> void:
	_step += 1
	if _step == 1:
		_chk(path.ends_with("flow_room_b.tscn"), "change_scene lands in room B")
		_chk(_scene_flow_lite().current_path().ends_with("flow_room_b.tscn"), "current_path tracks the swap")
		var p := _player()
		_chk(p != null and p.global_position.is_equal_approx(Vector2(400, 300)), "player placed on the 'east' spawn")
		# placed on room B's door: it waits for them to step off and back on (1.1.2), so
		# step off and back on
		_off_and_on(p)
	elif _step == 2:
		_chk(path.ends_with("flow_room_c.tscn"), "touching a door travels")
		var p := _player()
		_chk(p != null and p.global_position.is_equal_approx(Vector2(123, 45)), "door delivers onto its target spawn")
		_chk(_fades["out"] == 2 and _fades["in"] >= 1, "fades ran on both travels")
		_finish()


# Off the door, a beat, and back onto it: the door then travels like any door.
func _off_and_on(p: Node2D) -> void:
	if p == null:
		return
	var spot := p.global_position
	p.global_position = spot + Vector2(300, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	_chk(not _scene_flow_lite().just_placed(), "the landing wait is over half a second on")
	p.global_position = spot


func _finish() -> void:
	if _finished:
		return
	_finished = true
	await get_tree().create_timer(0.3, true, false, true).timeout
	done.emit(_ok, _lines)


func _timeout() -> void:
	if _finished:
		return
	_finished = true
	_chk(false, "scene-swap leg timed out at step %d" % _step)
	done.emit(_ok, _lines)


func _player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node2D if players.size() > 0 else null


func _chk(cond: bool, label: String) -> void:
	_lines.append(("[ok] " if cond else "[XX] ") + label)
	_ok = _ok and cond


# SceneFlowLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const SCENE_FLOW_LITE := preload("res://addons/scene_flow_lite/scene_flow_lite.gd")


static func _scene_flow_lite() -> SCENE_FLOW_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"SceneFlowLite") as SCENE_FLOW_LITE
