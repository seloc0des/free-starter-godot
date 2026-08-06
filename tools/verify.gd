extends Node

# Headless checks for the Story slice:
#  A) the chassis loop — talking starts the quest, collecting 3 herbs completes it.
#  B) the Save contract — player position + herb collected-state round-trip.
#   ~/.local/bin/godot --headless --path free-starter res://tools/verify.tscn

const WORLD := preload("res://game/world.tscn")

var _started: bool = false
var _completed: bool = false


func _ready() -> void:
	var ok := true

	# --- A) loop ---
	QuestsLite.quest_started.connect(func(id: String): if id == "gather_herbs": _started = true)
	QuestsLite.quest_completed.connect(func(id: String): if id == "gather_herbs": _completed = true)
	DialoguesLite.start("healer_intro")
	DialoguesLite.choose(0)
	ok = _exp(_started, "talking to the healer started the quest") and ok
	DialoguesLite.advance()
	DialoguesLite.advance()
	for i in 3:
		GameEvents.item_collected.emit("herb", 1)
	ok = _exp(_completed, "collecting 3 herbs completed the quest") and ok

	# --- B) save / load round-trip ---
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().process_frame
	var player: Node2D = world.get_node("Player")
	var herb: Node = world.get_node("Herb1")
	herb._enable()
	player.global_position = Vector2(111, 222)
	herb._collect()
	SaveLite.save()
	# perturb, then load from disk
	player.global_position = Vector2.ZERO
	herb.visible = true
	SaveLite.load()
	ok = _exp(player.global_position.is_equal_approx(Vector2(111, 222)), "save/load restored player position") and ok
	ok = _exp(not herb.visible, "save/load restored collected herb (hidden)") and ok

	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)


func _exp(cond: bool, label: String) -> bool:
	print("  ", "[ok]" if cond else "[XX]", " ", label)
	return cond
