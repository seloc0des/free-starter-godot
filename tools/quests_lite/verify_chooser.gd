extends Node

# Headless test for the Quests — Lite chooser's wiring (the part behind Apply).
# Editor-only calls (get_edited_scene_root/selection) are split out; this drives
# the pure wire_* helpers against a scene built the way a buyer's is, asserts the
# result is baked in, re-entrant and ownership-scoped, then packs the scene the
# dock built and plays it: the player walks in, a Health says died, J gets pressed.
# Run: godot --headless --path . res://tools/quests_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/quests_lite/editor/quests_chooser_dock.gd")
const RESOURCE_SCRIPT := preload("res://addons/quests_lite/quest_lite.gd")
const BOARD_SCRIPT := preload("res://addons/quests_lite/quest_board_lite.gd")
const TARGET_SCRIPT := preload("res://addons/quests_lite/quest_target_lite.gd")
const TRACKER_SCRIPT := preload("res://addons/quests_lite/quest_tracker_lite.gd")
const START := 0  # QuestBoardLite.StartMode.ON_SCENE_START
const TOUCH := 1  # QuestBoardLite.StartMode.ON_PLAYER_TOUCH

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- quests lite chooser verify ---")
	var dock: Object = CHOOSER.new()  # not added to tree; we only call pure helpers
	_starter_and_objectives(dock)
	_board_and_area(dock)
	_targets(dock)
	_tracker_and_key(dock)
	_player_and_ids(dock)
	await _legacy(dock)
	await _played_end_to_end(dock)
	await _quests_tab_new(dock)
	dock.free()
	await _run_quest_list_refresh()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# ---- starter quest + the objective dropdown ---------------------------------

func _starter_and_objectives(dock: Object) -> void:
	var starter: Resource = dock.make_starter_quest("starter_quest")
	_assert(starter.get_script() == RESOURCE_SCRIPT, "starter is a QuestLite")
	_assert(String(starter.id) == "starter_quest", "starter quest's id is the one it's given (matches its file)")
	_assert(starter.objectives.size() == 2, "starter quest has 2 objectives")
	_assert(int(starter.objectives[0].type) == QuestObjectiveLite.Type.COLLECT and int(starter.objectives[1].type) == QuestObjectiveLite.Type.KILL,
		"starter has one collect and one kill objective")
	var items: Array = dock.objective_items(starter)
	var labels := PackedStringArray()
	for it in items:
		labels.append(String(it["label"]))
	_assert(labels == PackedStringArray(["Collect herb x3", "Defeat slime x2"]), "objective dropdown lists \"Collect herb x3\", \"Defeat slime x2\" (got %s)" % [labels])
	_assert(items.size() == 2 and items[1]["objective"] == starter.objectives[1], "each dropdown entry carries its objective")
	var bare: Resource = RESOURCE_SCRIPT.new()
	_assert(dock.objective_items(bare).is_empty() and dock.objective_items(null).is_empty(), "no objectives (or no quest): an empty dropdown, no crash")
	# the starter drives the real autoload end to end
	_wipe()
	_quests_lite().register(starter)
	_quests_lite().start_quest("starter_quest")
	_quests_lite().report_collect("herb", 3)
	_quests_lite().report_kill("slime", 2)
	_assert(_quests_lite().is_complete("starter_quest"), "starter quest completes when reported")
	_wipe()


# ---- QuestBoard + QuestArea ----------------------------------------------------

