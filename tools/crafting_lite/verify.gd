extends Node

# Headless test for Crafting — Lite.
# Run: godot --headless --path . res://tools/crafting_lite/verify.tscn

const CHOOSER := preload("res://addons/crafting_lite/editor/crafting_chooser_dock.gd")
const TAB := preload("res://addons/crafting_lite/editor/lite_dock.gd")
const DemoBag := preload("res://addons/crafting_lite/_demo_bag.gd")

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- crafting lite verify ---")
	await _run_happy_path_craft()
	await _run_missing_inputs_rejected()
	await _run_no_inventory_rejected()
	await _run_craft_completed_alias()
	await _run_link_player()
	await _run_bench_play()
	await _run_anywhere_play()
	await _run_tab_recipe_play()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/crafting_lite/acceptance_report.gd").new()
		get_tree().root.add_child(report)
		report.render(_passes, _failures, _log)


func _assert(cond: bool, msg: String) -> void:
	_log.append([cond, msg])
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# ---- helpers -------------------------------------------------------------

# Minimal duck-typed bag for the crafting tests. The Lite crafting addon
# expects has_item / remove_item / add_item.
class _MiniBag extends Node:
	var items: Dictionary = {}  # id -> count
	func count_item(item: Resource) -> int:
		return int(items.get(str(item.id), 0))
	func has_item(item: Resource, amount: int = 1) -> bool:
		return count_item(item) >= amount
	func add_item(item: Resource, amount: int) -> int:
		items[str(item.id)] = count_item(item) + amount
		return 0
	func remove_item(item: Resource, amount: int) -> int:
		var have: int = count_item(item)
		var take: int = mini(have, amount)
		items[str(item.id)] = have - take
		if items[str(item.id)] <= 0:
			items.erase(str(item.id))
		return take


# Resources that quack like ItemLite — anything with `.id` works.
class _Item extends Resource:
	@export var id: String = ""
	@export var name: String = ""


func _item(id: String, display := "") -> Resource:
	var it := _Item.new()
	it.id = id
	it.name = display
	return it


func _recipe(inputs: Array, outputs: Array) -> RecipeLite:
	var r := RecipeLite.new()
	r.id = "test_recipe"
	r.inputs = inputs
	r.outputs = outputs
	return r


func _make_component(bag: Node) -> CraftingLite:
	var c := CraftingLite.new()
	c._inventory = bag
	add_child(c)
	return c


# ---- tests ---------------------------------------------------------------

func _run_happy_path_craft() -> void:
	await get_tree().process_frame
	var bag := _MiniBag.new()
	add_child(bag)
	var wood := _item("wood")
	var stick := _item("stick")
	bag.add_item(wood, 5)
	var comp := _make_component(bag)
	var ok := comp.craft(_recipe(
		[RecipeLite.io(wood, 1)],
		[RecipeLite.io(stick, 4)],
	))
	_assert(ok, "Happy: craft returns true")
	_assert(bag.count_item(wood) == 4, "Happy: 1 wood consumed (4 left, got %d)" % bag.count_item(wood))
	_assert(bag.count_item(stick) == 4, "Happy: 4 sticks produced (got %d)" % bag.count_item(stick))
	comp.queue_free(); bag.queue_free()


func _run_missing_inputs_rejected() -> void:
	await get_tree().process_frame
	var bag := _MiniBag.new()
	add_child(bag)
	var wood := _item("wood")
	var stick := _item("stick")
	# Empty bag — no wood.
	var comp := _make_component(bag)
	# GDScript lambdas capture scalars by value, so accumulate into an Array
	# (reference-typed) and read the last entry instead.
	var reason_box: Array = []
	comp.craft_failed.connect(func(_r, r): reason_box.append(r))
	var ok := comp.craft(_recipe(
		[RecipeLite.io(wood, 1)],
		[RecipeLite.io(stick, 1)],
	))
	_assert(not ok, "Missing: craft returns false")
	_assert(reason_box.size() == 1 and String(reason_box[0]) == CraftingLite.REASON_MISSING_INPUTS,
		"Missing: reason is missing_inputs (got %s)" % str(reason_box))
	comp.queue_free(); bag.queue_free()


