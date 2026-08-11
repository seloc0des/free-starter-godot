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
	DialoguesLite.line_shown.connect(on_line)
	DialoguesLite.event_fired.connect(on_event)
	DialoguesLite.dialogue_finished.connect(on_finish)

	DialoguesLite.register(DEMO.healer_intro())

	ok = _chk(lines, DialoguesLite.start("healer_intro"), "start() returns true") and ok
	ok = _chk(lines, shown.size() == 1, "1 line shown at entry (n1)") and ok
	DialoguesLite.choose(0)                                  # -> n2 (fires event)
	ok = _chk(lines, events.size() == 1 and events[0] == "give_quest:gather_herbs", "event fired on n2") and ok
	ok = _chk(lines, shown.size() == 2, "2 lines after choose") and ok
	DialoguesLite.advance()                                  # -> n3
	ok = _chk(lines, shown.size() == 3, "3 lines after advance") and ok
	DialoguesLite.advance()                                  # empty next -> finish
	ok = _chk(lines, finished["id"] == "healer_intro", "finished with correct id") and ok
	ok = _chk(lines, not DialoguesLite.is_active(), "inactive after finish") and ok

	DialoguesLite.line_shown.disconnect(on_line)
	DialoguesLite.event_fired.disconnect(on_event)
	DialoguesLite.dialogue_finished.disconnect(on_finish)

	lines.append("")
	lines.append("--- transcript ---")
	for l in shown:
		lines.append("  " + l)

	return {"ok": ok, "lines": lines}


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
