extends Node

# Headless checks for the Survival slice:
#  A) genres/survival content parses: autostarting camp quest, 3 collect objectives
#  B) the world has the forage roster (3 wood + 2 mushrooms) and the camp spot
#  C) the gather pipe — pickup -> bag + quest progress
#  D) the craft pipe — enough wood -> chest crafted -> quest completes
#  E) the Save contract round-trips the player position (Controller mover)
#   ~/.local/bin/godot --headless --path free-starter res://tools/survival/verify.tscn

const WORLD := preload("res://game/world_survival.tscn")

var content_dir: String = "res://genres/survival/content/" \
	if FileAccess.file_exists("res://genres/survival/content/game.json") else "res://content/"

var _completed := false


func _ready() -> void:
	var ok := true

	# --- A) content ---
	var game_cfg: Dictionary = _load_json(content_dir + "game.json")
	ok = _exp(game_cfg.get("genre", "") == "survival", "game.json declares the survival genre") and ok
	var quests: Array = _load_json_array(content_dir + "quests.json")
	ok = _exp(quests.size() == 1, "one quest defined") and ok
	var qd: Dictionary = quests[0]
	ok = _exp(bool(qd.get("autostart", false)), "quest autostarts") and ok
	var objs: Array = qd.get("objectives", [])
	ok = _exp(objs.size() == 3, "three collect objectives") and ok

	var quest := QuestLite.new()
	quest.id = String(qd.get("id", ""))
	quest.title = String(qd.get("title", ""))
	var built: Array[QuestObjectiveLite] = []
	for o in objs:
		var od: Dictionary = o
		var obj := QuestObjectiveLite.new()
		obj.id = String(od.get("id", ""))
		obj.type = QuestObjectiveLite.Type.COLLECT
		obj.target_id = String(od.get("target", ""))
		obj.required = int(od.get("required", 1))
		built.append(obj)
	quest.objectives = built
	QuestsLite.register(quest)
	QuestsLite.quest_completed.connect(func(id: String) -> void:
		if id == quest.id: _completed = true)
	QuestsLite.start_quest(quest.id)
	ok = _exp(QuestsLite.is_active(quest.id), "quest active") and ok

	# --- B) roster ---
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().process_frame
	var woods: Array[Node] = []
	var shrooms: Array[Node] = []
	for c in world.get_children():
		var it: Variant = c.get("item")
		if it is ItemLite:
			if it.id == "wood":
				woods.append(c)
			elif it.id == "mushroom":
				shrooms.append(c)
	ok = _exp(woods.size() == 3, "3 firewood in the clearing") and ok
	ok = _exp(shrooms.size() == 2, "2 mushroom patches in the clearing") and ok
	var station: Area2D = world.get_node("CampSpot")
	ok = _exp(station != null, "camp spot exists") and ok
	var player: CharacterBody2D = world.get_node("Player")
	ok = _exp(player.is_in_group("player"), "mover put the player in the player group") and ok

	# --- F) rake: equipping it raises Foraging, which drives gather yield ---
	var rake_node: Area2D = world.get_node("Rake")
	ok = _exp(rake_node != null, "the forager's rake is in the clearing") and ok
	var stats: StatsComponentLite = player.get_node("Stats")
	ok = _exp(int(stats.get_stat("foraging")) == 1, "Foraging starts at 1") and ok
	rake_node._on_body_entered(player)
	await get_tree().process_frame
	ok = _exp(player.get_node("Equipment").get_equipped("weapon_main") != null, "rake equips into weapon_main") and ok
	ok = _exp(int(stats.get_stat("foraging")) == 2, "the rake raised Foraging 1 -> 2") and ok

	# --- C) gather everything (the rake doubles each pull) ---
	var wood_item := preload("res://game/survival/items/wood.tres")
	var mush_item := preload("res://game/survival/items/mushroom.tres")
	var bag: InventoryLite = world.get_node("CampBag")
	woods[0]._collect()
	await get_tree().process_frame
	ok = _exp(bag.count_item(wood_item) == 2, "with the rake, one wood pull brings back 2") and ok
	for p in woods.slice(1) + shrooms:
		p._collect()
		await get_tree().process_frame
	ok = _exp(bag.count_item(wood_item) == 6, "3 wood pulls at Foraging 2 = 6 wood") and ok
	ok = _exp(bag.count_item(mush_item) == 4, "2 mushroom pulls at Foraging 2 = 4") and ok

	# --- D) craft at the camp spot ---
	station._on_body_entered(player)
	await get_tree().process_frame
	ok = _exp(station._crafted, "walking up with the wood crafts the chest") and ok
	ok = _exp(bag.count_item(wood_item) == 3, "crafting spent 3 of the 6 wood") and ok
	ok = _exp(_completed, "camp made, quest completed") and ok

	# --- E) save round-trip via the Controller mover contract ---
	player.global_position = Vector2(333, 444)
	SaveLite.save()
	player.global_position = Vector2.ZERO
	SaveLite.load()
	ok = _exp(player.global_position.is_equal_approx(Vector2(333, 444)), "save/load restored player position") and ok

	# --- F) the weapon-slot bonus is a bonus, not a counter ---
	# add_modifier appends and never replaces by source, so every re-equip used to
	# pile on another +1 Foraging and nothing took it back off on unequip.
	var equip: EquipmentLite = player.get_node("Equipment")
	equip.try_equip(rake_node.item)
	equip.try_equip(rake_node.item)
	await get_tree().process_frame
	ok = _exp(int(stats.get_stat("foraging")) == 2, "re-equipping the rake doesn't stack the Foraging bonus") and ok
	equip.unequip("weapon_main")
	await get_tree().process_frame
	ok = _exp(int(stats.get_stat("foraging")) == 1, "taking the rake off gives the bonus back") and ok

	# --- G) a save file with nulls in it ---
	# bool(null) throws rather than giving false, and the throw aborts load_state
	# partway, leaving that one node stuck in whatever state it spawned with.
	var forage: Node = woods[0]
	forage._collected = true
	forage.visible = false
	forage.load_state({"collected": null})
	var survived: bool = not forage._collected
	rake_node._taken = true
	rake_node.load_state({"taken": null})
	survived = survived and not rake_node._taken
	station.load_state({"crafted": null})
	survived = survived and not station._crafted
	ok = _exp(survived, "a null in the save doesn't abort a survival load_state") and ok

	# --- H) camp spot with its crafting_path pointing nowhere ---
	# It looked up the node with get_node_or_null and then called straight into
	# it, so moving the Crafting node in the scene aborted _ready: body_entered
	# never got connected and the camp spot quietly did nothing all game.
	var orphan := station.duplicate()
	orphan.crafting_path = NodePath("NoSuchNode")
	world.add_child(orphan)
	await get_tree().process_frame
	orphan._on_body_entered(player)
	ok = _exp(orphan._crafting == null and orphan._prompt.visible,
		"a camp spot with a broken crafting_path still reacts instead of dying quietly") and ok
	orphan.queue_free()

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
