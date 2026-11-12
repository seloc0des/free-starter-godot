extends RefCounted

# Checks for the 3D half of Controller (Lite): the 3D mover, the follow camera,
# the 3D interactor and interactable. Shared by the headless verify and the
# acceptance banner; `host` must be in the SceneTree. Everything explicitly
# typed, Lite verifies run strict.
#
# Every movement check drives keyboard-only stand-in actions (never move_*),
# because those carry a stick and a real controller plugged into the machine
# would blend its drift into the result.

const C := preload("res://tools/controller_lite/controller_checks.gd")


# Everything that needs no physics frames.
static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok: bool = true

	var td: TopDownMoverLite3D = TopDownMoverLite3D.new()
	ok = _chk(lines, td.action_left == &"move_left" and td.action_up == &"move_up", "3D: a new 3D mover asks for the pack's move actions") and ok
	ok = _chk(lines, is_equal_approx(td.speed, 5.0), "3D: it defaults to 5 m/s") and ok
	td.free()
	var ir: InteractorLite3D = InteractorLite3D.new()
	ok = _chk(lines, ir.action == &"interact", "3D: a new 3D interactor asks for 'interact'") and ok
	ir.free()

	# --- player registration, orphan, save contract ---
	var body: CharacterBody3D = CharacterBody3D.new()
	var mover: TopDownMoverLite3D = TopDownMoverLite3D.new()
	body.add_child(mover)
	host.add_child(body)
	ok = _chk(lines, C._controllers_lite().player == body and body.is_in_group("player"), "3D: the mover registers its body as THE player and tags it") and ok
	var orphan_parent: Node = Node.new()
	var orphan: TopDownMoverLite3D = TopDownMoverLite3D.new()
	orphan_parent.add_child(orphan)
	host.add_child(orphan_parent)
	ok = _chk(lines, not orphan.is_physics_processing(), "3D: a mover on a non-CharacterBody3D parent turns itself off") and ok
	orphan_parent.queue_free()

	body.global_position = Vector3(1.5, 2.5, -3.5)
	body.global_rotation.y = 0.75
	var snap: Dictionary = mover.save_state()
	ok = _chk(lines, snap.size() == 4 and snap.has("x") and snap.has("y") and snap.has("z") and snap.has("yaw"), "3D: save_state stores x, y, z and yaw") and ok
	body.global_position = Vector3(99, 99, 99)
	body.global_rotation.y = 0.0
	mover.load_state(snap)
	ok = _chk(lines, body.global_position.is_equal_approx(Vector3(1.5, 2.5, -3.5)) and is_equal_approx(body.global_rotation.y, 0.75), "3D: load_state puts the body back, facing included") and ok
	mover.load_state({"x": 4.0, "y": 0.0, "z": 5.0})
	ok = _chk(lines, body.global_position.is_equal_approx(Vector3(4, 0, 5)) and is_equal_approx(body.global_rotation.y, 0.75), "3D: a save with no yaw moves the body and keeps its facing") and ok
	# these two print an engine error each, on purpose: the mover is refusing a bad save
	mover.load_state({"x": 1.0, "y": INF, "z": 1.0, "yaw": 0.0})
	ok = _chk(lines, body.global_position.is_equal_approx(Vector3(4, 0, 5)), "3D: a non-finite position is refused, the body stays put") and ok
	mover.load_state({"x": 1.0, "y": 1.0, "z": 1.0, "yaw": NAN})
	ok = _chk(lines, body.global_position.is_equal_approx(Vector3(4, 0, 5)), "3D: and so is a non-finite facing") and ok
	mover.load_state({"x": "junk", "y": null, "z": 2.0})
	ok = _chk(lines, body.global_position.is_equal_approx(Vector3(0, 0, 2)), "3D: junk values load as 0 like the 2D mover, rather than aborting") and ok
	body.queue_free()

	# --- interactable: bus mirror + one_shot; interactor: nearest focus ---
	var seen: Dictionary = {"count": 0, "event": &"", "by": null}
	var on_int: Callable = func(ia: Node, by: Node) -> void:
		seen["count"] += 1
		seen["event"] = ia.get("event")
		seen["by"] = by
	C._controllers_lite().interacted.connect(on_int)
	var holder: CharacterBody3D = CharacterBody3D.new()
	host.add_child(holder)
	var sign_ia: InteractableLite3D = InteractableLite3D.new()
	sign_ia.event = &"sign_read"
	sign_ia.one_shot = true
	host.add_child(sign_ia)
	sign_ia.interact(holder)
	sign_ia.interact(holder)
	ok = _chk(lines, seen["count"] == 1 and seen["event"] == &"sign_read" and seen["by"] == holder, "3D: one_shot interactable fires once and mirrors its event on the bus") and ok
	C._controllers_lite().interacted.disconnect(on_int)

	var reach: InteractorLite3D = InteractorLite3D.new()
	holder.add_child(reach)
	var near: InteractableLite3D = InteractableLite3D.new()
	near.position = Vector3(1, 0, 0)
	near.one_shot = true
	var far: InteractableLite3D = InteractableLite3D.new()
	far.position = Vector3(10, 0, 0)
	host.add_child(near)
	host.add_child(far)
	reach._on_area_entered(far)
	reach._on_area_entered(near)
	ok = _chk(lines, reach.current_focus() == near, "3D: focus picks the nearest interactable") and ok
	reach.interact()
	reach._refresh_focus()
	ok = _chk(lines, reach.current_focus() == far, "3D: a used one_shot loses focus") and ok
	far.free()   # a pickup or an enemy freed while the player stands next to it
	reach._refresh_focus()
	ok = _chk(lines, reach.current_focus() == null, "3D: an interactable freed while focused leaves no stale focus") and ok
	reach.interact()
	# any other Area leaving reach (a hitbox, a door) must not print engine errors
	var catcher: _ErrorCatcher = _ErrorCatcher.new()
	OS.add_logger(catcher)
	var other_area: Area3D = Area3D.new()
	host.add_child(other_area)
	reach._on_area_entered(other_area)
	reach._on_area_exited(other_area)
	var reach_2d: InteractorLite = InteractorLite.new()
	var other_2d: Area2D = Area2D.new()
	reach_2d._on_area_entered(other_2d)
	reach_2d._on_area_exited(other_2d)
	OS.remove_logger(catcher)
	ok = _chk(lines, catcher.count == 0, "3D: another kind of Area leaving reach prints no errors, in 3D or 2D (%d)" % catcher.count) and ok
	other_area.free()
	other_2d.free()
	reach_2d.free()
	for n: Node in [holder, sign_ia, near]:
		n.queue_free()
	return {"ok": ok, "lines": lines}


