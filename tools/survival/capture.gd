extends Node

# Marketing capture of the Survival slice (windowed, NOT --headless). Registers
# the camp quest the way the chassis would, gathers and crafts on camera, and
# saves frames into res://.capture/ with a survival_ prefix.

const WORLD := preload("res://game/world_survival.tscn")
const CONTENT := "res://genres/survival/content/"
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
		obj.type = QuestObjectiveLite.Type.COLLECT
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

	await _wait(0.6)
	# stand among the forage so the lit pickups fill the frame
	player.global_position = Vector2(620, 380)
	await _wait(0.5)
	await _shot("survival_clearing")

	# grab the rake first — Foraging jumps to 2, the tool shows on the belt
	_world.get_node("Rake")._on_body_entered(player)
	await _wait(0.4)
	await _shot("survival_rake")

	_world.get_node("Wood1")._collect()
	await _wait(0.35)
	_world.get_node("Mushroom1")._collect()
	await _wait(0.4)
	await _shot("survival_gather")

	for n in ["Wood2", "Wood3", "Mushroom2"]:
		_world.get_node(n)._collect()
		await _wait(0.3)
	player.global_position = Vector2(700, 372)
	await _wait(0.4)
	_world.get_node("CampSpot")._on_body_entered(player)
	await _wait(0.5)
	await _shot("survival_camp")

	_capturing = false
	await _wait(0.2)
	get_tree().quit()


func _capture_loop() -> void:
	while _capturing:
		await RenderingServer.frame_post_draw
		_save(OUT + "survival_gif_%03d.png" % _frame)
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
