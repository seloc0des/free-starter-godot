extends Node

# Headless test for Quests — Lite.
# Run: godot --headless --path . res://tools/quests_lite/verify.tscn

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- quests lite verify ---")
	await _run_register_and_state()
	await _run_collect_progresses()
	await _run_kill_progresses()
	await _run_completion_fires_once()
	await _run_objective_progressed_signature()
	await _run_stringname_id_normalization()
	# the no-code nodes, played in a running scene
	await _run_board_scene_start()
	await _run_board_touch()
	await _run_collect_target()
	await _run_kill_target()
	await _run_tracker()
	await _run_toasts()
	_wipe()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/quests_lite/acceptance_report.gd").new()
		get_tree().root.add_child(report)
		report.render(_passes, _failures, _log)


func _assert(cond: bool, msg: String) -> void:
	_log.append([cond, msg])
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# ---- helpers -------------------------------------------------------------

func _wipe() -> void:
	# Reset the autoload's internal state between tests.
	_quests_lite()._quests.clear()
	_quests_lite()._state.clear()
	_quests_lite()._progress.clear()


func _obj(id: String, type: int, target: String, required: int) -> QuestObjectiveLite:
	var o := QuestObjectiveLite.new()
	o.id = id
	o.type = type
	o.target_id = target
	o.required = required
	return o


func _quest(id: String, objectives: Array) -> QuestLite:
	var q := QuestLite.new()
	q.id = id
	q.title = id.capitalize()
	# QuestLite.objectives is typed Array[QuestObjectiveLite]; promote the
	# plain Array we got into the typed form so the assignment is legal.
	var typed: Array[QuestObjectiveLite] = []
	for o in objectives:
		typed.append(o)
	q.objectives = typed
	return q


# ---- tests ---------------------------------------------------------------

func _run_register_and_state() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("q1", [_obj("o1", QuestObjectiveLite.Type.COLLECT, "herb", 3)])
	_quests_lite().register(q)
	_assert(_quests_lite().is_registered("q1"), "Register: q1 known")
	_assert(_quests_lite().get_state("q1") == QUESTS_LITE.State.AVAILABLE, "Register: starts AVAILABLE")
	_assert(_quests_lite().start_quest("q1"), "Start: start_quest returns true")
	_assert(_quests_lite().is_active("q1"), "Start: now ACTIVE")
	_assert(not _quests_lite().start_quest("q1"), "Start: second start returns false")


func _run_collect_progresses() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("collect_test", [_obj("herb_o", QuestObjectiveLite.Type.COLLECT, "herb", 3)])
	_quests_lite().register(q)
	_quests_lite().start_quest("collect_test")
	_quests_lite().report_collect("herb", 2)
	_assert(_quests_lite().get_progress("collect_test", "herb_o") == 2, "Collect: progress 2 after first report")
	_quests_lite().report_collect("herb", 5)  # over-cap
	_assert(_quests_lite().get_progress("collect_test", "herb_o") == 3,
		"Collect: progress clamps at required (got %d)" % _quests_lite().get_progress("collect_test", "herb_o"))


func _run_kill_progresses() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("kill_test", [_obj("wolves", QuestObjectiveLite.Type.KILL, "wolf", 2)])
	_quests_lite().register(q)
	_quests_lite().start_quest("kill_test")
	_quests_lite().report_kill("wolf", 1)
	_quests_lite().report_kill("wolf", 1)
	_assert(_quests_lite().is_complete("kill_test"), "Kill: 2 wolves completes the quest")


func _run_completion_fires_once() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("done_test", [_obj("h", QuestObjectiveLite.Type.COLLECT, "herb", 1)])
	_quests_lite().register(q)
	_quests_lite().start_quest("done_test")
	var fired: Array = []
	var cb := func(qid: String):
		if qid == "done_test":
			fired.append(qid)
	_quests_lite().quest_completed.connect(cb)
	_quests_lite().report_collect("herb", 1)
	_quests_lite().report_collect("herb", 1)  # extra report after complete
	_quests_lite().quest_completed.disconnect(cb)
	_assert(fired.size() == 1, "Once: quest_completed fired exactly once (got %d)" % fired.size())


