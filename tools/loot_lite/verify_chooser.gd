extends Node

# Headless test for the Loot — Lite chooser's wiring (the part behind Apply).
# Editor-only calls (get_edited_scene_root/selection) are split out; this drives
# the pure wire_drop / make_starter_table / table_paths helpers against a real
# scene tree, then packs a scene the dock built and plays it: the player walks
# into the chest and the enemy dies, and the loot lands in the bag.
# Run: godot --headless --path . res://tools/loot_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/loot_lite/editor/loot_chooser_dock.gd")
const RESOURCE_SCRIPT := preload("res://addons/loot_lite/loot_table.gd")
const ITEM_SCRIPT := preload("res://addons/loot_lite/item_resource.gd")
const DROP_SCRIPT := preload("res://addons/loot_lite/loot_drop_lite.gd")
const BAG_SCRIPT := preload("res://tools/loot_lite/test_bag.gd")
const HEALTH_SCRIPT := preload("res://tools/loot_lite/test_health.gd")

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- loot lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node2D.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)
	var chest := Node2D.new()
	chest.name = "Chest"
	root.add_child(chest); chest.owner = root
	var table := _table("bandit_drop")

	# TOUCH on a plain node: a LootDrop plus a LootArea to walk into.
	var d1 = dock.wire_drop(root, chest, "touch", table)
	_assert(d1 != null and d1.get_script() == DROP_SCRIPT, "touch Apply added a LootDropLite")
	_assert(d1.get_parent() == chest and d1.owner == root, "it sits on the chosen node, owned by the scene root (bakes into the .tscn)")
	_assert(String(d1.name) == "LootDrop", "it has a readable name (%s)" % d1.name)
	_assert(int(d1.get("trigger")) == 0 and d1.get("table") == table, "it drops on touch, from the picked table")
	_assert(bool(d1.get("once")), "it drops once by default")
	var area := chest.get_node_or_null("LootArea")
	_assert(area is Area2D and area.owner == root, "a plain node gets a LootArea to walk into, baked in")
	var shape: Node = area.get_node_or_null("CollisionShape") if area != null else null
	_assert(shape is CollisionShape2D and shape.shape is CircleShape2D and shape.owner == root, "the LootArea has a shape, baked in")

	# RE-ENTRANT: Apply again updates the same nodes, never a second set.
	var table2 := _table("bandit_drop_v2")
	var d2 = dock.wire_drop(root, chest, "touch", table2)
	_assert(d2 == d1 and d2.get("table") == table2, "second Apply reused the LootDrop and swapped the table")
	_assert(_count(chest, DROP_SCRIPT) == 1 and _named(chest, "LootArea") == 1, "exactly one LootDrop and one LootArea after two Applies")
	dock.wire_drop(root, chest, "touch", null)
	_assert(d1.get("table") == table2, "Apply with no table picked keeps the one it has")
	d1.set("once", false)
	dock.wire_drop(root, chest, "touch", table2)
	_assert(not bool(d1.get("once")), "re-Apply keeps an Inspector change (Once off)")

	# An Area that already has a shape is touched as is; one without gets a LootArea.
	var zone := Area2D.new()
	zone.name = "Zone"
	root.add_child(zone); zone.owner = root
	var zs := CollisionShape2D.new()
	zs.shape = RectangleShape2D.new()
	zone.add_child(zs); zs.owner = root
	dock.wire_drop(root, zone, "touch", table)
	_assert(zone.get_node_or_null("LootArea") == null, "an Area with a shape needs no LootArea")
	var bare_area := Area2D.new()
	bare_area.name = "EmptyArea"
	root.add_child(bare_area); bare_area.owner = root
	dock.wire_drop(root, bare_area, "touch", table)
	_assert(bare_area.get_node_or_null("LootArea") is Area2D, "an Area with no shape gets a LootArea (it could never be touched)")

	# 3D scenes get an Area3D.
	var root3 := Node3D.new()
	get_tree().root.add_child(root3)
	var crate := Node3D.new()
	crate.name = "Crate"
	root3.add_child(crate); crate.owner = root3
	dock.wire_drop(root3, crate, "touch", table)
	var a3 := crate.get_node_or_null("LootArea")
	_assert(a3 is Area3D and a3.get_node("CollisionShape").shape is SphereShape3D, "a 3D node gets an Area3D with a sphere")
	root3.queue_free()

	# DIES: no area, trigger set; the dock tells a node without died apart.
	var enemy := CharacterBody2D.new()
	enemy.name = "Enemy"
	root.add_child(enemy); enemy.owner = root
	var de = dock.wire_drop(root, enemy, "dies", table)
	_assert(int(de.get("trigger")) == 1 and enemy.get_node_or_null("LootArea") == null, "dies Apply sets the trigger and adds no area")
	_assert(not dock.has_died_signal(enemy), "the dock sees a node with no died signal (so it can warn)")
	var hp: Node = HEALTH_SCRIPT.new()
	hp.name = "Health"
	enemy.add_child(hp); hp.owner = root
	_assert(dock.has_died_signal(enemy), "a Health child with died counts")
	var self_dies: Node = HEALTH_SCRIPT.new()
	root.add_child(self_dies); self_dies.owner = root
	_assert(dock.has_died_signal(self_dies), "a node that has died itself counts")
	dock.wire_drop(root, chest, "dies", table)
	_assert(_count(chest, DROP_SCRIPT) == 1 and int(d1.get("trigger")) == 1, "switching touch to dies updates the same LootDrop")

	# NO TABLE yet: Apply must not crash and bakes a drop with no table.
	var crate2 := Node2D.new()
	root.add_child(crate2); crate2.owner = root
	var dn = dock.wire_drop(root, crate2, "touch", null)
	_assert(dn != null and dn.get("table") == null, "no-table Apply bakes a drop with no table (pick one later)")
	var crate3 := Node2D.new()
	root.add_child(crate3); crate3.owner = root
	dock.wire_drop(root, crate3, "touch", table)
	var at_names := crate3.get_children().filter(func(c): return String(c.name).begins_with("@"))
	_assert(crate3.get_child_count() > 0 and at_names.is_empty(), "nodes it adds never get @-names")

	# OWNERSHIP SKIP: a LootDrop in an instanced sub-scene (owner != root) is left
	# alone; Apply makes a fresh one the scene actually owns.
	var root2 := Node2D.new()
	get_tree().root.add_child(root2)
	var sub := Node2D.new()
	root2.add_child(sub); sub.owner = root2
	var buried: Node = DROP_SCRIPT.new()
	buried.name = "LootDrop"
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	var fresh = dock.wire_drop(root2, sub, "dies", table)
	_assert(fresh != buried and fresh.owner == root2, "did not hijack a LootDrop owned by a sub-scene")
	root2.queue_free()

	# Apply selects what it made, so the next Apply must step back up to the host.
	_assert(dock._host_of(d1, root) == chest, "a selected LootDrop steps up to its node")
	_assert(area != null and shape != null and dock._host_of(area, root) == chest and dock._host_of(shape, root) == chest, "so do the LootArea and its shape")
	_assert(dock._host_of(chest, root) == chest, "a normal node is its own host")

	# A2: touch drops only fire for the player, so the dock says when there isn't one.
	_assert(dock.no_player_note(root).contains("Make the selected node the player"), "no player in the scene: the dock says so")
	var stray := Node.new()
	stray.add_to_group("player")
	get_tree().root.add_child(stray)
	_assert(dock.no_player_note(root) != "", "a player outside this scene doesn't count")
	var pl := CharacterBody2D.new()
	pl.add_to_group("player")
	root.add_child(pl); pl.owner = root
	_assert(dock.no_player_note(root) == "", "a player in the scene: no note")
	stray.queue_free()

	# STARTER TABLE: the pure factory produces a rollable LootTableLite.
	var starter = dock.make_starter_table("touch")
	_assert(starter.get_script() == RESOURCE_SCRIPT and starter.entries.size() == 2, "starter is a LootTableLite with 2 entries")
	_assert(int(starter.rolls) == 3 and str(starter.id) == "chest_loot", "a touch starter is a chest table that rolls 3 times")
	_assert(not starter.roll(_seeded()).is_empty(), "starter table actually rolls loot")
	var foe_starter = dock.make_starter_table("dies")
	_assert(int(foe_starter.rolls) == 1 and str(foe_starter.id) == "enemy_loot", "a dies starter rolls once")
	# numbered like the tables tab: base, base_2, base_3
	var num_dir := "user://loot_lite_num_test"
	DirAccess.make_dir_recursive_absolute(num_dir)
	ResourceSaver.save(_table("first"), num_dir.path_join("chest_loot.tres"))
	_assert(dock._unique(num_dir.path_join("chest_loot")).get_file() == "chest_loot_2.tres", "a second starter table is chest_loot_2.tres")
	DirAccess.remove_absolute(num_dir.path_join("chest_loot.tres"))
	DirAccess.remove_absolute(num_dir)

	# TABLE LIST: your tables first, then the examples; only loot tables.
	var own_dir := "user://loot_lite_test_own"
	var demo_dir := "user://loot_lite_test_demo"
	for d in [own_dir, demo_dir]:
		DirAccess.make_dir_recursive_absolute(d)
	ResourceSaver.save(_table("zz_mine"), own_dir.path_join("zz_mine.tres"))
	ResourceSaver.save(_table("aa_example"), demo_dir.path_join("aa_example.tres"))
	ResourceSaver.save(ITEM_SCRIPT.new(), own_dir.path_join("not_a_table.tres"))
	var listed: PackedStringArray = dock.table_paths([own_dir], [demo_dir])
	_assert(listed.size() == 2 and listed[0].ends_with("zz_mine.tres") and listed[1].ends_with("aa_example.tres"), "tables list yours before the examples, and skips other resources (%s)" % str(listed))
	for d in [own_dir, demo_dir]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)
	# The starter kits carry this test without the lite demo, so there's no example
	# table to offer there. Only check it when this pack's demo is in the project.
	var has_demo := DirAccess.dir_exists_absolute("res://demo/loot_lite/loot_lite") \
		or FileAccess.file_exists("res://demo/loot_lite/loot_demo.tscn")  # repo layout
	if has_demo:
		var shipped: PackedStringArray = dock.table_paths([CHOOSER.TABLE_DIR], dock._demo_dirs())
		var has_example := false
		for p in shipped:
			if p.ends_with("bandit_drop.tres"):
				has_example = true
		_assert(has_example, "the shipped example table shows up in the list (%s)" % str(shipped))
	else:
		_skip("no Loot demo in this project, so there's no example table to check")

	root.queue_free()
	await get_tree().process_frame
	await _run_played_scene(dock)
	dock.free()
	await _run_table_list_refresh()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# Build a level with the dock's own wiring, pack it the way Save does, play it.
