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
	_controllers_lite().movement_locked_changed.connect(on_lock)
	_controllers_lite().lock_movement(&"dialogue")
	_controllers_lite().lock_movement(&"cutscene")
	ok = _chk(lines, _controllers_lite().is_locked(), "two locks -> locked") and ok
	_controllers_lite().unlock_movement(&"dialogue")
	ok = _chk(lines, _controllers_lite().is_locked(), "one released -> still locked") and ok
	_controllers_lite().unlock_movement(&"cutscene")
	ok = _chk(lines, not _controllers_lite().is_locked(), "both released -> unlocked") and ok
	ok = _chk(lines, lock_events == [true, false], "lock signal fired exactly twice") and ok
	_controllers_lite().movement_locked_changed.disconnect(on_lock)

	# --- player registration ---
	var body := CharacterBody2D.new()
	var mover := TopDownMoverLite.new()
	body.add_child(mover)
	host.add_child(body)
	ok = _chk(lines, _controllers_lite().player == body, "mover registers its body as THE player") and ok
	ok = _chk(lines, body.is_in_group("player"), "player body joined the 'player' group") and ok

	# --- interactable: bus mirror + one_shot ---
	var seen := {"count": 0, "event": &""}
	var on_int := func(ia: Node, _by: Node) -> void:
		seen["count"] += 1
		seen["event"] = ia.get("event")
	_controllers_lite().interacted.connect(on_int)
	var sign_ia := InteractableLite.new()
	sign_ia.event = &"sign_read"
	sign_ia.one_shot = true
	host.add_child(sign_ia)
	sign_ia.interact(body)
	sign_ia.interact(body)
	ok = _chk(lines, seen["count"] == 1, "one_shot interactable fires once") and ok
	ok = _chk(lines, seen["event"] == &"sign_read", "event string mirrored on the bus") and ok
	_controllers_lite().interacted.disconnect(on_int)

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

	# Keyboard-only stand-ins for the movement actions.
	#
	# The real actions carry a left-stick binding, and so do Godot's own ui_left
	# and ui_right, which these checks used before. If a physical controller is
	# plugged into the machine running this, its stick drifts a little, that
	# drift blends into get_axis, and the body never quite brakes to zero. The
	# check then fails on a pack that is working perfectly, about half the time.
	# All four directions: get_vector reads up and down too, and a stick pushed
	# up or down still bent the path so the body hadn't braked in time.
	_isolate_actions()

	var td_body := CharacterBody2D.new()
	var td := TopDownMoverLite.new()
	td.action_left = TEST_LEFT
	td.action_right = TEST_RIGHT
	td.action_up = TEST_UP
	td.action_down = TEST_DOWN
	td.speed = 100.0
	td_body.add_child(td)
	host.add_child(td_body)
	Input.action_press(TEST_RIGHT)
	await tree.physics_frame
	await tree.physics_frame
	ok = _chk(lines, td_body.velocity.x > 0.0, "held right -> moving right") and ok
	_controllers_lite().lock_movement(&"test")
	await tree.physics_frame
	await tree.physics_frame
	ok = _chk(lines, is_zero_approx(td_body.velocity.x), "movement lock zeroes velocity") and ok
	_controllers_lite().unlock_movement(&"test")
	td.friction = 200.0
	td.acceleration = 400.0
	await tree.physics_frame
	await tree.physics_frame
	var ramping: float = td_body.velocity.x
	ok = _chk(lines, ramping > 0.0 and ramping < 100.0, "acceleration ramps instead of snapping") and ok
	Input.action_release(TEST_RIGHT)
	# Physics frames, not the wall clock. Friction advances per physics step and
	# a timer promises no particular number of steps ran inside it.
	for i in int(ceil(0.8 * float(Engine.physics_ticks_per_second))):
		await tree.physics_frame
	ok = _chk(lines, is_zero_approx(td_body.velocity.x), "friction brakes to a stop") and ok
	td_body.queue_free()

	# --- stands still while a Dialogue conversation runs, Lite or Pro ---
	for manager in ["DialoguesLite", "DialogueManager"]:
		var stub: Node = _dialogue_stub(tree.root, manager)
		if stub == null:
			continue  # a real one we can't drive is installed; its own pack tests it
		var fb := CharacterBody2D.new()
		var fm := TopDownMoverLite.new()
		fm.action_left = TEST_LEFT
		fm.action_right = TEST_RIGHT
		fm.action_up = TEST_UP
		fm.action_down = TEST_DOWN
		fm.speed = 100.0
		fb.add_child(fm)
		host.add_child(fb)
		Input.action_press(TEST_RIGHT)
		await tree.physics_frame
		await tree.physics_frame
		ok = _chk(lines, fb.velocity.x > 0.0, "%s: walks before the conversation" % manager) and ok
		_talk(stub, true)
		await tree.physics_frame
		await tree.physics_frame
		ok = _chk(lines, is_zero_approx(fb.velocity.x), "%s: stands still while a conversation runs" % manager) and ok
		_talk(stub, false)
		await tree.physics_frame
		await tree.physics_frame
		ok = _chk(lines, fb.velocity.x > 0.0, "%s: walks again once it ends" % manager) and ok
		fm.freeze_during_dialogue = false
		_talk(stub, true)
		await tree.physics_frame
		await tree.physics_frame
		ok = _chk(lines, fb.velocity.x > 0.0, "%s: freeze_during_dialogue off keeps walking" % manager) and ok
		_talk(stub, false)
		Input.action_release(TEST_RIGHT)
		fb.queue_free()
		if stub.has_meta("cc_fake"):
			stub.queue_free()
		await tree.physics_frame

	return {"ok": ok, "lines": lines}


