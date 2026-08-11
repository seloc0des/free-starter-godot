extends RefCounted

# Shared checks for Controller — Lite, used by the headless verify and the
# acceptance banner. `host` must be in the SceneTree (node _ready wiring +
# physics frames). Everything explicitly typed — Lite verifies run strict.

static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true

	# --- bus: reason-counted movement locks ---
	var lock_events: Array = []
	var on_lock := func(locked: bool) -> void: lock_events.append(locked)
	ControllersLite.movement_locked_changed.connect(on_lock)
	ControllersLite.lock_movement(&"dialogue")
	ControllersLite.lock_movement(&"cutscene")
	ok = _chk(lines, ControllersLite.is_locked(), "two locks -> locked") and ok
	ControllersLite.unlock_movement(&"dialogue")
	ok = _chk(lines, ControllersLite.is_locked(), "one released -> still locked") and ok
	ControllersLite.unlock_movement(&"cutscene")
	ok = _chk(lines, not ControllersLite.is_locked(), "both released -> unlocked") and ok
	ok = _chk(lines, lock_events == [true, false], "lock signal fired exactly twice") and ok
	ControllersLite.movement_locked_changed.disconnect(on_lock)

	# --- player registration ---
	var body := CharacterBody2D.new()
	var mover := TopDownMoverLite.new()
	body.add_child(mover)
	host.add_child(body)
	ok = _chk(lines, ControllersLite.player == body, "mover registers its body as THE player") and ok
	ok = _chk(lines, body.is_in_group("player"), "player body joined the 'player' group") and ok

	# --- interactable: bus mirror + one_shot ---
	var seen := {"count": 0, "event": &""}
	var on_int := func(ia: Node, _by: Node) -> void:
		seen["count"] += 1
		seen["event"] = ia.get("event")
	ControllersLite.interacted.connect(on_int)
	var sign_ia := InteractableLite.new()
	sign_ia.event = &"sign_read"
	sign_ia.one_shot = true
	host.add_child(sign_ia)
	sign_ia.interact(body)
	sign_ia.interact(body)
	ok = _chk(lines, seen["count"] == 1, "one_shot interactable fires once") and ok
	ok = _chk(lines, seen["event"] == &"sign_read", "event string mirrored on the bus") and ok
	ControllersLite.interacted.disconnect(on_int)

	# --- interactor: nearest focus, used one_shot loses focus ---
	var interactor := InteractorLite.new()
	interactor.global_position = Vector2.ZERO
	host.add_child(interactor)
	var near := InteractableLite.new()
	near.global_position = Vector2(10, 0)
	near.one_shot = true
	var far := InteractableLite.new()
	far.global_position = Vector2(100, 0)
	host.add_child(near)
	host.add_child(far)
	interactor._on_area_entered(far)
	interactor._on_area_entered(near)
	ok = _chk(lines, interactor.current_focus() == near, "focus picks the nearest interactable") and ok
	interactor.interact()
	interactor._refresh_focus()
	ok = _chk(lines, interactor.current_focus() == far, "a used one_shot loses focus") and ok

	# --- save contract roundtrip ---
	body.global_position = Vector2(42, 24)
	var snap: Dictionary = mover.save_state()
	body.global_position = Vector2(999, 999)
	mover.load_state(snap)
	ok = _chk(lines, body.global_position.is_equal_approx(Vector2(42, 24)), "save/load restores position") and ok

	for n in [body, sign_ia, interactor, near, far]:
		n.queue_free()

	return {"ok": ok, "lines": lines}


# Async: movement over physics frames.
static func run_physics(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree: SceneTree = host.get_tree()

	var td_body := CharacterBody2D.new()
	var td := TopDownMoverLite.new()
	td.speed = 100.0
	td_body.add_child(td)
	host.add_child(td_body)
	Input.action_press(&"ui_right")
	await tree.physics_frame
	await tree.physics_frame
	ok = _chk(lines, td_body.velocity.x > 0.0, "held right -> moving right") and ok
	ControllersLite.lock_movement(&"test")
	await tree.physics_frame
	await tree.physics_frame
	ok = _chk(lines, is_zero_approx(td_body.velocity.x), "movement lock zeroes velocity") and ok
	ControllersLite.unlock_movement(&"test")
	td.friction = 200.0
	td.acceleration = 400.0
	await tree.physics_frame
	await tree.physics_frame
	var ramping: float = td_body.velocity.x
	ok = _chk(lines, ramping > 0.0 and ramping < 100.0, "acceleration ramps instead of snapping") and ok
	Input.action_release(&"ui_right")
	await tree.create_timer(0.8, true, false, true).timeout
	await tree.physics_frame
	ok = _chk(lines, is_zero_approx(td_body.velocity.x), "friction brakes to a stop") and ok
	td_body.queue_free()

	return {"ok": ok, "lines": lines}


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