# Async: movement, facing, steps and the camera, over real physics frames.
static func run_physics(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok: bool = true
	var tree: SceneTree = host.get_tree()
	C._isolate_actions()

	var ground: StaticBody3D = _box(host, Vector3(120, 1, 120), Vector3(0, -0.5, 0))
	await tree.physics_frame

	var rig: Array = _player(host, Vector3(0, 3, 0))
	var body: CharacterBody3D = rig[0]
	var mover: TopDownMoverLite3D = rig[1]
	var frames: int = 0
	while not body.is_on_floor() and frames < 240:
		await tree.physics_frame
		frames += 1
	ok = _chk(lines, body.is_on_floor() and absf(body.global_position.y) < 0.05, "3D: gravity drops it onto the floor (y %.3f)" % body.global_position.y) and ok

	# a shove from outside (Combat knockback adds to velocity) with the default feel
	mover.world_relative = true
	body.global_position = Vector3(0, 0.02, 0)
	body.velocity = Vector3.ZERO
	await _wait(tree, 0.1)
	var shove_from: float = body.global_position.x
	body.velocity += Vector3(8, 0, 0)
	var stopped_at: float = -1.0
	for i in int(Engine.physics_ticks_per_second):    # one second, at any tick rate
		await tree.physics_frame
		if stopped_at < 0.0 and absf(body.velocity.x) < 0.05:
			stopped_at = float(i + 1) / float(Engine.physics_ticks_per_second)
	var slid: float = body.global_position.x - shove_from
	ok = _chk(lines, stopped_at > 0.0 and stopped_at < 0.4 and slid > 0.5 and slid < 1.5, "3D: an 8 m/s shove fades under default friction in %.2f s over %.2f m" % [stopped_at, slid]) and ok
	var saved_friction: float = mover.friction
	var saved_accel: float = mover.acceleration
	mover.friction = 0.0
	mover.acceleration = 0.0
	body.velocity += Vector3(8, 0, 0)
	await tree.physics_frame
	ok = _chk(lines, absf(body.velocity.x) < 0.01, "3D: with friction 0 (instant) a shove is wiped the next frame") and ok
	mover.friction = saved_friction
	mover.acceleration = saved_accel
	body.velocity.y = 6.0
	await tree.physics_frame
	await tree.physics_frame
	ok = _chk(lines, not body.is_on_floor() and body.velocity.y > 0.0, "3D: an upward kick lifts the body off the floor") and ok
	await _wait(tree, 1.0)
	ok = _chk(lines, body.is_on_floor(), "3D: and it comes back down") and ok

	mover.world_relative = true
	mover.speed = 4.0
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 0.5)
	ok = _chk(lines, body.velocity.x > 3.9 and absf(body.velocity.z) < 0.01, "3D: held right -> 4 m/s along +X (%.2f)" % body.velocity.x) and ok
	ok = _chk(lines, body.global_position.x > 1.0, "3D: position actually advanced") and ok
	ok = _chk(lines, absf(body.global_rotation.y - (-PI / 2.0)) < 0.05, "3D: the body turned to face +X (yaw %.2f)" % body.global_rotation.y) and ok
	C._controllers_lite().lock_movement(&"test")
	await _wait(tree, 0.3)
	ok = _chk(lines, Vector2(body.velocity.x, body.velocity.z).length() < 0.001, "3D: a movement lock stops it") and ok
	C._controllers_lite().unlock_movement(&"test")
	Input.action_release(C.TEST_RIGHT)
	await _wait(tree, 0.5)
	ok = _chk(lines, is_zero_approx(body.velocity.x) and body.is_on_floor(), "3D: friction brakes it to a stop on the floor") and ok
	mover.acceleration = 10.0
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 0.1)
	ok = _chk(lines, body.velocity.x > 0.0 and body.velocity.x < 2.0, "3D: acceleration ramps instead of snapping (%.2f)" % body.velocity.x) and ok
	Input.action_release(C.TEST_RIGHT)
	mover.acceleration = 0.0
	mover.friction = 0.0
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 0.1)
	var instant: float = body.velocity.x
	Input.action_release(C.TEST_RIGHT)
	await _wait(tree, 0.1)
	ok = _chk(lines, is_equal_approx(instant, 4.0) and is_zero_approx(body.velocity.x), "3D: 0 acceleration and 0 friction are instant, as in 2D") and ok
	mover.acceleration = 30.0
	mover.friction = 40.0

	body.global_position = Vector3(-10, 0, 0)
	Input.action_press(C.TEST_RIGHT)
	Input.action_press(C.TEST_DOWN)
	await _wait(tree, 0.4)
	var diag: float = Vector2(body.velocity.x, body.velocity.z).length()
	Input.action_release(C.TEST_RIGHT)
	Input.action_release(C.TEST_DOWN)
	ok = _chk(lines, absf(diag - 4.0) < 0.05 and body.velocity.z > 0.0, "3D: a diagonal is still 4 m/s, and down is +Z (%.2f)" % diag) and ok
	await _wait(tree, 0.4)

	# movement follows the camera
	mover.world_relative = false
	var look_cam: Camera3D = Camera3D.new()
	look_cam.rotation.y = -PI / 2.0   # looking along +X
	host.add_child(look_cam)
	look_cam.make_current()
	await tree.physics_frame
	body.global_position = Vector3(-10, 0, 0)
	Input.action_press(C.TEST_UP)
	await _wait(tree, 0.4)
	Input.action_release(C.TEST_UP)
	ok = _chk(lines, body.velocity.x > 3.9 and absf(body.velocity.z) < 0.05, "3D: up goes where the camera looks (+X here) (%.2f, %.2f)" % [body.velocity.x, body.velocity.z]) and ok
	mover.world_relative = true
	body.global_position = Vector3(-10, 0, 0)
	Input.action_press(C.TEST_UP)
	await _wait(tree, 0.4)
	Input.action_release(C.TEST_UP)
	ok = _chk(lines, body.velocity.z < -3.9 and absf(body.velocity.x) < 0.05, "3D: world_relative ignores the camera, up is -Z") and ok
	mover.world_relative = false
	look_cam.rotation = Vector3(-PI / 2.0, 0, 0)    # straight down, screen-up is -Z
	body.global_position = Vector3(-10, 0, 0)
	await tree.physics_frame
	Input.action_press(C.TEST_UP)
	await _wait(tree, 0.4)
	Input.action_release(C.TEST_UP)
	ok = _chk(lines, body.velocity.z < -3.9, "3D: a camera looking straight down still gives up a direction") and ok
	look_cam.free()
	mover.world_relative = true
	await _wait(tree, 0.4)

	# a body under a rotated parent still faces where it walks
	var turned: Node3D = Node3D.new()
	turned.rotation.y = PI / 2.0
	host.add_child(turned)
	var kid: CharacterBody3D = CharacterBody3D.new()
	kid.add_child(_capsule())
	var kid_mover: TopDownMoverLite3D = TopDownMoverLite3D.new()
	_wire(kid_mover)
	kid_mover.world_relative = true
	kid_mover.is_player = false
	kid.add_child(kid_mover)
	turned.add_child(kid)
	kid.position = Vector3(0, 0.05, 0)
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 0.6)
	Input.action_release(C.TEST_RIGHT)
	ok = _chk(lines, absf(wrapf(kid.global_rotation.y - (-PI / 2.0), -PI, PI)) < 0.05, "3D: under a yawed parent it still faces +X in the world (yaw %.2f)" % kid.global_rotation.y) and ok
	ok = _chk(lines, kid.global_position.x > 0.5, "3D: and walks along world +X there") and ok
	turned.queue_free()

	# a scaled body, or one under a scaled parent, keeps its scale when it turns
	var big: Node3D = Node3D.new()
	big.scale = Vector3(2, 2, 2)
	host.add_child(big)
	var fat: CharacterBody3D = CharacterBody3D.new()
	fat.scale = Vector3(1.5, 1.5, 1.5)
	fat.add_child(_capsule())
	var fat_mover: TopDownMoverLite3D = TopDownMoverLite3D.new()
	_wire(fat_mover)
	fat_mover.world_relative = true
	fat_mover.is_player = false
	fat.add_child(fat_mover)
	big.add_child(fat)
	fat.position = Vector3(0, 0.05, 0)
	var before_scale: Vector3 = fat.global_basis.get_scale()
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 0.6)
	Input.action_release(C.TEST_RIGHT)
	ok = _chk(lines, fat.global_basis.get_scale().is_equal_approx(before_scale) and fat.scale.is_equal_approx(Vector3(1.5, 1.5, 1.5)) and big.scale.is_equal_approx(Vector3(2, 2, 2)), "3D: a scaled body under a scaled parent keeps its scale when it turns (%s)" % str(fat.global_basis.get_scale())) and ok
	ok = _chk(lines, absf(wrapf(fat.global_basis.orthonormalized().get_euler().y + PI / 2.0, -PI, PI)) < 0.05, "3D: and still turns to face +X") and ok
	big.queue_free()
	await tree.physics_frame

	# steps, walls, ramps
	mover.world_relative = true
	mover.speed = 4.0
	var step: StaticBody3D = _box(host, Vector3(8.0, 0.25, 6.0), Vector3(7.0, 0.125, 0.0))
	body.global_position = Vector3(0, 0.02, 0)
	body.velocity = Vector3.ZERO
	await tree.physics_frame
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 1.6)
	Input.action_release(C.TEST_RIGHT)
	ok = _chk(lines, body.global_position.x > 4.2 and absf(body.global_position.y - 0.25) < 0.06 and body.is_on_floor(), "3D: it walks up a 25 cm step and stands on it (x %.2f, y %.3f)" % [body.global_position.x, body.global_position.y]) and ok
	mover.step_height = 0.0
	body.global_position = Vector3(0, 0.02, 0)
	await tree.physics_frame
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 1.6)
	Input.action_release(C.TEST_RIGHT)
	ok = _chk(lines, body.global_position.x < 3.1, "3D: step_height 0 turns stepping off, the step stops it (x %.2f)" % body.global_position.x) and ok
	mover.step_height = 0.3
	step.queue_free()

	# ledges taller than step_height are walls: stopped cleanly, no hopping in place
	for h: float in [0.35, 0.40, 0.45]:
		var ledge: StaticBody3D = _box(host, Vector3(8.0, h, 6.0), Vector3(7.0, h * 0.5, 0.0))
		body.global_position = Vector3(0, 0.02, 0)
		body.velocity = Vector3.ZERO
		await tree.physics_frame
		Input.action_press(C.TEST_RIGHT)
		var highest: float = 0.0
		for i in 90:
			await tree.physics_frame
			highest = maxf(highest, body.global_position.y)
		Input.action_release(C.TEST_RIGHT)
		ok = _chk(lines, body.global_position.x < 3.0 and highest < 0.06, "3D: a %d cm ledge is a wall, with no bobbing against it (x %.2f, highest y %.3f)" % [int(h * 100.0), body.global_position.x, highest]) and ok
		ledge.queue_free()
		await tree.physics_frame

	var wall: StaticBody3D = _box(host, Vector3(1.0, 3.0, 6.0), Vector3(3.5, 1.5, 0.0))
	body.global_position = Vector3(0, 0.02, 0)
	await tree.physics_frame
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 1.6)
	Input.action_release(C.TEST_RIGHT)
	ok = _chk(lines, body.global_position.x < 3.0 and body.global_position.y < 0.1, "3D: a wall is not a step, it stops the body (x %.2f)" % body.global_position.x) and ok
	wall.queue_free()

	var ramp: StaticBody3D = _ramp(host, 20.0, 4.0)
	body.global_position = Vector3(0, 0.02, 0)
	await tree.physics_frame
	Input.action_press(C.TEST_RIGHT)
	await _wait(tree, 2.0)
	Input.action_release(C.TEST_RIGHT)
	ok = _chk(lines, body.global_position.y > 1.0 and body.is_on_floor(), "3D: it walks up a 20 degree ramp and stays on it (y %.2f)" % body.global_position.y) and ok
	ramp.queue_free()
	await _wait(tree, 0.5)

	# stands still while a conversation runs, Lite or Pro
	for manager: String in ["DialoguesLite", "DialogueManager"]:
		var stub: Node = C._dialogue_stub(tree.root, manager)
		if stub == null:
			continue
		body.global_position = Vector3(-20, 0.02, 0)
		await tree.physics_frame
		Input.action_press(C.TEST_RIGHT)
		await _wait(tree, 0.2)
		ok = _chk(lines, body.velocity.x > 0.0, "3D %s: walks before the conversation" % manager) and ok
		C._talk(stub, true)
		await _wait(tree, 0.2)
		ok = _chk(lines, is_zero_approx(body.velocity.x), "3D %s: stands still while a conversation runs" % manager) and ok
		C._talk(stub, false)
		await _wait(tree, 0.2)
		ok = _chk(lines, body.velocity.x > 0.0, "3D %s: walks again once it ends" % manager) and ok
		mover.freeze_during_dialogue = false
		C._talk(stub, true)
		await _wait(tree, 0.2)
		ok = _chk(lines, body.velocity.x > 0.0, "3D %s: freeze_during_dialogue off keeps walking" % manager) and ok
		mover.freeze_during_dialogue = true
		C._talk(stub, false)
		Input.action_release(C.TEST_RIGHT)
		if stub.has_meta("cc_fake"):
			stub.queue_free()
		await _wait(tree, 0.3)

	# falling off an edge
	var perch: StaticBody3D = _box(host, Vector3(2.0, 0.5, 2.0), Vector3(-30, 2.75, 0))
	body.global_position = Vector3(-30, 3.02, 0)
	body.velocity = Vector3.ZERO
	await _wait(tree, 0.3)
	ok = _chk(lines, body.is_on_floor() and body.global_position.y > 2.9, "3D: it stands on a raised platform") and ok
	perch.free()
	await _wait(tree, 0.2)
	ok = _chk(lines, not body.is_on_floor() and body.velocity.y < 0.0, "3D: with the platform gone it falls") and ok
	await _wait(tree, 0.8)
	body.queue_free()
	await tree.physics_frame

	ok = await _camera_checks(host, lines) and ok
	ok = await _interaction_checks(host, lines) and ok

	ground.queue_free()
	C._controllers_lite().player = null
	await tree.physics_frame
	return {"ok": ok and not lines.any(func(l: String) -> bool: return l.begins_with("[XX]")), "lines": lines}


