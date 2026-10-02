extends Node

# Headless test for the Inventory — Lite chooser's wiring logic (the part behind the
# Apply button). Editor-only calls (get_edited_scene_root/selection) are split out;
# this drives the pure wire_inventory helper against a real scene tree and asserts
# the result is baked-in and re-entrant.
# Run: godot --headless --path . res://tools/inventory_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/inventory_lite/editor/inventory_chooser_dock.gd")

# item fixtures live in user://, not the demo: the starter kits carry this test
# without the lite demo folder
const FIXTURES := "user://verify_chooser_fixtures"
const DEMO_ITEMS := "res://demo/inventory_lite/items"

var _passes := 0
var _failures := 0
var _apple: Resource
var _sword: Resource
var _potion: Resource


func _ready() -> void:
	await get_tree().process_frame
	print("--- inventory lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# PLAYER on the root — adds an InventoryLite baked into the scene
	var inv1 = dock.wire_inventory(root, root, "player")
	_assert(inv1 != null, "wire_inventory created an InventoryLite")
	_assert(inv1.get_script() != null and inv1.get_script().get_global_name() == "InventoryLite", "spawned node is an InventoryLite")
	_assert(int(inv1.get("capacity")) == 24, "player outcome set capacity 24 (got %d)" % int(inv1.get("capacity")))
	_assert(inv1.owner == root, "component owned by scene root: bakes into the .tscn")
	_assert(not root.is_in_group("player"), "a plain level root isn't marked as the player")

	# RE-ENTRANT — a second Apply on the same target reuses the node, never a second
	var inv2 = dock.wire_inventory(root, root, "container")
	_assert(inv2 == inv1, "second Apply reused the same component (no duplicate)")
	_assert(int(inv2.get("capacity")) == 16, "container outcome updated capacity in place to 16 (got %d)" % int(inv2.get("capacity")))
	var inv_count := 0
	for c in root.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == "InventoryLite":
			inv_count += 1
	_assert(inv_count == 1, "exactly one InventoryLite on the root after two Applies (got %d)" % inv_count)

	# SCOPE: a selected child gets its OWN component, independent of the root's
	var child := Node.new()
	child.name = "Chest"
	root.add_child(child)
	child.owner = root
	var inv_child = dock.wire_inventory(root, child, "small")
	_assert(inv_child != inv1, "selected-child scope made a distinct component under the child")
	_assert(inv_child.get_parent() == child, "child component parented under the selected node")
	_assert(inv_child.owner == root, "child component still owned by the scene root (bakes in)")
	_assert(int(inv_child.get("capacity")) == 6, "small outcome set capacity 6 (got %d)" % int(inv_child.get("capacity")))
	_assert(not child.is_in_group("player"), "a pouch on a chest doesn't mark it as the player")

	# PLAYER on a selected body: it gets marked as the player, and that's saved
	var hero := CharacterBody2D.new()
	hero.name = "Hero"
	root.add_child(hero)
	hero.owner = root
	dock.wire_inventory(root, hero, "player")
	_assert(hero.is_in_group("player"), "the player inventory marks its holder as the player")
	var packed := PackedScene.new()
	packed.pack(root)
	var copy := packed.instantiate()
	_assert(copy.get_node("Hero").is_in_group("player"), "the player tag is saved with the scene")
	copy.free()

	# OWNERSHIP — a component inside an instanced sub-scene (owner != root) must NOT
	# be hijacked; Apply should make a fresh one the scene actually owns. Fresh root
	# so the ONLY InventoryLite present is the buried, non-owned one.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var sub := Node.new()
	root2.add_child(sub)
	sub.owner = root2
	var buried = load("res://addons/inventory_lite/inventory_lite.gd").new()
	sub.add_child(buried)
	buried.owner = sub  # owned by the sub-scene, not root2
	var fresh = dock.wire_inventory(root2, root2, "player")
	_assert(fresh != buried, "did not hijack a component owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh component the scene root owns")
	root2.queue_free()

	root.queue_free()
	_make_fixtures()
	await _pickup_wiring(dock)
	await _bag_list_wiring(dock)
	await _new_items(dock)
	await _played(dock)
	await _played_3d(dock)
	dock.free()
	_wipe(FIXTURES)
	await _run_item_list_refresh()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# ---- A pickup ------------------------------------------------------------

func _pickup_wiring(dock) -> void:
	var apple := _apple
	var sword := _sword
	var level := Node2D.new()
	var coin := _own(level, Sprite2D.new(), "Coin")
	var chest := _own(level, Area2D.new(), "Chest")
	var p: Node = dock.wire_pickup(level, coin, apple, 3)
	_assert(p != null and p.get_parent() == coin and _is(p, "PickupLite") and p.owner == level, "A pickup: a PickupLite on the selected node, owned by the scene")
	_assert(p.name == "Pickup", "it has a readable name (%s)" % p.name)
	_assert(p.get("item") == apple and int(p.get("amount")) == 3, "it holds the picked item and amount")
	var area := coin.get_node_or_null("PickupArea")
	_assert(area is Area2D and area.owner == level, "a node that isn't an area gets a PickupArea, owned by the scene")
	var shp: Node = null
	if area != null:
		shp = area.get_node_or_null("PickupShape")
	_assert(shp is CollisionShape2D and (shp as CollisionShape2D).shape is CircleShape2D and shp.owner == level, "the PickupArea gets a round shape to touch")
	var p2: Node = dock.wire_pickup(level, coin, sword, 1)
	_assert(p2 == p and p.get("item") == sword and int(p.get("amount")) == 1, "Apply again on it swaps the item and amount in place")
	_assert(_kids(coin, "PickupLite") == 1 and _kids(coin, "Area2D") == 1 and area.get_child_count() == 1, "still one pickup, one area, one shape")
	var pc: Node = dock.wire_pickup(level, chest, apple, 1)
	_assert(pc.get_parent() == chest and chest.get_node_or_null("PickupArea") == null, "an Area2D is touched directly, no extra area")
	_assert(chest.get_node_or_null("PickupShape") is CollisionShape2D, "an Area2D with no shape gets one, so it can be touched")
	var box := _own(level, Area2D.new(), "Box")
	var own_shape := CollisionShape2D.new()
	own_shape.shape = RectangleShape2D.new()
	box.add_child(own_shape)
	own_shape.owner = level
	dock.wire_pickup(level, box, apple, 1)
	_assert(box.get_child_count() == 2 and box.get_node_or_null("PickupShape") == null, "an area that already has a shape keeps it and gets no second one")
	level.free()
	var level3 := Node3D.new()
	var gem := _own(level3, MeshInstance3D.new(), "Gem")
	dock.wire_pickup(level3, gem, apple, 1)
	var a3 := gem.get_node_or_null("PickupArea")
	var s3: Node = null
	if a3 != null:
		s3 = a3.get_node_or_null("PickupShape")
	_assert(a3 is Area3D and s3 is CollisionShape3D and (s3 as CollisionShape3D).shape is SphereShape3D, "a 3D node gets an Area3D with a sphere")
	level3.free()
	await get_tree().process_frame


# ---- Player inventory's bag list + the I key ---------------------------------

func _bag_list_wiring(dock) -> void:
	var level := Node2D.new()
	level.name = "Level"
	var hero := _own(level, CharacterBody2D.new(), "Hero")
	dock.wire_inventory(level, hero, "player")
	var list: Node = dock.wire_bag_list(level)
	_assert(list != null and _is(list, "BagListLite"), "Player inventory adds a BagListLite")
	_assert(list.get_parent() is CanvasLayer and list.get_parent().owner == level and list.owner == level, "it sits on a CanvasLayer the scene owns, so it saves")
	_assert(list.name == "BagList", "it has a readable name (%s)" % list.name)
	var c: Control = list
	_assert(not c.visible, "it starts hidden")
	_assert(c.anchor_left == 0.0 and c.anchor_top == 1.0 and c.anchor_bottom == 1.0 and c.offset_left == 16.0 and c.offset_bottom == -16.0, "it's anchored bottom-left, 16 px in")
	_assert(dock.wire_bag_list(level) == list and _count(level, "BagListLite") == 1, "Apply again reuses it (one list per scene)")
	c.offset_left = 100.0
	c.offset_right = 340.0
	dock.wire_bag_list(level)
	_assert(c.offset_left == 100.0, "a list the buyer moved stays where they put it")
	c.offset_left = 16.0
	c.offset_right = 256.0
	# the I key, registered the way the Input Map editor stores it
	var ev: InputEventKey = null
	var cfg: Variant = ProjectSettings.get_setting("input/inventory", null)
	if cfg is Dictionary and not (cfg as Dictionary).get("events", []).is_empty():
		ev = (cfg as Dictionary)["events"][0] as InputEventKey
	_assert(ev != null and ev.physical_keycode == KEY_I and ev.device == -1, "it registers the inventory action on physical I, any device")
	_assert(dock.action_keys("inventory") == "I", "the status line can name the key (%s)" % dock.action_keys("inventory"))
	# a binding the project already has wins
	var saved: Variant = ProjectSettings.get_setting("input/inventory")
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	ProjectSettings.set_setting("input/inventory", {"deadzone": 0.5, "events": [tab]})
	dock.ensure_action("inventory", KEY_I, false)
	_assert(dock.action_keys("inventory") == "Tab", "an inventory key the project already has is left alone")
	ProjectSettings.set_setting("input/inventory", saved)
	# in a 1280x720 window it's a real panel, bottom-left, on screen
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
	var rl: Control = run.find_child("BagList", true, false)
	var r := rl.get_global_rect()
	_assert(r.size.x >= 200.0 and r.size.y >= 200.0 and is_equal_approx(r.position.x, 16.0) and is_equal_approx(r.end.y, 704.0) and r.position.y >= 0.0,
		"in 1280x720 it's a %dx%d panel at the bottom-left (%s)" % [int(r.size.x), int(r.size.y), str(r)])
	vp.queue_free()
	await get_tree().process_frame


# ---- New item ------------------------------------------------------------

func _new_items(dock) -> void:
	var dir := "user://verify_chooser_items"
	_wipe(dir)
	var p1: String = dock.make_item(dir)
	var p2: String = dock.make_item(dir)
	_assert(p1.get_file() == "new_item.tres" and p2.get_file() == "new_item_2.tres", "New item makes new_item.tres, then new_item_2.tres (%s, %s)" % [p1.get_file(), p2.get_file()])
	var it1: Resource = load(p1)
	var it2: Resource = load(p2)
	_assert(it1 != null and it1.get_script() == load("res://addons/inventory_lite/item_resource.gd"), "it's a Lite item")
	_assert(str(it1.get("id")) == "new_item" and str(it1.get("name")) == "New Item" and str(it2.get("id")) == "new_item_2" and str(it2.get("name")) == "New Item 2",
		"it has an id and a name already (%s / %s)" % [it1.get("name"), it2.get("name")])
	_wipe(dir)
	# the picker: the buyer's own items first, then the demo's three as examples
	add_child(dock)
	dock._refresh_items()
	var own: PackedStringArray = dock._scan_items("res://items")
	var paths: PackedStringArray = dock._item_paths
	if _has_demo():
		var demo_ok := paths.size() == own.size() + 3 and paths.slice(0, own.size()) == own
		for i in range(own.size(), paths.size()):
			demo_ok = demo_ok and paths[i].begins_with("res://demo/inventory_lite/")
		_assert(demo_ok, "the item picker lists res://items first, then the demo's items (%s)" % str(paths))
		_assert(dock._item_pick.item_count == paths.size() and dock._item_pick.get_item_text(paths.size() - 1) != "", "each shows by its name (%s)" % (dock._item_pick.get_item_text(0) if dock._item_pick.item_count > 0 else ""))
	else:
		_assert(paths == own, "the item picker lists the project's own items (%d)" % own.size())
		print("[--] item picker: no demo in this project, so there are no examples to check")
	remove_child(dock)


# ---- Play it: the scene the tab built, run ---------------------------------

func _played(dock) -> void:
	var apple := _apple
	var sword := _sword
	var potion := _potion
	var level := Node2D.new()
	level.name = "Level"
	var hero := _own(level, CharacterBody2D.new(), "Hero")
	var hs := CollisionShape2D.new()  # the buyer's own player has a shape
	var hc := CircleShape2D.new()
	hc.radius = 10.0
	hs.shape = hc
	hero.add_child(hs)
	hs.owner = level
	var coin: Node2D = _own(level, Sprite2D.new(), "Coin")
	coin.position = Vector2(400, 100)
	var chest: Node2D = _own(level, Area2D.new(), "Chest")
	chest.position = Vector2(400, 300)
	dock.wire_inventory(level, hero, "player")
	dock.wire_bag_list(level)
	dock.wire_pickup(level, coin, apple, 2)
	dock.wire_pickup(level, chest, sword, 1)
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	InputMap.load_from_project_settings()  # a game started after Apply has the tab's action
	var run := ps.instantiate()
	add_child(run)
	for i in 3:
		await get_tree().physics_frame
	var player: Node2D = run.get_node("Hero")
	var bag: Node = run.get_node("Hero/InventoryLite")
	var list: Control = run.find_child("BagList", true, false)
	_assert(bag.count_item(apple) == 0 and run.get_node_or_null("Coin") != null, "Played: nothing is picked up before the player gets there")
	_assert(not list.visible, "Played: the bag list starts hidden")
	await _walk(player, Vector2(400, 100))
	_assert(bag.count_item(apple) == 2, "Played: walking into the coin puts 2 Apples in the bag (got %d)" % bag.count_item(apple))
	_assert(run.get_node_or_null("Coin") == null, "Played: the coin is gone")
	await _press(KEY_I)
	_assert(list.visible, "Played: I opens the bag list")
	_assert(_rows(list) == PackedStringArray(["Apple x2"]), "Played: it reads Apple x2 (got %s)" % str(_rows(list)))
	await _walk(player, Vector2(400, 300))
	_assert(bag.count_item(sword) == 1 and run.get_node_or_null("Chest") == null, "Played: the Area2D pickup works too, and goes away")
	_assert(_rows(list) == PackedStringArray(["Apple x2", "Iron Sword x1"]), "Played: the open list follows the bag (got %s)" % str(_rows(list)))
	_assert(_inside(list), "Played: every line sits inside the panel")
	await _press(KEY_I)
	_assert(not list.visible, "Played: I again closes it")
	# a full bag leaves a new pickup where it lies
	bag.set("capacity", int(bag.call("slot_count")))
	var rock := Sprite2D.new()
	rock.name = "Rock"
	rock.position = Vector2(700, 100)
	run.add_child(rock)
	dock.wire_pickup(run, rock, potion, 1)
	await get_tree().physics_frame
	await _walk(player, Vector2(700, 100))
	_assert(bag.count_item(potion) == 0 and is_instance_valid(rock) and not rock.is_queued_for_deletion(), "Played: with the bag full, the potion stays on the ground")
	var said_full := false
	for t in get_tree().get_nodes_in_group("lite_toast"):
		said_full = said_full or String(t.text) == "Bag is full"
	_assert(said_full, "Played: and it says Bag is full")
	# nothing the list builds at runtime ends up saved
	rock.free()
	var again := PackedScene.new()
	again.pack(run)
	var copy := again.instantiate()
	_assert(copy.find_child("BagList", true, false).get_child_count() == 0, "Played: the list's rows are built at runtime only, never saved into the scene")
	copy.free()
	run.queue_free()
	await get_tree().process_frame


# The same in 3D: a CharacterBody3D walking into a mesh the tab made a pickup.
func _played_3d(dock) -> void:
	var apple := _apple
	var level := Node3D.new()
	level.name = "Level3D"
	var hero := _own(level, CharacterBody3D.new(), "Hero")
	var hs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.5
	hs.shape = sph
	hero.add_child(hs)
	hs.owner = level
	var gem: Node3D = _own(level, MeshInstance3D.new(), "Gem")
	gem.position = Vector3(6, 0, 0)
	dock.wire_inventory(level, hero, "player")
	dock.wire_pickup(level, gem, apple, 2)
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	var run := ps.instantiate()
	add_child(run)
	for i in 3:
		await get_tree().physics_frame
	var bag: Node = run.get_node("Hero/InventoryLite")
	_assert(bag.count_item(apple) == 0 and run.get_node_or_null("Gem") != null, "Played 3D: nothing is picked up from across the room")
	var body: Node3D = run.get_node("Hero")
	body.global_position = Vector3(6, 0, 0)
	for i in 6:
		await get_tree().physics_frame
	await get_tree().process_frame
	_assert(bag.count_item(apple) == 2 and run.get_node_or_null("Gem") == null, "Played 3D: walking into the Gem puts 2 Apples in the bag and the Gem goes")
	run.queue_free()
	await get_tree().process_frame


# ---- helpers for the above ---------------------------------------------------

# Saved, then loaded back, so each has a path: a packed scene points at the file
# and the running copy gets the very same item.
func _make_fixtures() -> void:
	_wipe(FIXTURES)
	DirAccess.make_dir_recursive_absolute(FIXTURES)
	_apple = _fixture("apple", "Apple", 99)
	_sword = _fixture("sword", "Iron Sword", 1)
	_potion = _fixture("potion", "Health Potion", 16)


func _fixture(id: String, item_name: String, max_stack: int) -> Resource:
	var it: Resource = load("res://addons/inventory_lite/item_resource.gd").new()
	it.set("id", id)
	it.set("name", item_name)
	it.set("max_stack", max_stack)
	var path := FIXTURES.path_join(id + ".tres")
	ResourceSaver.save(it, path)
	return load(path)


# The demo's items are only there in the lite's own project and its zip. Asked
# of the folder itself, not the tab's list, so a tab that lost its demo path
# still fails the examples check instead of skipping it. (The build and the
# starter kits rewrite this path to wherever they put the demo.)
func _has_demo() -> bool:
	return DirAccess.dir_exists_absolute(DEMO_ITEMS)


func _own(parent: Node, n: Node, nm: String) -> Node:
	n.name = nm
	parent.add_child(n)
	n.owner = parent if parent.owner == null else parent.owner
	return n


func _is(n: Node, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls


func _kids(n: Node, cls: String) -> int:
	var k := 0
	for c in n.get_children():
		if c.is_class(cls) or _is(c, cls):
			k += 1
	return k


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


# An item made in the Items (Lite) tab while both tabs are on screen is in the
# Item list the next time it opens, and the picked item stays picked.
func _run_item_list_refresh() -> void:
	var tab = CHOOSER.new()
	add_child(tab)
	await get_tree().process_frame
	tab._on_pick("pickup")
	var pick: OptionButton = tab._item_pick
	if pick.item_count > 0:
		pick.select(pick.item_count - 1)
	var kept := pick.get_item_text(pick.selected) if pick.selected >= 0 else ""
	var had_dir := DirAccess.dir_exists_absolute("res://items")
	DirAccess.make_dir_recursive_absolute("res://items")
	var item: Resource = load(CHOOSER.ITEM_SCRIPT).new()
	item.set("id", "f12b_fresh")
	item.set("name", "Fresh From The Items Tab")
	var path := "res://items/f12b_fresh.tres"
	ResourceSaver.save(item, path)
	pick.get_popup().about_to_popup.emit()
	_assert(_option_texts(pick).has("Fresh From The Items Tab"), "an item made after the tab was built is in its Item list when it opens (%s)" % [_option_texts(pick)])
	_assert(kept == "" or pick.get_item_text(pick.selected) == kept, "and the item that was picked stays picked (%s)" % kept)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
