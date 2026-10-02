class_name EnemyBrainLite
extends Node

# The free enemy brain: idle -> chase -> attack, with a leash that walks it
# home. Drives the parent CharacterBody2D (top-down). Hunts the nearest node in
# `target_group` — the Controller pack puts the player there.
# A Combat hitbox on the body gets switched on for each attack.

signal state_changed(from: StringName, to: StringName)
signal target_acquired(target: Node2D)
signal target_lost
signal attacked(target: Node2D)

const IDLE := &"idle"
const CHASE := &"chase"
const ATTACK := &"attack"
const RETURN := &"return"

@export var move_speed: float = 90.0         ## return-home speed
@export var chase_speed: float = 140.0
@export var detect_radius: float = 160.0
@export var attack_radius: float = 40.0
@export var give_up_radius: float = 320.0    ## leash: this far from home -> walk back
@export var attack_cooldown: float = 1.0
@export var attack_duration: float = 0.25    ## how long a Combat hitbox on the body stays live per attack
@export var target_group: StringName = &"player"
@export var enabled: bool = true

var state: StringName = IDLE
var target: Node2D = null
var home := Vector2.ZERO

var _body: CharacterBody2D = null
var _cooldown := 0.0
var _swing: Area2D = null     # the hitbox switched on for the current attack
var _swing_left := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	if _body == null:
		push_warning("EnemyBrainLite needs a CharacterBody2D parent.")
		set_physics_process(false)
		return
	home = _body.global_position


func _physics_process(delta: float) -> void:
	if not enabled:
		# switched off mid-swing (death, cutscene): don't leave the hitbox live
		if _swing_left > 0.0:
			_swing_left = 0.0
			_arm(false)
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_tick_swing(delta)
	_update_target()

	# leash applies while engaged, mid-attack included
	if (state == CHASE or state == ATTACK) \
			and _body.global_position.distance_to(home) > give_up_radius:
		_drop_target()
		_switch(RETURN)

	match state:
		IDLE:
			_body.velocity = _body.velocity.move_toward(Vector2.ZERO, 800.0 * delta)
		CHASE:
			_do_chase()
		ATTACK:
			_do_attack()
		RETURN:
			_do_return()
	_body.move_and_slide()


func set_state(to: StringName) -> void:
	_switch(to)


# ---- states --------------------------------------------------------------

func _do_chase() -> void:
	if target == null:
		return
	if _body.global_position.distance_to(target.global_position) <= attack_radius:
		_switch(ATTACK)
		return
	_body.velocity = _body.global_position.direction_to(target.global_position) * chase_speed


func _do_attack() -> void:
	_body.velocity = Vector2.ZERO
	if target == null:
		return
	if _body.global_position.distance_to(target.global_position) > attack_radius * 1.2:
		_switch(CHASE)
		return
	if _cooldown <= 0.0:
		_cooldown = attack_cooldown
		_swing = _hitbox()
		_swing_left = attack_duration
		_arm(true)
		attacked.emit(target)
		_enemy_ai_lite().attack_started.emit(_body, target)


func _do_return() -> void:
	if _body.global_position.distance_to(home) < 8.0:
		_body.velocity = Vector2.ZERO
		_switch(IDLE)
		return
	_body.velocity = _body.global_position.direction_to(home) * move_speed


# ---- internals -----------------------------------------------------------

func _update_target() -> void:
	if state == RETURN:
		return                                              # deaf until home — no leash ping-pong
	var best: Node2D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(target_group):
		if n is Node2D and is_instance_valid(n) and n != _body:
			var d: float = _body.global_position.distance_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n
	if best != null and best_d <= detect_radius:
		if target == null:
			target = best
			target_acquired.emit(best)
			if state == IDLE:
				_switch(CHASE)
		else:
			target = best
	elif target != null:
		_drop_target()
		if state == CHASE or state == ATTACK:
			_switch(RETURN)


func _drop_target() -> void:
	target = null
	target_lost.emit()


# A Combat hitbox (Pro or Lite) on the body, told apart by its exports so this
# brain never needs the Combat pack. A hitbox only hits when something starts
# touching it, so it goes off after each attack and back on for the next one:
# coming back on is what hits the player again while they stay in reach.
func _hitbox() -> Area2D:
	for c in _body.get_children():
		if c is Area2D and "team" in c and ("damage" in c or "base_damage" in c):
			return c as Area2D
	return null


func _tick_swing(delta: float) -> void:
	if _swing_left <= 0.0:
		return
	_swing_left -= delta
	if _swing_left <= 0.0:
		_arm(false)


func _arm(on: bool) -> void:
	if _swing != null and is_instance_valid(_swing):
		_swing.set_deferred("monitoring", on)


func _switch(to: StringName) -> void:
	if to == state:
		return
	var from := state
	state = to
	state_changed.emit(from, to)
	_enemy_ai_lite().state_changed.emit(_body if _body != null else self, from, to)


# EnemyAILite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const ENEMY_AI_LITE := preload("res://addons/enemy_ai_lite/enemy_ai_bus_lite.gd")


static func _enemy_ai_lite() -> ENEMY_AI_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"EnemyAILite") as ENEMY_AI_LITE