func _board_and_area(dock: Object) -> void:
	var root := _level()
	var npc: Node2D = root.get_node("NPC")
	var quest := _quest("fetch_herbs", "Fetch herbs")
	var board: Node = dock.wire_board(root, npc, quest, TOUCH)
	_assert(board != null and board.get_script() == BOARD_SCRIPT, "wire_board made a QuestBoardLite")
	_assert(board.get_parent() == npc and board.owner == root, "board parented under the NPC, owned by the scene root (bakes into the .tscn)")
	_assert(board.name == "QuestBoard", "board has a readable name")
	_assert(board.get("quest") == quest and int(board.get("start_mode")) == TOUCH, "board carries the quest and the touch start mode")
	var area: Node = dock.wire_touch_area(root, npc, "QuestArea")
	_assert(area is Area2D and area.name == "QuestArea" and area.get_parent() == npc and area.owner == root, "a 2D NPC got a QuestArea, owned by the root")
	var shape: Node = area.get_node_or_null("Shape")
	var radius := ((shape as CollisionShape2D).shape as CircleShape2D).radius if shape is CollisionShape2D else 0.0
	_assert(shape != null and shape.owner == root and radius == 48.0, "the QuestArea has a round shape to touch (radius %s)" % radius)

	# RE-ENTRANT: Apply again updates in place
	var quest2 := _quest("fetch_herbs_v2", "Fetch more herbs")
	var board2: Node = dock.wire_board(root, npc, quest2, START)
	var area2: Node = dock.wire_touch_area(root, npc, "QuestArea")
	_assert(board2 == board and area2 == area, "second Apply reused the same board and QuestArea")
	_assert(board2.get("quest") == quest2 and int(board2.get("start_mode")) == START, "re-apply swapped the quest and the start mode in place")
	var boards := _count_script(npc, BOARD_SCRIPT)
	var areas := _count_class(npc, "Area2D")
	_assert(boards == 1 and areas == 1 and area.get_child_count() == 1,
		"exactly one board, one QuestArea, one shape after two Applies (%d, %d, %d)" % [boards, areas, area.get_child_count()])
	var keep: Node = dock.wire_board(root, npc, null, START)
	_assert(keep.get("quest") == quest2, "an Apply with no quest keeps the one it has")

	# an Area2D host (the Chest) is its own touch area, and gets a shape once
	var chest: Node = root.get_node("Chest")
	var chest_area: Node = dock.wire_touch_area(root, chest, "QuestArea")
	dock.wire_touch_area(root, chest, "QuestArea")
	_assert(chest_area == chest and chest.get_child_count() == 1 and chest.get_child(0) is CollisionShape2D,
		"an Area2D is its own touch area and gets one shape, not two")

	# 3D
	var root3 := Node3D.new()
	root3.name = "Level3D"
	var npc3 := Node3D.new()
	npc3.name = "NPC"
	root3.add_child(npc3)
	npc3.owner = root3
	dock.wire_board(root3, npc3, quest, TOUCH)
	var area3: Node = dock.wire_touch_area(root3, npc3, "QuestArea")
	_assert(area3 is Area3D and area3.get_node_or_null("Shape") is CollisionShape3D, "a 3D NPC got an Area3D with a sphere shape")
	root3.free()

	# OWNERSHIP SKIP: a board inside an instanced sub-scene isn't hijacked
	var sub := Node2D.new()
	root.add_child(sub)
	sub.owner = root
	var buried: Node = BOARD_SCRIPT.new()
	buried.name = "QuestBoard"
	sub.add_child(buried)
	buried.owner = sub  # owned by the sub-scene, not root
	var fresh: Node = dock.wire_board(root, sub, quest, START)
	_assert(fresh != buried and fresh.owner == root, "did not hijack a board owned by a sub-scene")
	root.free()


# ---- QuestTarget -----------------------------------------------------------