# Regression: objective_progressed was widened from 3 → 4 args to match the
# Pro signature (qid, oid, current, required). Lock that in.
func _run_objective_progressed_signature() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("sig_test", [_obj("h", QuestObjectiveLite.Type.COLLECT, "herb", 5)])
	_quests_lite().register(q)
	_quests_lite().start_quest("sig_test")
	var observations: Array = []
	var cb := func(qid: String, oid: String, current: int, required: int):
		observations.append([qid, oid, current, required])
	_quests_lite().objective_progressed.connect(cb)
	_quests_lite().report_collect("herb", 2)
	_quests_lite().objective_progressed.disconnect(cb)
	_assert(observations.size() == 1, "SigArgs: one progress event")
	if observations.size() == 1:
		var o = observations[0]
		_assert(o[2] == 2 and o[3] == 5,
			"SigArgs: emits (qid, oid, current=2, required=5). Got (%s, %s, %d, %d)" % o)


# Regression: objective ids stored as StringName used to silently miss the
# String-keyed _progress dict. Both forms must work after normalization.
func _run_stringname_id_normalization() -> void:
	await get_tree().process_frame
	_wipe()
	var o := QuestObjectiveLite.new()
	o.id = StringName("herb_o")  # StringName instead of String
	o.type = QuestObjectiveLite.Type.COLLECT
	o.target_id = "herb"
	o.required = 1
	var q := _quest("sn_test", [o])
	_quests_lite().register(q)
	_quests_lite().start_quest("sn_test")
	_quests_lite().report_collect("herb", 1)
	_assert(_quests_lite().get_progress("sn_test", "herb_o") == 1,
		"StringName: lookup by String works after normalization (got %d)" % _quests_lite().get_progress("sn_test", "herb_o"))
	_assert(_quests_lite().is_complete("sn_test"),
		"StringName: quest completes despite StringName objective id")


# ---- no-code nodes, end to end ---------------------------------------------
# Built the way the Setup tab leaves them, then played: bodies walk into areas,
# a Health says died, J gets pressed.

const TOAST := preload("res://addons/quests_lite/quest_toast_lite.gd")


func _body(pos: Vector2, is_player: bool) -> CharacterBody2D:
	var b := CharacterBody2D.new()
	b.name = "Player" if is_player else "Stranger"
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 8.0
	cs.shape = c
	b.add_child(cs)
	if is_player:
		b.add_to_group("player")
	b.position = pos
	return b


func _area(area_name: String, radius: float) -> Area2D:
	var a := Area2D.new()
	a.name = area_name
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	a.add_child(cs)
	return a


func _pickup(node_name: String, pos: Vector2, target: String) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.position = pos
	var t := QuestTargetLite.new()
	t.type = QuestTargetLite.Type.COLLECT
	t.target_id = target
	n.add_child(t)
	n.add_child(_area("PickupArea", 32.0))
	return n


# stands in for a Health node: all a kill target needs is the signal
func _died_script(with_arg := false) -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nsignal died%s\n" % ("(by)" if with_arg else "")
	s.reload()
	return s


func _physics(frames := 4) -> void:
	for i in frames:
		await get_tree().physics_frame


func _toasts() -> PackedStringArray:
	var out := PackedStringArray()
	for n in get_tree().get_nodes_in_group("lite_toast"):
		if n is Label and not n.is_queued_for_deletion():
			out.append((n as Label).text)
	return out


func _clear_toasts() -> void:
	for n in get_tree().get_nodes_in_group("lite_toast"):
		n.remove_from_group("lite_toast")
		n.get_parent().queue_free()


