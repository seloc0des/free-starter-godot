extends Node

# Headless test for Loot — Lite.
# Run: godot --headless --path . res://tools/loot_lite/verify.tscn

const ItemLiteScript := preload("res://addons/loot_lite/item_resource.gd")
const DropScript := preload("res://addons/loot_lite/loot_drop_lite.gd")
const BagScript := preload("res://tools/loot_lite/test_bag.gd")
const HealthScript := preload("res://tools/loot_lite/test_health.gd")

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- loot lite verify ---")
	await _run_basic_weighted_roll()
	await _run_count_range_respected()
	await _run_empty_table_returns_empty()
	await _run_zero_weight_filtered()
	await _run_deterministic_with_seed()
	# LootDropLite in a played scene: no code, the player just walks in or it dies
	await _run_touch_drop_fills_bag()
	await _run_touch_ignores_non_player()
	await _run_touch_again_when_not_once()
	await _run_death_drop()
	await _run_death_signal_with_argument()
	await _run_death_skips_player_being_freed()
	await _run_no_bag_still_says_so()
	await _run_full_bag_says_so()
	await _run_messages_stack_and_clear()
	await _run_touch_drop_3d()
	_run_describe()
	_clear_toasts()  # the test messages would sit on top of the banner
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/loot_lite/acceptance_report.gd").new()
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

func _item(id: String) -> Resource:
	var it: Resource = ItemLiteScript.new()
	it.id = id
	it.name = id.capitalize()
	return it


func _make_table(entries: Array, rolls: int = 1) -> LootTableLite:
	var t := LootTableLite.new()
	t.entries = entries
	t.rolls = rolls
	return t


# ---- tests ---------------------------------------------------------------

func _run_basic_weighted_roll() -> void:
	await get_tree().process_frame
	# 50/50 between coin and ruby over 2000 rolls should land within ~5%.
	var coin := _item("coin")
	var ruby := _item("ruby")
	var t := _make_table([
		{"item": coin, "weight": 50, "min": 1, "max": 1},
		{"item": ruby, "weight": 50, "min": 1, "max": 1},
	])
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var coin_count := 0
	var ruby_count := 0
	for i in range(2000):
		for r in t.roll(rng):
			if str(r.item.id) == "coin":
				coin_count += 1
			elif str(r.item.id) == "ruby":
				ruby_count += 1
	var ratio: float = float(coin_count) / float(maxi(ruby_count, 1))
	_assert(ratio > 0.85 and ratio < 1.15,
		"Weights: ~50/50 distribution (ratio %.2f, coin %d, ruby %d)" % [ratio, coin_count, ruby_count])


func _run_count_range_respected() -> void:
	await get_tree().process_frame
	var coin := _item("coin")
	var t := _make_table([
		{"item": coin, "weight": 100, "min": 3, "max": 5},
	])
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var min_seen := 100
	var max_seen := 0
	for i in range(200):
		for r in t.roll(rng):
			min_seen = mini(min_seen, int(r.count))
			max_seen = maxi(max_seen, int(r.count))
	_assert(min_seen >= 3 and max_seen <= 5,
		"CountRange: counts stay in [3..5] (seen %d..%d)" % [min_seen, max_seen])


func _run_empty_table_returns_empty() -> void:
	await get_tree().process_frame
	var t := _make_table([])
	_assert(t.roll().is_empty(), "Empty: empty entries → empty Array")
	var t2 := _make_table([{"item": _item("x"), "weight": 100}], 0)
	_assert(t2.roll().is_empty(), "Empty: rolls=0 → empty Array")


func _run_zero_weight_filtered() -> void:
	await get_tree().process_frame
	# Only zero-weight entries → total weight is 0 → empty result.
	var coin := _item("coin")
	var t := _make_table([
		{"item": coin, "weight": 0, "min": 1, "max": 1},
	])
	_assert(t.roll().is_empty(), "ZeroWeight: total weight 0 → empty result")


func _run_deterministic_with_seed() -> void:
	await get_tree().process_frame
	var a := _item("a")
	var b := _item("b")
	var c := _item("c")
	var t := _make_table([
		{"item": a, "weight": 30, "min": 1, "max": 1},
		{"item": b, "weight": 30, "min": 1, "max": 1},
		{"item": c, "weight": 40, "min": 1, "max": 1},
	], 3)
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var ids1: Array = []
	var ids2: Array = []
	for r in t.roll(rng1): ids1.append(str(r.item.id))
	for r in t.roll(rng2): ids2.append(str(r.item.id))
	_assert(ids1 == ids2, "Seed: same seed → same drops (%s vs %s)" % [str(ids1), str(ids2)])


# ---- LootDropLite: played scenes ------------------------------------------

func _gold() -> Resource:
	var it := _item("gold")
	it.name = "Gold"
	return it


func _gold_table(count: int = 5) -> LootTableLite:
	return _make_table([{"item": _gold(), "weight": 100, "min": count, "max": count}])