func _targets(dock: Object) -> void:
	var root := _level()
	var starter: Resource = dock.make_starter_quest("starter_quest")
	var herb_obj: Resource = starter.objectives[0]
	var slime_obj: Resource = starter.objectives[1]
	var herb := Node2D.new()
	herb.name = "Herb"
	root.add_child(herb)
	herb.owner = root
	var t: Node = dock.wire_target(root, herb, herb_obj)
	_assert(t.get_script() == TARGET_SCRIPT and t.name == "QuestTarget" and t.owner == root, "wire_target made a QuestTarget owned by the root")
	_assert(int(t.get("type")) == 0 and String(t.get("target_id")) == "herb", "collect target copies the objective (collect, herb)")
	_assert(int(t.get("amount")) == 1 and bool(t.get("remove_when_collected")), "defaults: counts 1, removes the pickup")
	var pick: Node = herb.get_node_or_null("PickupArea")
	_assert(pick is Area2D and pick.owner == root and pick.get_node_or_null("Shape") is CollisionShape2D, "a plain Node2D pickup got a PickupArea with a shape")
	# re-apply as the kill objective: same target, retargeted
	var t2: Node = dock.wire_target(root, herb, slime_obj)
	_assert(t2 == t and int(t.get("type")) == 1 and String(t.get("target_id")) == "slime", "re-apply updates the same target in place")
	_assert(_count_script(herb, TARGET_SCRIPT) == 1 and _count_class(herb, "Area2D") == 1, "still one target and one PickupArea")
	# the Chest (an Area2D) needs no PickupArea
	var chest: Node = root.get_node("Chest")
	dock.wire_target(root, chest, herb_obj)
	_assert(chest.get_node_or_null("PickupArea") == null and chest.get_node_or_null("Shape") is CollisionShape2D,
		"a collect target on an Area2D uses it (plus a shape), no PickupArea")
	# kill: the died check
	var enemy: Node = root.get_node("Enemy")
	_assert(not dock.has_died_signal(enemy), "an enemy with no Health has no died signal (the dock warns)")
	var health := Node.new()
	health.name = "Health"
	health.set_script(_died_script())
	enemy.add_child(health)
	health.owner = root
	_assert(dock.has_died_signal(enemy), "a Health under the enemy counts as a died signal")
	var kt: Node = dock.wire_target(root, enemy, slime_obj)
	_assert(int(kt.get("type")) == 1 and enemy.get_node_or_null("PickupArea") == null, "a kill target adds no PickupArea")
	root.free()


# ---- tracker + the quest_log key ----------------------------------------------

func _tracker_and_key(dock: Object) -> void:
	var saved: Variant = ProjectSettings.get_setting("input/quest_log", null)
	ProjectSettings.set_setting("input/quest_log", null)
	var root := _level()
	var tr: Node = dock.wire_tracker(root)
	_assert(tr.get_script() == TRACKER_SCRIPT and tr.name == "QuestTracker" and tr.owner == root, "wire_tracker made a QuestTracker owned by the root")
	var layer := tr.get_parent()
	_assert(layer is CanvasLayer and layer.name == "UILayer" and layer.owner == root and layer.get_parent() == root, "it sits on an owned UILayer")
	var c := tr as Control
	_assert(c.anchor_left == 1.0 and c.anchor_right == 1.0 and c.anchor_top == 0.0 and c.anchor_bottom == 0.0
		and c.offset_right == -16.0 and c.offset_top == 16.0 and c.offset_right - c.offset_left == 360.0,
		"anchored top right, 16 px in, 360 wide")
	var again: Node = dock.wire_tracker(root)
	_assert(again == tr and _count_script(root, TRACKER_SCRIPT) == 1 and _count_class(root, "CanvasLayer") == 1,
		"once per scene: a second Apply reuses it and the UILayer")
	# a tracker already in an instanced HUD scene counts too
	var root2 := _level()
	var hud := CanvasLayer.new()
	root2.add_child(hud)
	hud.owner = root2
	var theirs: Node = TRACKER_SCRIPT.new()
	hud.add_child(theirs)
	theirs.owner = hud
	_assert(dock.wire_tracker(root2) == theirs, "a tracker inside an instanced sub-scene is reused, not doubled")
	root2.free()
	# J, on every device
	var cfg: Variant = ProjectSettings.get_setting("input/quest_log", null)
	var ok := cfg is Dictionary and (cfg["events"] as Array).size() == 1
	if ok:
		var k: InputEventKey = cfg["events"][0]
		ok = k.physical_keycode == KEY_J and k.device == -1
	_assert(ok, "Apply registers quest_log on J (physical key, every device)")
	_assert(dock.action_keys("quest_log") == "J", "the status line reads the key back as J")
	# a binding the project already has is left alone
	var kk := InputEventKey.new()
	kk.physical_keycode = KEY_L
	ProjectSettings.set_setting("input/quest_log", {"deadzone": 0.5, "events": [kk]})
	dock.ensure_log_action(false)
	_assert(dock.action_keys("quest_log") == "L", "an existing quest_log binding is kept")
	ProjectSettings.set_setting("input/quest_log", saved)
	# sized inside a 1280x720 parent
	var frame := Control.new()
	frame.size = Vector2(1280, 720)
	add_child(frame)
	var copy: Control = root.find_child("QuestTracker", true, false).duplicate()
	frame.add_child(copy)
	var r := copy.get_rect()
	_assert(r.size.x == 360.0 and r.size.y > 0.0 and r.end.x == 1264.0 and r.position.y == 16.0,
		"in a 1280x720 parent it's 360 wide at the top right (%s)" % r)
	frame.free()
	root.free()