func _press_j() -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEY_J
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = KEY_J
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _run_board_scene_start() -> void:
	await get_tree().process_frame
	_wipe()
	_clear_toasts()
	var q := _quest("board_start", [_obj("h", QuestObjectiveLite.Type.COLLECT, "herb", 1)])
	q.title = "Board start"
	var scene := Node2D.new()
	var board := QuestBoardLite.new()
	board.quest = q
	board.start_mode = QuestBoardLite.StartMode.ON_SCENE_START
	scene.add_child(board)
	# negative control: a board with nothing picked registers nothing
	var empty := QuestBoardLite.new()
	scene.add_child(empty)
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_quests_lite().is_active("board_start"), "Board (scene start): the quest is active once the scene runs")
	_assert(_toasts().has("Quest started: Board start"), "Board (scene start): shows 'Quest started: Board start' (got %s)" % [_toasts()])
	_assert(_quests_lite().list_quests().size() == 1, "Board (scene start): a board with no quest picked adds nothing")
	scene.queue_free()


func _run_board_touch() -> void:
	await get_tree().process_frame
	_wipe()
	_clear_toasts()
	var q := _quest("board_touch", [_obj("h", QuestObjectiveLite.Type.COLLECT, "herb", 1)])
	q.title = "Board touch"
	var scene := Node2D.new()
	var npc := Node2D.new()
	npc.name = "NPC"
	var board := QuestBoardLite.new()
	board.quest = q
	board.start_mode = QuestBoardLite.StartMode.ON_PLAYER_TOUCH
	npc.add_child(board)
	npc.add_child(_area("QuestArea", 48.0))
	scene.add_child(npc)
	var stranger := _body(Vector2(900, 900), false)
	var player := _body(Vector2(-900, -900), true)
	scene.add_child(stranger)
	scene.add_child(player)
	add_child(scene)
	await _physics()
	_assert(_quests_lite().is_registered("board_touch") and not _quests_lite().is_active("board_touch"),
		"Board (touch): registered when the scene starts, then waits for the player")
	stranger.global_position = Vector2.ZERO
	await _physics()
	_assert(not _quests_lite().is_active("board_touch"), "Board (touch): a body that isn't the player doesn't start it")
	player.global_position = Vector2.ZERO
	await _physics()
	_assert(_quests_lite().is_active("board_touch"), "Board (touch): the player walking into the QuestArea starts it")
	_assert(_toasts().has("Quest started: Board touch"), "Board (touch): shows 'Quest started: Board touch'")
	scene.queue_free()


func _run_collect_target() -> void:
	await get_tree().process_frame
	_wipe()
	_clear_toasts()
	var q := _quest("gather", [_obj("herbs", QuestObjectiveLite.Type.COLLECT, "herb", 2)])
	_quests_lite().register(q)  # registered, not started yet
	var scene := Node2D.new()
	var herb1 := _pickup("Herb1", Vector2(200, 0), "herb")
	var herb2 := _pickup("Herb2", Vector2(400, 0), "herb")
	var stranger := _body(Vector2(900, 900), false)
	var player := _body(Vector2(-900, -900), true)
	for n in [herb1, herb2, stranger, player]:
		scene.add_child(n)
	add_child(scene)
	await _physics()
	player.global_position = herb1.global_position
	await _physics()
	_assert(is_instance_valid(herb1) and herb1.is_inside_tree() and _quests_lite().get_progress("gather", "herbs") == 0,
		"Collect: touching it before its quest is active leaves it lying there")
	# the player is still standing on it when the quest starts
	_quests_lite().start_quest("gather")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_quests_lite().get_progress("gather", "herbs") == 1, "Collect: starting the quest while the player stands on it counts it")
	_assert(not is_instance_valid(herb1), "Collect: ...and removes it")
	_assert(_toasts().has("+1 herb"), "Collect: shows '+1 herb' (got %s)" % [_toasts()])
	stranger.global_position = herb2.global_position
	await _physics()
	_assert(is_instance_valid(herb2) and _quests_lite().get_progress("gather", "herbs") == 1,
		"Collect: a body that isn't the player doesn't pick it up")
	player.global_position = herb2.global_position
	await _physics()
	await get_tree().process_frame
	_assert(_quests_lite().get_progress("gather", "herbs") == 2 and not is_instance_valid(herb2),
		"Collect: the player touching the second one counts it and removes it")
	_assert(_quests_lite().is_complete("gather"), "Collect: two herbs complete the quest")
	scene.queue_free()