# A chest you can walk into: an Area2D with a shape, holding a LootDropLite.
func _chest(parent: Node, pos: Vector2, table: LootTableLite) -> Node:
	var chest := Area2D.new()
	chest.name = "Chest"
	chest.position = pos
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 32.0
	cs.shape = circle
	chest.add_child(cs)
	parent.add_child(chest)
	chest.add_child(_drop(table, 0))
	return chest


func _drop(table: LootTableLite, trigger: int) -> Node:
	var d: Node = DropScript.new()
	d.name = "LootDrop"
	d.table = table
	d.trigger = trigger
	return d


func _hero(parent: Node, pos: Vector2, is_player: bool, with_bag: bool = true) -> CharacterBody2D:
	var hero := CharacterBody2D.new()
	hero.name = "Hero"
	hero.position = pos
	if is_player:
		hero.add_to_group("player")
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(16, 16)
	cs.shape = box
	hero.add_child(cs)
	if with_bag:
		var bag: Node = BagScript.new()
		bag.name = "Bag"
		hero.add_child(bag)
	parent.add_child(hero)
	return hero


func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _toasts() -> PackedStringArray:
	var out := PackedStringArray()
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Label and not t.is_queued_for_deletion():
			out.append((t as Label).text)
	return out


func _toast_has(text: String) -> bool:
	for t in _toasts():
		if t.contains(text):
			return true
	return false


# toasts from an earlier check would pass a later one, so each check starts clean
func _clear_toasts() -> void:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		t.remove_from_group("lite_toast")
		t.get_parent().queue_free()


func _run_touch_drop_fills_bag() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var gold_table := _gold_table()
	var gold: Resource = gold_table.entries[0].item
	var chest := _chest(lvl, Vector2(400, 200), gold_table)
	var hero := _hero(lvl, Vector2(40, 40), true)
	var bag: Node = hero.get_node("Bag")
	await _physics(3)
	_assert(bag.count_item(gold) == 0 and _toasts().is_empty(), "Touch: nothing drops before the player arrives")
	hero.position = chest.position
	await _physics(4)
	_assert(bag.count_item(gold) == 5, "Touch: walking in puts the loot in the player's bag (got %d)" % bag.count_item(gold))
	_assert(_toast_has("Found: Gold x5"), "Touch: a message says what dropped (%s)" % ", ".join(_toasts()))
	hero.position = Vector2(40, 40)
	await _physics(3)
	hero.position = chest.position
	await _physics(4)
	_assert(bag.count_item(gold) == 5, "Once: walking in again drops nothing more (got %d)" % bag.count_item(gold))
	lvl.queue_free()


# control for the check above: the same walk-in by a body that isn't the player
func _run_touch_ignores_non_player() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var gold_table := _gold_table()
	var chest := _chest(lvl, Vector2(400, 200), gold_table)
	var npc := _hero(lvl, Vector2(40, 40), false)
	await _physics(2)
	npc.position = chest.position
	await _physics(4)
	var bag: Node = npc.get_node("Bag")
	_assert(bag.total() == 0 and _toasts().is_empty(), "Touch: a body that isn't the player drops nothing")
	lvl.queue_free()


func _run_touch_again_when_not_once() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var gold_table := _gold_table()
	var chest := _chest(lvl, Vector2(400, 200), gold_table)
	chest.get_node("LootDrop").once = false
	var hero := _hero(lvl, Vector2(40, 40), true)
	var bag: Node = hero.get_node("Bag")
	await _physics(2)
	for i in 2:
		hero.position = chest.position
		await _physics(4)
		hero.position = Vector2(40, 40)
		await _physics(3)
	_assert(bag.total() == 10, "Once off: each visit drops again (got %d after two)" % bag.total())
	lvl.queue_free()


func _run_death_drop() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	var enemy := CharacterBody2D.new()
	enemy.name = "Bandit"
	lvl.add_child(enemy)
	var hp: Node = HealthScript.new()
	hp.name = "Health"
	enemy.add_child(hp)
	enemy.add_child(_drop(_gold_table(3), 1))
	var hero := _hero(lvl, Vector2(40, 40), true)
	get_tree().root.add_child(lvl)
	await get_tree().process_frame
	var bag: Node = hero.get_node("Bag")
	_assert(bag.total() == 0, "Dies: nothing drops while it's alive")
	hp.emit_signal("died")
	_assert(bag.total() == 3, "Dies: its Health's died puts the loot in the player's bag (got %d)" % bag.total())
	_assert(_toast_has("Found: Gold x3"), "Dies: a message says what dropped (%s)" % ", ".join(_toasts()))
	hp.emit_signal("died")
	_assert(bag.total() == 3, "Once: dying twice drops once (got %d)" % bag.total())
	lvl.queue_free()


