class_name SceneDoorLite
extends Area2D

# Touch-to-travel door: a "player" group body walks in and SceneFlowLite swaps
# scenes onto the target spawn point. Pro adds press-E doors and
# locked/key-gated doors.

signal traveled(by: Node)

@export_file("*.tscn") var target_scene: String
@export var target_spawn: StringName = &""
@export var enabled: bool = true

var _player_in: Node = null
var _wait_exit := false    # placed onto this door by a scene change: off and on again first


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func try_travel(by: Node) -> void:
	if not enabled or target_scene == "":
		return
	if _scene_flow_lite().is_changing():
		# touched mid-fade (e.g. spawned onto the door) — retry while they stand
		# in it. Guard the door itself: the in-flight change can free this scene.
		var door := self
		get_tree().create_timer(0.15).timeout.connect(func() -> void:
			if is_instance_valid(door) and door._player_in != null and is_instance_valid(door._player_in):
				door.try_travel(door._player_in))
		return
	traveled.emit(by)
	_scene_flow_lite().change_scene(target_scene, target_spawn)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_in = body
	# A door on the spot a scene change just dropped the player on (the way back, on the
	# landing spot) would send them straight back, and the two rooms would bounce them
	# for ever. They step off and back on, and it works like any door.
	if _scene_flow_lite().just_placed():
		_wait_exit = true
		return
	try_travel(body)


func _on_body_exited(body: Node) -> void:
	if body == _player_in:
		_player_in = null
		_wait_exit = false


# SceneFlowLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const SCENE_FLOW_LITE := preload("res://addons/scene_flow_lite/scene_flow_lite.gd")


static func _scene_flow_lite() -> SCENE_FLOW_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"SceneFlowLite") as SCENE_FLOW_LITE
