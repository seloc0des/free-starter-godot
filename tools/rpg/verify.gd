extends Node

# Headless checks for the RPG slice:
#  A) genres/rpg content parses: autostarting gear quest, 3 collect objectives
#  B) the world has 5 coins, the stall, a stocked vendor and a wallet
#  C) broke shopping is refused; coins fill the wallet
#  D) the buy pipe — wallet pays, sword equips, Attack rises, quest completes
#  E) the Save contract round-trips the player position (Controller mover)
#   ~/.local/bin/godot --headless --path free-starter res://tools/rpg/verify.tscn

const WORLD := preload("res://game/world_rpg.tscn")

var content_dir: String = "res://genres/rpg/content/" \
	if FileAccess.file_exists("res://genres/rpg/content/game.json") else "res://content/"

var _completed := false


func _ready() -> void:
	var ok := true

	# --- A) content ---
	var game_cfg: Dictionary = _load_json(content_dir + "game.json")
	ok = _exp(game_cfg.get("genre", "") == "rpg", "game.json declares the rpg genre") and ok
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
	var coins: Array[Node] = []
	for c in world.get_children():
		if String(c.name).begins_with("Coin"):
			coins.append(c)
	ok = _exp(coins.size() == 5, "5 coins in town") and ok
	var stall: Area2D = world.get_node("Stall")
	var vendor: VendorLite = world.get_node("Vendor")
	var wallet: WalletLite = world.get_node("Wallet")
	ok = _exp(stall != null and vendor != null and wallet != null, "stall, vendor and wallet exist") and ok
	ok = _exp(vendor.stock.size() == 1 and int(vendor.stock[0].get("price", 0)) == 5, "one sword in stock at 5 gold") and ok
	var player: CharacterBody2D = world.get_node("Player")
	ok = _exp(player.is_in_group("player"), "mover put the player in the player group") and ok
	var stats: StatsComponentLite = player.get_node("Stats")
	ok = _exp(int(stats.get_stat("attack")) == 5, "base Attack is 5") and ok

	# --- C) broke shopping refused, then coins pay ---
	stall._on_body_entered(player)
	await get_tree().process_frame
	ok = _exp(not stall._sold, "no gold, no sword") and ok
	for c in coins:
		c._collect()
		await get_tree().process_frame
	ok = _exp(wallet.get_balance() == 5, "5 coins landed in the wallet") and ok

	# --- D) buy, equip, level the stat, finish ---
	stall._on_body_entered(player)
	await get_tree().process_frame
	ok = _exp(stall._sold, "with 5 gold the sword sells") and ok
	ok = _exp(wallet.get_balance() == 0, "the vendor took the gold") and ok
	ok = _exp(player.get_node("Equipment").get_equipped("weapon_main") != null, "sword sits in weapon_main") and ok
	ok = _exp(int(stats.get_stat("attack")) == 10, "Attack rose 5 -> 10 from the gear modifier") and ok
	ok = _exp(_completed, "geared up — quest completed") and ok

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