# a died that carries an argument (who killed it) still counts
func _run_death_signal_with_argument() -> void:
	_clear_toasts()
	var hp_script := GDScript.new()
	hp_script.source_code = "extends Node\nsignal died(by)\n"
	hp_script.reload()
	var lvl := Node2D.new()
	var enemy := Node2D.new()
	lvl.add_child(enemy)
	var hp := Node.new()
	hp.set_script(hp_script)
	enemy.add_child(hp)
	enemy.add_child(_drop(_gold_table(2), 1))
	var hero := _hero(lvl, Vector2(40, 40), true)
	get_tree().root.add_child(lvl)
	await get_tree().process_frame
	hp.emit_signal("died", hero)
	_assert(hero.get_node("Bag").total() == 2, "Dies: a died(by) signal drops too")
	lvl.queue_free()


# a level on its way out still has its player in the group for the rest of the frame
func _run_death_skips_player_being_freed() -> void:
	_clear_toasts()
	var old_lvl := Node2D.new()
	get_tree().root.add_child(old_lvl)
	var old_hero := _hero(old_lvl, Vector2(40, 40), true)
	var lvl := Node2D.new()
	var enemy := Node2D.new()
	lvl.add_child(enemy)
	var hp: Node = HealthScript.new()
	enemy.add_child(hp)
	enemy.add_child(_drop(_gold_table(4), 1))
	var hero := _hero(lvl, Vector2(40, 40), true)
	get_tree().root.add_child(lvl)
	await get_tree().process_frame
	old_lvl.queue_free()
	hp.emit_signal("died")
	_assert(hero.get_node("Bag").total() == 4 and old_hero.get_node("Bag").total() == 0, "Dies: the loot goes to the player the game has now, not one being freed")
	lvl.queue_free()


func _run_no_bag_still_says_so() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var chest := _chest(lvl, Vector2(400, 200), _gold_table())
	var hero := _hero(lvl, Vector2(40, 40), true, false)
	await _physics(2)
	hero.position = chest.position
	await _physics(4)
	_assert(_toast_has("Found: Gold x5"), "No bag: the message still shows (%s)" % ", ".join(_toasts()))
	lvl.queue_free()


func _run_full_bag_says_so() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var chest := _chest(lvl, Vector2(400, 200), _gold_table())
	var hero := _hero(lvl, Vector2(40, 40), true)
	var bag: Node = hero.get_node("Bag")
	bag.room = 3
	await _physics(2)
	hero.position = chest.position
	await _physics(4)
	_assert(bag.total() == 3 and _toast_has("No room in the bag for Gold x2"), "Full bag: it keeps what fits and says what didn't (%s)" % ", ".join(_toasts()))
	lvl.queue_free()


func _run_messages_stack_and_clear() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var a := _chest(lvl, Vector2(300, 200), _gold_table(1))
	var b := _chest(lvl, Vector2(600, 200), _gold_table(2))
	b.name = "Chest2"
	var quiet := _chest(lvl, Vector2(900, 200), _gold_table(4))
	quiet.name = "Chest3"
	quiet.get_node("LootDrop").show_messages = false
	var hero := _hero(lvl, Vector2(40, 40), true)
	await _physics(2)
	for c in [a, b, quiet]:
		hero.position = c.position
		await _physics(4)
	var labels: Array = get_tree().get_nodes_in_group("lite_toast")
	_assert(labels.size() == 2, "Messages: Show Messages off keeps that one quiet (%d showing)" % labels.size())
	if labels.size() == 2:
		var first: Label = labels[0]
		var second: Label = labels[1]
		_assert(second.position.y >= first.position.y + first.size.y, "Messages: a second one sits below the first (%d vs %d)" % [second.position.y, first.position.y])
		_assert(first.get_parent() is CanvasLayer and (first.get_parent() as CanvasLayer).layer == 100 and first.anchor_left == 0.5, "Messages: top centre, on a CanvasLayer above the game")
	await get_tree().create_timer(2.3).timeout
	_assert(get_tree().get_nodes_in_group("lite_toast").is_empty(), "Messages: they clear themselves after about 2 seconds")
	lvl.queue_free()


func _run_touch_drop_3d() -> void:
	_clear_toasts()
	var lvl := Node3D.new()
	get_tree().root.add_child(lvl)
	var crate := Area3D.new()
	crate.position = Vector3(10, 0, 0)
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	cs.shape = sphere
	crate.add_child(cs)
	lvl.add_child(crate)
	crate.add_child(_drop(_gold_table(), 0))
	var hero := CharacterBody3D.new()
	hero.add_to_group("player")
	var hs := CollisionShape3D.new()
	var capsule := BoxShape3D.new()
	hs.shape = capsule
	hero.add_child(hs)
	var bag: Node = BagScript.new()
	hero.add_child(bag)
	lvl.add_child(hero)
	await _physics(2)
	hero.position = crate.position
	await _physics(4)
	_assert(bag.total() == 5, "Touch 3D: walking into an Area3D fills the bag too (got %d)" % bag.total())
	lvl.queue_free()


func _run_describe() -> void:
	var gem := _item("gem")
	gem.name = "Gem"
	var gold := _gold()
	var text: String = DropScript.describe([{"item": gold, "count": 2}, {"item": gem, "count": 1}, {"item": gold, "count": 3}])
	_assert(text == "Gold x5, Gem", "Message text: the same item adds up, a single one has no count (%s)" % text)
