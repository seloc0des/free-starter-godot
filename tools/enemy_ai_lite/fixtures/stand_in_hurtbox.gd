extends Area2D

# Test stand-in for a Combat hurtbox (team + health_path is how the dock spots
# one). Adds up whatever the stand-in hitbox lands on it, and when.

@export var team: int = 0
@export var health_path: NodePath

var taken := 0.0
var hit_frames: Array[int] = []


func take_hit(amount: float) -> void:
	taken += amount
	hit_frames.append(Engine.get_physics_frames())