# ---- player group + ids ----------------------------------------------------

func _player_and_ids(dock: Object) -> void:
	var root := _level()
	_assert(not dock.has_player(root), "has_player: false before anything is marked")
	var player: Node = root.get_node("Player")
	dock.mark_player(player)
	_assert(dock.has_player(root), "has_player: true after Make the selected node the player")
	var ps := PackedScene.new()
	ps.pack(root)
	var inst := ps.instantiate()
	_assert(inst.get_node("Player").is_in_group("player"), "the player group is persistent (saved with the scene)")
	inst.free()
	root.free()
	# blank and repeated ids get filled in
	var q: Resource = RESOURCE_SCRIPT.new()
	var a := _objective("", 0, "herb", 1)
	var b := _objective("", 0, "herb", 1)
	var c := _objective("same", 1, "wolf", 1)
	var d := _objective("same", 1, "boar", 1)
	var typed: Array[QuestObjectiveLite] = []
	for o in [a, b, c, d]:
		typed.append(o)
	q.objectives = typed
	_assert(dock.fill_missing_ids(q), "fill_missing_ids reports it changed something")
	_assert(String(q.id) == "quest" and a.id == "collect_herb" and b.id == "collect_herb_2" and c.id == "same" and d.id == "defeat_boar",
		"blank quest id and blank or repeated objective ids are filled (%s %s %s %s %s)" % [q.id, a.id, b.id, c.id, d.id])
	_assert(not dock.fill_missing_ids(q), "a second pass changes nothing")


# ---- 1.2 boards (plain Node + metadata) ------------------------------------------

func _legacy(dock: Object) -> void:
	var root := _level()
	var elder := Node2D.new()
	elder.name = "Elder"
	root.add_child(elder)
	elder.owner = root
	var old_quest := _quest("old_one", "Old one")
	var old := Node.new()
	old.name = "QuestBoard"
	old.set_meta("quest_kind", "quest_giver")
	old.set_meta("quest", old_quest)
	old.set_meta("auto_start", true)
	elder.add_child(old)
	old.owner = root

	# never re-Applied: plays exactly as before (a plain Node, nothing runs)
	_wipe()
	var ps := PackedScene.new()
	ps.pack(root)
	var played := ps.instantiate()
	add_child(played)
	await get_tree().process_frame
	await get_tree().process_frame
	var still: Node = played.get_node("Elder/QuestBoard")
	_assert(still.get_script() == null and still.get_meta("quest") != null and _quests_lite().list_quests().is_empty(),
		"an old board that's never re-Applied is still a plain Node with its metadata, and starts nothing")
	played.free()

	# re-Apply converts it in place
	var conv: Node = dock.wire_board(root, elder, null, START)
	_assert(conv == old, "re-Apply converts the same node (no second board)")
	_assert(conv.get_script() == BOARD_SCRIPT and conv.name == "QuestBoard", "it's a QuestBoardLite now, same name")
	_assert(conv.get("quest") == old_quest, "the quest moved from metadata into the Quest export")
	_assert(not conv.has_meta("quest_kind") and not conv.has_meta("quest") and not conv.has_meta("auto_start"), "the old metadata is gone")
	_assert(int(conv.get("start_mode")) == START, "auto_start=true became the scene-start mode")
	# auto_start=false meant "don't start it yet"
	var waiting := Node.new()
	waiting.set_meta("quest_kind", "register_set")
	waiting.set_meta("quest", old_quest)
	waiting.set_meta("auto_start", false)
	dock.convert_legacy_board(waiting)
	_assert(int(waiting.get("start_mode")) == TOUCH and waiting.get("quest") == old_quest, "auto_start=false became the wait-for-the-player mode")
	waiting.free()
	# a picked quest wins over the old one
	var old2 := Node.new()
	old2.name = "QuestBoard"
	old2.set_meta("quest_kind", "quest_giver")
	old2.set_meta("quest", old_quest)
	var npc: Node = root.get_node("NPC")
	npc.add_child(old2)
	old2.owner = root
	var picked := _quest("picked", "Picked")
	dock.wire_board(root, npc, picked, TOUCH)
	_assert(old2.get("quest") == picked and int(old2.get("start_mode")) == TOUCH, "converting with a quest picked uses the picked quest")
	# negative control: a plain Node that merely has the name isn't taken over
	var imposter := Node.new()
	imposter.name = "QuestBoard"
	var chest: Node = root.get_node("Chest")
	chest.add_child(imposter)
	imposter.owner = root
	var made: Node = dock.wire_board(root, chest, picked, START)
	_assert(made != imposter and imposter.get_script() == null, "a node that's only named QuestBoard is left alone")
	# and the converted board really works once played
	_wipe()
	var ps2 := PackedScene.new()
	ps2.pack(root)
	var played2 := ps2.instantiate()
	add_child(played2)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(_quests_lite().is_active("old_one"), "the converted board starts its quest when played")
	played2.free()
	_wipe()
	root.free()


