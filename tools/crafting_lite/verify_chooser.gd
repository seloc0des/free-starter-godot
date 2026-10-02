extends Node

# Headless test for the Crafting — Lite chooser's wiring logic (the part behind
# the Apply button). Editor-only calls (get_edited_scene_root/selection) are split
# out; this drives the pure wire_* helper against a real scene tree and asserts the
# result is baked-in (owner == root), re-entrant, and ownership-scoped.
# Run: godot --headless --path . res://tools/crafting_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/crafting_lite/editor/crafting_chooser_dock.gd")
const CRAFTING := preload("res://addons/crafting_lite/crafting_lite.gd")
const TAB := preload("res://addons/crafting_lite/editor/lite_dock.gd")
const TMP_RECIPES := "user://vc_recipes"  # never the project's res://recipes
const TMP_ITEMS := "user://vc_items"
const TMP_FIX := "user://vc_fixture_items"
const OWN_ITEM_SCRIPT := "res://addons/crafting_lite/item_resource.gd"

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- crafting chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# SELECTED node — the component lands under the chosen target, owned by root
	var target := Node.new()
	target.name = "Bench"
	root.add_child(target); target.owner = root
	var comp1 = dock.wire_crafting(root, target)
	_assert(comp1 != null, "wire_crafting created a component")
	_assert(comp1.get_script() == CRAFTING, "spawned node is a CraftingLite")
	_assert(comp1.get_parent() == target, "component parented under the selected node")
	_assert(comp1.owner == root, "component owned by scene root: bakes into the .tscn")

	# RE-ENTRANT — applying again on the same target reuses the same component
	var comp2 = dock.wire_crafting(root, target)
	_assert(comp2 == comp1, "second Apply reused the same component (no duplicate)")
	var count := 0
	for c in target.get_children():
		if c.get_script() == CRAFTING:
			count += 1
	_assert(count == 1, "exactly one CraftingLite under the target after two Applies (got %d)" % count)

	# RECIPES — Apply hands over every recipe in res://recipes; a hand-added one from
	# elsewhere stays, and one deleted from res://recipes drops out.
	var mine1 := RecipeLite.new(); mine1.id = "mine1"
	mine1.take_over_path("res://recipes/verify_mine1.tres")
	var other := RecipeLite.new(); other.id = "other"
	other.take_over_path("res://elsewhere/verify_other.tres")
	_assert(dock.wire_recipes(comp1, [mine1]) == 1 and comp1.get("recipes")[0] == mine1, "Apply gave the component the recipe in res://recipes")
	_assert(dock.wire_recipes(comp1, [mine1]) == 1, "re-Apply doesn't add it twice")
	comp1.get("recipes").append(other)
	_assert(dock.wire_recipes(comp1, []) == 1 and comp1.get("recipes")[0] == other, "a recipe gone from res://recipes drops out, a hand-added one stays")

	# PLAYER TAG — crafting anywhere goes on the player; a plain scene root isn't tagged
	var hero := CharacterBody2D.new()
	root.add_child(hero); hero.owner = root
	_assert(dock.tag_player(root, hero) and hero.is_in_group("player"), "Player crafts anywhere tags the player")
	var on_hero = dock.wire_crafting(root, hero)
	_assert(dock._host_of(on_hero, root) == hero, "a selected CraftingLite counts as the node it sits on, so the player tag never lands on the component")
	_assert(not str(CHOOSER.OUTCOMES).contains("open-on-interact") and not str(CHOOSER.OUTCOMES).contains("opens from a button"),
		"the Pro note no longer promises a trigger or a menu button Pro doesn't add")
	_assert(not dock.tag_player(root, root) and not root.is_in_group("player"), "a plain scene root isn't tagged as the player")

	# SCENE ROOT scope — targeting root itself finds/creates a root-owned component
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var rc = dock.wire_crafting(root2, root2)
	_assert(rc.get_parent() == root2, "scene-root scope parents the component under root")
	_assert(rc.owner == root2, "scene-root component is owned by root")
	var rc2 = dock.wire_crafting(root2, root2)
	_assert(rc2 == rc, "scene-root scope is re-entrant too")
	root2.queue_free()

	# OWNERSHIP — a component inside an instanced sub-scene (owner != root) must NOT
	# be hijacked; Apply should make a fresh component the scene actually owns. Fresh
	# root so the ONLY CraftingLite present is the buried, non-owned one.
	var root3 := Node.new()
	get_tree().root.add_child(root3)
	var sub := Node.new()
	root3.add_child(sub); sub.owner = root3
	var buried = CRAFTING.new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root3
	var fresh = dock.wire_crafting(root3, root3)
	_assert(fresh != buried, "did not hijack a component owned by a sub-scene")
	_assert(fresh.owner == root3, "made a fresh component the scene root owns")
	root3.queue_free()

	# PARENT vs CHILD — a Town Applied after its Forge gets crafting of its own
	var root4 := Node.new()
	get_tree().root.add_child(root4)
	var town := Node2D.new(); town.name = "Town"
	root4.add_child(town); town.owner = root4
	var forge := Node2D.new(); forge.name = "Forge"
	town.add_child(forge); forge.owner = root4
	var at_forge = dock.wire_crafting(root4, forge)
	var at_town = dock.wire_crafting(root4, town)
	_assert(at_town != at_forge and at_town.get_parent() == town, "Apply on a parent makes its own crafting instead of taking the child's")
	_assert(at_forge.get_parent() == forge, "the child's crafting stays where it was")
	_assert(dock.wire_crafting(root4, town) == at_town, "re-Apply on the parent reuses its own")
	root4.queue_free()

	root.queue_free()

	_panel_checks(dock)
	_action_checks(dock)
	await _layout_checks(dock)
	await _dock_ui_checks()
	await _recipe_tab_checks()
	dock.free()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# ---- the crafting panel ----------------------------------------------------

