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
	SceneFlowLite.fade_time = 0.05
	SceneFlowLite.faded_out.connect(func() -> void: _fades["out"] += 1)
	SceneFlowLite.faded_in.connect(func() -> void: _fades["in"] += 1)
	SceneFlowLite.scene_changed.connect(_on_changed)
	get_tree().create_timer(10.0, true, false, true).timeout.connect(_timeout)
	SceneFlowLite.change_scene("res://tools/scene_flow_lite/flow_room_b.tscn", &"east")


func _on_changed(path: String) -> void:
	_step += 1
	if _step == 1:
		_chk(path.ends_with("flow_room_b.tscn"), "change_scene lands in room B")
		_chk(SceneFlowLite.current_path().ends_with("flow_room_b.tscn"), "current_path tracks the swap")
		var p := _player()
		_chk(p != null and p.global_position.is_equal_approx(Vector2(400, 300)), "player placed on the 'east' spawn")
		# standing on room B's door -> it retries through the fade and travels
	elif _step == 2:
		_chk(path.ends_with("flow_room_c.tscn"), "touching a door travels")
		var p := _player()
		_chk(p != null and p.global_position.is_equal_approx(Vector2(123, 45)), "door delivers onto its target spawn")
		_chk(_fades["out"] == 2 and _fades["in"] >= 1, "fades ran on both travels")
		_finish()


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
