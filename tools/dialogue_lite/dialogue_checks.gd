extends RefCounted

# Shared checks for Dialogue — Lite, used by both the headless verify and the
# on-screen acceptance banner. Drives the manager through a full conversation
# (branch + event + advance to end) and asserts the signal contract.

const DEMO := preload("res://tools/dialogue_lite/demo/demo_dialogue.gd")


static func run(_host: Node) -> Dictionary:
	var lines: Array[String] = []
	var shown: Array[String] = []
	var events: Array[String] = []
	var finished := {"id": ""}
	var ok := true

	var on_line := func(s: String, t: String) -> void: shown.append(s + ": " + t)
	var on_event := func(e: String) -> void: events.append(e)
	var on_finish := func(id: String) -> void: finished["id"] = id
	_dialogues_lite().line_shown.connect(on_line)
	_dialogues_lite().event_fired.connect(on_event)
	_dialogues_lite().dialogue_finished.connect(on_finish)

	_dialogues_lite().register(DEMO.healer_intro())

	ok = _chk(lines, _dialogues_lite().start("healer_intro"), "start() returns true") and ok
	ok = _chk(lines, shown.size() == 1, "1 line shown at entry (n1)") and ok
	_dialogues_lite().choose(0)                                  # -> n2 (fires event)
	ok = _chk(lines, events.size() == 1 and events[0] == "give_quest:gather_herbs", "event fired on n2") and ok
	ok = _chk(lines, shown.size() == 2, "2 lines after choose") and ok
	_dialogues_lite().advance()                                  # -> n3
	ok = _chk(lines, shown.size() == 3, "3 lines after advance") and ok
	_dialogues_lite().advance()                                  # empty next -> finish
	ok = _chk(lines, finished["id"] == "healer_intro", "finished with correct id") and ok
	ok = _chk(lines, not _dialogues_lite().is_active(), "inactive after finish") and ok

	_dialogues_lite().line_shown.disconnect(on_line)
	_dialogues_lite().event_fired.disconnect(on_event)
	_dialogues_lite().dialogue_finished.disconnect(on_finish)

	lines.append("")
	lines.append("--- transcript ---")
	for l in shown:
		lines.append("  " + l)

	return {"ok": ok, "lines": lines}


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond


# DialoguesLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const DIALOGUES_LITE := preload("res://addons/dialogue_lite/dialogue_manager_lite.gd")


static func _dialogues_lite() -> DIALOGUES_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"DialoguesLite") as DIALOGUES_LITE