func _panel_checks(dock) -> void:
	var lvl := Node2D.new()
	lvl.name = "Village"
	get_tree().root.add_child(lvl)
	var forge := _child(lvl, Node2D.new(), "Forge")
	var comp = dock.wire_crafting(lvl, forge)
	var panel: Node = dock.wire_panel(lvl, comp, true)
	_assert(panel != null and panel == lvl.get_node_or_null("UILayer/CraftPanel") and _script_is(panel, "CraftPanelLite") and panel.owner == lvl,
		"A crafting bench adds a CraftPanel on a UILayer, saved with the scene")
	if panel == null:
		lvl.queue_free()
		return
	_assert(not panel.visible and panel.get_node_or_null(panel.get("crafting_path")) == comp, "it starts hidden and shows this bench's crafting")
	var area: Node = forge.get_node_or_null("CraftArea")
	_assert(area is Area2D and area.owner == lvl and area.get_child_count() == 1 and area.get_child(0) is CollisionShape2D and area.get_child(0).owner == lvl,
		"a bench with nothing to touch gets a CraftArea (Area2D and its shape), saved")
	_assert(panel.get_node_or_null(panel.get("area_path")) == area and StringName(panel.get("toggle_action")) == &"",
		"the bench's panel opens from its CraftArea, not from a key")
	dock.wire_panel(lvl, dock.wire_crafting(lvl, forge), true)
	var areas := 0
	for c in forge.get_children():
		if c is Area2D:
			areas += 1
	_assert(_count_script(lvl, "CraftPanelLite") == 1 and areas == 1, "Apply again keeps one panel and one area per bench")
	var loom := _child(lvl, Node2D.new(), "Loom")
	var p2: Node = dock.wire_panel(lvl, dock.wire_crafting(lvl, loom), true)
	_assert(p2 == lvl.get_node_or_null("UILayer/LoomCraftPanel") and _count_script(lvl, "CraftPanelLite") == 2, "a second bench gets its own panel, LoomCraftPanel")
	var pot := _child(lvl, Area2D.new(), "Cauldron")
	var sh := CollisionShape2D.new()
	sh.shape = CircleShape2D.new()
	_child(pot, sh, "Shape", lvl)
	var p3: Node = dock.wire_panel(lvl, dock.wire_crafting(lvl, pot), true)
	_assert(pot.get_node_or_null("CraftArea") == null and p3.get_node(p3.get("area_path")) == pot, "a bench that's an Area2D with a shape opens from the area itself, no extra CraftArea")
	var well := _child(lvl, Area2D.new(), "Well")
	var p5: Node = dock.wire_panel(lvl, dock.wire_crafting(lvl, well), true)
	_assert(well.get_node_or_null("CraftArea") is Area2D and p5.get_node(p5.get("area_path")) == well.get_node("CraftArea"),
		"an Area2D with no shape can't be walked into, so it gets a CraftArea")
	var hero := _child(lvl, CharacterBody2D.new(), "Hero")
	var mine = dock.wire_crafting(lvl, hero)
	var p4: Node = dock.wire_panel(lvl, mine, false)
	_assert(StringName(p4.get("toggle_action")) == &"crafting" and p4.get("area_path") == NodePath("") and not p4.visible and hero.get_node_or_null("CraftArea") == null,
		"crafting anywhere gets a hidden panel on the crafting action, no area")
	_assert(dock.wire_panel(lvl, forge.get_node("CraftingLite"), false) == panel and StringName(panel.get("toggle_action")) == &"crafting" and panel.get("area_path") == NodePath(""),
		"switching a bench to anywhere reuses its panel and moves it to the key")
	dock.wire_panel(lvl, forge.get_node("CraftingLite"), true)
	_assert(not _any_name_has(lvl, "@"), "every node the Setup tab added has a readable name (%s)" % _names_with(lvl, "@"))
	var saved_inside := 0
	for n in panel.find_children("*", "", true, false):
		if n.owner != null:
			saved_inside += 1
	_assert(saved_inside == 0, "the panel builds its buttons at runtime, so none of them is saved into the scene")
	_assert(dock._host_of(panel, lvl) == forge and dock._host_of(area, lvl) == forge, "with the CraftPanel or CraftArea selected, Apply means its bench")
	var lvl3 := Node3D.new()
	get_tree().root.add_child(lvl3)
	var anvil := _child(lvl3, Node3D.new(), "Anvil")
	dock.wire_panel(lvl3, dock.wire_crafting(lvl3, anvil), true)
	var a3: Node = anvil.get_node_or_null("CraftArea")
	_assert(a3 is Area3D and a3.get_child(0) is CollisionShape3D, "a 3D bench gets an Area3D CraftArea")
	lvl3.queue_free()

	# the status line: who's the player, and whether they have a bag
	var lone := Node2D.new()
	get_tree().root.add_child(lone)
	_assert(dock._no_player_note(lone).contains("Make the selected node the player"), "no player in the scene: the status says how to mark one")
	lone.queue_free()
	dock.tag_player(lvl, hero)
	_assert(dock._no_player_note(lvl) == "" and dock._bag_gap(lvl, comp).contains("no bag"), "with a player marked, it says the player has no bag yet")
	var bag := Node.new()
	bag.set_script(load("res://addons/crafting_lite/_demo_bag.gd"))
	_child(hero, bag, "Bag", lvl)
	_assert(dock._bag_gap(lvl, comp) == "", "a player with a bag needs nothing more")
	lvl.queue_free()


