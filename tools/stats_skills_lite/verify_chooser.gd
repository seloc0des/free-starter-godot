extends Node

# Headless test for the Stats — Lite chooser's wiring logic (the part behind the
# Apply button). Editor-only calls (get_edited_scene_root/selection) are split
# out; this drives the pure wire_stats helper against a real scene tree and
# asserts the result is baked-in and re-entrant.
# Run: godot --headless --path . res://tools/stats_skills_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/stats_skills_lite/editor/stats-skills_chooser_dock.gd")
const COMPONENT := "res://addons/stats_skills_lite/stats_component_lite.gd"
const LIST := preload("res://addons/stats_skills_lite/stats_list_lite.gd")
const PICKUP := preload("res://addons/stats_skills_lite/stat_pickup_lite.gd")

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- stats lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# A selected child, like a Player node. Bake onto it, owned by the scene root.
	var player := Node.new()
	player.name = "Player"
	root.add_child(player); player.owner = root

	# PLAYER STATS — component lands on the target
	var comp1 = dock.wire_stats(root, player, "player")
	_assert(comp1 != null, "wire_stats created a component")
	_assert(comp1.get_script() != null and comp1.get_script().get_global_name() == "StatsComponentLite",
		"created node is a StatsComponentLite")
	_assert(comp1.get_parent() == player, "component parented under the selected node")
	_assert(comp1.owner == root, "component owned by scene root: bakes into the .tscn")
	var defs1: Array = comp1.get("definitions")
	_assert(defs1.size() == 3, "player starter seeded 3 stat definitions (got %d)" % defs1.size())
	_assert(String(defs1[0].id) == "health", "first player stat is 'health' (got '%s')" % String(defs1[0].id))
	_assert(player.is_in_group("player"), "player stats marked the target as the player")
	var enemy_node := Node.new()
	root.add_child(enemy_node); enemy_node.owner = root
	dock.wire_stats(root, enemy_node, "enemy")
	_assert(not enemy_node.is_in_group("player"), "enemy stats don't mark the target as the player")

	# RE-ENTRANT — applying again reuses the same component, never a second one
	var comp2 = dock.wire_stats(root, player, "enemy")
	_assert(comp2 == comp1, "second Apply reused the same component (no duplicate)")
	var comp_count := 0
	for c in player.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == "StatsComponentLite":
			comp_count += 1
	_assert(comp_count == 1, "exactly one component after two Applies (got %d)" % comp_count)

	# OPTIONS PRESERVED — the second starter swapped the definitions in place
	var defs2: Array = comp2.get("definitions")
	_assert(defs2.size() == 2, "enemy starter swapped to 2 definitions (got %d)" % defs2.size())
	_assert(absf(float(defs2[0].base_value) - 30.0) < 0.001,
		"enemy health base is 30 (got %s)" % str(defs2[0].base_value))

	# SCOPE = scene root — target IS the root; component owned by (and re-editable on) root
	var root_only := Node.new()
	get_tree().root.add_child(root_only)
	var comp_root = dock.wire_stats(root_only, root_only, "blank")
	_assert(comp_root.get_parent() == root_only, "scene-root scope parents the component on the root")
	_assert(comp_root.owner == root_only, "scene-root component is owned by the root")
	_assert((comp_root.get("definitions") as Array).is_empty(), "blank starter seeds no definitions")
	root_only.queue_free()

	# OWNERSHIP — a component inside an instanced sub-scene (owner != root) must NOT
	# be hijacked; Apply should make a fresh component the scene actually owns.
	# Fresh root so the ONLY component present is the non-owned one.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var sub := Node.new()
	root2.add_child(sub); sub.owner = root2
	var buried = load(COMPONENT).new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	var fresh = dock.wire_stats(root2, root2, "player")
	_assert(fresh != buried, "did not hijack a component owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh component the scene root owns")
	root2.queue_free()

	# PLAYER STATS also add the stats list (once) and the C key
	var list: Node = root.get_node_or_null("UILayer/StatsList")
	_assert(list != null and list.get_script() == LIST and list.owner == root, "player stats added a StatsList, baked into the scene")
	_assert(list != null and list.get_parent() is CanvasLayer and list.get_parent().owner == root, "it sits on a UILayer CanvasLayer, so a moving camera doesn't take it along")
	_assert(list != null and not list.visible, "it starts hidden (C opens it)")
	dock.wire_stats(root, player, "player")
	_assert(_count_script(root, LIST) == 1, "re-applying player stats keeps one list (got %d)" % _count_script(root, LIST))
	var frame := Control.new()
	frame.size = Vector2(1280, 720)
	get_tree().root.add_child(frame)
	var lr := Rect2()
	if list is Control:
		var probe_list: Control = list.duplicate()
		frame.add_child(probe_list)
		lr = probe_list.get_rect()
	_assert(lr.size.x > 100 and lr.size.y > 100 and lr.position == Vector2(16, 80) and lr.end.y <= 340, "the list is sized and sits left, under the HUD strip, in 1280x720 (%s)" % lr)
	frame.queue_free()
	var cfg: Variant = ProjectSettings.get_setting("input/character", null)
	var ev: InputEventKey = null
	if cfg is Dictionary and not (cfg as Dictionary).get("events", []).is_empty():
		ev = (cfg as Dictionary)["events"][0] as InputEventKey
	_assert(ev != null and ev.physical_keycode == KEY_C and ev.device == -1, "it adds the character action: physical C, any device")
	_assert(dock.action_keys("character") == "C", "the status line can name the key (%s)" % dock.action_keys("character"))
	var foe := Node.new()
	foe.name = "Foe"
	root.add_child(foe); foe.owner = root
	dock.wire_stats(root, root, "enemy")
	var pdefs: Array = comp1.get("definitions")
	_assert(pdefs.size() == 3 and _count_script(root, load(COMPONENT)) >= 2, "enemy stats on the scene root get their own component (the player's keeps its 3 stats)")
	dock.wire_stats(root, player, "player")
	_assert((comp1.get("definitions") as Array).size() == 3, "player stats re-applied to the player update the player's component")
	var root_comp: Node = null
	for c in root.get_children():
		if c.get_script() != null and c.get_script().resource_path == COMPONENT:
			root_comp = c
	_assert(root_comp != null and (root_comp.get("definitions") as Array).size() == 2, "and the scene root's enemy stats are left alone")

	# the stat dropdown comes from the player's own stats
	var rows: Array = dock.player_stat_rows(root)
	var ids: Array = []
	for r in rows:
		ids.append(r["id"])
	_assert(ids == ["health", "attack", "defense"] and rows[1]["name"] == "Attack", "the stat picker lists the player's stats (%s)" % str(ids))
	var loner := Node.new()
	get_tree().root.add_child(loner)
	_assert(dock.player_stat_rows(loner).is_empty(), "no player with stats in the scene: nothing listed (the tab falls back to the starter's)")
	loner.queue_free()

	# BOOST: a StatPickup, plus a PickupArea when the node can't be touched as is
	var potion := Sprite2D.new()
	potion.name = "Potion"
	root.add_child(potion); potion.owner = root
	var pk1 = dock.wire_pickup(root, potion, "attack", 5.0, 10.0)
	_assert(pk1 != null and pk1.get_script() == PICKUP and pk1.get_parent() == potion and pk1.owner == root, "boost Apply added a StatPickupLite on the node, baked in")
	_assert(String(pk1.name) == "StatPickup", "it has a readable name (%s)" % pk1.name)
	_assert(str(pk1.get("stat_id")) == "attack" and _approx(float(pk1.get("amount")), 5.0) and _approx(float(pk1.get("duration")), 10.0), "it carries the picked stat, amount and seconds")
	var parea := potion.get_node_or_null("PickupArea")
	_assert(parea is Area2D and parea.owner == root and parea.get_node("CollisionShape").shape is CircleShape2D, "a sprite gets a PickupArea with a shape, baked in")
	var pk2 = dock.wire_pickup(root, potion, "defense", 2.0, 0.0)
	_assert(pk2 == pk1 and str(pk1.get("stat_id")) == "defense" and _approx(float(pk1.get("duration")), 0.0), "re-Apply updates the same pickup")
	_assert(_count_script(potion, PICKUP) == 1 and potion.get_children().filter(func(c): return String(c.name) == "PickupArea").size() == 1, "one pickup and one PickupArea after two Applies")
	var shrine := Area2D.new()
	shrine.name = "Shrine"
	root.add_child(shrine); shrine.owner = root
	var ss := CollisionShape2D.new()
	ss.shape = CircleShape2D.new()
	shrine.add_child(ss); ss.owner = root
	dock.wire_pickup(root, shrine, "attack", 1.0, 0.0)
	_assert(shrine.get_node_or_null("PickupArea") == null, "an Area with a shape needs no PickupArea")
	var root3 := Node3D.new()
	get_tree().root.add_child(root3)
	var gem := Node3D.new()
	root3.add_child(gem); gem.owner = root3
	dock.wire_pickup(root3, gem, "attack", 1.0, 0.0)
	_assert(gem.get_node_or_null("PickupArea") is Area3D, "a 3D node gets an Area3D")
	root3.queue_free()

	# Apply selects what it made, so the next Apply steps back up to the host
	_assert(dock._host_of(pk1, root) == potion and dock._host_of(parea, root) == potion and dock._host_of(parea.get_node("CollisionShape"), root) == potion, "a selected pickup, PickupArea or shape steps up to its node")
	_assert(dock._host_of(comp1, root) == player, "a selected stats component steps up to the player (so it never gets tagged as the player)")

	# A2: boosts only react to the player
	var bare := Node.new()
	get_tree().root.add_child(bare)
	_assert(dock.no_player_note(bare).contains("Make the selected node the player"), "no player in a scene: the note asks for one")
	bare.queue_free()
	_assert(dock.no_player_note(root) == "", "a scene with a player: no note")

	root.queue_free()
	await get_tree().process_frame
	await _run_played_scene(dock)
	dock.free()
	await _run_stat_list_refresh()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# Build a level with the dock's own wiring, pack it the way Save does, play it:
# press C, walk into the potion, watch the list.
func _run_played_scene(dock) -> void:
	var lvl := Node2D.new()
	lvl.name = "Level"
	var hero := CharacterBody2D.new()
	hero.name = "Hero"
	hero.position = Vector2(40, 40)
	lvl.add_child(hero); hero.owner = lvl
	var hs := CollisionShape2D.new()
	var hb := RectangleShape2D.new()
	hb.size = Vector2(16, 16)
	hs.shape = hb
	hero.add_child(hs); hs.owner = lvl
	var potion := Sprite2D.new()
	potion.name = "Potion"
	potion.position = Vector2(400, 200)
	lvl.add_child(potion); potion.owner = lvl
	dock.wire_stats(lvl, hero, "player")
	dock.wire_pickup(lvl, potion, "attack", 5.0, 0.5)
	var pk := PackedScene.new()
	pk.pack(lvl)
	lvl.free()
	# what the game reads from project.godot: the action the dock added
	var had := InputMap.has_action("character")
	if not had:
		InputMap.add_action("character")
		for e in (ProjectSettings.get_setting("input/character") as Dictionary)["events"]:
			InputMap.action_add_event("character", e)
	var run := pk.instantiate()
	get_tree().root.add_child(run)
	for i in 3:
		await get_tree().physics_frame
	var list: Control = run.get_node("UILayer/StatsList")
	var player: Node2D = run.get_node("Hero")
	_assert(not list.visible, "played: the stats list starts hidden")
	await _key(KEY_C)
	_assert(list.visible, "played: C opens it")
	_assert("Attack: 10" in list.lines(), "played: it lists the player's Attack (%s)" % ", ".join(list.lines()))
	player.position = Vector2(400, 200)
	for i in 4:
		await get_tree().physics_frame
	var stats: Node = run.get_node("Hero/StatsLite")
	_assert(_approx(float(stats.get_stat("attack")), 15.0), "played: walking into the dock-built potion raises Attack to 15")
	_assert("Attack: 15" in list.lines(), "played: the list shows it (%s)" % ", ".join(list.lines()))
	_assert(_toast_has("+5 Attack for 0.5s"), "played: a message says +5 Attack for 0.5s")
	_assert(run.get_node_or_null("Potion") == null or run.get_node("Potion").is_queued_for_deletion(), "played: the potion disappears")
	await get_tree().create_timer(0.8).timeout
	_assert(_approx(float(stats.get_stat("attack")), 10.0) and "Attack: 10" in list.lines(), "played: the boost wears off and the list follows")
	await _key(KEY_C)
	_assert(not list.visible, "played: C closes it")
	if not had:
		InputMap.erase_action("character")
	run.queue_free()


func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = code
	Input.parse_input_event(up)
	await get_tree().process_frame


func _toast_has(text: String) -> bool:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Label and (t as Label).text.contains(text):
			return true
	return false


func _count_script(node: Node, script: Script) -> int:
	var n := 0
	for c in node.find_children("*", "", true, false):
		if c.get_script() == script:
			n += 1
	return n


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


# The boost's Stat list reads the player's stats again each time it opens, so a
# stat added in the Stats (Lite) tab shows up. (Reading them needs the open scene,
# so outside the editor this checks the list is hooked to the refresh.)
func _run_stat_list_refresh() -> void:
	var tab = CHOOSER.new()
	add_child(tab)
	await get_tree().process_frame
	_assert(tab._stat_pick.get_popup().about_to_popup.is_connected(tab._refresh_stat_choices), "the boost's Stat list reads the player's stats again when it opens")
	tab.free()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)
