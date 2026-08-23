extends Node

# Headless checks for the Story slice:
#  A) the chassis loop: talking starts the quest.
#  B) the world: the Controller mover carries the player, the 3 herbs land in an
#     Inventory bag, and collecting them completes the quest.
#  C) the Save contract: player position + herb collected-state round-trip.
#  D) content robustness: a typo in content/*.json must not take the game down.
#   ~/.local/bin/godot --headless --path free-starter res://tools/verify.tscn

const WORLD := preload("res://game/world.tscn")

var _started: bool = false
var _completed: bool = false


func _ready() -> void:
	var ok := true

	# --- A) talk -> quest ---
	QuestsLite.quest_started.connect(func(id: String): if id == "gather_herbs": _started = true)
	QuestsLite.quest_completed.connect(func(id: String): if id == "gather_herbs": _completed = true)
	DialoguesLite.start("healer_intro")
	DialoguesLite.choose(0)
	ok = _exp(_started, "talking to the healer started the quest") and ok

	# --- B) controller mover + inventory bag + quest complete ---
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().process_frame
	var player: CharacterBody2D = world.get_node("Player")
	ok = _exp(player.has_node("Mover"), "the player walks on the Controller mover") and ok
	ok = _exp(player.is_in_group("player"), "the mover registered the player in the player group") and ok

	var bag: InventoryLite = world.get_node("HerbBag")
	var herb_item := preload("res://game/items/herb.tres")
	for hid in ["Herb1", "Herb2", "Herb3"]:
		var h := world.get_node(hid)
		h._enable()
		h._collect()
		await get_tree().process_frame
	ok = _exp(bag.count_item(herb_item) == 3, "the 3 herbs went into the Inventory bag") and ok
	ok = _exp(_completed, "collecting 3 herbs completed the quest") and ok

	# --- C) save / load round-trip (mover contract + herb state) ---
	player.global_position = Vector2(111, 222)
	SaveLite.save()
	player.global_position = Vector2.ZERO
	world.get_node("Herb1").visible = true
	SaveLite.load()
	ok = _exp(player.global_position.is_equal_approx(Vector2(111, 222)), "save/load restored player position") and ok
	ok = _exp(not world.get_node("Herb1").visible, "save/load kept the herb collected (hidden)") and ok

	# --- D) hand-edited content that's wrong somewhere ---
	# The buyer edits content/*.json by hand; that's the whole pitch. A stray
	# value used to be a hard runtime error, and GDScript aborts the enclosing
	# function on those — so one typo silently dropped every quest after it and
	# the game still booted looking fine. The red lines below are deliberate.
	print("  -- feeding the chassis bad content on purpose; errors below are expected --")
	ok = _exp_content() and ok
	ok = _exp_required_floor() and ok
	ok = _exp_corrupt_save() and ok
	ok = _exp_null_in_save(world) and ok

	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# Junk in four different shapes, two good quests at the end. Both must register.
func _exp_content() -> bool:
	var path := "user://verify_bad_quests.json"
	_write(path, '[
	  "not an object",
	  {"id": "vq_a", "title": null, "objectives": "not a list"},
	  {"title": "no id at all"},
	  {"id": "vq_a", "title": "duplicate id"},
	  {"id": "vq_b", "objectives": [ 42, {"id": "o1", "target": "herb", "required": 2} ]}
	]')
	GameBootstrap._register_quests(path)
	var survived: bool = QuestsLite.is_registered("vq_a") and QuestsLite.is_registered("vq_b")
	return _exp(survived, "a typo in quests.json skips that entry, not the rest of the file")


# A 0-requirement objective completes the quest the moment you pick up anything
# at all, related or not. "required": 0 gets floored; garbage like "three" falls
# back to 1 on the way in, so 0 is the value that actually exercises the floor.
func _exp_required_floor() -> bool:
	var path := "user://verify_floor_quest.json"
	_write(path, '[{"id": "vq_floor", "objectives":
	  [{"id": "o1", "type": "collect", "target": "goldleaf", "required": 0}]}]')
	GameBootstrap._register_quests(path)
	QuestsLite.start_quest("vq_floor")
	QuestsLite.report_collect("something_else", 1)
	if QuestsLite.is_complete("vq_floor"):
		return _exp(false, "a \"required\" of 0 floors to 1 instead of auto-completing")
	QuestsLite.report_collect("goldleaf", 1)
	return _exp(QuestsLite.is_complete("vq_floor"), "a \"required\" of 0 floors to 1 instead of auto-completing")


# A truncated or hand-edited save used to abort load() outright, so neither
# load_completed nor load_failed fired and the game heard nothing at all.
func _exp_corrupt_save() -> bool:
	var heard: Array[String] = []
	var on_ok := func(_p: String) -> void: heard.append("completed")
	var on_bad := func(_r: String) -> void: heard.append("failed")
	SaveLite.load_completed.connect(on_ok)
	SaveLite.load_failed.connect(on_bad)
	var path := "user://verify_corrupt_save.json"
	_write(path, '{"nodes": "junk"}')
	var returned: bool = SaveLite.load(path)
	SaveLite.load_completed.disconnect(on_ok)
	SaveLite.load_failed.disconnect(on_bad)
	return _exp(not returned and heard == ["failed"], "a corrupt save reports load_failed instead of going quiet")


# Same class one level down: the herb's own load_state used to call bool() on
# whatever the save held, and bool(null) throws rather than giving false.
func _exp_null_in_save(world: Node) -> bool:
	var herb := world.get_node("Herb1")
	herb._collected = true
	herb.visible = false
	herb.load_state({"collected": null})
	return _exp(not herb._collected, "a null in the save doesn't abort a pickup's load_state")


func _exp(cond: bool, label: String) -> bool:
	print("  ", "[ok]" if cond else "[XX]", " ", label)
	return cond
