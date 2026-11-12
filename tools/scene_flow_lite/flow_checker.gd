extends Node

# The scene-swap leg of the Lite verify. Lives on /root so it survives the
# swaps it causes: travels to room B (spawn placement), where the player lands
# on a door that travels to room C (touch travel + fades along the way). The 3D
# leg then repeats the trip between 3D rooms.

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
	get_tree().create_timer(20.0, true, false, true).timeout.connect(_timeout)
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
		_go_when_idle("res://tools/scene_flow_lite/flow_room_b_3d.tscn", &"east")
	elif _step == 3:
		_on_room_b_3d(path)
	elif _step == 4:
		_on_room_c_3d(path)


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


# ---- the 3D leg -----------------------------------------------------------

func _on_room_b_3d(path: String) -> void:
	_chk(path.ends_with("flow_room_b_3d.tscn"), "3D: change_scene lands in the 3D room B")
	var p := _player_3d()
	_chk(p != null and p.global_position.is_equal_approx(Vector3(4, 1, 3)), "3D: player placed on the 'east' spawn")
	_chk(p != null and _yaw_is(p, 1.0), "3D: player faces the way the spawn faces")
	_chk(p is CharacterBody3D and (p as CharacterBody3D).velocity == Vector3.ZERO, "3D: a falling player's velocity is zeroed on arrival")
	_chk(_scene_flow_lite().just_placed(), "3D: just_placed is true right after placement")
	_off_and_on_3d(p)


# Off the door, a beat, and back onto it: the door then travels like any door.
func _off_and_on_3d(p: Node3D) -> void:
	if p == null:
		return
	await get_tree().create_timer(0.6, true, false, true).timeout
	_chk(_scene_flow_lite().current_path().ends_with("flow_room_b_3d.tscn") and _step == 3, "3D: standing still on the landing door doesn't send you back")
	var spot := p.global_position
	p.global_position = spot + Vector3(20, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	_chk(not _scene_flow_lite().just_placed(), "3D: the landing wait is over half a second on")
	p.global_position = spot


func _on_room_c_3d(path: String) -> void:
	_chk(path.ends_with("flow_room_c_3d.tscn"), "3D: touching a door travels")
	var p := _player_3d()
	_chk(p != null and p.global_position.is_equal_approx(Vector3(-7, 1, 2)), "3D: door delivers onto its target spawn")
	_chk(p != null and _yaw_is(p, -0.5), "3D: and the player faces the way that spawn faces")
	_chk(_fades["out"] == 4 and _fades["in"] >= 3, "3D: fades ran on both travels")
	_finish()


# scene_changed fires before the fade back in ends, and a change asked for in that
# moment is ignored. Wait for the travel lock first.
func _go_when_idle(path: String, spawn: StringName) -> void:
	while _scene_flow_lite().is_changing():
		await get_tree().process_frame
	_scene_flow_lite().change_scene(path, spawn)


func _yaw_is(p: Node3D, yaw: float) -> bool:
	var forward := -p.global_basis.z
	return absf(angle_difference(atan2(-forward.x, -forward.z), yaw)) < 0.001


func _player_3d() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if players.size() > 0 else null


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