static func _camera_checks(host: Node, lines: Array[String]) -> bool:
	var ok: bool = true
	var tree: SceneTree = host.get_tree()
	var rig: Array = _player(host, Vector3(3, 0.02, 4))
	var tbody: CharacterBody3D = rig[0]
	var tmover: TopDownMoverLite3D = rig[1]
	tmover.world_relative = true
	await tree.physics_frame

	var cam: FollowCameraLite3D = FollowCameraLite3D.new()
	cam.follow_speed = 0.0
	cam.distance = 10.0
	cam.pitch = -45.0
	cam.yaw = 0.0
	host.add_child(cam)
	cam.make_current()
	await _wait(tree, 0.1)
	var focus: Vector3 = tbody.global_position + cam.target_offset
	var want: Vector3 = focus + Vector3(0, 10.0 * sin(deg_to_rad(45.0)), 10.0 * cos(deg_to_rad(45.0)))
	ok = _chk(lines, cam.global_position.distance_to(want) < 0.05, "3D camera: with no target set it finds the player and sits 10 m back at 45 degrees") and ok
	var aim: Vector3 = -cam.global_basis.z
	ok = _chk(lines, aim.dot((focus - cam.global_position).normalized()) > 0.999, "3D camera: and looks straight at it") and ok
	ok = _chk(lines, cam.get_viewport().get_camera_3d() == cam, "3D camera: it is the active camera") and ok

	cam.follow_speed = 4.0
	tbody.global_position = Vector3(4, 0.02, 4)    # 1 m: a walk, not a teleport
	await tree.physics_frame
	var gap: float = (tbody.global_position + cam.target_offset).distance_to(cam._focus)
	ok = _chk(lines, gap > 0.5 and gap < 1.0, "3D camera: a small move is followed smoothly, not snapped (gap %.2f)" % gap) and ok
	await _wait(tree, 2.0)
	ok = _chk(lines, (tbody.global_position + cam.target_offset).distance_to(cam._focus) < 0.05, "3D camera: and it catches up") and ok

	cam.follow_speed = 1.0
	tbody.global_position = Vector3(60, 0.02, 4)    # a door
	await tree.physics_frame
	ok = _chk(lines, (tbody.global_position + cam.target_offset).distance_to(cam._focus) < 0.01, "3D camera: a far teleport snaps instead of swooping") and ok
	# the way a checkpoint or a door really plays out: the camera ticks once at the
	# old spot, then the player is placed 4 m away
	await _wait(tree, 0.3)
	tbody.global_position += Vector3(4, 0, 0)
	await tree.physics_frame
	ok = _chk(lines, (tbody.global_position + cam.target_offset).distance_to(cam._focus) < 0.01, "3D camera: so does a 4 m one, well under the old 10 m") and ok
	await _wait(tree, 0.3)
	tmover.set_physics_process(false)    # so the mover does not brake the velocity set below
	tbody.velocity = Vector3(60, 0, 0)   # a sprint: 1 m a tick of its own
	tbody.global_position += Vector3(60.0 / float(Engine.physics_ticks_per_second) + 1.0, 0, 0)    # its own travel in a tick, plus 1 m
	await tree.physics_frame
	ok = _chk(lines, (tbody.global_position + cam.target_offset).distance_to(cam._focus) > 1.0, "3D camera: a fast move the target's speed explains is followed, not snapped") and ok
	tbody.velocity = Vector3.ZERO
	tmover.set_physics_process(true)
	cam.snap_distance = 100.0
	tbody.global_position = Vector3(-30, 0.02, 4)
	await tree.physics_frame
	ok = _chk(lines, (tbody.global_position + cam.target_offset).distance_to(cam._focus) > 30.0, "3D camera: snap_distance is the knob (raised, the same jump is followed)") and ok
	cam.snap_distance = 1.5

	# a player freed mid-game (death) must not break it, and a new one is picked up
	cam.follow_speed = 0.0
	await _wait(tree, 0.2)
	var parked: Vector3 = cam.global_position
	tbody.queue_free()
	await _wait(tree, 0.2)
	ok = _chk(lines, cam.global_position.is_equal_approx(parked), "3D camera: when the player is freed it stays where it was, without errors") and ok
	var rig2: Array = _player(host, Vector3(20, 0.02, 20))
	var body2: CharacterBody3D = rig2[0]
	await _wait(tree, 0.2)
	ok = _chk(lines, (body2.global_position + cam.target_offset).distance_to(cam._focus) < 0.05, "3D camera: and it follows the next player that registers") and ok
	body2.queue_free()
	await tree.physics_frame

	var pin: Node3D = Node3D.new()
	pin.position = Vector3(-7, 1, 2)
	host.add_child(pin)
	cam.target_path = cam.get_path_to(pin)
	cam._resolve_target()
	await _wait(tree, 0.1)
	ok = _chk(lines, (pin.global_position + cam.target_offset).distance_to(cam._focus) < 0.05, "3D camera: target_path follows that node instead of the player") and ok
	pin.queue_free()

	# a camera nobody can follow leaves its own placement alone
	var loner: FollowCameraLite3D = FollowCameraLite3D.new()
	loner.position = Vector3(7, 8, 9)
	C._controllers_lite().player = null
	host.add_child(loner)
	await _wait(tree, 0.1)
	ok = _chk(lines, loner.position.is_equal_approx(Vector3(7, 8, 9)), "3D camera: with nothing to follow it stays where you put it") and ok
	loner.queue_free()
	cam.queue_free()
	await tree.physics_frame
	return ok


