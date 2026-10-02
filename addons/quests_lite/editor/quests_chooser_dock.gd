@tool
extends Control

# The "chooser" panel for Quests (Lite): pick what a node does for your quests,
# pick the quest, hit Apply, and it's wired into your own scene. A QuestBoard
# gives the quest (when the scene starts, or when the player touches the node), a
# QuestTarget counts toward one of its objectives (a pickup to collect, an enemy
# to defeat), and a small tracker lists progress at the top right. Re-pick and
# Apply again to update in place (it never duplicates), or tweak the dropped nodes
# in the Inspector. The "Quests (Lite)" tab is where the quests get written.

# The runtime scripts never name the QuestsLite autoload, so preloading them is
# safe on the very first enable, before the autoload exists.
const RESOURCE_SCRIPT := preload("res://addons/quests_lite/quest_lite.gd")
const OBJECTIVE_SCRIPT := preload("res://addons/quests_lite/quest_objective_lite.gd")
const BOARD_SCRIPT := preload("res://addons/quests_lite/quest_board_lite.gd")
const TARGET_SCRIPT := preload("res://addons/quests_lite/quest_target_lite.gd")
const TRACKER_SCRIPT := preload("res://addons/quests_lite/quest_tracker_lite.gd")
const QUEST_DIR := "res://quests"
const BOARD_NAME := "QuestBoard"
const TARGET_NAME := "QuestTarget"
const TRACKER_NAME := "QuestTracker"
const QUEST_AREA := "QuestArea"
const PICKUP_AREA := "PickupArea"
const PLAYER_GROUP := "player"
const LOG_ACTION := "quest_log"  # hides and shows the tracker, J unless the project already has it
const NO_PLAYER := " Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

# id -> label. Order = display order.
const OUTCOMES := {
	"give_on_start": "Give this quest when the scene starts",
	"give_on_touch": "Give this quest when the player touches this",
	"counts_toward": "This counts toward a quest",
}

var _chosen := ""
var _buttons := {}
var _quest_pick: OptionButton
var _obj_row: HBoxContainer
var _obj_pick: OptionButton
var _objectives: Array = []  # _obj_pick index -> QuestObjectiveLite
var _tracker_box: CheckBox
var _status: Label
var _quest_paths: PackedStringArray = PackedStringArray()


func _ready() -> void:
	name = "Quests · Setup"
	custom_minimum_size = Vector2(0, 440)
	# Taller than the dock, the tab scrolls. Nothing in it is wider than a default
	# dock at 100% or 125%, so it never has to scroll sideways.
	var page := ScrollContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.minimum_size_changed.connect(update_minimum_size)
	add_child(page)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	page.add_child(root)

	root.add_child(_h("1.  What do you want to add?"))
	for id in OUTCOMES.keys():
		var b := Button.new()
		b.text = OUTCOMES[id]
		b.toggle_mode = true
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_on_pick.bind(id))
		root.add_child(b)
		_buttons[id] = b

	root.add_child(_h("2.  Which quest?"))
	var qrow := HBoxContainer.new()
	root.add_child(qrow)
	_quest_pick = OptionButton.new()
	_quest_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_pick.clip_text = true
	# its longest entry used to set the width of the whole tab; the open list still shows every name in full
	_quest_pick.fit_to_longest_item = false
	_quest_pick.item_selected.connect(func(_i: int) -> void: _refresh_objectives())
	qrow.add_child(_quest_pick)
	qrow.add_child(_btn("Refresh", _on_refresh))
	# a quest made in the Quests (Lite) tab is in the list the next time it opens
	_quest_pick.get_popup().about_to_popup.connect(_refresh_quests)
	var nrow := HBoxContainer.new()
	root.add_child(nrow)
	# side by side these two were wider than a default dock; now they share the row and wrap
	for b: Button in [_btn("New starter quest…", _on_new_quest, true), _btn("Edit this quest…", _on_edit_quest, true)]:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nrow.add_child(b)

	# which objective a target counts toward, only for that outcome
	_obj_row = HBoxContainer.new()
	var obj_label := Label.new()
	obj_label.text = "Counts toward"
	_obj_row.add_child(obj_label)
	_obj_pick = OptionButton.new()
	_obj_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_pick.clip_text = true
	_obj_pick.fit_to_longest_item = false
	_obj_row.add_child(_obj_pick)
	_obj_pick.get_popup().about_to_popup.connect(_refresh_objectives)
	root.add_child(_obj_row)
	_obj_row.visible = false

	_tracker_box = CheckBox.new()
	_tracker_box.text = "Show the quest tracker (J)"
	_tracker_box.button_pressed = true
	_tracker_box.tooltip_text = "A small list of the player's quests at the top right of the game. J hides and shows it."
	root.add_child(_tracker_box)

	root.add_child(_btn("Apply", _on_apply, true))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	# on a row of its own, so on a narrow dock it wraps its label instead of widening the tab
	var player_btn := _btn("Make the selected node the player", _on_make_player)
	player_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	player_btn.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	root.add_child(player_btn)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "Select the node first: the NPC that gives the quest, or the pickup or enemy that counts. Re-pick and Apply to update it in place, or tweak it in the Inspector. Write quests in the \"Quests (Lite)\" tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	root.add_child(HSeparator.new())
	var pro := Label.new()
	pro.text = "🔒 Pro adds a QuestGiver that talks the player through taking and handing in quests, a styled QuestLogUI with tabs, rewards, quest chains, six more objective types and save integration."
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.modulate = Color(0.85, 0.8, 0.55)
	root.add_child(pro)

	_refresh_quests()