func _run_played_scene(dock) -> void:
	var gold: Resource = ITEM_SCRIPT.new()
	gold.id = "gold"
	gold.name = "Gold"
	var gem: Resource = ITEM_SCRIPT.new()
	gem.id = "gem"
	gem.name = "Gem"
	var gold_table: Resource = RESOURCE_SCRIPT.new()
	gold_table.entries = [RESOURCE_SCRIPT.entry(gold, 100, 5, 5)]
	var gem_table: Resource = RESOURCE_SCRIPT.new()
	gem_table.entries = [RESOURCE_SCRIPT.entry(gem, 100, 1, 1)]
	var lvl := Node2D.new()
	lvl.name = "Level"
	var box := Sprite2D.new()
	box.name = "Chest"
	box.position = Vector2(300, 200)
	lvl.add_child(box); box.owner = lvl
	var foe := CharacterBody2D.new()
	foe.name = "Enemy"
	foe.position = Vector2(700, 200)
	lvl.add_child(foe); foe.owner = lvl
	var hp: Node = HEALTH_SCRIPT.new()
	hp.name = "Health"
	foe.add_child(hp); hp.owner = lvl
	dock.wire_drop(lvl, box, "touch", gold_table)
	dock.wire_drop(lvl, foe, "dies", gem_table)
	var pk := PackedScene.new()
	pk.pack(lvl)
	lvl.free()
	var run := pk.instantiate()
	get_tree().root.add_child(run)
	var hero := CharacterBody2D.new()
	hero.add_to_group("player")
	var hc := CollisionShape2D.new()
	var hb := RectangleShape2D.new()
	hb.size = Vector2(16, 16)
	hc.shape = hb
	hero.add_child(hc)
	var bag: Node = BAG_SCRIPT.new()
	hero.add_child(bag)
	hero.position = Vector2(40, 40)
	run.add_child(hero)
	for i in 3:
		await get_tree().physics_frame
	_assert(bag.total() == 0, "played: nothing drops at the start")
	hero.position = Vector2(300, 200)
	for i in 4:
		await get_tree().physics_frame
	_assert(bag.count_item(gold) == 5, "played: walking into the dock-built chest puts 5 Gold in the bag (got %d)" % bag.count_item(gold))
	_assert(_toast_has("Found: Gold x5"), "played: and a message says so")
	run.get_node("Enemy/Health").emit_signal("died")
	_assert(bag.count_item(gem) == 1, "played: the dock-built enemy drops its Gem when its Health dies (got %d)" % bag.count_item(gem))
	_assert(_toast_has("Found: Gem"), "played: and a message says so")
	run.queue_free()


