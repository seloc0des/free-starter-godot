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


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func try_travel(by: Node) -> void:
	if not enabled or target_scene == "":
		return
	if SceneFlowLite.is_changing():
		# touched mid-fade (e.g. spawned onto the door) — retry while they stand
		# in it. Guard the door itself: the in-flight change can free this scene.
		var door := self
		get_tree().create_timer(0.15).timeout.connect(func() -> void:
			if is_instance_valid(door) and door._player_in != null and is_instance_valid(door._player_in):
				door.try_travel(door._player_in))
		return
	traveled.emit(by)
	SceneFlowLite.change_scene(target_scene, target_spawn)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_in = body
	try_travel(body)


func _on_body_exited(body: Node) -> void:
	if body == _player_in:
		_player_in = null
