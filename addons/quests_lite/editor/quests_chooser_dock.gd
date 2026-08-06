@tool
extends Control

# The "chooser" panel for Quests — Lite: pick what gives out quests in YOUR game,
# pick WHERE, hit Apply — it bakes a quest board onto the node you chose. Re-pick
# and Apply again (it updates in place, never duplicates), tweak it in the
# Inspector, or open the "Quests — Lite" tab to author the quest's objectives.
#
# Lite has no runtime component — just the QuestLite Resource + the QuestsLite
# autoload you call from code. So a board is a plain Node carrying the chosen
# quest in its metadata (serializes into your .tscn, editable in the Inspector's
# Metadata section). From gameplay you call QuestsLite.register(board.get_meta(
# "quest")) and start_quest(...). Pro turns this into a QuestGiver + QuestLogUI +
# EventTrigger that hand out and track quests with zero code — see the bottom note.

const RESOURCE_SCRIPT := preload("res://addons/quests_lite/quest_lite.gd")
const OBJECTIVE_SCRIPT := preload("res://addons/quests_lite/quest_objective_lite.gd")
const QUEST_DIR := "res://quests"
const BOARD_NAME := "QuestBoard"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

# Lite outcomes: both bake a QuestBoard marker, they just differ in whether the
# quest is meant to auto-start (a giver hands it over) or wait to be registered
# (a startup set). No QuestGiver/QuestLogUI/EventTrigger here — that's Pro.
enum Scope { SELECTED, SCENE_ROOT }

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _quest_pick: OptionButton
var _status: Label
var _quest_paths: PackedStringArray = PackedStringArray()


