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
	# Guarded rather than cast: this self-test is the first thing a buyer runs
	# after editing content, so a typo in quests.json has to read as a failed
	# check with a name on it, not a red script error out of the test harness.
	var qd: Dictionary = quests[0] if quests.size() > 0 and quests[0] is Dictionary else {}
	ok = _exp(not qd.is_empty(), "quests.json entry 0 is an object") and ok
	ok = _exp(qd.get("autostart", false) == true, "quest autostarts (no dialogue in this genre)") and ok
	var objs: Array = qd.get("objectives", []) if qd.get("objectives", []) is Array else []
	ok = _exp(objs.size() == 2, "two kill objectives") and ok

	# Register through the real chassis instead of a copy of it, so this checks
	# the code the game actually boots with. The copy could drift and pass.
	var quest_id := String(qd.get("id", ""))
	QuestsLite.quest_completed.connect(func(id: String) -> void:
		if id == quest_id: _completed = true)
	GameBootstrap._register_quests(content_dir + "quests.json")
	ok = _exp(QuestsLite.is_active(quest_id), "quest active after autostart path") and ok

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

	# --- D) death respawns the knight at the door ---
	var spawn: Vector2 = player.global_position
	player.global_position = spawn + Vector2(50, 0)
	player.get_node("Health").take_damage(999.0)
	await get_tree().process_frame
	ok = _exp(player.global_position.is_equal_approx(spawn), "death respawns the knight at the door") and ok
	ok = _exp(player.get_node("Health").is_alive(), "and revives at full health") and ok

	# --- F) the sword actually damages the enemy in front, for the Stats amount ---
	var target: CharacterBody2D = skeletons[0]
	target.get_node("Brain").enabled = false
	target.get_node("Touch").set_deferred("monitoring", false)
	target.global_position = player.global_position + Vector2(16, 0)
	player._facing = Vector2.RIGHT
	player._cooldown = 0.0
	await get_tree().physics_frame
	var thp: float = target.get_node("Health").current
	player.attack()
	ok = _exp(player.get_node("Attack").monitoring, "the swing enables the hitbox") and ok
	for _f in 8:
		await get_tree().physics_frame
	var dealt: float = thp - target.get_node("Health").current
	ok = _exp(dealt > 0.0, "the sword swing damaged the enemy in front of it") and ok
	ok = _exp(is_equal_approx(dealt, player.get_node("Stats").get_stat("attack")),
		"the hit dealt the Stats attack amount, once (%d)" % int(player.get_node("Stats").get_stat("attack"))) and ok

	# --- F2) two swings closer together than the swing window ---
	# attack_cooldown is an @export the buyer is invited to tune. Drop it under
	# the ~0.1s poll window and the older swing used to switch the hitbox off
	# underneath the newer one, which then asked a disabled Area2D for overlaps
	# once per frame (a red engine error each time) and landed nothing.
	var hitbox: Area2D = player.get_node("Attack")
	var old_cd: float = player.attack_cooldown
	player.attack_cooldown = 0.05
	player._cooldown = 0.0
	player.attack()
	await get_tree().physics_frame
	await get_tree().physics_frame
	player._cooldown = 0.0
	player.attack()                       # overlaps the first swing
	for _f in 4:
		await get_tree().physics_frame    # frame 6: the first swing would have cut out here
	ok = _exp(hitbox.monitoring, "an overlapping swing keeps the hitbox its caller owns") and ok
	for _f in 3:
		await get_tree().physics_frame
	ok = _exp(not hitbox.monitoring, "and the last swing still closes it when it ends") and ok
	player.attack_cooldown = old_cd

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

	# ...and it really is where the goblin fell. Drops used to be positioned
	# before they entered the tree, where global_position is only a local
	# transform, so anything spawned under a world root that isn't at the origin
	# landed offset by exactly that much.
	var mark := world.get_child_count()
	world.position = Vector2(500, 500)
	await get_tree().physics_frame
	var corpse: Vector2 = goblins[0].global_position
	goblins[0]._spark()
	goblins[0].loot_table = sure_drop
	goblins[0]._drop_loot()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var placed := world.get_child_count() > mark
	for i in range(mark, world.get_child_count()):
		if not world.get_child(i).global_position.is_equal_approx(corpse):
			placed = false
	ok = _exp(placed, "a drop lands on the corpse even when the world root has moved") and ok
	world.position = Vector2.ZERO
	await get_tree().physics_frame

	# A drop whose item has a junk "heal" must still despawn. float() throws on a
	# null, and the throw used to skip the queue_free, so the drop sat there
	# unpickable and threw again on every touch.
	var junk_item := ItemLite.new()
	junk_item.id = "junk_flask"
	junk_item.metadata = {"heal": null}
	var junk_drop := CryptDrop.new()
	junk_drop.item = junk_item
	world.add_child(junk_drop)
	junk_drop._on_body_entered(player)
	ok = _exp(junk_drop.is_queued_for_deletion(), "a drop with a junk heal value still despawns") and ok

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