# ---- the scene the dock built, played ----------------------------------------------

func _played_end_to_end(dock: Object) -> void:
	_wipe()
	var saved: Variant = ProjectSettings.get_setting("input/quest_log", null)
	ProjectSettings.set_setting("input/quest_log", null)
	var root := _level()
	var player: CharacterBody2D = root.get_node("Player")
	_give_shape(player)
	player.position = Vector2(-900, -900)
	var quest: Resource = RESOURCE_SCRIPT.new()
	quest.id = "herbs_and_slimes"
	quest.title = "Herbs and slimes"
	var typed: Array[QuestObjectiveLite] = []
	typed.append(_objective("collect_herb", 0, "herb", 2))
	typed.append(_objective("defeat_slime", 1, "slime", 1))
	quest.objectives = typed
	var npc: Node2D = root.get_node("NPC")
	npc.position = Vector2(0, 0)
	var herb1 := _node2d(root, "Herb", Vector2(300, 0))
	var herb2 := _node2d(root, "Herb2", Vector2(600, 0))
	var slime: Node2D = root.get_node("Enemy")
	slime.position = Vector2(900, 400)
	var health := Node.new()
	health.name = "Health"
	health.set_script(_died_script())
	slime.add_child(health)
	health.owner = root
	# the same calls the three outcomes make
	dock.wire_board(root, npc, quest, TOUCH)
	dock.wire_touch_area(root, npc, "QuestArea")
	dock.wire_target(root, herb1, quest.objectives[0])
	dock.wire_target(root, herb2, quest.objectives[0])
	dock.wire_target(root, slime, quest.objectives[1])
	dock.wire_tracker(root)
	_assert(not dock.has_player(root), "negative control: before Make the selected node the player, nothing is the player (the dock warns)")
	dock.mark_player(player)
	# a new game reads the Input Map from the project settings the dock wrote
	InputMap.load_from_project_settings()
	var ps := PackedScene.new()
	_assert(ps.pack(root) == OK, "the dock-built scene packs")
	root.free()
	var level := ps.instantiate()
	add_child(level)
	await _physics()
	var tracker: Control = level.get_node("UILayer/QuestTracker")
	var p: CharacterBody2D = level.get_node("Player")
	_assert(_quests_lite().is_registered("herbs_and_slimes") and not _quests_lite().is_active("herbs_and_slimes"), "played: the board registered the quest and waits")
	_assert(tracker.visible and tracker.get_text() == "", "played: the tracker is up, empty until a quest starts")
	p.global_position = level.get_node("NPC").global_position
	await _physics()
	_assert(_quests_lite().is_active("herbs_and_slimes"), "played: walking into the NPC starts the quest")
	_assert(_toasts().has("Quest started: Herbs and slimes"), "played: 'Quest started: Herbs and slimes' shows")
	_assert(tracker.get_text().contains("Collect herb 0/2"), "played: the tracker lists it (%s)" % tracker.get_text().replace("\n", " | "))
	var h1: Node = level.get_node("Herb")
	p.global_position = (h1 as Node2D).global_position
	await _physics()
	await get_tree().process_frame
	_assert(_quests_lite().get_progress("herbs_and_slimes", "collect_herb") == 1 and not is_instance_valid(h1), "played: touching a herb counts it and removes it")
	_assert(tracker.get_text().contains("Collect herb 1/2"), "played: the tracker shows 1/2")
	p.global_position = (level.get_node("Herb2") as Node2D).global_position
	await _physics()
	_assert(_toasts().has("Collect herb 2/2 done"), "played: 'Collect herb 2/2 done' shows")
	level.get_node("Enemy/Health").emit_signal("died")
	await get_tree().process_frame
	_assert(_quests_lite().is_complete("herbs_and_slimes"), "played: the slime's died completes the quest")
	_assert(_toasts().has("Quest complete: Herbs and slimes") and tracker.get_text().contains("Herbs and slimes: complete"),
		"played: 'Quest complete' shows and the tracker marks it")
	var r := tracker.get_global_rect()
	_assert(r.size.x == 360.0 and r.size.y > 0.0, "played: the tracker has a real size (%s)" % r)
	await _press_j()
	_assert(not tracker.visible, "played: J (the action the dock registered) hides the tracker")
	await _press_j()
	_assert(tracker.visible, "played: J shows it again")
	level.free()
	ProjectSettings.set_setting("input/quest_log", saved)
	InputMap.load_from_project_settings()
	_wipe()


