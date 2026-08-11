extends CharacterBody2D

# Dungeon knight. Movement comes from the Controller Lite mover child; this
# script owns what's on top: facing, the sword swing (a HitboxLite pulse), and
# getting hurt. Dies politely — back to the spawn point at full health.

const PLAYER_TEAM := 0

@export var attack_cooldown: float = 0.35

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _attack: Area2D = $Attack
@onready var _sword: Sprite2D = $Sword
@onready var _health: HealthLite = $Health
@onready var _stats: StatsComponentLite = $Stats

var _facing := Vector2.RIGHT
var _cooldown := 0.0
var _spawn := Vector2.ZERO


func _ready() -> void:
	_spawn = global_position
	_attack.monitoring = false
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
	_sword.position = _facing * 14.0
	_sword.rotation = _facing.angle() + PI / 2.0
	_sword.visible = true
	get_tree().create_timer(0.12).timeout.connect(func() -> void: _sword.visible = false)
	_strike()


# Poll the hitbox for overlapping enemy hurtboxes across the whole swing and
# damage each one once. Querying overlaps is deterministic; relying on
# area_entered to fire when you toggle monitoring on an already-overlapping area
# is not, which is why the swing used to whiff. Polling a few frames also lets
# a monster that steps into the arc mid-swing still take the hit.
func _strike() -> void:
	_attack.monitoring = true
	var struck := {}
	for _i in 6:
		await get_tree().physics_frame
		if not is_instance_valid(_attack):
			return
		var dmg := _stats.get_stat("attack")   # same Stats math the RPG kit uses
		for area in _attack.get_overlapping_areas():
			if area is HurtboxLite and area.team != PLAYER_TEAM and not struck.has(area):
				struck[area] = true
				area.receive_hit(dmg, _attack)
	_attack.monitoring = false


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
