extends Node

# Headless test for the Dialogue · Setup chooser (Lite). First the wire_* helpers
# behind Apply, against a real scene tree (baked in, re-entrant, sized), then the
# part a buyer actually sees: the scene packed the way Play saves it, played
# back, a player walking into the NPC and a conversation starting.
# tools/verify.tscn runs this too.
#   godot --headless --path . res://tools/dialogue_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/dialogue_lite/editor/dialogue_chooser_dock.gd")
const DEMO := preload("res://tools/dialogue_lite/demo/demo_dialogue.gd")
const BOX_SCENE := "res://addons/dialogue_lite/dialogue_box_lite.tscn"
const TRIGGER_PATH := "res://addons/dialogue_lite/dialogue_trigger_lite.gd"


func _ready() -> void:
	var r: Dictionary = await run(self)
	for l in r["lines"]:
		print("  ", l)
	print("=== ", "PASS" if r["ok"] else "FAIL", " ===")
	get_tree().quit(0 if r["ok"] else 1)


static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree := host.get_tree()

	var dock: Control = CHOOSER.new()
	host.add_child(dock)  # _ready builds the picker
	ok = _chk(lines, String(dock.name) == "Dialogue · Setup", "chooser: names its tab 'Dialogue · Setup'") and ok

	# --- picker: the buyer's own first, then the demo's as an example ---
	var own_dir := "user://chooser_own_dialogues"
	DirAccess.make_dir_recursive_absolute(own_dir)
	var mine := DialogueLite.new()
	mine.id = "my_guard"
	ResourceSaver.save(mine, own_dir.path_join("my_guard.tres"))
	var found: Array = dock.scan_dialogues(own_dir)
	ok = _chk(lines, found.size() >= 1 and String(found[0]["path"]).ends_with("my_guard.tres") and not found[0]["example"],
		"picker: the buyer's own conversation is listed first") and ok
	var healer_path := ""
	for f in found:
		if f["example"] and String(f["path"]).ends_with("healer_intro.tres"):
			healer_path = f["path"]
	# The starter kits carry this test without the lite demo, so there are no
	# examples to offer there. Only check them when the demo is in the project.
	var has_demo := false
	for d in CHOOSER.EXAMPLE_DIRS:
		has_demo = has_demo or DirAccess.dir_exists_absolute(d)
	DirAccess.remove_absolute(own_dir.path_join("my_guard.tres"))
	DirAccess.remove_absolute(own_dir)
	if has_demo:
		ok = _chk(lines, healer_path != "", "picker: the demo's healer_intro is offered as an example (%s)" % healer_path) and ok
		var shown: PackedStringArray = dock._paths
		ok = _chk(lines, shown.size() >= 1 and dock._picker.get_item_text(0).contains("(example)"),
			"picker: fills itself on open, examples tagged") and ok
	else:
		lines.append("[--] picker: no demo in this project, so there are no examples to check")
	if healer_path == "":
		# same conversation, built by the demo script and saved so it has a path
		healer_path = "user://chooser_fixture_healer_intro.tres"
		ResourceSaver.save(DEMO.healer_intro(), healer_path)
	var healer: DialogueLite = load(healer_path)

	# --- talk to this NPC (2D): the scene is built loose, like the editor's ---
	var root := Node2D.new()
	root.name = "Level"
	var npc: Node2D = _owned(root, root, Node2D.new(), "NPC")
	npc.position = Vector2(300, 300)
	var player: CharacterBody2D = _owned(root, root, CharacterBody2D.new(), "Player")
	_add_box_shape(root, player, Vector2(20, 20))
	var crate: CharacterBody2D = _owned(root, root, CharacterBody2D.new(), "Crate")
	crate.position = Vector2(-300, 0)
	_add_box_shape(root, crate, Vector2(20, 20))

	var trig: Node = dock.wire_talk(root, npc, healer)
	var area: Node = npc.get_node_or_null("TalkArea")
	ok = _chk(lines, area is Area2D and area.owner == root, "talk: a plain Node2D NPC gets an owned TalkArea (Area2D)") and ok
	var shape: CollisionShape2D = area.get_node_or_null("Shape") if area != null else null
	ok = _chk(lines, shape != null and shape.shape is CircleShape2D and shape.owner == root,
		"talk: the TalkArea has a round collision shape that saves with the scene") and ok
	var trig_script: Script = trig.get_script() if trig != null else null
	ok = _chk(lines, trig != null and trig_script != null and trig_script.resource_path == TRIGGER_PATH
		and trig.get_parent() == area and trig.owner == root and String(trig.name) == "TalkTrigger",
		"talk: a DialogueTriggerLite sits inside the area, owned by the scene") and ok
	ok = _chk(lines, int(trig.get("when")) == 0 and String(trig.get("require_group")) == "player"
		and trig.get("dialogue") == healer, "talk: fires on touch, player group only, with the picked .tres") and ok

	var again: Node = dock.wire_talk(root, npc, healer)
	ok = _chk(lines, again == trig and _count(npc, "TalkArea") == 1 and area.get_child_count() == 2,
		"talk: a second Apply reuses the area, shape and trigger") and ok
	var other := DialogueLite.new()
	other.id = "other_one"
	dock.wire_talk(root, npc, other)
	ok = _chk(lines, trig.get("dialogue") == other, "talk: re-picking swaps the conversation on the same trigger") and ok
	dock.wire_talk(root, npc, healer)

	# an NPC that already is an Area keeps its own area, and gets a shape if it has none
	var sign_area: Area2D = _owned(root, root, Area2D.new(), "Sign")
	var sign_trig: Node = dock.wire_talk(root, sign_area, healer)
	ok = _chk(lines, sign_trig.get_parent() == sign_area and sign_area.get_node_or_null("TalkArea") == null,
		"talk: an Area2D NPC hosts the trigger itself") and ok
	ok = _chk(lines, sign_area.get_node_or_null("Shape") is CollisionShape2D, "talk: a shapeless Area2D NPC gets a shape") and ok
	sign_area.free()

	# 3D NPC
	var root3 := Node3D.new()
	var npc3: Node3D = _owned(root3, root3, Node3D.new(), "Villager")
	dock.wire_talk(root3, npc3, healer)
	var area3: Node = npc3.get_node_or_null("TalkArea")
	var shape3: Node = area3.get_node_or_null("Shape") if area3 != null else null
	ok = _chk(lines, area3 is Area3D and shape3 is CollisionShape3D and shape3.shape is SphereShape3D,
		"talk: a Node3D NPC gets an Area3D with a sphere") and ok
	root3.free()

	# --- the dialogue box ---
	var box: Node = dock.wire_box(root)
	ok = _chk(lines, box is Control and box.get_parent() is CanvasLayer and String(box.get_parent().name) == "UILayer"
		and box.get_parent().owner == root and box.owner == root, "box: added under an owned UILayer") and ok
	ok = _chk(lines, box.scene_file_path == BOX_SCENE, "box: it's an instance of dialogue_box_lite.tscn, not a flattened copy") and ok
	var c := box as Control
	ok = _chk(lines, c != null and c.anchor_right == 1.0 and c.anchor_bottom == 1.0 and c.anchor_left == 0.0 and c.anchor_top == 0.0,
		"box: anchored full screen") and ok
	ok = _chk(lines, dock.wire_box(root) == box and _count(root, "UILayer") == 1, "box: a second Apply adds no second box") and ok

	# a box already in the scene counts even inside an instanced sub-scene
	var root4 := Node2D.new()
	var hud: Node = _owned(root4, root4, Node.new(), "Hud")
	var their_box: Node = (load(BOX_SCENE) as PackedScene).instantiate()
	hud.add_child(their_box)
	their_box.owner = hud  # owned by the sub-scene, like an instanced HUD
	ok = _chk(lines, dock.wire_box(root4) == their_box and root4.get_node_or_null("UILayer") == null,
		"box: one inside an instanced sub-scene is reused, not doubled") and ok
	root4.free()

	# pressing Play right after Apply has to show it properly: a 1280x720 screen
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	host.add_child(vp)
	var level := Node2D.new()
	vp.add_child(level)
	var sized: Control = dock.wire_box(level)
	sized.show()
	await tree.process_frame
	await tree.process_frame
	var panel: Control = sized.get_node_or_null("Margin")
	ok = _chk(lines, sized.size == Vector2(1280, 720), "box: fills a 1280x720 screen (%s)" % str(sized.size)) and ok
	ok = _chk(lines, panel != null and panel.size.x == 1280.0 and panel.size.y > 0.0 and panel.position.y >= 360.0,
		"box: its panel sits along the bottom (%s at %s)" % [str(panel.size) if panel else "-", str(panel.position) if panel else "-"]) and ok
	vp.free()

	# --- the player group ---
	ok = _chk(lines, not dock.has_player(root), "player: nothing marked yet is reported") and ok
	player.add_to_group("player")  # runtime-only, the way a live script would add it
	dock.mark_player(player)
	ok = _chk(lines, dock.has_player(root), "player: marked after 'Make the selected node the player'") and ok

	# --- play it back: pack the way Play saves it, then walk into the NPC ---
	var ps := PackedScene.new()
	ok = _chk(lines, ps.pack(root) == OK, "play: the wired scene packs") and ok
	root.free()
	var live: Node2D = ps.instantiate()
	host.add_child(live)
	var live_player: CharacterBody2D = live.get_node("Player")
	var live_box: Control = live.get_node("UILayer").get_child(0)
	ok = _chk(lines, live_player.is_in_group("player"), "play: the player group was saved with the scene, even over a runtime-only one") and ok
	ok = _chk(lines, dock.has_player(live), "player: found through the tree once it's running") and ok

	var started: Array[String] = []
	var on_start := func(id: String) -> void: started.append(id)
	_dialogues_lite().dialogue_started.connect(on_start)
	await _physics(tree, 3)
	ok = _chk(lines, started.is_empty(), "play: nothing starts while the player is away") and ok

	var live_crate: Node2D = live.get_node("Crate")
	var live_area: Area2D = live.get_node("NPC/TalkArea")
	live_crate.global_position = live.get_node("NPC").global_position
	for i in 30:
		await tree.physics_frame
		if live_area.overlaps_body(live_crate):
			break
	ok = _chk(lines, live_area.overlaps_body(live_crate) and started.is_empty(),
		"play: a body outside the player group walks in and nothing starts") and ok

	live_player.global_position = live.get_node("NPC").global_position
	for i in 30:
		await tree.physics_frame
		if not started.is_empty():
			break
	ok = _chk(lines, started.size() == 1 and started[0] == "healer_intro",
		"play: walking into the NPC starts 'healer_intro' (%s)" % str(started)) and ok
	ok = _chk(lines, live_box.visible and _dialogues_lite().current_node() != null, "play: the box shows the first line") and ok
	ok = _chk(lines, _dialogues_lite()._registry.get("healer_intro") == healer,
		"play: a conversation from outside any registered list got registered on the way") and ok

	# a second touch mid-talk doesn't restart it
	var line_before := _dialogues_lite().current_node()
	ok = _chk(lines, not _dialogues_lite().start_dialogue(other) and _dialogues_lite().current_node() == line_before,
		"start_dialogue: won't cut off a running conversation") and ok
	await _end_talk(tree)
	live.free()

	# --- start when the scene loads ---
	var root2 := Node2D.new()
	root2.name = "Intro"
	var on_load: Node = dock.wire_on_load(root2, healer)
	dock.wire_box(root2)
	ok = _chk(lines, on_load.get_parent() == root2 and on_load.owner == root2 and String(on_load.name) == "DialogueOnLoad",
		"on load: a DialogueOnLoad trigger at the scene root") and ok
	ok = _chk(lines, int(on_load.get("when")) == 1 and on_load.get("dialogue") == healer,
		"on load: fires on ready with the picked .tres") and ok
	ok = _chk(lines, dock.wire_on_load(root2, healer) == on_load, "on load: a second Apply reuses the trigger") and ok
	var ps2 := PackedScene.new()
	ps2.pack(root2)
	root2.free()
	started.clear()
	var intro: Node = ps2.instantiate()
	host.add_child(intro)
	await tree.process_frame
	await tree.process_frame
	ok = _chk(lines, started.size() == 1 and started[0] == "healer_intro",
		"on load: the conversation starts as the scene opens (%s)" % str(started)) and ok
	await _end_talk(tree)
	intro.free()

	# --- start_dialogue guards ---
	ok = _chk(lines, not _dialogues_lite().start_dialogue(null), "start_dialogue: null is refused with a warning") and ok
	ok = _chk(lines, not _dialogues_lite().start_dialogue(Resource.new()), "start_dialogue: a non-DialogueLite resource is refused") and ok

	_dialogues_lite().dialogue_started.disconnect(on_start)
	dock.free()
	return {"ok": ok, "lines": lines}


static func _owned(root: Node, parent: Node, n: Node, node_name: String) -> Node:
	n.name = node_name
	parent.add_child(n)
	n.owner = root
	return n


static func _add_box_shape(root: Node, body: Node, size: Vector2) -> void:
	var rect := RectangleShape2D.new()
	rect.size = size
	var cs := CollisionShape2D.new()
	cs.shape = rect
	_owned(root, body, cs, "Shape")


static func _count(parent: Node, node_name: String) -> int:
	var n := 0
	for c in parent.get_children():
		if String(c.name) == node_name:
			n += 1
	return n


static func _physics(tree: SceneTree, frames: int) -> void:
	for i in frames:
		await tree.physics_frame


# a frame first, so nothing the box queued deferred lands on a freed node
static func _end_talk(tree: SceneTree) -> void:
	await tree.process_frame
	if _dialogues_lite().is_active():
		_dialogues_lite()._finish()


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond


# DialoguesLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const DIALOGUES_LITE := preload("res://addons/dialogue_lite/dialogue_manager_lite.gd")


static func _dialogues_lite() -> DIALOGUES_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"DialoguesLite") as DIALOGUES_LITE