func _run_no_inventory_rejected() -> void:
	await get_tree().process_frame
	var wood := _item("wood")
	var stick := _item("stick")
	var comp := CraftingLite.new()
	comp._inventory = null
	add_child(comp)
	var reason_box: Array = []
	comp.craft_failed.connect(func(_r, r): reason_box.append(r))
	var ok := comp.craft(_recipe(
		[RecipeLite.io(wood, 1)],
		[RecipeLite.io(stick, 1)],
	))
	_assert(not ok, "NoInv: craft returns false")
	_assert(reason_box.size() == 1 and String(reason_box[0]) == CraftingLite.REASON_NO_INVENTORY,
		"NoInv: reason is no_inventory_bound (got %s)" % str(reason_box))
	comp.queue_free()


# Regression: the `craft_completed` alias was added to align Lite with Pro
# (which uses `craft_completed` exclusively). Both names must continue to
# fire so existing Lite consumers don't break.
func _run_craft_completed_alias() -> void:
	await get_tree().process_frame
	var bag := _MiniBag.new()
	add_child(bag)
	var wood := _item("wood")
	var stick := _item("stick")
	bag.add_item(wood, 1)
	var comp := _make_component(bag)
	var saw: Array = []
	comp.crafted.connect(func(_r, _o): saw.append("legacy"))
	comp.craft_completed.connect(func(_r, _o): saw.append("aligned"))
	comp.craft(_recipe(
		[RecipeLite.io(wood, 1)],
		[RecipeLite.io(stick, 1)],
	))
	_assert("legacy" in saw, "Alias: legacy `crafted` still fires (saw %s)" % str(saw))
	_assert("aligned" in saw, "Alias: aligned `craft_completed` also fires (saw %s)" % str(saw))
	comp.queue_free(); bag.queue_free()


# No path set: the crafting finds the bag on the "player" group's node.
func _run_link_player() -> void:
	await get_tree().process_frame
	var comp := CraftingLite.new()
	add_child(comp)
	_assert(comp.link_player() == CraftingLite.REASON_NO_PLAYER, "LinkPlayer: nothing in the player group says no_player")
	var hero := Node2D.new()
	hero.add_to_group("player")
	add_child(hero)
	_assert(comp.link_player() == CraftingLite.REASON_NO_INVENTORY, "LinkPlayer: a player with no bag says no_inventory_bound")
	var bag := _MiniBag.new()
	hero.add_child(bag)
	_assert(comp.link_player() == "" and comp.get_inventory() == bag, "LinkPlayer: it finds the bag on the player")
	var own := _MiniBag.new()
	add_child(own)
	var comp2 := CraftingLite.new()
	comp2.bind_inventory(own)
	add_child(comp2)
	comp2.link_player()
	_assert(comp2.get_inventory() == own, "LinkPlayer: a bag set on the crafting wins")
	comp.queue_free(); comp2.queue_free(); own.queue_free(); hero.queue_free()


