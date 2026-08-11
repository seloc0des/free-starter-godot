extends CharacterBody2D

# Forest wanderer. The Controller Lite mover child does the walking; this
# script just faces the sprite the right way and gives it a little step-bob,
# since the Kenney tiny characters are single-frame.

@onready var _sprite: Sprite2D = $Sprite

var _bob := 0.0


func _physics_process(delta: float) -> void:
	if velocity.length_squared() > 1.0:
		if absf(velocity.x) > 0.0:
			_sprite.flip_h = velocity.x < 0.0
		_bob += delta * 14.0
		_sprite.offset.y = -2.0 - (1.0 if int(_bob) % 2 == 0 else 0.0)
	else:
		_bob = 0.0
		_sprite.offset.y = -2.0
