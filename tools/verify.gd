extends Node

# Headless checks for the Story slice:
#  A) the chassis loop: talking starts the quest.
#  B) the world: the Controller mover carries the player, the 3 herbs land in an
#     Inventory bag, and collecting them completes the quest.
#  C) the Save contract: player position + herb collected-state round-trip.
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

	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)


func _exp(cond: bool, label: String) -> bool:
	print("  ", "[ok]" if cond else "[XX]", " ", label)
	return cond
