extends Node

# Headless test for the Equipment — Lite chooser's wiring logic (the part behind
# the Apply button). Editor-only calls (get_edited_scene_root/selection) are split
# out; this drives the pure wire_* helpers against a real scene tree and asserts
# the result is baked-in, re-entrant, and ownership-scoped.
# Run: godot --headless --path . res://tools/equipment_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/equipment_lite/editor/equipment_chooser_dock.gd")
const COMPONENT_SCRIPT := "res://addons/equipment_lite/equipment_lite.gd"

# item fixtures live in user://, not the demo: the starter kits carry this test
# without the lite demo folder
const FIXTURES := "user://verify_chooser_fixtures"
const DEMO_ITEMS := "res://demo/equipment_lite/items"
const INVENTORY_ITEMS := ["res://addons/inventory/resources/item_resource.gd", "res://addons/inventory_lite/item_resource.gd"]

var _passes := 0
var _failures := 0
var _sword: Resource
var _boots: Resource


func _ready() -> void:
	await get_tree().process_frame
	print("--- equipment chooser verify ---")
	var dock: Object = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# SCENE ROOT scope — component lands on the root itself, baked into the .tscn
	var comp1: Node = dock.wire_component(root, root)
	_assert(comp1 != null, "wire_component created a component")
	_assert(comp1.get_script() != null and comp1.get_script().get_global_name() == "EquipmentLite",
		"created node is an EquipmentLite")
	_assert(comp1.owner == root, "component owned by scene root: bakes into the .tscn")

	# RE-ENTRANT — applying again to the same target reuses it, never a second one
	var comp2: Node = dock.wire_component(root, root)
	_assert(comp2 == comp1, "second Apply reused the same component (no duplicate)")
	var root_count := _count_owned(root, root)
	_assert(root_count == 1, "exactly one EquipmentLite on the root after two Applies (got %d)" % root_count)

	# SELECTED-NODE scope — component parents under the chosen child, still owned
	# by the scene root so it serializes. Independent of the root's own component.
	var child := Node.new()
	child.name = "Player"
	root.add_child(child); child.owner = root
	var comp3: Node = dock.wire_component(root, child)
	_assert(comp3 != null and comp3 != comp1, "selected-node scope made a distinct component")
	_assert(comp3.get_parent() == child, "component parented under the selected node")
	_assert(comp3.owner == root, "selected-node component still owned by root (serializes)")
	# re-entrant on the child target too
	var comp4: Node = dock.wire_component(root, child)
	_assert(comp4 == comp3, "re-apply on the selected node reused its component")

	# OWNERSHIP — a component buried in an instanced sub-scene (owner != root) must
	# NOT be hijacked; Apply makes a fresh one the scene root actually owns. Fresh
	# root so the ONLY component present is the non-owned one.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var sub := Node.new()
	root2.add_child(sub); sub.owner = root2
	var buried: Node = load(COMPONENT_SCRIPT).new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	var fresh: Node = dock.wire_component(root2, root2)
	_assert(fresh != buried, "did not hijack a component owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh component the scene root owns")
	root2.queue_free()

	root.queue_free()
	_make_fixtures()
	await _player_wiring(dock)
	await _pickup_wiring(dock)
	await _items(dock)
	await _played(dock)
	await _played_3d(dock)
	await _equippables_new(dock)
	dock.free()
	_wipe(FIXTURES)
	await _run_item_list_refresh()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# ---- Player equipment: slots, the player tag, the list and the C key --------