func _action_checks(dock) -> void:
	var key := "input/crafting"
	var had: Variant = ProjectSettings.get_setting(key, null)
	ProjectSettings.set_setting(key, null)
	dock.ensure_crafting_action(false)
	var cfg: Variant = ProjectSettings.get_setting(key, null)
	var ev: Variant = (cfg as Dictionary).get("events", [null])[0] if cfg is Dictionary else null
	_assert(ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_B and (ev as InputEventKey).device == -1,
		"crafting anywhere adds the crafting action on B, physical key, any device")
	_assert(dock.action_keys("crafting") == "B", "the status line reads the key back (%s)" % dock.action_keys("crafting"))
	var c := InputEventKey.new()
	c.physical_keycode = KEY_C
	ProjectSettings.set_setting(key, {"deadzone": 0.5, "events": [c]})
	dock.ensure_crafting_action(false)
	_assert(dock.action_keys("crafting") == "C", "a key you rebound it to is left alone")
	ProjectSettings.set_setting(key, had)


# The Setup tab places the panel, so Play shows it right away (it doesn't lay
# itself out when it's been placed).
func _layout_checks(dock) -> void:
	# not in the tree, so the panel can't lay itself out: this is the dock's placement
	var lvl := Node2D.new()
	lvl.name = "Workshop"
	var bench := _child(lvl, Node2D.new(), "Bench")
	var panel: Control = dock.wire_panel(lvl, dock.wire_crafting(lvl, bench), true)
	_assert(panel.anchor_left == 0.5 and panel.anchor_right == 0.5 and panel.anchor_top == 0.0 and panel.anchor_bottom == 0.0, "the panel's anchors are set: top centre")
	panel.offset_top = 40.0
	dock.wire_panel(lvl, dock.wire_crafting(lvl, bench), true)
	_assert(panel.offset_top == 40.0, "a spot you picked survives Apply again")
	panel.offset_top = 16.0
	var ps := PackedScene.new()
	ps.pack(lvl)
	lvl.free()
	for size in [Vector2i(1280, 720), Vector2i(1152, 648)]:
		var vp := SubViewport.new()
		vp.size = size
		add_child(vp)
		var copy := ps.instantiate()
		vp.add_child(copy)
		await get_tree().process_frame
		var r: Rect2 = (copy.get_node("UILayer/CraftPanel") as Control).get_global_rect()
		_assert(r.is_equal_approx(Rect2(size.x / 2.0 - 160.0, 16.0, 320.0, 300.0)), "at %dx%d the panel is 320x300, top centre (%s)" % [size.x, size.y, r])
		vp.queue_free()


