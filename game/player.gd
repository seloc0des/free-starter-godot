extends CharacterBody2D

# Top-down player. The Controller Lite mover child walks it and freezes it while
# the Healer is talking; this script just animates the knight.

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	# freeze while a conversation is up
	DialoguesLite.dialogue_started.connect(func(_id: String) -> void: ControllersLite.lock_movement(&"dialogue"))
	DialoguesLite.dialogue_finished.connect(func(_id: String) -> void: ControllersLite.unlock_movement(&"dialogue"))


func _physics_process(_delta: float) -> void:
	if velocity.length_squared() > 1.0:
		_sprite.play("run")
		if absf(velocity.x) > 0.0:
			_sprite.flip_h = velocity.x < 0.0
	else:
		_sprite.play("idle")
