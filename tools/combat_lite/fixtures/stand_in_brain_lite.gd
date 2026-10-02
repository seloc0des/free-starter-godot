extends Node

# Test stand-in for an Enemy AI Lite brain: no attack_node_path, it switches a
# hitbox on its body on by itself for attack_duration.

@export var detect_radius: float = 160.0
@export var attack_radius: float = 40.0
@export var target_group: StringName = &"player"
@export var attack_cooldown: float = 1.0
@export var attack_duration: float = 0.25