# Async: the prompt above an interactable in reach, and its message on use, fed
# real physics overlaps and a real key press.
static func run_interaction(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree: SceneTree = host.get_tree()

	var player := CharacterBody2D.new()
	host.add_child(player)
	var reach := InteractorLite.new()
	_box(reach, Vector2(48, 48))
	player.add_child(reach)
	var sign_ia := InteractableLite.new()
	sign_ia.prompt_text = "Read"
	sign_ia.message = "Welcome to town."
	sign_ia.position = Vector2(400, 0)
	_box(sign_ia, Vector2(40, 40))
	host.add_child(sign_ia)
	await _settle(tree)
	var label: Label = sign_ia.get_node_or_null("Prompt") as Label
	ok = _chk(lines, label != null and not label.visible, "prompt: hidden while the player is out of reach") and ok
	player.global_position = Vector2(370, 0)
	await _settle(tree)
	ok = _chk(lines, label != null and label.visible and label.text == "E  Read", "prompt: shows \"E  Read\" once the player is in reach (got %s)" % (label.text if label != null else "no label")) and ok
	ok = _chk(lines, label != null and label.position.y + label.size.y <= -20.0, "prompt: sits above the interactable's shape") and ok
	_clear_toasts(tree)
	_press(KEY_E)
	await tree.process_frame
	await tree.process_frame
	ok = _chk(lines, _toast_texts(tree) == PackedStringArray(["Welcome to town."]), "message: pressing E shows it on screen (got %s)" % str(_toast_texts(tree))) and ok
	# mid-conversation E mustn't start anything; once it ends, E works again
	var talk: Node = _dialogue_stub(tree.root, "DialoguesLite")
	if talk != null:
		_talk(talk, true)
		_clear_toasts(tree)
		_press(KEY_E)
		await tree.process_frame
		await tree.process_frame
		ok = _chk(lines, _toast_texts(tree).is_empty(), "interact: E does nothing while a conversation is on screen (got %s)" % str(_toast_texts(tree))) and ok
		ok = _chk(lines, label != null and not label.visible, "prompt: hidden while a conversation is on screen") and ok
		_talk(talk, false)
		_press(KEY_E)
		await tree.process_frame
		await tree.process_frame
		ok = _chk(lines, _toast_texts(tree) == PackedStringArray(["Welcome to town."]), "interact: E works again once the conversation ends") and ok
		ok = _chk(lines, label != null and label.visible, "prompt: back once it ends") and ok
		if talk.has_meta("cc_fake"):
			talk.queue_free()
		_clear_toasts(tree)
	# the prompt reads whatever key the Interactor's action is bound to
	if not InputMap.has_action(TEST_USE):
		InputMap.add_action(TEST_USE, 0.5)
		var f := InputEventKey.new()
		f.physical_keycode = KEY_F
		InputMap.action_add_event(TEST_USE, f)
	reach.action = TEST_USE
	player.global_position = Vector2.ZERO
	await _settle(tree)
	ok = _chk(lines, label != null and not label.visible, "prompt: hides again when the player walks away") and ok
	player.global_position = Vector2(370, 0)
	await _settle(tree)
	ok = _chk(lines, label != null and label.text == "F  Read", "prompt: follows the key the action is bound to (got %s)" % (label.text if label != null else "no label")) and ok
	# no message typed: using it shows nothing
	sign_ia.message = ""
	_clear_toasts(tree)
	_press(KEY_F)
	await tree.process_frame
	await tree.process_frame
	ok = _chk(lines, _toast_texts(tree).is_empty(), "message: an empty message shows nothing") and ok
	# the player leaving the scene takes its prompt with it
	player.queue_free()
	await tree.process_frame
	ok = _chk(lines, label != null and not label.visible, "prompt: a freed player doesn't leave it hanging") and ok
	sign_ia.queue_free()
	_clear_toasts(tree)
	return {"ok": ok, "lines": lines}


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond


const TEST_LEFT := &"__cc_test_left"
const TEST_RIGHT := &"__cc_test_right"
const TEST_UP := &"__cc_test_up"
const TEST_DOWN := &"__cc_test_down"
const TEST_USE := &"__cc_test_use"


# Stands in for a Dialogue autoload in a project that doesn't have one.
class _FakeDialogue extends Node:
	var active := false
	func is_active() -> bool:
		return active


# The node the mover will find at /root/<manager_name>: a stand-in when there's
# none, or a real Dialogue manager, driven through the field its is_active() reads.
static func _dialogue_stub(root: Node, manager_name: String) -> Node:
	var real := root.get_node_or_null(manager_name)
	if real != null:
		return real if "_active_id" in real else null
	var fake := _FakeDialogue.new()
	fake.name = manager_name
	fake.set_meta("cc_fake", true)
	root.add_child(fake)
	return fake


static func _talk(stub: Node, on: bool) -> void:
	if stub.has_meta("cc_fake"):
		stub.set("active", on)
	else:
		stub.set("_active_id", "cc_probe" if on else "")


static func _box(area: Node, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	area.add_child(cs)


static func _settle(tree: SceneTree) -> void:
	for i in 4:
		await tree.physics_frame


static func _press(code: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = code
	Input.parse_input_event(up)


static func _toast_texts(tree: SceneTree) -> PackedStringArray:
	var out := PackedStringArray()
	for t in tree.get_nodes_in_group("lite_toast"):
		if not t.is_queued_for_deletion():
			out.append(String(t.get("text")))
	return out


static func _clear_toasts(tree: SceneTree) -> void:
	for t in tree.get_nodes_in_group("lite_toast"):
		t.get_parent().free()


## Keyboard-only actions the physics checks drive, so a controller plugged into
## the machine cannot reach them. The default action names have their own check.
static func _isolate_actions() -> void:
	for pair in [[TEST_LEFT, KEY_LEFT], [TEST_RIGHT, KEY_RIGHT], [TEST_UP, KEY_UP], [TEST_DOWN, KEY_DOWN]]:
		if InputMap.has_action(pair[0]):
			continue
		InputMap.add_action(pair[0], 0.5)
		var k := InputEventKey.new()
		k.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], k)


# ControllersLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const CONTROLLERS_LITE := preload("res://addons/controller_lite/controllers_bus_lite.gd")


static func _controllers_lite() -> CONTROLLERS_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"ControllersLite") as CONTROLLERS_LITE
