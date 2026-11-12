class_name SceneSpawnPointLite3D
extends Marker3D

# The 3D twin of SceneSpawnPointLite. Doors name a spawn `id`; SceneFlowLite
# drops the "player" group here, facing the way this marker's -Z
# direction points (Rotation Y 0 = -Z, 180 = +Z). One per entrance; `default` is the fallback.

@export var id: StringName = &"default"


func _ready() -> void:
	add_to_group("scene_spawn")
