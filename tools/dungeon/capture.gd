extends Node

# Marketing capture of the Dungeon slice (windowed, NOT --headless). Registers
# the dungeon quest the way the chassis would, drives a short fight, and saves
# frames into res://.capture/ with a dungeon_ prefix.

const WORLD := preload("res://game/world_dungeon.tscn")
const CONTENT := "res://genres/dungeon/content/"
const OUT := "res://.capture/"

var _frame: int = 0
var _capturing: bool = false
var _world: Node = null


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(960, 600))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_register_quest()
	_world = WORLD.instantiate()
	add_child(_world)
	_run()


func _register_quest() -> void:
	var f := FileAccess.open(CONTENT + "quests.json", FileAccess.READ)
	var quests: Array = JSON.parse_string(f.get_as_text())
	var qd: Dictionary = quests[0]
	var quest := QuestLite.new()
	quest.id = String(qd.get("id", ""))
	quest.title = String(qd.get("title", ""))
	var built: Array[QuestObjectiveLite] = []
	for o in qd.get("objectives", []):
		var od: Dictionary = o
		var obj := QuestObjectiveLite.new()
		obj.id = String(od.get("id", ""))
		obj.type = QuestObjectiveLite.Type.KILL
		obj.target_id = String(od.get("target", ""))
		obj.required = int(od.get("required", 1))
		built.append(obj)
	quest.objectives = built
	QuestsLite.register(quest)
	QuestsLite.start_quest(quest.id)


func _run() -> void:
	_capturing = true
	_capture_loop()

	var player: CharacterBody2D = _world.get_node("Player")

	await _wait(0.5)
	# land in the middle of the pack so the whole roster charges into frame
	player.global_position = Vector2(800, 380)
	await _wait(0.7)
	await _shot("dungeon_approach")

	# trade blows: get hurt, swing, drop two goblins
	player.get_node("Health").take_damage(30.0)
	player.attack()
	# guarantee a flask so the drop shows in frame
	var sure := LootTableLite.new()
	sure.entries = [LootTableLite.entry(preload("res://game/dungeon/items/flask_big.tres"), 1)]
	_world.get_node("Goblin1").loot_table = sure
	_world.get_node("Goblin1").get_node("Hurt").receive_hit(999.0, player)
	await _wait(0.2)
	await _shot("dungeon_fight")
	_world.get_node("Goblin2").get_node("Hurt").receive_hit(999.0, player)
	await _wait(0.5)
	await _shot("dungeon_loot")

	for n in ["Goblin3", "Skeleton1", "Skeleton2"]:
		_world.get_node(n).get_node("Hurt").receive_hit(999.0, player)
		await _wait(0.35)
	await _wait(0.4)
	await _shot("dungeon_clear")

	_capturing = false
	await _wait(0.2)
	get_tree().quit()


func _capture_loop() -> void:
	while _capturing:
		await RenderingServer.frame_post_draw
		_save(OUT + "dungeon_gif_%03d.png" % _frame)
		_frame += 1
		await _wait(0.08)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	_save(OUT + "shot_%s.png" % shot_name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
