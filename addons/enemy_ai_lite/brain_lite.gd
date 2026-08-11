class_name EnemyBrainLite
extends Node

# The free enemy brain: idle -> chase -> attack, with a leash that walks it
# home. Drives the parent CharacterBody2D (top-down). Hunts the nearest node in
# `target_group` — the Controller pack puts the player there.

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
@export var target_group: StringName = &"player"
@export var enabled: bool = true

var state: StringName = IDLE
var target: Node2D = null
var home := Vector2.ZERO

var _body: CharacterBody2D = null
var _cooldown := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	if _body == null:
		push_warning("EnemyBrainLite needs a CharacterBody2D parent.")
		set_physics_process(false)
		return
	home = _body.global_position


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
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
		attacked.emit(target)
		EnemyAILite.attack_started.emit(_body, target)


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


func _switch(to: StringName) -> void:
	if to == state:
		return
	var from := state
	state = to
	state_changed.emit(from, to)
	EnemyAILite.state_changed.emit(_body if _body != null else self, from, to)