func _run_kill_target() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("slay", [_obj("slimes", QuestObjectiveLite.Type.KILL, "slime", 3)])
	_quests_lite().register(q)
	_quests_lite().start_quest("slay")
	var scene := Node2D.new()
	# died on a Health under the enemy (the Combat pack's layout)
	var slime := Node2D.new()
	slime.name = "Slime"
	var health := Node.new()
	health.name = "Health"
	health.set_script(_died_script())
	slime.add_child(health)
	var t := QuestTargetLite.new()
	t.type = QuestTargetLite.Type.KILL
	t.target_id = "slime"
	slime.add_child(t)
	# died on the enemy itself, sent with an argument
	var boss := Node2D.new()
	boss.name = "Boss"
	boss.set_script(_died_script(true))
	var t2 := QuestTargetLite.new()
	t2.type = QuestTargetLite.Type.KILL
	t2.target_id = "slime"
	boss.add_child(t2)
	# negative control: something that dies with no QuestTarget on it
	var bystander := Node.new()
	bystander.set_script(_died_script())
	# and a kill target with nothing that can die: warns, never counts
	var dummy := Node2D.new()
	var t3 := QuestTargetLite.new()
	t3.type = QuestTargetLite.Type.KILL
	t3.target_id = "slime"
	dummy.add_child(t3)
	for n in [slime, boss, bystander, dummy]:
		scene.add_child(n)
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame  # the died hook is deferred
	bystander.emit_signal("died")
	_assert(_quests_lite().get_progress("slay", "slimes") == 0, "Kill: a died signal from something without a QuestTarget doesn't count")
	health.emit_signal("died")
	_assert(_quests_lite().get_progress("slay", "slimes") == 1, "Kill: the Health's died signal counts one")
	boss.emit_signal("died", null)
	_assert(_quests_lite().get_progress("slay", "slimes") == 2, "Kill: died on the enemy itself, with an argument, counts too")
	health.emit_signal("died")
	_assert(_quests_lite().is_complete("slay"), "Kill: the third one completes the quest")
	scene.queue_free()