func _dock_ui_checks() -> void:
	var d = CHOOSER.new()
	add_child(d)  # builds its UI in _ready, no editor calls there
	await get_tree().process_frame
	var mk: Button = null
	var text := ""
	for n in d.find_children("*", "", true, false):
		if n is Button and (n as Button).text == "Make the selected node the player":
			mk = n
		elif n is Label:
			text += (n as Label).text + " "
	_assert(mk != null and mk.tooltip_text == "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group.",
		"the Setup tab has the Make the selected node the player button, with its tooltip")
	_assert(not text.contains("Inventory Path") and not str(CHOOSER.OUTCOMES).contains("unlocks no-code wiring") and str(CHOOSER.OUTCOMES).contains("styled recipe browser"),
		"the notes no longer ask you to bind an inventory, and say what Pro adds")
	d.queue_free()


func _child(parent: Node, n: Node, n_name: String, owner_root: Node = null) -> Node:
	n.name = n_name
	parent.add_child(n)
	n.owner = owner_root if owner_root != null else parent
	return n


func _script_is(n: Node, cls: String) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.get_global_name() == cls


func _count_script(root: Node, cls: String) -> int:
	var k := 0
	for n in root.find_children("*", "", true, false):
		if _script_is(n, cls):
			k += 1
	return k


# Scene nodes only: the panel's own controls are built at runtime and never saved.
func _names_with(root: Node, bit: String) -> String:
	var out := PackedStringArray()
	for n in root.find_children("*", "", true, true):
		if String(n.name).contains(bit):
			out.append(String(root.get_path_to(n)))
	return ", ".join(out)


