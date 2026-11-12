extends RefCounted

# 3D checks for Scene Flow (Lite): spawn lookup across 2D and 3D, placing a 3D
# player, the 3D door, the dock's 3D builds and the 3D demo rooms. The
# scene-swap leg (travel between 3D rooms, fades) is in flow_checker.gd.

const ROOM_B := "res://tools/scene_flow_lite/flow_room_b_3d.tscn"


static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true

	# --- spawn lookup, 2D and 3D side by side ---
	var s3 := SceneSpawnPointLite3D.new()
	s3.id = &"east"
	host.add_child(s3)
	s3.global_position = Vector3(5, 2, -3)
	s3.rotation.y = 0.8
	var s3d := SceneSpawnPointLite3D.new()
	s3d.id = &"default"
	host.add_child(s3d)
	var s2 := SceneSpawnPointLite.new()
	s2.id = &"north"
	host.add_child(s2)
	ok = _chk(lines, s3.is_in_group("scene_spawn"), "3D spawn joins the scene_spawn group") and ok
	ok = _chk(lines, _scene_flow_lite()._find_spawn(&"east") == s3, "3D spawn lookup by id") and ok
	ok = _chk(lines, _scene_flow_lite()._find_spawn(&"north") == s2, "a 2D spawn is still found next to 3D ones") and ok
	ok = _chk(lines, _scene_flow_lite()._find_spawn(&"missing") == s3d, "unknown id falls back to the 3D 'default'") and ok

	# --- placing a 3D player ---
	var hero := CharacterBody3D.new()
	hero.add_to_group("player")
	host.add_child(hero)
	hero.velocity = Vector3(1, -9, 2)
	hero.global_position = Vector3(-20, 0, 0)
	_scene_flow_lite().place_player(&"east")
	ok = _chk(lines, hero.global_position.is_equal_approx(Vector3(5, 2, -3)), "a 3D player lands on a 3D spawn") and ok
	ok = _chk(lines, absf(angle_difference(hero.global_rotation.y, 0.8)) < 0.001, "and takes the spawn's yaw") and ok
	ok = _chk(lines, hero.velocity == Vector3.ZERO, "a CharacterBody3D's velocity is zeroed on arrival") and ok
	ok = _chk(lines, _scene_flow_lite().just_placed(), "placing a 3D player counts for just_placed") and ok
	var plain := Node3D.new()
	plain.add_to_group("player")
	host.add_child(plain)
	_scene_flow_lite().place_player(&"east")
	ok = _chk(lines, plain.global_position.is_equal_approx(Vector3(5, 2, -3)), "any Node3D in the player group is placed, not only bodies") and ok

	var body := RigidBody3D.new()
	body.add_to_group("player")
	host.add_child(body)
	body.linear_velocity = Vector3(0, -5, 0)
	_scene_flow_lite().place_player(&"east")
	ok = _chk(lines, body.linear_velocity == Vector3.ZERO, "a RigidBody3D's linear velocity is zeroed on arrival") and ok
	body.free()

	# --- a player under a turned parent still faces the spawn's way ---
	var turned := Node3D.new()
	turned.rotation.y = 1.3
	turned.position = Vector3(3, 0, 3)
	host.add_child(turned)
	hero.reparent(turned)
	_scene_flow_lite().place_player(&"east")
	var fwd := -hero.global_basis.z
	var spawn_fwd := -s3.global_basis.z
	ok = _chk(lines, hero.global_position.is_equal_approx(Vector3(5, 2, -3)) and fwd.is_equal_approx(spawn_fwd), "a player under a turned parent still lands on the spot and faces the spawn's way") and ok
	hero.scale = Vector3(2, 2, 2)
	turned.scale = Vector3(1.5, 1.5, 1.5)
	_scene_flow_lite().place_player(&"east")
	var got := hero.global_basis.get_scale()
	ok = _chk(lines, got.is_equal_approx(Vector3(3, 3, 3)) and hero.global_position.is_equal_approx(Vector3(5, 2, -3)) and (-hero.global_basis.z).normalized().is_equal_approx(spawn_fwd), "a scaled player under a scaled parent keeps its scale and still faces the spawn's way") and ok
	turned.scale = Vector3.ONE
	hero.scale = Vector3(2, 2, 2)
	_scene_flow_lite().place_player(&"east")
	ok = _chk(lines, hero.global_basis.get_scale().is_equal_approx(Vector3(2, 2, 2)), "a scaled player keeps its scale on arrival") and ok
	turned.free()                       # frees the hero under it too
	plain.free()

	# --- 2D and 3D must not mix silently ---
	var flat := CharacterBody2D.new()
	flat.add_to_group("player")
	host.add_child(flat)
	flat.global_position = Vector2(7, 8)
	_scene_flow_lite()._warned_mismatch = false
	_scene_flow_lite().place_player(&"east")
	ok = _chk(lines, flat.global_position == Vector2(7, 8), "a 2D player is left alone by a 3D spawn") and ok
	ok = _chk(lines, _scene_flow_lite()._warned_mismatch, "and the mismatch is reported") and ok
	_scene_flow_lite()._warned_mismatch = false
	_scene_flow_lite().place_player(&"north")
	ok = _chk(lines, flat.global_position == s2.global_position, "a 2D player still lands on a 2D spawn") and ok
	ok = _chk(lines, not _scene_flow_lite()._warned_mismatch, "which reports nothing") and ok
	flat.queue_free()

	# --- door guards ---
	var door := SceneDoorLite3D.new()
	host.add_child(door)
	var traveled := {"n": 0}
	door.traveled.connect(func(_by: Node) -> void: traveled["n"] += 1)
	var visitor := Node3D.new()
	host.add_child(visitor)
	door.try_travel(visitor)
	ok = _chk(lines, traveled["n"] == 0, "3D: door without a target is a safe no-op") and ok
	door.target_scene = ROOM_B
	door.enabled = false
	door.try_travel(visitor)
	ok = _chk(lines, traveled["n"] == 0, "3D: disabled door refuses") and ok
	door.enabled = true

	# --- a door on the landing spot waits for the player to step off it first ---
	# (the travel signal re-takes the travel lock, so no scene really swaps here)
	var lock := func(_by: Node) -> void: _scene_flow_lite()._changing = true
	door.traveled.connect(lock)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	host.add_child(player)
	var before: int = traveled["n"]
	_scene_flow_lite()._placed_msec = Time.get_ticks_msec()
	door._on_body_entered(player)
	ok = _chk(lines, door._wait_exit and door._player_in == player and traveled["n"] == before, "3D: a player placed onto a door isn't sent straight back through it") and ok
	door._on_body_exited(player)
	ok = _chk(lines, not door._wait_exit and door._player_in == null, "3D: stepping off the door clears the wait") and ok
	_scene_flow_lite()._placed_msec = -100000
	door._on_body_entered(player)
	ok = _chk(lines, traveled["n"] == before + 1, "3D: back on it, the door travels like any door") and ok
	_scene_flow_lite()._changing = false
	door._on_body_exited(player)
	var passer := Node3D.new()
	host.add_child(passer)
	door._on_body_entered(passer)
	ok = _chk(lines, door._player_in == null and traveled["n"] == before + 1, "3D: only the player group sets a door off") and ok
	passer.queue_free()
	for n in [door, visitor, s3, s3d, s2, player]:
		n.queue_free()
	return {"ok": ok, "lines": lines}


