class_name SceneSpawnPointLite
extends Marker2D

# Where travelers land. Doors name a spawn `id`; SceneFlowLite drops the
# "player" group here. One per entrance; `default` is the fallback.

@export var id: StringName = &"default"


func _ready() -> void:
	add_to_group("scene_spawn")