# ---- helpers -----------------------------------------------------------------

# The probe stage: MyGame with Player, Enemy (CharacterBody2D), Chest (Area2D), NPC.
func _level() -> Node2D:
	var root := Node2D.new()
	root.name = "MyGame"
	var player := CharacterBody2D.new()
	player.name = "Player"
	var enemy := CharacterBody2D.new()
	enemy.name = "Enemy"
	var chest := Area2D.new()
	chest.name = "Chest"
	chest.position = Vector2(300, 320)
	var npc := Node2D.new()
	npc.name = "NPC"
	for n in [player, enemy, chest, npc]:
		root.add_child(n)
		n.owner = root
	return root


func _node2d(root: Node, node_name: String, pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.position = pos
	root.add_child(n)
	n.owner = root
	return n


func _give_shape(body: Node) -> void:
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 8.0
	cs.shape = c
	body.add_child(cs)
	cs.owner = body.owner


func _quest(id: String, title: String = "") -> Resource:
	var q: Resource = RESOURCE_SCRIPT.new()
	q.id = id
	q.title = title
	return q


func _objective(id: String, type: int, target: String, required: int) -> QuestObjectiveLite:
	var o := QuestObjectiveLite.new()
	o.id = id
	o.type = type
	o.target_id = target
	o.required = required
	return o


func _died_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nsignal died\n"
	s.reload()
	return s


func _count_script(parent: Node, script: Script) -> int:
	var n := 0
	for c in parent.find_children("*", "", true, false):
		if c.get_script() == script:
			n += 1
	return n


func _count_class(parent: Node, cls: String) -> int:
	var n := 0
	for c in parent.find_children("*", "", true, false):
		if c.is_class(cls):
			n += 1
	return n


# ---- the Quests (Lite) tab's own New ----------------------------------------

# New starts from an id and a title (new_quest / "New Quest", then new_quest_2
# ...) and never lands on the Setup tab's starter_quest.tres in the same folder.
func _quests_tab_new(dock: Object) -> void:
	var dir := "user://verify_quests_tab_new/"
	_wipe_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var starter_path := dir.path_join("starter_quest.tres")
	ResourceSaver.save(dock.make_starter_quest("starter_quest"), starter_path)  # what New starter quest… writes
	var tab: Control = load("res://addons/quests_lite/editor/lite_dock.gd").new()
	add_child(tab)
	await get_tree().process_frame
	tab._dir = dir
	tab._on_new()
	var first: String = tab._current_path
	var q1: Resource = _fresh(first)
	_assert(first.get_file() == "new_quest.tres" and q1 != null and String(q1.id) == "new_quest" and String(q1.title) == "New Quest",
		"Quests tab New gives its quest an id and a title (%s: %s / %s)" % [first.get_file(), q1.id if q1 else "?", q1.title if q1 else "?"])
	_assert(tab._current != null and String(tab._current.title) == "New Quest", "the tab's form shows that title straight away")
	_assert(String(tab._status.text).begins_with("Made " + first), "its status says where it went (%s)" % tab._status.text)
	tab._on_new()
	var second: String = tab._current_path
	var q2: Resource = _fresh(second)
	_assert(second.get_file() == "new_quest_2.tres" and q2 != null and String(q2.id) == "new_quest_2" and String(q2.title) == "New Quest 2",
		"a second New is new_quest_2, New Quest 2 (%s)" % second.get_file())
	var starter: Resource = _fresh(starter_path)
	_assert(starter != null and String(starter.id) == "starter_quest" and String(starter.title) == "Starter quest" and starter.objectives.size() == 2,
		"the Setup tab's starter_quest.tres is left alone")
	var next_starter: String = dock._unique(dir.path_join("starter_quest"))
	_assert(not next_starter.get_file().begins_with("new_quest") and not FileAccess.file_exists(next_starter),
		"and its next starter quest doesn't land on a tab-made one (%s)" % next_starter.get_file())
	var ids := {}
	for p in tab._paths:
		ids[String(_fresh(p).id)] = true
	_assert(tab._paths.size() == 3 and ids.size() == 3, "the tab lists all three quests, with three different ids (%s)" % str(ids.keys()))
	var labels := {}
	for i in tab._list.item_count:
		labels[tab._list.get_item_text(i)] = true
	_assert(labels.has("New Quest") and labels.has("New Quest 2") and labels.has("Starter quest"),
		"the tab lists quests by title, not by file name (%s)" % str(labels.keys()))
	tab.queue_free()
	_wipe_dir(dir)
	await get_tree().process_frame


# Straight from disk, past anything an earlier step left in the cache.
func _fresh(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _wipe_dir(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func _wipe() -> void:
	_quests_lite()._quests.clear()
	_quests_lite()._state.clear()
	_quests_lite()._progress.clear()


func _physics(frames := 4) -> void:
	for i in frames:
		await get_tree().physics_frame


func _toasts() -> PackedStringArray:
	var out := PackedStringArray()
	for n in get_tree().get_nodes_in_group("lite_toast"):
		if n is Label and not n.is_queued_for_deletion():
			out.append((n as Label).text)
	return out


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


# A quest made in the Quests (Lite) tab while this one is on screen is in the quest
# list the next time it opens, and the picked quest stays picked.
func _run_quest_list_refresh() -> void:
	var tab = CHOOSER.new()
	add_child(tab)
	await get_tree().process_frame
	var pick: OptionButton = tab._quest_pick
	var had_dir := DirAccess.dir_exists_absolute(CHOOSER.QUEST_DIR)
	DirAccess.make_dir_recursive_absolute(CHOOSER.QUEST_DIR)
	ResourceSaver.save(RESOURCE_SCRIPT.new(), CHOOSER.QUEST_DIR.path_join("f12b_a.tres"))
	pick.get_popup().about_to_popup.emit()
	var at := _option_texts(pick).find("f12b_a")
	_assert(at >= 0, "a quest made after the tab was built is in its list when it opens (%s)" % [_option_texts(pick)])
	if at >= 0:
		pick.select(at)
	ResourceSaver.save(RESOURCE_SCRIPT.new(), CHOOSER.QUEST_DIR.path_join("f12b_b.tres"))
	pick.get_popup().about_to_popup.emit()
	_assert(_option_texts(pick).has("f12b_b") and pick.get_item_text(pick.selected) == "f12b_a",
		"the next one shows up too, and the quest that was picked stays picked (%s)" % pick.get_item_text(pick.selected))
	_assert(tab._obj_pick.get_popup().about_to_popup.is_connected(tab._refresh_objectives), "its Counts toward list reads the quest again when it opens")
	for f in ["f12b_a.tres", "f12b_b.tres"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHOOSER.QUEST_DIR.path_join(f)))
	if not had_dir:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHOOSER.QUEST_DIR))
	tab.free()
func _option_texts(ob: OptionButton) -> PackedStringArray:
	var out := PackedStringArray()
	for i in ob.item_count:
		out.append(ob.get_item_text(i))
	return out


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# QuestsLite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const QUESTS_LITE := preload("res://addons/quests_lite/quest_manager_lite.gd")


static func _quests_lite() -> QUESTS_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"QuestsLite") as QUESTS_LITE