# End to end, the way a buyer gets it: "A crafting bench" wired by the Setup tab,
# packed and played. Walk up, craft, walk away.
func _run_bench_play() -> void:
	await get_tree().process_frame
	var dock = CHOOSER.new()
	var level := Node2D.new()
	level.name = "Level"
	var player := _body_2d(level, "Player", Vector2(100, 100))
	var bag = DemoBag.new()
	bag.name = "Bag"
	player.add_child(bag)
	bag.owner = level
	dock.tag_player(level, player)
	var forge := Node2D.new()
	forge.name = "Forge"
	forge.position = Vector2(500, 300)
	level.add_child(forge)
	forge.owner = level
	var wood := _item("wood", "Wood")
	var stick := _item("stick", "Stick")
	var iron := _item("iron", "Iron")
	var sword := _item("sword", "Iron Sword")
	var comp = dock.wire_crafting(level, forge)
	dock.wire_recipes(comp, [
		_titled("Carve Sticks", [RecipeLite.io(wood, 1)], [RecipeLite.io(stick, 2)]),
		_titled("Forge a Sword", [RecipeLite.io(iron, 2), RecipeLite.io(stick, 1)], [RecipeLite.io(sword, 1)]),
	])
	dock.wire_panel(level, comp, true)
	var ps := PackedScene.new()
	_assert(ps.pack(level) == OK, "BenchPlay: the scene the Setup tab built packs")
	level.free()
	dock.free()

	var vp := SubViewport.new()
	vp.size = Vector2i(1152, 648)  # a new project's window
	add_child(vp)
	var game: Node = ps.instantiate()
	vp.add_child(game)
	await get_tree().process_frame
	var hero: Node2D = game.get_node("Player")
	var gbag: Node = hero.get_node("Bag")
	gbag.add_item(wood, 3)
	gbag.add_item(iron, 2)
	var panel: Control = game.get_node_or_null("UILayer/CraftPanel")
	_assert(panel is CraftPanelLite and not panel.visible, "BenchPlay: the CraftPanel starts hidden")
	if not (panel is CraftPanelLite):
		vp.queue_free()
		return
	var near: Vector2 = game.get_node("Forge").global_position + Vector2(30, 0)
	hero.global_position = near
	await _physics(4)
	_assert(panel.visible, "BenchPlay: walking up to the bench opens it")
	await get_tree().process_frame
	var r := panel.get_global_rect()
	_assert(r.is_equal_approx(Rect2(416, 16, 320, 300)), "BenchPlay: it sits top centre, 320x300 in a 1152x648 window (%s)" % r)
	var need: Vector2 = panel.get_child(0).get_combined_minimum_size()
	_assert(need.x <= r.size.x and need.y <= r.size.y, "BenchPlay: its content fits inside it (needs %s)" % need)
	var sticks := _row_button(panel, "Carve Sticks", "Craft")
	var swords := _row_button(panel, "Forge a Sword", "Craft")
	_assert(sticks != null and not sticks.disabled, "BenchPlay: Carve Sticks can be crafted (3 wood in the bag)")
	_assert(swords != null and swords.disabled, "BenchPlay: Forge a Sword is greyed out, no stick yet")
	_assert(_has_text(panel, "1 Wood (have 3)") and _has_text(panel, "Makes: 2 Stick"), "BenchPlay: each recipe lists what it needs, what you have and what it makes")
	if sticks == null or swords == null:
		vp.queue_free()
		return
	sticks.pressed.emit()
	await get_tree().process_frame
	_assert(gbag.count_item(wood) == 2 and gbag.count_item(stick) == 2,
		"BenchPlay: Craft used 1 wood and put 2 sticks in the bag (%d wood, %d stick)" % [gbag.count_item(wood), gbag.count_item(stick)])
	_assert(_toast("+2 Stick"), "BenchPlay: a \"+2 Stick\" message shows top centre")
	swords = _row_button(panel, "Forge a Sword", "Craft")
	_assert(swords != null and not swords.disabled, "BenchPlay: with a stick in the bag the sword lights up")
	if swords != null:
		swords.pressed.emit()
	await get_tree().process_frame
	_assert(gbag.count_item(iron) == 0 and gbag.count_item(stick) == 1 and gbag.count_item(sword) == 1,
		"BenchPlay: the sword took 2 iron and a stick (%d iron, %d stick, %d sword)" % [gbag.count_item(iron), gbag.count_item(stick), gbag.count_item(sword)])
	_assert(_has_text(panel, "Made Forge a Sword."), "BenchPlay: the panel says what it made")
	# a click can't reach a greyed-out button, so press its handler
	_click(_row_button(panel, "Forge a Sword", "Craft"))
	await get_tree().process_frame
	_assert(_has_text(panel, "You don't have everything for that yet.") and gbag.count_item(stick) == 1,
		"BenchPlay: short of iron it says why and takes nothing")

	# a long recipe list scrolls inside the panel instead of growing it
	var many: Array = []
	for i in 12:
		many.append(_titled("Recipe %d" % i, [RecipeLite.io(wood, 1)], [RecipeLite.io(stick, 1)]))
	var gcomp: Node = game.get_node("Forge/CraftingLite")
	gcomp.set("recipes", many)
	gcomp.recipes_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = panel.find_children("*", "ScrollContainer", true, false)[0]
	_assert(panel.get_global_rect().is_equal_approx(r) and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,
		"BenchPlay: 12 recipes scroll inside the same 320x300 panel")

	hero.global_position = Vector2(100, 100)
	await _physics(4)
	_assert(not panel.visible, "BenchPlay: walking away closes it")
	hero.global_position = near
	await _physics(4)
	_assert(panel.visible, "BenchPlay: walking back up opens it again")
	var shut := _button(panel, "Close")
	if shut != null:
		shut.pressed.emit()
	_assert(not panel.visible, "BenchPlay: Close shuts it")
	vp.queue_free()


