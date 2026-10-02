extends Area2D

# Test stand-in for a Combat contact hitbox. The dock spots one by its exports
# (team + damage), and this one lands a hit on real overlap like Combat's does,
# so a played fight needs no Combat pack.

@export var team: int = 1
@export var damage: float = 10.0


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_hit") and int(area.get("team")) != team:
		area.call("take_hit", damage)