func _run_tracker() -> void:
	await get_tree().process_frame
	_wipe()
	_clear_toasts()
	# the Setup tab puts quest_log on J; a game reads it at start
	var had_action := InputMap.has_action("quest_log")
	if not had_action:
		InputMap.add_action("quest_log")
		var j := InputEventKey.new()
		j.physical_keycode = KEY_J
		j.device = -1
		InputMap.action_add_event("quest_log", j)
	var q := _quest("track", [_obj("herbs", QuestObjectiveLite.Type.COLLECT, "herb", 2),
		_obj("slimes", QuestObjectiveLite.Type.KILL, "slime", 1)])
	q.title = "Track me"
	_quests_lite().register(q)
	var layer := CanvasLayer.new()
	var tracker := QuestTrackerLite.new()
	tracker.name = "QuestTracker"
	layer.add_child(tracker)
	add_child(layer)
	await get_tree().process_frame
	_assert(tracker.visible and tracker.get_text() == "", "Tracker: visible from the start, and empty with no active quest")
	_quests_lite().start_quest("track")
	await get_tree().process_frame
	var txt := tracker.get_text()
	_assert(txt.contains("Track me") and txt.contains("Collect herb 0/2") and txt.contains("Defeat slime 0/1"),
		"Tracker: lists the active quest and each objective (got %s)" % txt.replace("\n", " | "))
	_assert(txt.begins_with("Quests (J)"), "Tracker: its header names the key")
	_quests_lite().report_collect("herb", 1)
	await get_tree().process_frame
	_assert(tracker.get_text().contains("Collect herb 1/2"), "Tracker: progress updates to 1/2")
	_quests_lite().report_collect("herb", 1)
	await get_tree().process_frame
	_assert(tracker.get_text().contains("Collect herb 2/2  done"), "Tracker: a finished objective is marked done")
	_assert(_toasts().has("Collect herb 2/2 done"), "Tracker: shows 'Collect herb 2/2 done' (got %s)" % [_toasts()])
	await get_tree().process_frame
	var r := tracker.get_global_rect()
	var vp := tracker.get_viewport_rect().size
	_assert(r.size.x >= 300.0 and r.size.y > 40.0, "Tracker: it has a real size (%s)" % r.size)
	_assert(absf(r.end.x - (vp.x - 16.0)) < 1.0 and absf(r.position.y - 16.0) < 1.0,
		"Tracker: sits at the top right, 16 px in (%s in %s)" % [r, vp])
	_quests_lite().report_kill("slime", 1)
	await get_tree().process_frame
	_assert(tracker.get_text().contains("Track me: complete"), "Tracker: the finished quest stays on it, marked complete")
	_assert(_toasts().has("Quest complete: Track me"), "Tracker: shows 'Quest complete: Track me'")
	_assert(not _toasts().has("Defeat slime 1/1 done"), "Tracker: no separate objective message when it finishes the quest")
	await _press_j()
	_assert(not tracker.visible, "Tracker: J hides it")
	await _press_j()
	_assert(tracker.visible, "Tracker: J shows it again")
	# a long list scrolls instead of running down the screen
	for i in 12:
		var extra := _quest("extra_%d" % i, [_obj("o", QuestObjectiveLite.Type.COLLECT, "stone", 5)])
		_quests_lite().register(extra)
		_quests_lite().start_quest("extra_%d" % i)
	await get_tree().process_frame
	var scroll: ScrollContainer = tracker.find_children("*", "ScrollContainer", true, false)[0]
	var list: Control = scroll.get_child(0)
	_assert(tracker.size.y < 320.0 and list.size.y > scroll.size.y + 100.0,
		"Tracker: a long list scrolls inside a capped height (%d tall, list %d)" % [tracker.size.y, list.size.y])
	# negative control: no quest_log action, and J does nothing (and doesn't error)
	var events := InputMap.action_get_events("quest_log")
	InputMap.erase_action("quest_log")
	await _press_j()
	_assert(tracker.visible, "Tracker: without the quest_log action J does nothing")
	if had_action:
		InputMap.add_action("quest_log")
		for e in events:
			InputMap.action_add_event("quest_log", e)
	layer.queue_free()


func _run_toasts() -> void:
	await get_tree().process_frame
	_clear_toasts()
	TOAST.show_toast(self, "first")
	TOAST.show_toast(self, "second")
	var labels: Array = []
	for n in get_tree().get_nodes_in_group("lite_toast"):
		labels.append(n)
	_assert(labels.size() == 2, "Toasts: both messages show")
	if labels.size() == 2:
		var a: Control = labels[0]
		var b: Control = labels[1]
		_assert(b.get_global_rect().position.y >= a.get_global_rect().end.y,
			"Toasts: the second sits below the first (%s / %s)" % [a.get_global_rect(), b.get_global_rect()])
		_assert(a.get_parent() is CanvasLayer and (a.get_parent() as CanvasLayer).layer == 100, "Toasts: on a CanvasLayer at layer 100")
	# negative control: show_messages off, no toast
	_wipe()
	_clear_toasts()
	var q := _quest("quiet", [_obj("h", QuestObjectiveLite.Type.COLLECT, "herb", 1)])
	var board := QuestBoardLite.new()
	board.quest = q
	board.show_messages = false
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_quests_lite().is_active("quiet") and _toasts().is_empty(), "Toasts: show_messages off starts the quest without one")
	board.queue_free()
	TOAST.show_toast(self, "gone")
	await get_tree().create_timer(TOAST.LIFE + 0.3).timeout
	_assert(not _toasts().has("gone"), "Toasts: a toast frees itself after about 2 seconds")


# QuestsLite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const QUESTS_LITE := preload("res://addons/quests_lite/quest_manager_lite.gd")


static func _quests_lite() -> QUESTS_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"QuestsLite") as QUESTS_LITE