# "Player crafts anywhere": the panel toggles with B, once the Setup tab has
# added the crafting action. A bench next to it shows one window at a time.
func _run_anywhere_play() -> void:
	await get_tree().process_frame
	var dock = CHOOSER.new()
	var level := Node2D.new()
	level.name = "Camp"
	var player := _body_2d(level, "Player", Vector2(100, 100))
	var bag = DemoBag.new()
	bag.name = "Bag"
	player.add_child(bag)
	bag.owner = level
	var wood := _item("wood", "Wood")
	var plank := _item("plank", "Plank")
	var comp = dock.wire_crafting(level, player)
	dock.tag_player(level, player)
	dock.wire_recipes(comp, [_titled("Saw Planks", [RecipeLite.io(wood, 1)], [RecipeLite.io(plank, 2)])])
	dock.wire_panel(level, comp, false)
	var bench := Node2D.new()
	bench.name = "Bench"
	bench.position = Vector2(500, 300)
	level.add_child(bench)
	bench.owner = level
	dock.wire_panel(level, dock.wire_crafting(level, bench), true)
	# start from a project without the action, whatever project hosts this test
	var had: Variant = ProjectSettings.get_setting("input/crafting", null)
	ProjectSettings.set_setting("input/crafting", null)
	_reload_action("crafting")
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()

	# on the root viewport, where key presses land
	var game: Node = ps.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.get_node("Player/Bag").add_item(wood, 2)
	var panel: Control = game.get_node_or_null("UILayer/CraftPanel")
	var at_bench: Control = game.get_node_or_null("UILayer/BenchCraftPanel")
	_assert(panel is CraftPanelLite and not panel.visible and StringName(panel.get("toggle_action")) == &"crafting",
		"AnywherePlay: the player's CraftPanel starts hidden, toggled by the crafting action")
	_assert(at_bench is CraftPanelLite, "AnywherePlay: a second bench's panel gets a readable name, BenchCraftPanel")
	if panel is CraftPanelLite and at_bench is CraftPanelLite:
		await _anywhere_steps(dock, game, panel, at_bench, wood, plank)
	game.queue_free()
	dock.free()
	ProjectSettings.set_setting("input/crafting", had)
	_reload_action("crafting")


func _anywhere_steps(dock, game: Node, panel: Control, at_bench: Control, wood: Resource, plank: Resource) -> void:
	var hero: Node2D = game.get_node("Player")
	await _press(KEY_B)
	_assert(not panel.visible, "AnywherePlay: B does nothing until the Setup tab adds the crafting action")
	dock.ensure_crafting_action(false)
	_reload_action("crafting")  # what a game does with it when it starts
	_assert(dock.action_keys("crafting") == "B", "AnywherePlay: the crafting action is on B (%s)" % dock.action_keys("crafting"))
	await _press(KEY_B)
	_assert(panel.visible, "AnywherePlay: B opens it")
	await get_tree().process_frame
	var saw := _row_button(panel, "Saw Planks", "Craft")
	_assert(saw != null and not saw.disabled, "AnywherePlay: it lists the player's recipe, ready to craft")
	if saw != null:
		saw.pressed.emit()
	await get_tree().process_frame
	_assert(hero.get_node("Bag").count_item(plank) == 2 and hero.get_node("Bag").count_item(wood) == 1, "AnywherePlay: crafting anywhere works from the player's bag")
	await _press(KEY_B)
	_assert(not panel.visible, "AnywherePlay: B closes it again")

	hero.global_position = game.get_node("Bench").global_position + Vector2(30, 0)
	await _physics(4)
	_assert(at_bench.visible, "AnywherePlay: the bench's own panel opens on walk-up")
	await _press(KEY_B)
	_assert(panel.visible and not at_bench.visible, "AnywherePlay: pressing B at the bench swaps windows, never two on top of each other")


# Loads one Input Map action from the project settings, the way the game does at
# start, without touching any other action.
func _reload_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	var cfg: Variant = ProjectSettings.get_setting("input/" + action, null)
	if cfg is Dictionary:
		InputMap.add_action(action, float((cfg as Dictionary).get("deadzone", 0.5)))
		for e in (cfg as Dictionary).get("events", []):
			InputMap.action_add_event(action, e)


