class_name HitboxLite3D
extends Area3D

# 3D twin of HitboxLite. The "deals damage" area: on overlapping a HurtboxLite3D of a
# different team it applies `damage`. Drop it in, set damage + team, give it a
# CollisionShape3D.

@export var damage: float = 10.0
@export var team: int = 1
## Disable after the first hurtbox it hits (good for projectiles).
@export var one_shot: bool = false


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area3D) -> void:
	if area is HurtboxLite3D and area.team != team:
		area.receive_hit(damage, self)
		if one_shot:
			set_deferred("monitoring", false)
