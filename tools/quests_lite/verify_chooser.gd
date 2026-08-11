extends Node

# Headless test for the Quests — Lite chooser's wiring (the part behind Apply).
# Editor-only calls (get_edited_scene_root/selection) are split out; this drives
# the pure wire_board / make_starter_quest helpers against a real scene tree and
# asserts the result is baked-in, re-entrant, and ownership-scoped.
# Run: godot --headless --path . res://tools/quests_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/quests_lite/editor/quests_chooser_dock.gd")
const RESOURCE_SCRIPT := preload("res://addons/quests_lite/quest_lite.gd")

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- quests lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node3D.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)
	var target := Node3D.new()
	target.name = "Elder"
	root.add_child(target); target.owner = root

	var quest := _quest("fetch_herbs")

	# APPLY on the selected node — bakes a QuestBoard carrying the quest.
	dock._chosen = "quest_giver"
	var board1 = dock.wire_board(root, target, quest, true)
	_assert(board1 != null, "wire_board created a quest board")
	_assert(board1.get_parent() == target, "board parented under the chosen node")
	_assert(board1.owner == root, "board owned by scene root: bakes into the .tscn")
	_assert(board1.get_meta("quest_kind") == "quest_giver", "board records the picked kind")
	_assert(board1.get_meta("quest") == quest, "board carries the chosen quest")
	_assert(bool(board1.get_meta("auto_start")) == true, "giver board records auto_start=true")

	# RE-ENTRANT — Apply again updates the same board, never a second one.
	var quest2 := _quest("fetch_herbs_v2")
	dock._chosen = "register_set"
	var board2 = dock.wire_board(root, target, quest2, false)
	_assert(board2 == board1, "second Apply reused the same board (no duplicate)")
	_assert(board2.get_meta("quest") == quest2, "re-apply swapped the quest in place")
	_assert(bool(board2.get_meta("auto_start")) == false, "re-apply updated auto_start in place")
	_assert(board2.get_meta("quest_kind") == "register_set", "re-apply updated the kind in place")
	var count := 0
	for c in target.get_children():
		if c.get_class() == "Node" and c.has_meta("quest_kind"):
			count += 1
	_assert(count == 1, "exactly one quest board after two Applies (got %d)" % count)

	# SCOPE variants — a board on the scene root itself.
	dock._chosen = "register_set"
	var board_root = dock.wire_board(root, root, quest, false)
	_assert(board_root.get_parent() == root, "scene-root scope parents the board on the root")
	_assert(board_root.owner == root, "root-scoped board still owned by root (baked in)")
	_assert(board_root.get_meta("quest_kind") == "register_set", "root-scoped board records its kind")

	# NO QUEST yet — Apply must not crash and must not wipe an unset quest.
	var bare := Node3D.new()
	bare.name = "Board"
	root.add_child(bare); bare.owner = root
	dock._chosen = "quest_giver"
	var board_bare = dock.wire_board(root, bare, null, true)
	_assert(board_bare != null and not board_bare.has_meta("quest"), "no-quest Apply bakes a board with no quest (author later)")
	_assert(bool(board_bare.get_meta("auto_start")) == true, "no-quest board still records auto_start")

	# OWNERSHIP SKIP — a QuestBoard buried in an instanced sub-scene (owner != root)
	# must NOT be hijacked; Apply makes a fresh board the scene actually owns.
	# Fresh root so the ONLY board present is the non-owned one.
	var root2 := Node3D.new()
	get_tree().root.add_child(root2)
	var sub := Node3D.new()
	root2.add_child(sub); sub.owner = root2
	var buried := Node.new()
	buried.name = "QuestBoard"
	buried.set_meta("quest_kind", "quest_giver")
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	dock._chosen = "quest_giver"
	var fresh = dock.wire_board(root2, sub, quest, true)
	_assert(fresh != buried, "did not hijack a board owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh board the scene root owns")
	root2.queue_free()

	# STARTER QUEST — pure factory produces a registerable, completable QuestLite.
	var starter := dock.make_starter_quest("register_set")
	_assert(starter.get_script() == RESOURCE_SCRIPT, "starter is a QuestLite")
	_assert(String(starter.id) != "", "starter quest has an id")
	_assert(starter.objectives.size() == 1, "starter quest has 1 objective")
	_assert(int(starter.objectives[0].type) == QuestObjectiveLite.Type.COLLECT, "register-set starter is a COLLECT quest")
	var giver_starter := dock.make_starter_quest("quest_giver")
	_assert(int(giver_starter.objectives[0].type) == QuestObjectiveLite.Type.KILL, "giver starter is a KILL quest")
	# Prove it actually drives the real autoload end-to-end (register → start → complete).
	QuestsLite._quests.clear(); QuestsLite._state.clear(); QuestsLite._progress.clear()
	QuestsLite.register(giver_starter)
	_assert(QuestsLite.is_registered(String(giver_starter.id)), "starter quest registers into the autoload")
	QuestsLite.start_quest(String(giver_starter.id))
	QuestsLite.report_kill("wolf", 2)
	_assert(QuestsLite.is_complete(String(giver_starter.id)), "starter quest completes when reported")
	QuestsLite._quests.clear(); QuestsLite._state.clear(); QuestsLite._progress.clear()

	root.queue_free()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _quest(id: String) -> Resource:
	var q: Resource = RESOURCE_SCRIPT.new()
	q.id = id
	return q


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)
