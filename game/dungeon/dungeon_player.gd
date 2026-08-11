extends CharacterBody2D

# Dungeon knight. Movement comes from the Controller Lite mover child; this
# script owns what's on top: facing, the sword swing (a HitboxLite pulse), and
# getting hurt. Dies politely — back to the spawn point at full health.

@export var attack_damage: float = 25.0
@export var attack_cooldown: float = 0.35

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _attack: HitboxLite = $Attack
@onready var _sword: Sprite2D = $Sword
@onready var _health: HealthLite = $Health

var _facing := Vector2.RIGHT
var _cooldown := 0.0
var _spawn := Vector2.ZERO


func _ready() -> void:
	_spawn = global_position
	_attack.monitoring = false
	_attack.damage = attack_damage
	_sword.visible = false
	_health.died.connect(_on_died)
	$Hurt.hit.connect(func(_amount: float, _source: Node) -> void: _flash(Color(1, 0.4, 0.4)))


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if velocity.length_squared() > 1.0:
		_facing = velocity.normalized()
		_sprite.play("run")
		if absf(velocity.x) > 0.0:
			_sprite.flip_h = velocity.x < 0.0
	else:
		_sprite.play("idle")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		attack()
		get_viewport().set_input_as_handled()


func attack() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = attack_cooldown
	_attack.position = _facing * 18.0
	_attack.monitoring = true
	_sword.position = _facing * 14.0
	_sword.rotation = _facing.angle() + PI / 2.0
	_sword.visible = true
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		_attack.set_deferred("monitoring", false)
		_sword.visible = false)


func _on_died() -> void:
	global_position = _spawn
	_health.revive()
	_flash(Color(1, 1, 1, 0.6))
	# a second of grace so a monster camping the door can't chain-kill you
	$Hurt.set_deferred("monitorable", false)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		$Hurt.set_deferred("monitorable", true))


func _flash(c: Color) -> void:
	_sprite.modulate = c
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		_sprite.modulate = Color.WHITE)