# As wide as what's in it and no wider. The old fixed width pushed a laptop's
# default dock (270 px) wider whenever this tab was open.
func _get_minimum_size() -> Vector2:
	if get_child_count() == 0 or not (get_child(0) is Control):
		return Vector2.ZERO
	return Vector2((get_child(0) as Control).get_combined_minimum_size().x, 0.0)


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_obj_row.visible = (id == "counts_toward")
	_refresh_quests()
	match id:
		"give_on_start":
			_say("Picked \"%s\". Pick the quest, then Apply." % OUTCOMES[id], OK_COLOR)
		"give_on_touch":
			_say("Picked \"%s\". Select the NPC or object the player walks into, pick the quest, then Apply." % OUTCOMES[id], OK_COLOR)
		_:
			_say("Picked \"%s\". Select the pickup or enemy, pick the quest and the objective, then Apply." % OUTCOMES[id], OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick what you want to add first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var quest: Resource = _selected_quest()
	if quest == null:
		_say("Pick a quest first, or press \"New starter quest…\".", WARN_COLOR)
		return
	var extra := ""
	if fill_missing_ids(quest) and quest.resource_path != "":
		ResourceSaver.save(quest, quest.resource_path)
		extra = " Filled in the quest's missing ids and saved it."
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var picked: Node = sel[0] if not sel.is_empty() else null
	match _chosen:
		"give_on_start": _apply_start(root, picked, quest, extra)
		"give_on_touch": _apply_touch(root, picked, quest, extra)
		"counts_toward": _apply_counts(root, picked, quest, extra)


func _apply_start(root: Node, picked: Node, quest: Resource, extra: String) -> void:
	var host: Node = picked if picked != null else root
	var old := _find_legacy_board(host, root) != null
	var board := wire_board(root, host, quest, BOARD_SCRIPT.StartMode.ON_SCENE_START)
	var msg := "\"%s\" now starts as soon as the scene starts. Its QuestBoard is on \"%s\"." % [_quest_label(quest), host.name]
	if old:
		msg = "Updated the old QuestBoard on \"%s\". " % host.name + msg
	msg += _add_tracker(root) + extra
	_select(board)
	_say(msg + " Press Play to see it.", OK_COLOR)


func _apply_touch(root: Node, picked: Node, quest: Resource, extra: String) -> void:
	if picked == null:
		_say("Select the NPC or object the player walks into first.", WARN_COLOR)
		return
	if not (picked is Node2D or picked is Node3D):
		_say("\"%s\" isn't a 2D or 3D node, so the player can't touch it. Select the NPC or object itself." % picked.name, WARN_COLOR)
		return
	var old := _find_legacy_board(picked, root) != null
	var had_area := picked is Area2D or picked is Area3D or _find_area(root, picked, QUEST_AREA) != null
	var board := wire_board(root, picked, quest, BOARD_SCRIPT.StartMode.ON_PLAYER_TOUCH)
	wire_touch_area(root, picked, QUEST_AREA)
	var msg := "\"%s\" now starts when the player touches \"%s\"." % [_quest_label(quest), picked.name]
	if old:
		msg = "Updated the old QuestBoard on \"%s\". " % picked.name + msg
	if not had_area:
		msg += " Added a QuestArea to it, so there's something to touch."
	msg += _add_tracker(root) + extra
	_select(board)
	if not has_player(root):
		_say(msg + NO_PLAYER, WARN_COLOR)
		return
	_say(msg + " Press Play and walk into it.", OK_COLOR)


func _apply_counts(root: Node, picked: Node, quest: Resource, extra: String) -> void:
	if picked == null or picked == root:
		_say("Select the pickup or the enemy itself first, not the scene root.", WARN_COLOR)
		return
	if not (picked is Node2D or picked is Node3D):
		_say("\"%s\" isn't a 2D or 3D node. Select the pickup or the enemy itself." % picked.name, WARN_COLOR)
		return
	var obj := _selected_objective()
	if obj == null:
		_say("Pick the objective it counts toward. If the list is empty, the quest has no objectives yet: press \"Edit this quest…\", add one under Objectives, then press Refresh.", WARN_COLOR)
		return
	var what := "%s x%d" % [objective_label(obj), int(obj.get("required"))]
	var had_area := picked is Area2D or picked is Area3D or _find_area(root, picked, PICKUP_AREA) != null
	var target := wire_target(root, picked, obj)
	var msg := ""
	var warn := ""
	if int(obj.get("type")) == OBJECTIVE_SCRIPT.Type.KILL:
		msg = "Defeating \"%s\" now counts toward \"%s\" (%s)." % [picked.name, _quest_label(quest), what]
		if not has_died_signal(picked):
			warn = " Nothing on it sends a died signal yet, so it can't be defeated. Add a Health node to it (the Combat pack's Health works)."
	else:
		msg = "Touching \"%s\" now counts toward \"%s\" (%s), then it disappears. It stays put until that quest is active." % [picked.name, _quest_label(quest), what]
		if not had_area:
			msg += " Added a PickupArea to it, so there's something to touch."
		if not has_player(root):
			warn = NO_PLAYER
	msg += _add_tracker(root) + extra
	_select(target)
	if warn != "":
		_say(msg + warn, WARN_COLOR)
		return
	_say(msg, OK_COLOR)


# The tracker comes with every outcome unless the box is unticked, once per scene.
func _add_tracker(root: Node) -> String:
	if not _tracker_box.button_pressed:
		return ""
	var had := find_tracker(root) != null
	wire_tracker(root)
	if had:
		return ""
	return " Added a quest tracker at the top right (press %s in the game to hide or show it)." % action_keys(LOG_ACTION)


func _on_make_player() -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_say("Select your player node first.", WARN_COLOR)
		return
	var n: Node = sel[0]
	mark_player(n)
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % n.name, OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Each is re-entrant: it updates the existing node rather than duplicating.

## A QuestBoard under `target` giving `quest`. Reuses the one from the last Apply,
## and turns a 1.2 plain-Node board into the real thing. quest=null keeps the
## quest it already has.
func wire_board(root: Node, target: Node, quest: Resource, mode: int) -> Node:
	var board := _find_board(target, root)
	if board == null:
		board = _inert(BOARD_SCRIPT)
		board.name = BOARD_NAME
		target.add_child(board, true)
		# owner must be the scene ROOT so it bakes into the .tscn, even when the
		# target is a nested owned node
		board.owner = root
	elif _is_legacy_board(board):
		convert_legacy_board(board)
	if quest != null:
		board.set("quest", quest)
	board.set("start_mode", mode)
	return board


## Boards from 1.2 were a plain Node with the quest in metadata and your code
## doing the rest. Same node, now with the script, so its name, its place in the
## tree and anything under it stay put. The metadata moves into the exports.
func convert_legacy_board(board: Node) -> Node:
	var quest: Variant = board.get_meta("quest", null)
	var auto_start := bool(board.get_meta("auto_start", true))
	board.set_script(BOARD_SCRIPT)
	if quest is Resource:
		board.set("quest", quest)
	# auto_start=false meant "register it, don't start it yet": waiting for the player
	board.set("start_mode", BOARD_SCRIPT.StartMode.ON_SCENE_START if auto_start else BOARD_SCRIPT.StartMode.ON_PLAYER_TOUCH)
	for k in ["quest_kind", "quest", "auto_start"]:
		if board.has_meta(k):
			board.remove_meta(k)
	return board


## Something the player can touch on `host`: host itself if it's an Area2D/3D,
## else an Area child named `area_name`. Either way it gets a round shape if it
## has none, or it would never touch anything.
func wire_touch_area(root: Node, host: Node, area_name: String) -> Node:
	var area: Node = host if (host is Area2D or host is Area3D) else _find_area(root, host, area_name)
	if area == null:
		area = Area3D.new() if host is Node3D else Area2D.new()
		area.name = area_name
		host.add_child(area, true)
		area.owner = root
	if not _has_shape(area):
		_add_shape(root, area, area_name == QUEST_AREA)
	return area


## A QuestTarget under `host` counting toward `objective`. Collect targets get
## something to touch too.
func wire_target(root: Node, host: Node, objective: Resource) -> Node:
	var t: Node = null
	for c in host.get_children():
		if c.owner == root and c.get_script() == TARGET_SCRIPT:
			t = c
			break
	if t == null:
		t = _inert(TARGET_SCRIPT)
		t.name = TARGET_NAME
		host.add_child(t, true)
		t.owner = root
	t.set("type", int(objective.get("type")))
	t.set("target_id", String(objective.get("target_id")))
	if int(objective.get("type")) == OBJECTIVE_SCRIPT.Type.COLLECT:
		wire_touch_area(root, host, PICKUP_AREA)
	return t


## The tracker, once per scene: reused if the scene shows one anywhere, instanced
## sub-scenes included, since two would both draw. Also makes sure J exists.
func wire_tracker(root: Node) -> Node:
	ensure_log_action()
	var t := find_tracker(root)
	if t != null:
		return t
	var layer := _ui_layer(root)
	t = _inert(TRACKER_SCRIPT)
	t.name = TRACKER_NAME
	layer.add_child(t, true)
	t.owner = root
	# top right, 360 wide. Only the width and the corner matter: at runtime it
	# grows to fit its list. The 64 is so you can see where it sits in the editor.
	var c := t as Control
	c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	c.offset_left = -376.0
	c.offset_right = -16.0
	c.offset_top = 16.0
	c.offset_bottom = 80.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return t


func find_tracker(root: Node) -> Node:
	if root.get_script() == TRACKER_SCRIPT:
		return root
	for n in root.find_children("*", "", true, false):
		if n.get_script() == TRACKER_SCRIPT:
			return n
	return null


## The dropdown under "Counts toward": one {label, objective} per objective,
## e.g. "Collect herb x3".
func objective_items(quest: Resource) -> Array:
	var out: Array = []
	if quest == null:
		return out
	for o in quest.get("objectives"):
		if o == null:
			continue
		out.append({"label": "%s x%d" % [objective_label(o), int(o.required)], "objective": o})
	return out


func objective_label(o: Resource) -> String:
	return TRACKER_SCRIPT.objective_label(o)


## A kill only counts when the enemy says it died: a `died` signal on it or on
## something under it (a Health node).
func has_died_signal(node: Node) -> bool:
	if node.has_signal("died"):
		return true
	for n in node.find_children("*", "", true, false):
		if n.has_signal("died"):
			return true
	return false


## Persistent, so the group is saved with the scene.
func mark_player(node: Node) -> void:
	# re-add rather than trust an existing membership: one added at runtime isn't
	# persistent, and add_to_group() won't upgrade it
	if node.is_in_group(PLAYER_GROUP):
		node.remove_from_group(PLAYER_GROUP)
	node.add_to_group(PLAYER_GROUP, true)


func has_player(root: Node) -> bool:
	if not root.is_inside_tree():
		# no tree to ask (a headless test built it loose), so walk it
		for n in [root] + root.find_children("*", "", true, false):
			if n.is_in_group(PLAYER_GROUP):
				return true
		return false
	for n in root.get_tree().get_nodes_in_group(PLAYER_GROUP):
		if n == root or root.is_ancestor_of(n):
			return true
	return false


## Everything at runtime goes by id: a quest with a blank one never registers, and
## blank or repeated objective ids share one progress count. Fill those in.
func fill_missing_ids(quest: Resource) -> bool:
	var changed := false
	if String(quest.get("id")) == "":
		var base := quest.resource_path.get_file().get_basename()
		quest.set("id", base if base != "" else "quest")
		changed = true
	var used := {}
	for o in quest.get("objectives"):
		if o == null:
			continue
		var oid := String(o.id)
		if oid == "" or used.has(oid):
			var stem := ("defeat_" if int(o.type) == OBJECTIVE_SCRIPT.Type.KILL else "collect_") \
				+ (String(o.target_id).to_snake_case() if String(o.target_id) != "" else "item")
			var cand := stem
			var n := 2
			while used.has(cand):
				cand = "%s_%d" % [stem, n]
				n += 1
			o.id = cand
			changed = true
		used[String(o.id)] = true
	return changed


# The quest_log input action, on J. A binding the project already has is left
# alone. Safe from a test: save=false only touches the in-memory ProjectSettings,
# and even save=true only writes project.godot from inside the editor (a headless
# save rewrites its engine version line).
func ensure_log_action(save := true) -> void:
	var key := "input/" + LOG_ACTION
	if ProjectSettings.has_setting(key):
		return
	var j := InputEventKey.new()
	j.physical_keycode = KEY_J
	# every device, like the Input Map editor stores it. A new InputEventKey is
	# device 0 on 4.5 but 16 (the keyboard id) on 4.7, and a key saved with one
	# never matches presses on the other.
	j.device = -1
	ProjectSettings.set_setting(key, {"deadzone": 0.5, "events": [j]})
	if save and Engine.is_editor_hint():
		ProjectSettings.save()


# The key(s) an action is bound to, for the status line ("J").
func action_keys(action: String) -> String:
	var names := PackedStringArray()
	var cfg: Variant = ProjectSettings.get_setting("input/" + action, null)
	if cfg is Dictionary:
		for e in (cfg as Dictionary).get("events", []):
			if e is InputEventKey:
				var k: InputEventKey = e
				var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
				names.append(OS.get_keycode_string(code))
	if names.is_empty():
		return "the \"%s\" key" % action
	return " or ".join(names)


# ---- new starter quest ----------------------------------------------------

func _on_new_quest() -> void:
	if not DirAccess.dir_exists_absolute(QUEST_DIR):
		DirAccess.make_dir_recursive_absolute(QUEST_DIR)
	var path := _unique(QUEST_DIR.path_join("starter_quest"))
	var quest := make_starter_quest(path.get_file().get_basename())
	var err := ResourceSaver.save(quest, path)
	if err != OK:
		_say("Could not create the quest (err %d)." % err, ERR_COLOR)
		return
	quest.take_over_path(path)
	_register_uid(path)
	_scan_fs()
	_refresh_quests()
	_select_quest_path(path)
	_refresh_objectives()
	_say("Made %s: collect 3 herbs and defeat 2 slimes. Rename it in the Quests (Lite) tab, or change its objectives with \"Edit this quest…\"." % path, OK_COLOR)


# Pure so the test can drive it. Both objective kinds, so the "Counts toward"
# list shows how each one gets wired. The id matches the file, so two starters
# never share one.
func make_starter_quest(id: String = "starter_quest") -> Resource:
	var q: Resource = RESOURCE_SCRIPT.new()
	q.id = id
	q.title = "Starter quest"
	q.description = "Collect 3 herbs and defeat 2 slimes."
	var herb: Resource = OBJECTIVE_SCRIPT.new()
	herb.id = "collect_herb"
	herb.type = OBJECTIVE_SCRIPT.Type.COLLECT
	herb.target_id = "herb"
	herb.required = 3
	var slime: Resource = OBJECTIVE_SCRIPT.new()
	slime.id = "defeat_slime"
	slime.type = OBJECTIVE_SCRIPT.Type.KILL
	slime.target_id = "slime"
	slime.required = 2
	# QuestLite.objectives is typed Array[QuestObjectiveLite], so pack it typed
	var typed: Array[QuestObjectiveLite] = []
	typed.append(herb)
	typed.append(slime)
	q.objectives = typed
	return q


func _on_edit_quest() -> void:
	var quest := _selected_quest()
	if quest == null:
		_say("Pick a quest first.", WARN_COLOR)
		return
	EditorInterface.edit_resource(quest)
	_say("\"%s\" is open in the Inspector. Add or change objectives under Objectives (Type, Target Id, Required), then press Refresh here." % _quest_label(quest), OK_COLOR)


func _on_refresh() -> void:
	_refresh_quests()


# ---- quest + objective lists -----------------------------------------------

func _refresh_quests() -> void:
	var keep := _selected_path()
	_quest_paths = _scan_quests(QUEST_DIR)
	_quest_pick.clear()
	_quest_pick.add_item("(no quest yet)", 0)
	for i in _quest_paths.size():
		_quest_pick.add_item(_quest_paths[i].get_file().get_basename(), i + 1)
	if keep != "":
		_select_quest_path(keep)
	elif not _quest_paths.is_empty():
		_quest_pick.select(1)
	_refresh_objectives()


func _refresh_objectives() -> void:
	if _obj_pick == null:
		return
	var keep := _obj_pick.selected
	_obj_pick.clear()
	_objectives = []
	for it in objective_items(_selected_quest()):
		_obj_pick.add_item(String(it["label"]), _objectives.size())
		_objectives.append(it["objective"])
	_obj_pick.disabled = _objectives.is_empty()
	if _objectives.is_empty():
		_obj_pick.add_item("(no objectives yet)")
		return
	_obj_pick.select(clampi(keep, 0, _objectives.size() - 1))


func _selected_objective() -> Resource:
	var i := _obj_pick.selected
	if i < 0 or i >= _objectives.size():
		return null
	return _objectives[i]


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
	out.sort()
	return out


func _selected_path() -> String:
	if _quest_pick == null:
		return ""
	var id := _quest_pick.get_selected_id()
	if id <= 0 or id - 1 >= _quest_paths.size():
		return ""
	return _quest_paths[id - 1]


func _selected_quest() -> Resource:
	var p := _selected_path()
	return load(p) if p != "" else null


func _select_quest_path(path: String) -> void:
	for i in _quest_paths.size():
		if _quest_paths[i] == path:
			_quest_pick.select(i + 1)
			return


# ---- helpers -------------------------------------------------------------

func _find_board(target: Node, root: Node) -> Node:
	for c in target.get_children():
		if (c == root or c.owner == root) and (c.get_script() == BOARD_SCRIPT or _is_legacy_board(c)):
			return c
	return null


func _find_legacy_board(target: Node, root: Node) -> Node:
	var b := _find_board(target, root)
	return b if b != null and _is_legacy_board(b) else null


# The 1.2 board: a bare Node (no script) carrying the quest metadata. Matching on
# that, not the name, so we never grab an unrelated node called "QuestBoard".
# A board inside an instanced sub-scene (owner != root) is skipped by the callers:
# changing it wouldn't save into this scene.
func _is_legacy_board(node: Node) -> bool:
	return node.get_script() == null and node.get_class() == "Node" and node.has_meta("quest_kind")


func _find_area(root: Node, host: Node, area_name: String) -> Node:
	for c in host.get_children():
		if c.name == area_name and (c is Area2D or c is Area3D) and c.owner == root:
			return c
	return null


func _has_shape(area: Node) -> bool:
	for c in area.get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D or c is CollisionShape3D or c is CollisionPolygon3D:
			return true
	return false


# Round, and a bit bigger than a typical sprite so bumping into it counts. A
# quest giver gets more room than a pickup.
func _add_shape(root: Node, area: Node, roomy: bool) -> void:
	var shape: Node
	if area is Area3D:
		var sphere := SphereShape3D.new()
		sphere.radius = 1.5 if roomy else 1.0
		var s3 := CollisionShape3D.new()
		s3.shape = sphere
		shape = s3
	else:
		var circle := CircleShape2D.new()
		circle.radius = 48.0 if roomy else 32.0
		var s2 := CollisionShape2D.new()
		s2.shape = circle
		shape = s2
	shape.name = "Shape"
	area.add_child(shape, true)
	shape.owner = root


func _ui_layer(root: Node) -> Node:
	for c in root.get_children():
		if c is CanvasLayer and c.name == "UILayer" and c.owner == root:
			return c
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	root.add_child(layer, true)
	layer.owner = root
	return layer


# A runtime script's .new() is a live instance, so its game code would run in the
# editor until the scene is reopened. Attach the script to a plain native node
# instead: that's the inert placeholder a hand-added node gets. Exports still save.
func _inert(script: Script) -> Node:
	var n: Node = ClassDB.instantiate(script.get_instance_base_type())
	n.set_script(script)
	return n


func _quest_label(quest: Resource) -> String:
	var t := String(quest.get("title"))
	if t == "":
		t = String(quest.get("id"))
	return t if t != "" else quest.resource_path.get_file().get_basename()


func _select(n: Node) -> void:
	# Apply adds nodes without the undo manager, so the editor never flags the scene
	# and Play would run the saved file without them. Flag it by hand.
	EditorInterface.mark_scene_as_unsaved()
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


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