func _player_wiring(dock) -> void:
	_assert(dock.SLOTS == load(COMPONENT_SCRIPT).SLOTS, "the tab's slot list matches EquipmentLite.SLOTS")
	var level := Node2D.new()
	level.name = "Level"
	var hero := _own(level, CharacterBody2D.new(), "Hero")
	var rig: Node = dock.wire_player(level, hero)
	_assert(rig != null and rig.get_parent() == hero and _is(rig, "EquipmentLite") and rig.owner == level, "Player equipment puts an EquipmentLite on the selected node")
	_assert(hero.is_in_group("player"), "it marks that node as the player")
	var list := level.find_child("EquippedList", true, false)
	_assert(list != null and _is(list, "EquippedListLite"), "it adds an EquippedListLite, by a readable name")
	_assert(list != null and list.get_parent() is CanvasLayer and list.get_parent().owner == level and list.owner == level, "the list sits on a CanvasLayer the scene owns, so it saves")
	var c: Control = list
	_assert(not c.visible, "the list starts hidden")
	_assert(c.anchor_left == 1.0 and c.anchor_top == 1.0 and c.offset_right == -16.0 and c.offset_bottom == -16.0, "it's anchored bottom-right, 16 px in")
	dock.wire_player(level, hero)
	_assert(_count(level, "EquippedListLite") == 1 and _count(level, "EquipmentLite") == 1, "Apply again reuses the slots and the list")
	c.offset_left = -400.0
	dock.wire_equipped_list(level)
	_assert(c.offset_left == -400.0, "a list the buyer moved stays where they put it")
	c.offset_left = -256.0
	var ev: InputEventKey = null
	var cfg: Variant = ProjectSettings.get_setting("input/character", null)
	if cfg is Dictionary and not (cfg as Dictionary).get("events", []).is_empty():
		ev = (cfg as Dictionary)["events"][0] as InputEventKey
	_assert(ev != null and ev.physical_keycode == KEY_C and ev.device == -1, "it registers the character action on physical C, any device")
	_assert(dock.action_keys("character") == "C", "the status line can name the key (%s)" % dock.action_keys("character"))
	var saved: Variant = ProjectSettings.get_setting("input/character")
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	ProjectSettings.set_setting("input/character", {"deadzone": 0.5, "events": [tab]})
	dock.ensure_action("character", KEY_C, false)
	_assert(dock.action_keys("character") == "Tab", "a character key the project already has is left alone")
	ProjectSettings.set_setting("input/character", saved)
	# a plain level root isn't the player
	var bare := Node2D.new()
	dock.wire_player(bare, bare)
	_assert(not bare.is_in_group("player"), "a plain level root isn't marked as the player")
	bare.free()
	# in a 1280x720 window it's a real panel, bottom-right, on screen
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child(vp)
	var run := ps.instantiate()
	vp.add_child(run)
	await get_tree().process_frame
	await get_tree().process_frame
	var rl: Control = run.find_child("EquippedList", true, false)
	var r := rl.get_global_rect()
	_assert(r.size.x >= 200.0 and r.size.y >= 100.0 and is_equal_approx(r.end.x, 1264.0) and is_equal_approx(r.end.y, 704.0) and r.position.y >= 0.0,
		"in 1280x720 it's a %dx%d panel at the bottom-right (%s)" % [int(r.size.x), int(r.size.y), str(r)])
	vp.queue_free()
	await get_tree().process_frame


# ---- Equip it when the player picks it up ----------------------------------

func _pickup_wiring(dock) -> void:
	var sword := _sword
	var boots := _boots
	var level := Node2D.new()
	var thing := _own(level, Sprite2D.new(), "Sword")
	var chest := _own(level, Area2D.new(), "Chest")
	var p: Node = dock.wire_equip_pickup(level, thing, sword)
	_assert(p != null and p.get_parent() == thing and _is(p, "EquipPickupLite") and p.owner == level, "A pickup: an EquipPickupLite on the selected node, owned by the scene")
	_assert(p.name == "EquipPickup" and p.get("item") == sword, "it has a readable name and holds the item (%s)" % p.name)
	var area := thing.get_node_or_null("PickupArea")
	var shp: Node = null
	if area != null:
		shp = area.get_node_or_null("PickupShape")
	_assert(area is Area2D and shp is CollisionShape2D and (shp as CollisionShape2D).shape is CircleShape2D and area.owner == level and shp.owner == level, "a node that isn't an area gets a PickupArea with a round shape")
	var p2: Node = dock.wire_equip_pickup(level, thing, boots)
	_assert(p2 == p and p.get("item") == boots and thing.get_child_count() == 2 and area.get_child_count() == 1, "Apply again on it swaps the item in place")
	var pc: Node = dock.wire_equip_pickup(level, chest, sword)
	_assert(pc.get_parent() == chest and chest.get_node_or_null("PickupArea") == null and chest.get_node_or_null("PickupShape") is CollisionShape2D, "an Area2D is touched directly and gets a shape if it has none")
	level.free()
	var level3 := Node3D.new()
	var gem := _own(level3, MeshInstance3D.new(), "Helm")
	dock.wire_equip_pickup(level3, gem, sword)
	var a3 := gem.get_node_or_null("PickupArea")
	var s3: Node = null
	if a3 != null:
		s3 = a3.get_node_or_null("PickupShape")
	_assert(a3 is Area3D and s3 is CollisionShape3D and (s3 as CollisionShape3D).shape is SphereShape3D, "a 3D node gets an Area3D with a sphere")
	level3.free()
	await get_tree().process_frame


# ---- New item + the slot picker --------------------------------------------