# A recipe made in the Recipes (Lite) tab, rows and all, handed to a bench and
# crafted in a played scene.
func _run_tab_recipe_play() -> void:
	await get_tree().process_frame
	var dir := "user://vc_play_recipes"  # never the project's res://recipes
	var tab = TAB.new()
	add_child(tab)
	await get_tree().process_frame
	tab._dir = dir
	tab._on_new()
	var path: String = tab._current_path
	tab._current.set("title", "Saw Sticks")
	# items saved as files, made here: the starter kits carry this test without the demo
	var items_dir := "user://vc_play_items"
	DirAccess.make_dir_recursive_absolute(items_dir)
	var made := {}
	for spec in [["wood", "Wood"], ["stick", "Stick"]]:
		var it: Resource = load("res://addons/crafting_lite/item_resource.gd").new()
		it.set("id", spec[0])
		it.set("name", spec[1])
		ResourceSaver.save(it, items_dir.path_join(spec[0] + ".tres"))
		made[spec[0]] = load(items_dir.path_join(spec[0] + ".tres"))
	var wood: Resource = made["wood"]
	var stick: Resource = made["stick"]
	tab.set_item_row(tab._current, "inputs", tab.add_item_row(tab._current, "inputs", wood), "count", 2)
	tab.set_item_row(tab._current, "outputs", tab.add_item_row(tab._current, "outputs", stick), "count", 3)
	tab._on_save()
	var recipe: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	tab.queue_free()
	_assert(recipe != null and str(recipe.get("title")) == "Saw Sticks" and recipe.get("inputs").size() == 1, "TabRecipe: the tab saved a recipe with its rows")
	if recipe == null or wood == null or stick == null:
		return

	var dock = CHOOSER.new()
	var level := Node2D.new()
	level.name = "Yard"
	var player := _body_2d(level, "Player", Vector2(100, 100))
	var bag = DemoBag.new()
	bag.name = "Bag"
	player.add_child(bag)
	bag.owner = level
	dock.tag_player(level, player)
	var bench := Node2D.new()
	bench.name = "Sawhorse"
	bench.position = Vector2(500, 300)
	level.add_child(bench)
	bench.owner = level
	var comp = dock.wire_crafting(level, bench)
	dock.wire_recipes(comp, [recipe])
	dock.wire_panel(level, comp, true)
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	dock.free()
	var vp := SubViewport.new()
	vp.size = Vector2i(1152, 648)
	add_child(vp)
	var game: Node = ps.instantiate()
	vp.add_child(game)
	await get_tree().process_frame
	var hero: Node2D = game.get_node("Player")
	var gbag: Node = hero.get_node("Bag")
	gbag.add_item(wood, 2)
	hero.global_position = game.get_node("Sawhorse").global_position + Vector2(30, 0)
	await _physics(4)
	var panel: Control = game.get_node_or_null("UILayer/CraftPanel")
	await get_tree().process_frame
	var craft := _row_button(panel, "Saw Sticks", "Craft") if panel != null else null
	_assert(panel != null and panel.visible and craft != null and not craft.disabled and _has_text(panel, "2 Wood (have 2)") and _has_text(panel, "Makes: 3 Stick"),
		"TabRecipe: walking up to the bench shows it, ready to craft")
	_click(craft)
	await get_tree().process_frame
	_assert(gbag.count_item(wood) == 0 and gbag.count_item(stick) == 3, "TabRecipe: Craft turns 2 wood into 3 sticks (%d wood, %d stick)" % [gbag.count_item(wood), gbag.count_item(stick)])
	vp.queue_free()
	for tmp in [dir, items_dir]:
		var d := DirAccess.open(tmp)
		if d != null:
			for f in d.get_files():
				d.remove(f)


func _titled(title: String, inputs: Array, outputs: Array) -> RecipeLite:
	var r := _recipe(inputs, outputs)
	r.id = title.to_snake_case()
	r.title = title
	return r


func _body_2d(level: Node, n: String, at: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = n
	body.position = at
	level.add_child(body)
	body.owner = level
	var col := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(24, 24)
	col.shape = box
	body.add_child(col)
	col.owner = level
	return body


func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


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
	await get_tree().process_frame


# The row's button whose label mentions `text`.
func _row_button(root: Node, text: String, verb: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text != verb or not (b.get_parent() is HBoxContainer):
			continue
		for c in b.get_parent().get_children():
			if c is Label and (c as Label).text.contains(text):
				return b
	return null


# null-safe, so a broken panel reports FAIL lines instead of stopping the run
func _click(b: Button) -> void:
	if b != null:
		b.pressed.emit()


func _button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _has_text(root: Node, text: String) -> bool:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text.contains(text):
			return true
	return false


# A lite toast: a Label in group lite_toast, top centre on a layer-100 CanvasLayer.
func _toast(text: String) -> bool:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Label and (t as Label).text == text and not t.is_queued_for_deletion():
			var layer: Node = t.get_parent()
			return layer is CanvasLayer and (layer as CanvasLayer).layer == 100 and is_equal_approx((t as Label).anchor_left, 0.5)
	return false