func _ready() -> void:
	name = "Quests · Setup"
	custom_minimum_size = Vector2(320, 440)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  What gives out quests?"))
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	for id in ["quest_giver", "register_set"]:
		var b := Button.new()
		b.text = _pretty(id)
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		grid.add_child(b)
		_buttons[id] = b

	root.add_child(_h("2.  Where, and which quest?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene's root", Scope.SCENE_ROOT)
	root.add_child(_scope)

	_quest_pick = OptionButton.new()
	root.add_child(_quest_pick)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("New starter quest…", _on_new_quest))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game — re-pick and Apply to update in place, tweak the node in the Inspector, or open the \"Quests — Lite\" tab to author the quest's objectives."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	root.add_child(HSeparator.new())
	var pro := Label.new()
	pro.text = "🔒 Lite bakes the quest onto the node; you register + start it from code (QuestsLite.register / start_quest). Pro unlocks no-code wiring: a QuestGiver + QuestLogUI + EventTrigger that hand out and track quests on interact — no scripting."
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.modulate = Color(0.85, 0.8, 0.55)
	root.add_child(pro)

	_refresh_quests()


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_say("Picked \"%s\". Choose where + a quest, then Apply." % _pretty(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick what gives out quests first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var target: Node = root
	if _scope.get_selected_id() == Scope.SELECTED:
		var sel := EditorInterface.get_selection().get_selected_nodes()
		if sel.is_empty():
			_say("Select a node in the scene (or switch scope to \"This scene's root\").", WARN_COLOR)
			return
		target = sel[0]
	var quest: Resource = _selected_quest()
	var board := wire_board(root, target, quest, _chosen == "quest_giver")
	_select(board)
	var quest_msg := " with %s" % quest.resource_path.get_file() if quest != null else " (no quest yet — author one in the Quests tab)"
	_say("%s on \"%s\"%s. From code: QuestsLite.register(board.get_meta(\"quest\")), then start_quest(). Or tweak it in the Inspector." % [_pretty(_chosen), target.name, quest_msg], OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses the existing QuestBoard under `target` rather than adding a
# second one. The chosen quest + auto_start flag live in metadata so they
# serialize into the buyer's .tscn and stay editable in the Inspector's Metadata
# section.

func wire_board(root: Node, target: Node, quest: Resource, auto_start: bool) -> Node:
	var board := _ensure(target, root, BOARD_NAME)
	board.set_meta("quest_kind", _chosen if _chosen != "" else str(board.get_meta("quest_kind", "quest_giver")))
	if quest != null:
		board.set_meta("quest", quest)
	board.set_meta("auto_start", auto_start)
	return board


func _ensure(target: Node, root: Node, node_name: String) -> Node:
	var found := _find(target, root, node_name)
	if found != null:
		return found  # re-entrant: reuse it, never duplicate
	var n := Node.new()
	n.name = node_name
	target.add_child(n)
	# owner must be the scene ROOT so it bakes into the .tscn — even when the
	# target is a nested owned node, its owner is still the scene root.
	n.owner = root
	return n


# Re-entrancy search scoped to nodes the scene owns. A QuestBoard inside an
# instanced child scene (owner != root) is skipped — updating it wouldn't
# serialize into the buyer's scene, so we'd silently no-op. Same trap the save
# dock's CanvasLayer search had.
func _find(target: Node, root: Node, node_name: String) -> Node:
	for c in target.get_children():
		if (c == root or c.owner == root) and c.name == node_name and _is_board(c):
			return c
	return null


# A QuestBoard is our bare marker Node (no script, no native subclass) carrying
# the quest metadata — match on that, not on class, so we don't grab an unrelated
# node the buyer happened to name "QuestBoard".
func _is_board(node: Node) -> bool:
	return node.get_class() == "Node" and node.has_meta("quest_kind")


# ---- new starter quest ----------------------------------------------------

func _on_new_quest() -> void:
	if not DirAccess.dir_exists_absolute(QUEST_DIR):
		DirAccess.make_dir_recursive_absolute(QUEST_DIR)
	var quest := make_starter_quest(_chosen)
	var path := _unique(QUEST_DIR.path_join("%s_quest" % (_chosen if _chosen != "" else "starter")))
	var err := ResourceSaver.save(quest, path)
	if err != OK:
		_say("Could not create the quest (err %d)." % err, ERR_COLOR)
		return
	quest.take_over_path(path)
	_scan_fs()
	_refresh_quests()
	_select_quest_path(path)
	_say("Made a starter quest: %s. Pick it above, then Apply — or open the Quests tab to add objectives." % path.get_file(), OK_COLOR)


# Pure so the test can drive it. A minimal 1-objective quest the buyer can
# register + start right away, then flesh out in the authoring dock. A giver
# quest starts as a KILL (go slay X); a startup set starts as a COLLECT (fetch X).
func make_starter_quest(kind: String) -> Resource:
	var q: Resource = RESOURCE_SCRIPT.new()
	q.id = "%s_quest" % (kind if kind != "" else "starter")
	q.title = _pretty(kind if kind != "" else "starter")
	var o: Resource = OBJECTIVE_SCRIPT.new()
	o.id = "objective_1"
	if kind == "register_set":
		o.type = OBJECTIVE_SCRIPT.Type.COLLECT
		o.target_id = "herb"
		o.required = 3
	else:
		o.type = OBJECTIVE_SCRIPT.Type.KILL
		o.target_id = "wolf"
		o.required = 2
	# QuestLite.objectives is typed Array[QuestObjectiveLite] — pack the single
	# objective into the typed form so the assignment is legal.
	var typed: Array[QuestObjectiveLite] = []
	typed.append(o)
	q.objectives = typed
	return q


# ---- quest list ----------------------------------------------------------

func _refresh_quests() -> void:
	_quest_paths = _scan_quests(QUEST_DIR)
	_quest_pick.clear()
	_quest_pick.add_item("(no quest yet)", 0)
	for i in _quest_paths.size():
		_quest_pick.add_item(_quest_paths[i].get_file().get_basename(), i + 1)


func _scan_quests(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var res := load(dir_path.path_join(f))
			if res != null and res.get_script() == RESOURCE_SCRIPT:
				out.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	return out


func _selected_quest() -> Resource:
	var id := _quest_pick.get_selected_id()
	if id <= 0 or id - 1 >= _quest_paths.size():
		return null
	return load(_quest_paths[id - 1])


func _select_quest_path(path: String) -> void:
	for i in _quest_paths.size():
		if _quest_paths[i] == path:
			_quest_pick.select(i + 1)
			return


# ---- helpers -------------------------------------------------------------

func _select(n: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _unique(base: String) -> String:
	var p := base + ".tres"
	var n := 1
	while FileAccess.file_exists(p):
		p = "%s_%d.tres" % [base, n]
		n += 1
	return p


func _scan_fs() -> void:
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()


func _pretty(id: String) -> String:
	match id:
		"quest_giver": return "A quest giver"
		"register_set": return "Register quests at startup"
	return id.replace("_", " ").capitalize()


func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


func _btn(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _say(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text