static func _interaction_checks(host: Node, lines: Array[String]) -> bool:
	var ok: bool = true
	var tree: SceneTree = host.get_tree()
	var rig: Array = _player(host, Vector3.ZERO)
	var player: CharacterBody3D = rig[0]
	# it is steered by hand here, up in the air away from the floor
	var pm: TopDownMoverLite3D = rig[1]
	pm.gravity = 0.0
	pm.input_enabled = false
	player.global_position = Vector3(0, 5, 0)
	var reach: InteractorLite3D = InteractorLite3D.new()
	var rs: CollisionShape3D = CollisionShape3D.new()
	var ball: SphereShape3D = SphereShape3D.new()
	ball.radius = 1.0
	rs.shape = ball
	reach.add_child(rs)
	player.add_child(reach)
	var sign_ia: InteractableLite3D = InteractableLite3D.new()
	sign_ia.prompt_text = "Read"
	sign_ia.message = "Welcome to town."
	sign_ia.position = Vector3(20, 5, 0)
	var ss: CollisionShape3D = CollisionShape3D.new()
	var bx: BoxShape3D = BoxShape3D.new()
	bx.size = Vector3(1.5, 1.5, 1.5)
	ss.shape = bx
	sign_ia.add_child(ss)
	host.add_child(sign_ia)
	await C._settle(tree)
	var label: Label3D = sign_ia.get_node_or_null("Prompt") as Label3D
	ok = _chk(lines, label != null and not label.visible and label.get_owner() == null, "3D interact: the floating prompt waits out of reach, and is never owned by the scene") and ok
	player.global_position = Vector3(19, 5, 0)
	await C._settle(tree)
	ok = _chk(lines, label != null and label.visible and label.text == "E  Read", "3D interact: in reach it shows \"E  Read\" (got %s)" % (label.text if label != null else "no label")) and ok
	ok = _chk(lines, label != null and is_equal_approx(label.position.y, sign_ia.prompt_height), "3D interact: it floats prompt_height metres above the node") and ok
	C._clear_toasts(tree)
	C._press(KEY_E)
	await tree.process_frame
	await tree.process_frame
	ok = _chk(lines, C._toast_texts(tree) == PackedStringArray(["Welcome to town."]), "3D interact: pressing E shows the message, like 2D (got %s)" % str(C._toast_texts(tree))) and ok
	var talk: Node = C._dialogue_stub(tree.root, "DialoguesLite")
	if talk != null:
		C._talk(talk, true)
		C._clear_toasts(tree)
		C._press(KEY_E)
		await tree.process_frame
		await tree.process_frame
		ok = _chk(lines, C._toast_texts(tree).is_empty() and label != null and not label.visible, "3D interact: E does nothing and the prompt steps aside during a conversation") and ok
		C._talk(talk, false)
		await tree.process_frame
		C._press(KEY_E)
		await tree.process_frame
		await tree.process_frame
		ok = _chk(lines, C._toast_texts(tree) == PackedStringArray(["Welcome to town."]) and label != null and label.visible, "3D interact: and both come back when it ends") and ok
		if talk.has_meta("cc_fake"):
			talk.queue_free()
		C._clear_toasts(tree)
	# the prompt reads whatever key the Interactor's action is bound to
	if not InputMap.has_action(C.TEST_USE):
		InputMap.add_action(C.TEST_USE, 0.5)
		var f: InputEventKey = InputEventKey.new()
		f.physical_keycode = KEY_F
		InputMap.action_add_event(C.TEST_USE, f)
	reach.action = C.TEST_USE
	player.global_position = Vector3(0, 5, 0)
	await C._settle(tree)
	player.global_position = Vector3(19, 5, 0)
	await C._settle(tree)
	ok = _chk(lines, label != null and label.text == "F  Read", "3D interact: the prompt follows the key the action is bound to (got %s)" % (label.text if label != null else "no label")) and ok
	reach.action = &"interact"
	# turning the body swings the reach with it
	sign_ia.position = Vector3(19, 5, -4)
	reach.position = Vector3(0, 0, -3)
	await C._settle(tree)
	ok = _chk(lines, reach.current_focus() == sign_ia, "3D interact: a reach placed ahead of the body finds what is ahead") and ok
	player.rotation.y = PI
	await C._settle(tree)
	ok = _chk(lines, reach.current_focus() == null, "3D interact: and swings away when the body turns around") and ok
	player.rotation.y = 0.0
	await C._settle(tree)
	sign_ia.message = ""
	C._clear_toasts(tree)
	C._press(KEY_E)
	await tree.process_frame
	await tree.process_frame
	ok = _chk(lines, C._toast_texts(tree).is_empty(), "3D interact: an empty message shows nothing") and ok
	for n: Node in [player, sign_ia]:
		n.queue_free()
	C._clear_toasts(tree)
	await tree.physics_frame
	return ok