# The dock's 3D builds, called the way the buttons do but without the editor.
static func run_dock(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var dock: Control = load("res://addons/scene_flow_lite/editor/scene_flow_chooser_dock.gd").new()
	var room := Node3D.new()
	room.name = "Room"
	host.add_child(room)
	var spot := Node3D.new()
	spot.name = "Spot"
	room.add_child(spot)
	var door: Area3D = dock.build_door_3d(spot, room, "res://tools/scene_flow_lite/flow_room_c_3d.tscn", "start")
	ok = _chk(lines, door.get_parent() == spot and door.owner == room and door.get_script() == SceneDoorLite3D, "dock 3D: Add Door builds a SceneDoorLite3D the scene owns") and ok
	ok = _chk(lines, door.get("target_scene") == "res://tools/scene_flow_lite/flow_room_c_3d.tscn" and door.get("target_spawn") == &"start", "dock 3D: the door carries its target scene and spawn") and ok
	var shape := door.get_node_or_null("Shape") as CollisionShape3D
	ok = _chk(lines, shape != null and shape.owner == room and shape.shape is BoxShape3D, "dock 3D: the door gets a box to walk into") and ok
	ok = _chk(lines, shape != null and is_equal_approx(shape.position.y - (shape.shape as BoxShape3D).size.y * 0.5, 0.0), "dock 3D: the door's box stands on the node's origin, none underground") and ok
	var sp: Marker3D = dock.build_spawn_3d(spot, room, "west")
	ok = _chk(lines, sp.get_script() == SceneSpawnPointLite3D and sp.name == "Spawn_west" and sp.get("id") == &"west" and sp.owner == room, "dock 3D: Add Spawn Point builds a named SceneSpawnPointLite3D") and ok
	var sp_default: Marker3D = dock.build_spawn_3d(spot, room, "")
	ok = _chk(lines, sp_default.name == "SpawnPoint" and sp_default.get("id") == &"default", "dock 3D: no id means the default spawn") and ok
	ok = _chk(lines, dock._spawn_ids_in(ROOM_B).has("east"), "dock 3D: Door lands on lists 3D spawn points") and ok
	var flat: Array = []
	for cls in ["Area2D", "Marker2D", "CollisionShape2D"]:
		flat.append_array(room.find_children("*", cls, true, false))
	ok = _chk(lines, flat.is_empty(), "dock 3D: nothing 2D sneaks into a 3D scene") and ok
	# 3D or 2D: a Node3D root says 3D, a Node2D root says 2D, a plain Node follows the target
	var plain_root := Node.new()
	var kid_3d := Node3D.new()
	var kid_plain := Node.new()
	var root_2d := Node2D.new()
	ok = _chk(lines, dock.use_3d(room, kid_plain) and not dock.use_3d(root_2d, kid_3d), "dock: a Node3D root builds 3D, a Node2D root keeps 2D") and ok
	ok = _chk(lines, dock.use_3d(plain_root, kid_3d) and not dock.use_3d(plain_root, kid_plain), "dock: a plain Node root follows the selected node") and ok
	plain_root.free()
	kid_3d.free()
	kid_plain.free()
	root_2d.free()
	room.queue_free()
	dock.free()
	return {"ok": ok, "lines": lines}


# The two demo rooms: each loads, has a 3D player, a door pointing at the other
# room, and the spawn that door lands on. The starter kits ship these tools but
# no demo, so this skips when the demo isn't there.
static func run_demo(_host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var a_path := "res://demo/scene_flow_lite/room_a_3d.tscn"
	var b_path := "res://demo/scene_flow_lite/room_b_3d.tscn"
	if not ResourceLoader.exists(a_path) or not ResourceLoader.exists(b_path):
		lines.append("[--] 3D demo rooms: not in this project, skipped")
		return {"ok": ok, "lines": lines}
	var room_a: Node = (load(a_path) as PackedScene).instantiate()
	var room_b: Node = (load(b_path) as PackedScene).instantiate()
	var door_a := room_a.get_node_or_null("EastDoor")
	var door_b := room_b.get_node_or_null("WestDoor")
	ok = _chk(lines, room_a.get_node_or_null("Player") is CharacterBody3D and room_b.get_node_or_null("Player") is CharacterBody3D, "3D demo: both rooms have a 3D player") and ok
	ok = _chk(lines, door_a is SceneDoorLite3D and door_a.get("target_scene") == b_path and door_b is SceneDoorLite3D and door_b.get("target_scene") == a_path, "3D demo: the doors lead to each other") and ok
	ok = _chk(lines, room_b.get_node_or_null("WestSpawn") is SceneSpawnPointLite3D and room_a.get_node_or_null("EastSpawn") is SceneSpawnPointLite3D, "3D demo: each door has a spawn point to land on") and ok
	room_a.free()
	room_b.free()
	return {"ok": ok, "lines": lines}


# The mid-fade retry: a door touched while a change is in flight waits and tries
# again, once, when the lock lets go. Nothing here may really swap scenes, so the
# travel signal re-takes the lock.
static func run_retry(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var sf := _scene_flow_lite()
	for kind in ["2D", "3D"]:
		var door: Node
		var player: Node
		if kind == "2D":
			door = SceneDoorLite.new()
			player = Node2D.new()
		else:
			door = SceneDoorLite3D.new()
			player = Node3D.new()
		player.add_to_group("player")
		door.set("target_scene", ROOM_B)
		host.add_child(door)
		host.add_child(player)
		var travels := {"n": 0}
		door.connect("traveled", func(_by: Node) -> void:
			travels["n"] += 1
			sf._changing = true)
		sf._changing = true
		door.set("_player_in", player)
		door.call("try_travel", player)
		ok = _chk(lines, travels["n"] == 0, "%s door: touched mid-change, it holds off" % kind) and ok
		sf._changing = false
		await host.get_tree().create_timer(0.3).timeout
		ok = _chk(lines, travels["n"] == 1, "%s door: and travels once when the change is over" % kind) and ok
		sf._changing = false
		door.queue_free()
		player.queue_free()
	return {"ok": ok, "lines": lines}


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond


# SceneFlowLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const SCENE_FLOW_LITE := preload("res://addons/scene_flow_lite/scene_flow_lite.gd")


static func _scene_flow_lite() -> SCENE_FLOW_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"SceneFlowLite") as SCENE_FLOW_LITE