func _items(dock) -> void:
	var dir := "user://verify_chooser_items"
	_wipe(dir)
	var p1: String = dock.make_item("chest", dir)
	var p2: String = dock.make_item("ring", dir)
	_assert(p1.get_file() == "new_item.tres" and p2.get_file() == "new_item_2.tres", "New item makes new_item.tres, then new_item_2.tres (%s, %s)" % [p1.get_file(), p2.get_file()])
	var it1: Resource = load(p1)
	var want := _new_item_script()
	_assert(it1 != null and it1.get_script().resource_path == want and str(it1.get("id")) == "new_item" and str(it1.get("name")) == "New Item",
		"New item uses %s, with an id and a name (%s)" % ["the Inventory pack's item script (one is installed)" if want != CHOOSER.ITEM_SCRIPT else "Equipment's own item script (no Inventory pack here)", it1.get("name") if it1 != null else "?"])
	_assert(dock.item_slot(it1) == "chest" and dock.item_slot(load(p2)) == "ring", "it carries the slot picked in the tab")
	# the slot picker writes the slot into the item file
	_assert(dock.set_item_slot(it1, "boots"), "picking another slot changes the item")
	var disk := FileAccess.get_file_as_string(p1)
	_assert(disk.contains("\"equip_slot\": \"boots\""), "and saves it to the file")
	_assert(not dock.set_item_slot(it1, "boots") and not dock.set_item_slot(it1, "hat"), "the same slot again, or a made-up one, changes nothing")
	_wipe(dir)
	# the picker: the buyer's own items first, then the demo's six as examples,
	# each showing its slot; picking one shows its slot in the slot picker
	add_child(dock)
	dock._refresh_items()
	var own: PackedStringArray = dock._scan_items("res://items")
	var paths: PackedStringArray = dock._item_paths
	if not _has_demo():
		_assert(paths == own, "the item picker lists the project's own items (%d)" % own.size())
		print("[--] item picker: no demo in this project, so there are no examples (or their slots) to check")
		remove_child(dock)
		return
	var ok := paths.size() == own.size() + 6 and paths.slice(0, own.size()) == own
	for i in range(own.size(), paths.size()):
		ok = ok and paths[i].begins_with("res://demo/equipment_lite/")
	_assert(ok, "the item picker lists res://items first, then the demo's items (%s)" % str(paths))
	var boots_i := -1
	for i in paths.size():
		if paths[i].ends_with("leather_boots.tres"):
			boots_i = i
	_assert(boots_i >= 0 and dock._item_pick.get_item_text(boots_i) == "Leather Boots (Boots)", "each shows its name and slot (%s)" % (dock._item_pick.get_item_text(boots_i) if boots_i >= 0 else "?"))
	if boots_i >= 0:
		dock._item_pick.select(boots_i)
		dock._on_item_picked(boots_i)
	_assert(dock._slot_pick.selected == 2, "picking it shows its slot in the slot picker (%d)" % dock._slot_pick.selected)
	remove_child(dock)


# ---- Play it: the scene the tab built, run ---------------------------------

func _played(dock) -> void:
	var sword := _sword
	var boots := _boots
	var level := Node2D.new()
	level.name = "Level"
	var hero := _own(level, CharacterBody2D.new(), "Hero")
	var hs := CollisionShape2D.new()  # the buyer's own player has a shape
	var hc := CircleShape2D.new()
	hc.radius = 10.0
	hs.shape = hc
	hero.add_child(hs)
	hs.owner = level
	var thing: Node2D = _own(level, Sprite2D.new(), "Sword")
	thing.position = Vector2(400, 100)
	var box: Node2D = _own(level, Area2D.new(), "Boots")
	box.position = Vector2(400, 300)
	dock.wire_player(level, hero)
	dock.wire_equip_pickup(level, thing, sword)
	dock.wire_equip_pickup(level, box, boots)
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	InputMap.load_from_project_settings()  # a game started after Apply has the tab's action
	var run := ps.instantiate()
	add_child(run)
	for i in 3:
		await get_tree().physics_frame
	var player: Node2D = run.get_node("Hero")
	var rig: Node = run.get_node("Hero/EquipmentLite")
	var list: Control = run.find_child("EquippedList", true, false)
	_assert(not rig.is_equipped("weapon_main") and run.get_node_or_null("Sword") != null, "Played: nothing is equipped before the player gets there")
	_assert(not list.visible, "Played: the equipped list starts hidden")
	await _walk(player, Vector2(400, 100))
	_assert(rig.get_equipped("weapon_main") == sword, "Played: walking into the sword equips it")
	_assert(run.get_node_or_null("Sword") == null, "Played: the sword on the ground is gone")
	var said := false
	for t in get_tree().get_nodes_in_group("lite_toast"):
		said = said or String(t.text) == "Equipped Iron Sword"
	_assert(said, "Played: a toast says Equipped Iron Sword")
	await _press(KEY_C)
	_assert(list.visible, "Played: C opens the equipped list")
	_assert(_rows(list) == PackedStringArray(["Weapon: Iron Sword", "Chest: -", "Boots: -", "Ring: -"]), "Played: it shows the sword in the weapon slot (got %s)" % str(_rows(list)))
	_assert(_inside(list), "Played: every line sits inside the panel")
	await _walk(player, Vector2(400, 300))
	_assert(rig.get_equipped("boots") == boots and run.get_node_or_null("Boots") == null, "Played: the Area2D pickup equips its boots and goes away")
	_assert(_rows(list)[2] == "Boots: Leather Boots", "Played: the open list follows (got %s)" % str(_rows(list)))
	await _press(KEY_C)
	_assert(not list.visible, "Played: C again closes it")
	var again := PackedScene.new()
	again.pack(run)
	var copy := again.instantiate()
	_assert(copy.find_child("EquippedList", true, false).get_child_count() == 0, "Played: the list's rows are built at runtime only, never saved into the scene")
	copy.free()
	run.queue_free()
	await get_tree().process_frame