# ---- builders ---------------------------------------------------------------

static func _wire(m: TopDownMoverLite3D) -> void:
	m.action_left = C.TEST_LEFT
	m.action_right = C.TEST_RIGHT
	m.action_up = C.TEST_UP
	m.action_down = C.TEST_DOWN


static func _capsule() -> CollisionShape3D:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	return cs


# [body, mover], in the tree, on keyboard-only actions.
static func _player(host: Node, at: Vector3) -> Array:
	var body: CharacterBody3D = CharacterBody3D.new()
	body.add_child(_capsule())
	var mover: TopDownMoverLite3D = TopDownMoverLite3D.new()
	_wire(mover)
	body.add_child(mover)
	body.position = at
	host.add_child(body)
	return [body, mover]


static func _box(host: Node, size: Vector3, at: Vector3) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bx: BoxShape3D = BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	sb.add_child(cs)
	sb.position = at
	host.add_child(sb)
	return sb


# A slab rising toward +X at `degrees`, its top surface meeting the floor at x = start.
static func _ramp(host: Node, degrees: float, start: float) -> StaticBody3D:
	var length: float = 12.0
	var thick: float = 0.5
	var a: float = deg_to_rad(degrees)
	var along: Vector3 = Vector3(cos(a), sin(a), 0.0)
	var normal: Vector3 = Vector3(-sin(a), cos(a), 0.0)
	var sb: StaticBody3D = _box(host, Vector3(length, thick, 6.0), Vector3(start, 0.0, 0.0) - normal * thick * 0.5 + along * length * 0.5)
	sb.rotation.z = a
	return sb


## Wait in PHYSICS FRAMES, not on the wall clock: friction and gravity advance per
## physics step, and a timer promises no particular number of steps ran inside it.
static func _wait(tree: SceneTree, seconds: float) -> void:
	for i in int(ceil(seconds * float(Engine.physics_ticks_per_second))):
		await tree.physics_frame


# Counts the engine errors printed while it is installed.
class _ErrorCatcher extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
