class_name HitboxLite
extends Area2D

# The "deals damage" area — a swing, a projectile, a spike. On overlapping a
# HurtboxLite of a different team it applies `damage`. No code to wire: drop it in,
# set damage + team, give it a CollisionShape2D.

@export var damage: float = 10.0
@export var team: int = 1
## Disable after the first hurtbox it hits (good for projectiles).
@export var one_shot: bool = false


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if area is HurtboxLite and area.team != team:
		area.receive_hit(damage, self)
		if one_shot:
			set_deferred("monitoring", false)
