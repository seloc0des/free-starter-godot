extends RefCounted

# Shared checks for Scene Flow — Lite: spawn lookup, door guards, fades. The
# scene-swap travel leg is driven by flow_checker.gd from /root (this scene
# gets destroyed by the swap), used by the headless verify only.

static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true

	# --- door guards ---
	var door := SceneDoorLite.new()
	host.add_child(door)
	var traveled := {"n": 0}
	door.traveled.connect(func(_by: Node) -> void: traveled["n"] += 1)
	var fake_player := Node2D.new()
	host.add_child(fake_player)
	door.try_travel(fake_player)                               # no target set
	ok = _chk(lines, traveled["n"] == 0, "door without a target is a safe no-op") and ok
	door.target_scene = "res://tools/scene_flow_lite/flow_room_b.tscn"
	door.enabled = false
	door.try_travel(fake_player)
	ok = _chk(lines, traveled["n"] == 0, "disabled door refuses") and ok

	# --- spawn lookup ---
	var s1 := SceneSpawnPointLite.new()
	s1.id = &"east"
	s1.global_position = Vector2(400, 300)
	var s2 := SceneSpawnPointLite.new()
	s2.id = &"default"
	s2.global_position = Vector2(50, 60)
	host.add_child(s1)
	host.add_child(s2)
	ok = _chk(lines, SceneFlowLite._find_spawn(&"east") == s1, "spawn lookup by id") and ok
	ok = _chk(lines, SceneFlowLite._find_spawn(&"missing") == s2, "unknown id falls back to 'default'") and ok
	ok = _chk(lines, SceneFlowLite._find_spawn(&"") == s2, "empty id prefers 'default'") and ok

	for n in [door, fake_player, s1, s2]:
		n.queue_free()

	return {"ok": ok, "lines": lines}


static func run_fades(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var old_time: float = SceneFlowLite.fade_time
	SceneFlowLite.fade_time = 0.05
	var seen := {"out": false, "in": false}
	var on_out := func() -> void: seen["out"] = true
	var on_in := func() -> void: seen["in"] = true
	SceneFlowLite.faded_out.connect(on_out)
	SceneFlowLite.faded_in.connect(on_in)
	await SceneFlowLite.fade_out()
	ok = _chk(lines, seen["out"] and SceneFlowLite._fade_rect.color.a > 0.99, "fade_out covers the screen") and ok
	await SceneFlowLite.fade_in()
	ok = _chk(lines, seen["in"] and SceneFlowLite._fade_rect.color.a < 0.01 and not SceneFlowLite._fade_rect.visible, "fade_in clears and hides") and ok
	SceneFlowLite.faded_out.disconnect(on_out)
	SceneFlowLite.faded_in.disconnect(on_in)
	SceneFlowLite.fade_time = old_time
	return {"ok": ok, "lines": lines}


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