func _any_name_has(root: Node, bit: String) -> bool:
	return _names_with(root, bit) != ""


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# ---- the Recipes (Lite) tab: New, and the Needs / Makes rows -----------------

func _recipe_tab_checks() -> void:
	_wipe(TMP_RECIPES)
	_wipe(TMP_ITEMS)
	var tab = TAB.new()
	add_child(tab)  # builds its UI; the editor-only calls are guarded
	await get_tree().process_frame
	tab._dir = TMP_RECIPES
	tab._on_new()
	var made: Resource = load(tab._current_path)
	_assert(tab._current_path == TMP_RECIPES + "/new_recipe.tres" and str(made.get("title")) == "New Recipe" and str(made.get("id")) == "new_recipe",
		"New makes new_recipe.tres, titled New Recipe, id new_recipe")
	_assert(tab._status.text.begins_with("Made " + TMP_RECIPES + "/new_recipe.tres"), "and says so: '%s'" % tab._status.text)
	tab._on_new()
	var second: Resource = load(tab._current_path)
	_assert(tab._current_path == TMP_RECIPES + "/new_recipe_2.tres" and str(second.get("title")) == "New Recipe 2" and str(second.get("id")) == "new_recipe_2",
		"a second New counts on: new_recipe_2.tres, New Recipe 2")

	# Rows need items with a path, to come back from the saved recipe. Made here,
	# not taken from the demo: the starter kits carry these tests without the demo.
	var fix := _fixtures([["wood", "Wood"], ["stick", "Stick"], ["stone", "Stone"]])
	var wood: Resource = fix["wood"]
	var stick: Resource = fix["stick"]
	tab._item_dir = TMP_FIX  # the fixtures stand in for res://items
	if _has_demo():
		var ex: Array = tab.item_choices(TMP_ITEMS)
		var tagged := ex.size() == 6 and _pick(ex, "Wood") != null and _pick(ex, "Stick") != null
		for c in ex:
			tagged = tagged and String(c["label"]).ends_with("(example)")
		_assert(tagged, "the item pickers offer the demo's 6 items, marked as examples")
	else:
		print("[--] item pickers: no demo in this project, so there are no examples to check")
	# the editor hands a recipe's default lists back read-only
	var ro: Array = []
	ro.make_read_only()
	tab._current.set("inputs", ro)
	tab.add_item_row(tab._current, "inputs", wood)
	tab.set_item_row(tab._current, "inputs", 0, "count", 2)
	tab.add_item_row(tab._current, "outputs", stick)
	tab.set_item_row(tab._current, "outputs", 0, "count", 4)
	_assert(ro.is_empty() and tab._current.get("inputs") == [{"item": wood, "count": 2}] and tab._current.get("outputs") == [{"item": stick, "count": 4}],
		"rows write {item, count} into fresh lists and leave the read-only one alone")

	# the same through the tab's own controls
	tab._build_fields()
	var adds: Array = _buttons(tab._fields, "Add row")
	_assert(adds.size() == 2 and _buttons(tab._fields, "New item").size() == 2, "Needs and Makes each have Add row and New item")
	var picks: Array = tab._fields.find_children("*", "OptionButton", true, false)
	_assert(picks.size() == 2 and (picks[0] as OptionButton).get_item_text((picks[0] as OptionButton).selected).begins_with("Wood")
		and (picks[1] as OptionButton).get_item_text((picks[1] as OptionButton).selected).begins_with("Stick"), "each row shows its item")
	if adds.size() == 2:
		(adds[0] as Button).pressed.emit()
	var rows_now: Array = tab._fields.find_children("*", "OptionButton", true, false)
	var fresh: OptionButton = rows_now[1] if rows_now.size() == 3 else null
	var stone := -1
	if fresh != null:
		for k in fresh.item_count:
			if stone < 0 and fresh.get_item_text(k).begins_with("Stone"):
				stone = k
		fresh.select(stone)
		fresh.item_selected.emit(stone)
	var ins: Array = tab._current.get("inputs")
	_assert(ins.size() == 2 and ins[1]["item"] != null and str(ins[1]["item"].get("id")) == "stone" and int(ins[1]["count"]) == 1,
		"Add row, then picking Stone, adds 1 Stone to what it needs")
	var counts: Array = tab._fields.find_children("*", "SpinBox", true, false)
	(counts[1] as SpinBox).value = 3
	_assert(int(tab._current.get("inputs")[1]["count"]) == 3 and tab._status.text == "Changed. Press Save to keep it.", "a count changes the row, and the tab says to Save")
	var rm: Array = _buttons(tab._fields, "Remove")
	(rm[1] as Button).pressed.emit()
	_assert(tab._current.get("inputs").size() == 1, "Remove takes the row out")

	tab._on_save()
	var path: String = tab._current_path
	var txt := FileAccess.get_file_as_string(path)
	_assert(txt.contains(wood.resource_path) and txt.contains(stick.resource_path) and txt.contains("\"count\": 4"), "Save writes the rows into the recipe file")
	var back: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_assert(back.get("inputs").size() == 1 and back.get("inputs")[0]["item"].resource_path == wood.resource_path and int(back.get("inputs")[0]["count"]) == 2
		and back.get("outputs")[0]["item"].resource_path == stick.resource_path and int(back.get("outputs")[0]["count"]) == 4,
		"loaded back from disk, the rows are the same")
	var bag = load("res://addons/crafting_lite/_demo_bag.gd").new()
	add_child(bag)
	var comp = CRAFTING.new()
	add_child(comp)
	comp.bind_inventory(bag)
	bag.add_item(wood, 2)
	_assert(comp.craft(back) and bag.count_item(wood) == 0 and bag.count_item(stick) == 4, "CraftingLite crafts the saved recipe: 2 wood in, 4 sticks out")

	var np: String = tab.make_item(TMP_ITEMS)
	var ni: Resource = load(np)
	# next to an Inventory addon New item takes its script, so bags and recipes share items
	var want := _want_item_script()
	_assert(np == TMP_ITEMS + "/new_item.tres" and str(ni.get("name")) == "New Item" and ni.get_script().resource_path == want,
		"New item makes new_item.tres with a name, on %s" % ("the pack's own item script (no Inventory here)" if want == OWN_ITEM_SCRIPT else "the Inventory item script, since it's installed (%s)" % want))
	_assert(tab.item_choices(TMP_ITEMS)[0]["item"] == ni, "and your own items list first")
	comp.queue_free()
	bag.queue_free()
	tab.queue_free()
	_wipe(TMP_RECIPES)
	_wipe(TMP_ITEMS)
	_wipe(TMP_FIX)


func _pick(choices: Array, label: String) -> Resource:
	for c in choices:
		if String(c["label"]).begins_with(label):
			return c["item"]
	return null


func _buttons(root: Node, text: String) -> Array:
	var out: Array = []
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			out.append(b)
	return out


func _fixtures(specs: Array) -> Dictionary:
	_wipe(TMP_FIX)
	DirAccess.make_dir_recursive_absolute(TMP_FIX)
	var scr: Script = load(OWN_ITEM_SCRIPT)
	var out := {}
	for spec in specs:
		var it: Resource = scr.new()
		it.set("id", spec[0])
		it.set("name", spec[1])
		var path := TMP_FIX.path_join(spec[0] + ".tres")
		ResourceSaver.save(it, path)
		out[spec[0]] = load(path)
	return out


func _has_demo() -> bool:
	for d: String in TAB.DEMO_ITEM_DIRS:
		if DirAccess.dir_exists_absolute(d):
			return true
	return false


# What New item should use here: Inventory's script when it's installed.
func _want_item_script() -> String:
	for p in ["res://addons/inventory/resources/item_resource.gd", "res://addons/inventory_lite/item_resource.gd"]:
		if FileAccess.file_exists(p):
			return p
	return OWN_ITEM_SCRIPT


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
