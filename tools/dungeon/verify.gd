extends Node

# Headless checks for the Dungeon slice:
#  A) genres/dungeon content parses and describes the kill quest correctly
#  B) the world spawns the roster the quest needs (3 goblins + 2 skeletons)
#  C) the combat pipe — hurtbox -> health -> died -> enemy_defeated -> quest
#  D) player attack pulses + death respawn
#  E) the Save contract round-trips the player position (Controller mover)
#   ~/.local/bin/godot --headless --path free-starter res://tools/dungeon/verify.tscn

const WORLD := preload("res://game/world_dungeon.tscn")
# in the repo the dungeon content lives under genres/; in the shipped dungeon
# zip it IS the content/ folder
var content_dir: String = "res://genres/dungeon/content/" \
	if FileAccess.file_exists("res://genres/dungeon/content/game.json") else "res://content/"

var _completed := false


func _ready() -> void:
	var ok := true

	# --- A) content ---
	var game_cfg: Dictionary = _load_json(content_dir + "game.json")
	ok = _exp(game_cfg.get("genre", "") == "dungeon", "game.json declares the dungeon genre") and ok
	var quests: Array = _load_json_array(content_dir + "quests.json")
	ok = _exp(quests.size() == 1, "one quest defined") and ok
	var qd: Dictionary = quests[0]
	ok = _exp(bool(qd.get("autostart", false)), "quest autostarts (no dialogue in this genre)") and ok
	var objs: Array = qd.get("objectives", [])
	ok = _exp(objs.size() == 2, "two kill objectives") and ok

	# register it the way the chassis does, autostart included
	var quest := QuestLite.new()
	quest.id = String(qd.get("id", ""))
	quest.title = String(qd.get("title", ""))
	var built: Array[QuestObjectiveLite] = []
	for o in objs:
		var od: Dictionary = o
		var obj := QuestObjectiveLite.new()
		obj.id = String(od.get("id", ""))
		obj.type = QuestObjectiveLite.Type.KILL
		obj.target_id = String(od.get("target", ""))
		obj.required = int(od.get("required", 1))
		built.append(obj)
	quest.objectives = built
	QuestsLite.register(quest)
	QuestsLite.quest_completed.connect(func(id: String) -> void:
		if id == quest.id: _completed = true)
	QuestsLite.start_quest(quest.id)
	ok = _exp(QuestsLite.is_active(quest.id), "quest active after autostart path") and ok

	# --- B) roster ---
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	var goblins: Array[Node] = []
	var skeletons: Array[Node] = []
	for c in world.get_children():
		if c.get("enemy_id") == "goblin":
			goblins.append(c)
		elif c.get("enemy_id") == "skeleton":
			skeletons.append(c)
	ok = _exp(goblins.size() == 3, "3 goblins in the crypt") and ok
	ok = _exp(skeletons.size() == 2, "2 skeletons in the crypt") and ok
	var player: CharacterBody2D = world.get_node("Player")
	ok = _exp(player.is_in_group("player"), "mover put the player in the player group") and ok

	# --- D) attack pulse + respawn (before the kills so damage flow is fresh) ---
	player.attack()
	ok = _exp(player.get_node("Attack").monitoring, "attack pulse enables the hitbox") and ok
	var spawn: Vector2 = player.global_position
	player.global_position = spawn + Vector2(50, 0)
	player.get_node("Health").take_damage(999.0)
	await get_tree().process_frame
	ok = _exp(player.global_position.is_equal_approx(spawn), "death respawns the knight at the door") and ok
	ok = _exp(player.get_node("Health").is_alive(), "and revives at full health") and ok

	# --- F) stats drive the sword ---
	player.attack()
	ok = _exp(player.get_node("Attack").damage == player.get_node("Stats").get_stat("attack"),
		"sword damage reads from the Stats component") and ok

	# --- G) loot: table shape, drop spawn, flask heals ---
	var table: LootTableLite = preload("res://game/dungeon/crypt_loot.tres")
	ok = _exp(table.entries.size() == 3, "crypt table has 3 entries (small, big, nothing)") and ok
	var seen := {"flask_small": false, "flask_big": false, "nothing": false}
	var rng := RandomNumberGenerator.new()
	for i in 200:
		rng.seed = i
		var rolled: Array = table.roll(rng)
		if rolled.is_empty() or rolled[0].get("item") == null:
			seen["nothing"] = true
		else:
			seen[rolled[0].get("item").id] = true
	ok = _exp(seen["flask_small"] and seen["flask_big"] and seen["nothing"],
		"200 seeded rolls hit all three outcomes") and ok

	var sure_drop := LootTableLite.new()
	sure_drop.entries = [LootTableLite.entry(preload("res://game/dungeon/items/flask_small.tres"), 1)]
	goblins[0].loot_table = sure_drop
	goblins[0].get_node("Hurt").receive_hit(999.0, null)
	await get_tree().process_frame
	await get_tree().process_frame
	var dropped := false
	for c in world.get_children():
		if c is CryptDrop:
			dropped = true
	ok = _exp(dropped, "a guaranteed table left a drop where the goblin fell") and ok

	player.get_node("Health").take_damage(30.0)
	var before: float = player.get_node("Health").current
	for c in world.get_children():
		if c is CryptDrop:
			c._on_body_entered(player)
	ok = _exp(player.get_node("Health").current == before + 25.0, "the small flask healed 25") and ok

	# --- C) kill the rest through the hurtboxes ---
	for e in goblins.slice(1) + skeletons:
		e.get_node("Hurt").receive_hit(999.0, null)
		await get_tree().process_frame
	ok = _exp(_completed, "clearing the roster completed the quest") and ok

	# --- E) save round-trip via the Controller mover contract ---
	player.global_position = Vector2(333, 444)
	SaveLite.save()
	player.global_position = Vector2.ZERO
	SaveLite.load()
	ok = _exp(player.global_position.is_equal_approx(Vector2(333, 444)), "save/load restored player position") and ok

	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)


func _exp(cond: bool, label: String) -> bool:
	print("  ", "[ok]" if cond else "[XX]", " ", label)
	return cond


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


func _load_json_array(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Array else []
