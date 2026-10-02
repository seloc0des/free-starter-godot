class_name QuestTrackerLite
extends PanelContainer

# The small quest list at the top right: every active quest with its objectives
# ("Collect herb 1/3"), and a quest finished while it's up stays on it marked
# complete. The quest_log key (J) hides and shows it. Plain on purpose, text on
# the default theme; Pro has the full QuestLogUI with tabs.

const TOAST := preload("res://addons/quests_lite/quest_toast_lite.gd")
const OBJECTIVE := preload("res://addons/quests_lite/quest_objective_lite.gd")
const WIDTH := 360.0
const MARGIN := 16.0
const MAX_LIST_HEIGHT := 240.0  # past this the list scrolls
const DIM := Color(0.7, 0.72, 0.76)
const DONE := Color(0.55, 0.9, 0.55)

## The input action that hides and shows it. The Quests · Setup tab adds
## quest_log on J.
@export var toggle_action: StringName = &"quest_log"
## Shows "Quest complete: <title>" and finished objectives at the top of the screen.
@export var show_messages := true

var _box: VBoxContainer
var _title: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _done_here: Array[String] = []
var _warned_action := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # a HUD, so clicks go through to the game
	if _unplaced():
		place()
	_build()
	var qm := get_node_or_null("/root/QuestsLite")
	if qm == null:
		push_warning("QuestTrackerLite '%s': the QuestsLite autoload isn't running. Turn on Quests (Lite) in Project Settings > Plugins." % name)
	else:
		qm.connect("quest_started", _on_changed.unbind(1))
		qm.connect("objective_progressed", _on_changed.unbind(4))
		qm.connect("objective_completed", _on_objective_completed)
		qm.connect("quest_completed", _on_quest_completed)
	refresh()


## Top right, 360 wide, as tall as its list. The Setup tab does this for you;
## this is for one added by hand.
func place() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -WIDTH - MARGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN
	grow_horizontal = Control.GROW_DIRECTION_BEGIN


## Rebuild the list from QuestsLite. Runs on every quest signal.
func refresh() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var shown := 0
	var qm := get_node_or_null("/root/QuestsLite")
	if qm != null:
		for q in qm.list_quests():
			var qid := String(q.id)
			if qm.is_active(qid):
				_row(_quest_title(q), Color.WHITE)
				for o in q.objectives:
					if o == null:
						continue
					var have := int(qm.get_progress(qid, String(o.id)))
					var need := int(o.required)
					if have >= need:
						_row("   %s %d/%d  done" % [objective_label(o), have, need], DONE)
					else:
						_row("   %s %d/%d" % [objective_label(o), have, need], DIM)
				shown += 1
			elif qm.is_complete(qid) and _done_here.has(qid):
				_row("%s: complete" % _quest_title(q), DONE)
				shown += 1
	var key := _key_name()
	_title.text = "Quests (%s)" % key if key != "" else "Quests"
	# nothing to track: draw nothing, but stay "open" so J still means something later
	_box.visible = shown > 0
	self_modulate.a = 1.0 if shown > 0 else 0.0
	var list_h := _rows.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = minf(list_h, MAX_LIST_HEIGHT)
	# only grab the mouse wheel when there's something to scroll
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if list_h > MAX_LIST_HEIGHT else Control.MOUSE_FILTER_IGNORE


## Everything it shows, one line each. Handy for tests.
func get_text() -> String:
	if _box == null or not _box.visible:
		return ""
	var lines := PackedStringArray([_title.text])
	for c in _rows.get_children():
		if c is Label and not c.is_queued_for_deletion():
			lines.append((c as Label).text.strip_edges())
	return "\n".join(lines)


## "Collect herb" / "Defeat slime". The Setup tab's objective list uses it too.
static func objective_label(o: Resource) -> String:
	var what := String(o.get("target_id")).replace("_", " ").strip_edges()
	if int(o.get("type")) == OBJECTIVE.Type.KILL:
		return "Defeat %s" % (what if what != "" else "enemy")
	return "Collect %s" % (what if what != "" else "item")


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or toggle_action == &"":
		return
	# a missing action makes is_action_pressed() print an engine error on every
	# event, mouse motion included, so warn once instead
	if not InputMap.has_action(toggle_action):
		if not _warned_action:
			_warned_action = true
			push_warning("QuestTrackerLite '%s': there's no \"%s\" input action, so no key hides or shows it. Apply any outcome in the Quests · Setup tab to add it on J." % [name, toggle_action])
		return
	if event.is_action_pressed(toggle_action):
		visible = not visible


func _build() -> void:
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_title = Label.new()
	_box.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_rows)


func _row(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # long names can't widen the panel
	_rows.add_child(l)


func _on_changed() -> void:
	refresh()


func _on_objective_completed(quest_id: String, objective_id: String) -> void:
	refresh()
	if not show_messages:
		return
	var qm := get_node_or_null("/root/QuestsLite")
	var q: Resource = _find_quest(qm, quest_id)
	if q == null:
		return
	# the last one finishes the quest, and "Quest complete" says it better
	var all_done := true
	var label := ""
	for o in q.get("objectives"):
		if o == null:
			continue
		var have := int(qm.get_progress(quest_id, String(o.id)))
		if have < int(o.required):
			all_done = false
		if String(o.id) == objective_id:
			label = "%s %d/%d done" % [objective_label(o), have, int(o.required)]
	if not all_done and label != "":
		TOAST.show_toast(self, label)


func _on_quest_completed(quest_id: String) -> void:
	if not _done_here.has(quest_id):
		_done_here.append(quest_id)
	refresh()
	if not show_messages:
		return
	var q: Resource = _find_quest(get_node_or_null("/root/QuestsLite"), quest_id)
	if q != null:
		TOAST.show_toast(self, "Quest complete: %s" % _quest_title(q))


func _find_quest(qm: Node, quest_id: String) -> Resource:
	if qm == null:
		return null
	for q in qm.list_quests():
		if String(q.id) == quest_id:
			return q
	return null


func _quest_title(q: Resource) -> String:
	var t := String(q.get("title"))
	return t if t != "" else String(q.get("id"))


func _key_name() -> String:
	if toggle_action == &"" or not InputMap.has_action(toggle_action):
		return ""
	for e in InputMap.action_get_events(toggle_action):
		if e is InputEventKey:
			var k: InputEventKey = e
			var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
	return ""


# Still where a hand-added node spawns: no anchors, no offsets.
func _unplaced() -> bool:
	return anchor_left == 0.0 and anchor_top == 0.0 and anchor_right == 0.0 and anchor_bottom == 0.0 \
		and offset_left == 0.0 and offset_top == 0.0 and offset_right == 0.0 and offset_bottom == 0.0