func _toast_has(text: String) -> bool:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Label and (t as Label).text.contains(text):
			return true
	return false


func _count(parent: Node, script: Script) -> int:
	var n := 0
	for c in parent.get_children():
		if c.get_script() == script:
			n += 1
	return n


func _named(parent: Node, child_name: String) -> int:
	var n := 0
	for c in parent.get_children():
		if String(c.name) == child_name:
			n += 1
	return n


func _table(id: String) -> Resource:
	var t: Resource = RESOURCE_SCRIPT.new()
	t.id = id
	return t


func _seeded() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng


func _skip(msg: String) -> void:
	print("[--] " + msg)


# A table made in the Loot Tables (Lite) tab while this one is on screen is in the
# table list the next time it opens, and the picked table stays picked.
func _run_table_list_refresh() -> void:
	var tab = CHOOSER.new()
	add_child(tab)
	await get_tree().process_frame
	var pick: OptionButton = tab._table_pick
	var had_dir := DirAccess.dir_exists_absolute(CHOOSER.TABLE_DIR)
	DirAccess.make_dir_recursive_absolute(CHOOSER.TABLE_DIR)
	ResourceSaver.save(RESOURCE_SCRIPT.new(), CHOOSER.TABLE_DIR.path_join("f12b_a.tres"))
	pick.get_popup().about_to_popup.emit()
	var at := _option_texts(pick).find("f12b_a")
	_assert(at >= 0, "a table made after the tab was built is in its list when it opens (%s)" % [_option_texts(pick)])
	if at >= 0:
		pick.select(at)
	ResourceSaver.save(RESOURCE_SCRIPT.new(), CHOOSER.TABLE_DIR.path_join("f12b_b.tres"))
	pick.get_popup().about_to_popup.emit()
	_assert(_option_texts(pick).has("f12b_b") and pick.get_item_text(pick.selected) == "f12b_a",
		"the next one shows up too, and the table that was picked stays picked (%s)" % pick.get_item_text(pick.selected))
	for f in ["f12b_a.tres", "f12b_b.tres"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHOOSER.TABLE_DIR.path_join(f)))
	if not had_dir:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHOOSER.TABLE_DIR))
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
