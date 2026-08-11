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
	QuestsLite._quests.clear()
	QuestsLite._state.clear()
	QuestsLite._progress.clear()


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
	QuestsLite.register(q)
	_assert(QuestsLite.is_registered("q1"), "Register: q1 known")
	_assert(QuestsLite.get_state("q1") == QuestsLite.State.AVAILABLE, "Register: starts AVAILABLE")
	_assert(QuestsLite.start_quest("q1"), "Start: start_quest returns true")
	_assert(QuestsLite.is_active("q1"), "Start: now ACTIVE")
	_assert(not QuestsLite.start_quest("q1"), "Start: second start returns false")


func _run_collect_progresses() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("collect_test", [_obj("herb_o", QuestObjectiveLite.Type.COLLECT, "herb", 3)])
	QuestsLite.register(q)
	QuestsLite.start_quest("collect_test")
	QuestsLite.report_collect("herb", 2)
	_assert(QuestsLite.get_progress("collect_test", "herb_o") == 2, "Collect: progress 2 after first report")
	QuestsLite.report_collect("herb", 5)  # over-cap
	_assert(QuestsLite.get_progress("collect_test", "herb_o") == 3,
		"Collect: progress clamps at required (got %d)" % QuestsLite.get_progress("collect_test", "herb_o"))


func _run_kill_progresses() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("kill_test", [_obj("wolves", QuestObjectiveLite.Type.KILL, "wolf", 2)])
	QuestsLite.register(q)
	QuestsLite.start_quest("kill_test")
	QuestsLite.report_kill("wolf", 1)
	QuestsLite.report_kill("wolf", 1)
	_assert(QuestsLite.is_complete("kill_test"), "Kill: 2 wolves completes the quest")


func _run_completion_fires_once() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("done_test", [_obj("h", QuestObjectiveLite.Type.COLLECT, "herb", 1)])
	QuestsLite.register(q)
	QuestsLite.start_quest("done_test")
	var fired: Array = []
	var cb := func(qid: String):
		if qid == "done_test":
			fired.append(qid)
	QuestsLite.quest_completed.connect(cb)
	QuestsLite.report_collect("herb", 1)
	QuestsLite.report_collect("herb", 1)  # extra report after complete
	QuestsLite.quest_completed.disconnect(cb)
	_assert(fired.size() == 1, "Once: quest_completed fired exactly once (got %d)" % fired.size())


# Regression: objective_progressed was widened from 3 → 4 args to match the
# Pro signature (qid, oid, current, required). Lock that in.
func _run_objective_progressed_signature() -> void:
	await get_tree().process_frame
	_wipe()
	var q := _quest("sig_test", [_obj("h", QuestObjectiveLite.Type.COLLECT, "herb", 5)])
	QuestsLite.register(q)
	QuestsLite.start_quest("sig_test")
	var observations: Array = []
	var cb := func(qid: String, oid: String, current: int, required: int):
		observations.append([qid, oid, current, required])
	QuestsLite.objective_progressed.connect(cb)
	QuestsLite.report_collect("herb", 2)
	QuestsLite.objective_progressed.disconnect(cb)
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
	QuestsLite.register(q)
	QuestsLite.start_quest("sn_test")
	QuestsLite.report_collect("herb", 1)
	_assert(QuestsLite.get_progress("sn_test", "herb_o") == 1,
		"StringName: lookup by String works after normalization (got %d)" % QuestsLite.get_progress("sn_test", "herb_o"))
	_assert(QuestsLite.is_complete("sn_test"),
		"StringName: quest completes despite StringName objective id")