# The same in 3D: a CharacterBody3D walking into a mesh the tab made a pickup.
func _played_3d(dock) -> void:
	var sword := _sword
	var level := Node3D.new()
	level.name = "Level3D"
	var hero := _own(level, CharacterBody3D.new(), "Hero")
	var hs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.5
	hs.shape = sph
	hero.add_child(hs)
	hs.owner = level
	var helm: Node3D = _own(level, MeshInstance3D.new(), "Sword3D")
	helm.position = Vector3(6, 0, 0)
	dock.wire_player(level, hero)
	dock.wire_equip_pickup(level, helm, sword)
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	var run := ps.instantiate()
	add_child(run)
	for i in 3:
		await get_tree().physics_frame
	var rig: Node = run.get_node("Hero/EquipmentLite")
	_assert(not rig.is_equipped("weapon_main") and run.get_node_or_null("Sword3D") != null, "Played 3D: nothing is equipped from across the room")
	var body: Node3D = run.get_node("Hero")
	body.global_position = Vector3(6, 0, 0)
	for i in 6:
		await get_tree().physics_frame
	await get_tree().process_frame
	_assert(rig.get_equipped("weapon_main") == sword and run.get_node_or_null("Sword3D") == null, "Played 3D: walking into it equips the sword and it goes")
	run.queue_free()
	await get_tree().process_frame


# ---- the Equippables tab's own New -----------------------------------------

# It starts from a name and an id too, and counts new_item, new_item_2, ... the
# same way the Setup tab's New item does, so the two carry on from each other.
func _equippables_new(setup) -> void:
	var dir := "user://verify_equippables_new/"
	_wipe(dir)
	var tab: Control = load("res://addons/equipment_lite/editor/lite_dock.gd").new()
	add_child(tab)
	await get_tree().process_frame
	tab._dir = dir
	tab._on_new()
	var first: String = tab._current_path
	var it1: Resource = ResourceLoader.load(first, "", ResourceLoader.CACHE_MODE_IGNORE)
	_assert(first.get_file() == "new_item.tres" and it1 != null and str(it1.get("id")) == "new_item" and str(it1.get("name")) == "New Item",
		"Equippables New gives its item an id and a name (%s: %s)" % [first.get_file(), it1.get("name") if it1 != null else "?"])
	_assert(String(tab._status.text).begins_with("Made " + first), "its status says where it went (%s)" % tab._status.text)
	var second: String = setup.make_item("boots", dir)
	_assert(second.get_file() == "new_item_2.tres", "the Setup tab's New item takes the next number (%s)" % second.get_file())
	tab._on_new()
	var third: String = tab._current_path
	var it3: Resource = ResourceLoader.load(third, "", ResourceLoader.CACHE_MODE_IGNORE)
	_assert(third.get_file() == "new_item_3.tres" and it3 != null and str(it3.get("name")) == "New Item 3", "and the Equippables tab carries on after it (%s)" % third.get_file())
	var setup_is_ours: bool = _new_item_script() == CHOOSER.ITEM_SCRIPT
	_assert(tab._paths.size() == (3 if setup_is_ours else 2), "the Equippables list shows its Equipment items%s (%d)" % [", the Setup tab's one included" if setup_is_ours else " (the Setup tab's one is an Inventory item here)", tab._paths.size()])
	tab.queue_free()
	_wipe(dir)
	await get_tree().process_frame


# ---- helpers for the above ---------------------------------------------------

# Saved, then loaded back, so each has a path: a packed scene points at the file
# and the running copy gets the very same item.
func _make_fixtures() -> void:
	_wipe(FIXTURES)
	DirAccess.make_dir_recursive_absolute(FIXTURES)
	_sword = _fixture("sword", "Iron Sword", "weapon_main")
	_boots = _fixture("boots", "Leather Boots", "boots")


func _fixture(id: String, item_name: String, slot: String) -> Resource:
	var it: Resource = load("res://addons/equipment_lite/item_resource.gd").new()
	it.set("id", id)
	it.set("name", item_name)
	it.set("metadata", {"equip_slot": slot})
	var path := FIXTURES.path_join(id + ".tres")
	ResourceSaver.save(it, path)
	return load(path)


# The demo's items are only there in the lite's own project and its zip. Asked
# of the folder itself, not the tab's list, so a tab that lost its demo path
# still fails the examples check instead of skipping it. (The build and the
# starter kits rewrite this path to wherever they put the demo.)
func _has_demo() -> bool:
	return DirAccess.dir_exists_absolute(DEMO_ITEMS)


# What New item should make here: an installed Inventory pack's item, else ours.
func _new_item_script() -> String:
	for p: String in INVENTORY_ITEMS:
		if FileAccess.file_exists(p):
			return p
	return CHOOSER.ITEM_SCRIPT


func _own(parent: Node, n: Node, nm: String) -> Node:
	n.name = nm
	parent.add_child(n)
	n.owner = parent if parent.owner == null else parent.owner
	return n


func _is(n: Node, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls


func _count(n: Node, cls: String) -> int:
	var k := 1 if _is(n, cls) else 0
	for c in n.get_children():
		k += _count(c, cls)
	return k


func _walk(body: Node2D, to: Vector2) -> void:
	body.global_position = to
	for i in 6:
		await get_tree().physics_frame
	await get_tree().process_frame


func _press(key: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _rows(list: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in list.get("_rows").get_children():
		if not n.is_queued_for_deletion():
			out.append(String(n.text))
	return out


# The title and every row lie within the list's own rect (the panel fits its text).
func _inside(list: Control) -> bool:
	var box := list.get_global_rect().grow(0.5)
	for n in list.find_children("*", "Label", true, false):
		var lab: Label = n
		if not lab.is_queued_for_deletion() and not box.encloses(lab.get_global_rect()):
			return false
	return true


func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


# Count EquipmentLite nodes owned by `root` (mirrors the chooser's ownership scope).
func _count_owned(node: Node, root: Node) -> int:
	var n := 0
	if (node == root or node.owner == root):
		var scr: Script = node.get_script()
		if scr != null and scr.get_global_name() == "EquipmentLite":
			n += 1
	for c in node.get_children():
		n += _count_owned(c, root)
	return n


# An item made in another tab while this one is on screen is in the Item list the
# next time it opens; the picked item and a slot turned by hand stay as they were.
func _run_item_list_refresh() -> void:
	var tab = CHOOSER.new()
	add_child(tab)
	await get_tree().process_frame
	tab._on_pick("pickup")
	var ipick: OptionButton = tab._item_pick
	var spick: OptionButton = tab._slot_pick
	if ipick.item_count > 0:
		ipick.select(0)
		ipick.item_selected.emit(0)
	var kept_item := ipick.get_item_text(ipick.selected) if ipick.selected >= 0 else ""
	spick.select((spick.selected + 1) % spick.item_count)
	var kept_slot := spick.selected
	var had_dir := DirAccess.dir_exists_absolute("res://items")
	var made: String = tab.make_item("")
	var made_name := String(load(made).get("name")) if made != "" else "?"
	ipick.get_popup().about_to_popup.emit()
	var found := false
	for t in _option_texts(ipick):
		found = found or t.begins_with(made_name + " (")
	_assert(made != "" and found, "an item made after the tab was built is in its Item list when it opens (%s in %s)" % [made_name, _option_texts(ipick)])
	# a project with no items yet (a starter kit) had nothing picked, so there's nothing to keep
	_assert((kept_item == "" or ipick.get_item_text(ipick.selected) == kept_item) and spick.selected == kept_slot,
		"opening it keeps the picked item and the slot turned by hand (%s, %d)" % [kept_item, kept_slot])
	if made != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(made))
	if not had_dir:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://items"))
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
